#!/usr/bin/env python3
# ============================================================
# make_speech_mif.py  --  Encoder fuer speech.vhd (AtariFA)
#
# Erzeugt aus einer WAV-Datei (oder einem Test-Ton) den 1-Bit-Delta-Strom
# fuer das Boot-Sprachmodul speech.vhd und schreibt ihn als Quartus .mif.
#
# Verfahren: Delta-Modulation mit FESTEM Schritt -- identisch zum Decoder in
# speech.vhd. WICHTIG: --step muss exakt dem Generic STEP in speech.vhd
# entsprechen, sonst stimmt die Rekonstruktion nicht.
#
# Nur Python-Standardbibliothek (wave, array, math, argparse). Kein numpy,
# kein audioop (ab Python 3.13 entfernt).
#
# Typischer Ablauf (Roboterstimme passt zu espeak):
#   espeak -v en "Lisy" -w lisy_raw.wav
#   python tools/make_speech_mif.py --in lisy_raw.wav --out rom/lisy.mif \
#          --rate 16000 --step 6
#   -> gibt N_SAMPLES aus; diesen Wert als Generic in speech.vhd setzen.
#
# Schnelltest ohne WAV (1 kHz Ton, 0.4 s):
#   python tools/make_speech_mif.py --tone 1000 --secs 0.4 --out rom/lisy.mif
# ============================================================

import argparse
import array
import math
import struct
import wave


def read_wav_mono_float(path):
    """WAV einlesen -> (samples[-1..1], framerate). Mono-Mix, 8/16-Bit PCM."""
    with wave.open(path, "rb") as w:
        nch = w.getnchannels()
        sw = w.getsampwidth()
        fr = w.getframerate()
        n = w.getnframes()
        raw = w.readframes(n)

    if sw == 1:                       # 8-Bit PCM ist unsigned (0..255)
        a = array.array("B")
        a.frombytes(raw)
        data = [(v - 128) / 128.0 for v in a]
    elif sw == 2:                     # 16-Bit PCM signed
        a = array.array("h")
        a.frombytes(raw)
        data = [v / 32768.0 for v in a]
    else:
        raise SystemExit("Nur 8- oder 16-Bit PCM-WAV unterstuetzt (sampwidth=%d)" % sw)

    if nch > 1:                       # auf Mono mischen
        mono = [sum(data[i:i + nch]) / nch for i in range(0, len(data), nch)]
    else:
        mono = data
    return mono, fr


def resample_linear(samples, src_rate, dst_rate):
    """Einfache lineare Resampling-Interpolation."""
    if src_rate == dst_rate or not samples:
        return list(samples)
    n_out = int(len(samples) * dst_rate / src_rate)
    out = []
    for i in range(n_out):
        pos = i * src_rate / dst_rate
        i0 = int(pos)
        frac = pos - i0
        s0 = samples[i0]
        s1 = samples[i0 + 1] if i0 + 1 < len(samples) else s0
        out.append(s0 + (s1 - s0) * frac)
    return out


def make_tone(freq, secs, rate):
    n = int(secs * rate)
    return [0.7 * math.sin(2 * math.pi * freq * i / rate) for i in range(n)]


def smooth_movavg(samples, win):
    """Zentrierter Moving-Average-Tiefpass (win ungerade). Reduziert Hochton ->
    weniger Slope-Overload-/Granular-Rauschen der Delta-Modulation. win=1 = aus."""
    if win <= 1 or not samples:
        return list(samples)
    if win % 2 == 0:
        win += 1
    half = win // 2
    n = len(samples)
    out = [0.0] * n
    acc = 0.0
    # einfacher gleitender Mittelwert mit Randbehandlung (Werte am Rand wiederholt)
    for i in range(n):
        s = 0.0
        for k in range(-half, half + 1):
            j = i + k
            j = 0 if j < 0 else n - 1 if j >= n else j
            s += samples[j]
        out[i] = s / win
    return out


def fade_out(samples, rate, ms):
    """Lineare Ausblendung der letzten ms -> sanftes Auslaufen statt hartem Stopp
    (espeak kappt Vokal-Enden abrupt bei ~60% Pegel -> sonst 'abgeschnitten'/Klick)."""
    k = int(ms * rate / 1000.0)
    if k <= 0 or not samples:
        return samples
    k = min(k, len(samples))
    out = list(samples)
    base = len(out) - k
    for j in range(k):
        out[base + j] *= 1.0 - (j + 1) / k     # letztes Sample -> 0
    return out


