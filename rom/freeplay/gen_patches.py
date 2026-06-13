#!/usr/bin/env python3
"""
gen_patches.py — Freispiel-Patch-Generator/Validator fuer AtariFA.

Vergleicht jede Original-ROM (rom/<orig>.hex) mit ihrer Freispiel-Variante
(rom/freeplay/<orig+f>.hex) und gibt die geaenderten Bytes als VHDL-Eintraege
fuer die Konstante FP_PATCHES in AtariFA.vhd aus.

Hintergrund: Statt 6 zweite 2K-ROMs im BRAM zu halten (=+12 M9K, passt nicht auf
das 10CL006), werden nur die wenigen geaenderten Bytes per kombinatorischem Overlay
(fp_overlay-Prozess) ueberlagert, wenn options(3)=Freispiel aktiv ist (active-low).

Aufruf (aus dem Ordner rom/freeplay/ oder rom/):  python gen_patches.py
- Mit --check werden zusaetzlich Basis+Patch == Freeplay-ROM byteweise verifiziert.

Spielzuordnung (game-Index wie im VHDL-Mux):
  0=Atarians 1=Time2000 2=Airborne 3=MiddleEarth 4=SpaceRiders
Ersetzte ROM je Spiel: Atarians/Time/ME=ROM2 (slot 2), Airborne=ROM1 (slot 1),
SpaceRiders=ROM1+ROM2.
"""
import os
import sys

# (game, slot, basis-hex, freeplay-hex)  — Pfade relativ zum rom/-Ordner
PAIRS = [
    (0, 2, "atarian.e00.hex", "freeplay/atarianf.e00.hex"),  # Atarians  ROM2
    (1, 2, "time.e00.hex",    "freeplay/timef.e00.hex"),     # Time 2000 ROM2
    (2, 1, "airborne.e0.hex", "freeplay/airbornef.e0.hex"),  # Airborne  ROM1
    (3, 2, "609.hex",         "freeplay/609f.hex"),          # Middle Earth ROM2
    (4, 1, "spacel.hex",      "freeplay/spacelf.hex"),       # Space Riders ROM1
    (4, 2, "spacer.hex",      "freeplay/spacerf.hex"),       # Space Riders ROM2
]


def load(path):
    """Intel-HEX -> 2048-Byte-Image (8-bit ROM)."""
    img = bytearray(2048)
    with open(path, "r", encoding="latin-1") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith(":"):
                continue
            ll = int(line[1:3], 16)
            addr = int(line[3:7], 16)
            typ = int(line[7:9], 16)
            if typ != 0:                       # nur Data-Records
                continue
            img[addr:addr + ll] = bytes.fromhex(line[9:9 + 2 * ll])
    return img


def rom_dir():
    """Ordner 'rom' finden, egal ob aus rom/ oder rom/freeplay/ gestartet."""
    here = os.path.dirname(os.path.abspath(__file__))   # .../rom/freeplay
    return os.path.dirname(here)                          # .../rom


def main():
    check = "--check" in sys.argv
    root = rom_dir()
    all_ok = True
    total = 0
    print("-- FP_PATCHES (generiert von rom/freeplay/gen_patches.py)")
    for game, slot, base, fp in PAIRS:
        a = load(os.path.join(root, base))
        b = load(os.path.join(root, fp))
        diffs = [(i, b[i]) for i in range(2048) if a[i] != b[i]]
        total += len(diffs)
        tag = base.replace(".hex", "")
        addrs = ",".join(f"0x{i:03X}" for i, _ in diffs)
        print(f"  -- {tag} (game {game}, slot {slot}): {len(diffs)} Byte(s)  [{addrs}]")
        line = "  " + ",".join(f"({game},{slot},16#{i:03X}#,x\"{v:02X}\")" for i, v in diffs)
        print(line + ",")
        if check:
            patched = bytearray(a)
            for i, v in diffs:
                patched[i] = v
            if patched != b:
                all_ok = False
                print(f"  -- !! CHECK FEHLER: {tag}")
    print(f"-- Summe geaenderte Bytes: {total}")
    if check:
        print("-- CHECK: " + ("alle Basis+Patch == Freeplay-ROM (OK)" if all_ok
                              else "ABWEICHUNGEN gefunden!"))
        sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