def normalize(samples, peak=0.9):
    m = max((abs(s) for s in samples), default=0.0)
    if m < 1e-6:
        return samples
    g = peak / m
    return [s * g for s in samples]


def to_u8(samples):
    """[-1..1] -> 0..255 (zentriert auf 128)."""
    out = []
    for s in samples:
        v = int(round(128 + s * 127))
        out.append(0 if v < 0 else 255 if v > 255 else v)
    return out


def trim_silence(samples, rate, thresh=0.02, pad_ms=8.0):
    """Fuehrende/abschliessende Stille entfernen (SAPI haengt oft Stille an)."""
    if not samples:
        return samples
    peak = max((abs(s) for s in samples), default=0.0) or 1.0
    t = thresh * peak
    first = 0
    while first < len(samples) and abs(samples[first]) < t:
        first += 1
    last = len(samples) - 1
    while last > first and abs(samples[last]) < t:
        last -= 1
    if first >= last:
        return samples
    pad = int(pad_ms * rate / 1000.0)
    return samples[max(0, first - pad):min(len(samples), last + 1 + pad)]


def delta_encode(u8, step):
    """Delta-Modulation, fester Schritt -- exakt wie der Decoder in speech.vhd."""
    acc = 128
    bits = []
    for u in u8:
        bit = 1 if u > acc else 0
        acc = acc + step if bit else acc - step
        acc = 0 if acc < 0 else 255 if acc > 255 else acc
        bits.append(bit)
    return bits


def delta_decode(bits, step):
    """Rekonstruktion wie speech.vhd -- fuer die Preview-WAV."""
    acc = 128
    out = []
    for b in bits:
        acc = acc + step if b else acc - step
        acc = 0 if acc < 0 else 255 if acc > 255 else acc
        out.append(acc)
    return out


def write_wav(path, u8, rate):
    """8-Bit-PCM (0..255, Mitte 128) als 16-Bit-Mono-WAV schreiben (Preview)."""
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        frames = bytearray()
        for u in u8:
            s = (u - 128) * 256
            s = 32767 if s > 32767 else -32768 if s < -32768 else s
            frames += struct.pack("<h", s)
        w.writeframes(bytes(frames))


def write_mif_pcm(path, u8, depth):
    """8-Bit-PCM-.mif (WIDTH=8). Rest mit 128 (=Mittelpegel/Stille) fuellen --
    NICHT 0, das waere -128 = lauter DC-Knall am ROM-Ende."""
    if len(u8) > depth:
        u8 = u8[:depth]
    with open(path, "w", newline="\n") as f:
        f.write("-- erzeugt von tools/make_speech_mif.py -- 8-Bit-PCM, %d aktive Samples\n" % len(u8))
        f.write("WIDTH=8;\nDEPTH=%d;\nADDRESS_RADIX=DEC;\nDATA_RADIX=UNS;\n" % depth)
        f.write("CONTENT BEGIN\n")
        for i, v in enumerate(u8):
            f.write("%d : %d;\n" % (i, v))
        if len(u8) < depth:
            f.write("[%d..%d] : 128;\n" % (len(u8), depth - 1))   # Rest = Stille
        f.write("END;\n")


def write_mif(path, bits, depth):
    if len(bits) > depth:
        bits = bits[:depth]
    with open(path, "w", newline="\n") as f:
        f.write("-- erzeugt von tools/make_speech_mif.py -- %d aktive Samples\n" % len(bits))
        f.write("WIDTH=1;\nDEPTH=%d;\nADDRESS_RADIX=DEC;\nDATA_RADIX=BIN;\n" % depth)
        f.write("CONTENT BEGIN\n")
        for i, b in enumerate(bits):
            f.write("%d : %d;\n" % (i, b))
        if len(bits) < depth:
            f.write("[%d..%d] : 0;\n" % (len(bits), depth - 1))  # Rest = Stille
        f.write("END;\n")


def main():
    ap = argparse.ArgumentParser(description="WAV -> 1-Bit-Delta-.mif fuer speech.vhd")
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--in", dest="infile", help="Eingangs-WAV (8/16-Bit PCM)")
    src.add_argument("--tone", type=float, help="Test-Ton statt WAV: Frequenz in Hz")
    ap.add_argument("--secs", type=float, default=0.4, help="Dauer fuer --tone (s)")
    ap.add_argument("--out", default="rom/lisy.mif", help="Ausgabe-.mif")
    ap.add_argument("--rate", type=int, default=16000, help="Ziel-Samplerate (= SAMPLE_HZ)")
    ap.add_argument("--step", type=int, default=6, help="Delta-Schritt (== Generic STEP!)")
    ap.add_argument("--depth", type=int, default=8192, help="ROM-Tiefe (Worte)")
    ap.add_argument("--lead-ms", type=float, default=0.0, help="Vorlauf-Stille (Amp-Unmute)")
    ap.add_argument("--smooth", type=int, default=1, help="Tiefpass: Moving-Average-Fenster (ungerade, 1=aus)")
    ap.add_argument("--no-normalize", action="store_true", help="nicht normalisieren")
    ap.add_argument("--no-trim", action="store_true", help="Stille am Anfang/Ende nicht entfernen")
    ap.add_argument("--trim-thresh", type=float, default=0.02, help="Trim-Schwelle (Anteil vom Peak); kleiner = mehr Ausklang bleibt")
    ap.add_argument("--pad-ms", type=float, default=8.0, help="Pad um den getrimmten Bereich (ms); groesser = mehr Decay/Tail")
    ap.add_argument("--fade-out-ms", type=float, default=0.0, help="Ausblendung der letzten ms (sanftes Wortende, kein Klick)")
    ap.add_argument("--pcm", action="store_true", help="--out als 8-Bit-PCM-.mif schreiben (statt 1-Bit-Delta); fuer PCM-Decoder in speech.vhd")
    ap.add_argument("--preview-wav", help="zusaetzlich Preview-WAV (rekonstruiert = DAC-Klang)")
    ap.add_argument("--pcm-preview", help="Referenz-Preview als 8-Bit-PCM (kein Delta-Codec) -- zeigt sauberen Zielklang")
    args = ap.parse_args()

    if args.tone is not None:
        samples = make_tone(args.tone, args.secs, args.rate)
    else:
        samples, fr = read_wav_mono_float(args.infile)
        samples = resample_linear(samples, fr, args.rate)
        if not args.no_trim:
            samples = trim_silence(samples, args.rate, thresh=args.trim_thresh, pad_ms=args.pad_ms)

    if args.smooth > 1:
        samples = smooth_movavg(samples, args.smooth)

    if not args.no_normalize:
        samples = normalize(samples)

    if args.fade_out_ms > 0:
        samples = fade_out(samples, args.rate, args.fade_out_ms)

    lead = int(args.lead_ms * args.rate / 1000.0)
    u8 = [128] * lead + to_u8(samples)

    if len(u8) > args.depth:
        print("WARN: %d Samples > DEPTH %d -> wird abgeschnitten" % (len(u8), args.depth))

    n = min(len(u8), args.depth)

    if args.pcm:
        write_mif_pcm(args.out, u8, args.depth)
        print("OK: %s geschrieben (8-Bit-PCM)" % args.out)
        print("    Samplerate : %d Hz   CLK_DIV = 50e6/%d = %d" % (args.rate, args.rate, round(50_000_000 / args.rate)))
        print("    N_SAMPLES  : %d   <-- Generic in speech.vhd setzen" % n)
        print("    Dauer      : %.3f s   ROM : %d/%d Worte x8 Bit (%d M9K)"
              % (n / args.rate, n, args.depth, (args.depth + 1023) // 1024))
    else:
        bits = delta_encode(u8, args.step)
        write_mif(args.out, bits, args.depth)
        print("OK: %s geschrieben" % args.out)
        print("    Samplerate : %d Hz   STEP : %d" % (args.rate, args.step))
        print("    N_SAMPLES  : %d   <-- diesen Wert als Generic in speech.vhd setzen" % n)
        print("    Dauer      : %.3f s   ROM : %d/%d Bit belegt" % (n / args.rate, n, args.depth))

        if args.preview_wav:
            write_wav(args.preview_wav, delta_decode(bits[:n], args.step), args.rate)
            print("    Preview    : %s  (rekonstruiert = so klingt das ROM ueber den DAC)" % args.preview_wav)

    if args.pcm_preview:
        # 8-Bit-PCM-Referenz (ohne Delta-Codec): zeigt den sauberen Zielklang bei
        # gleicher Rate. ROM-Bedarf waere hier 8 Bit/Sample statt 1.
        write_wav(args.pcm_preview, u8, args.rate)
        print("    PCM-Ref    : %s  (8-Bit-PCM, kein Delta -- sauberer Referenzklang)" % args.pcm_preview)


if __name__ == "__main__":
    main()
