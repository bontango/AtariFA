# Machbarkeitsanalyse — Boot-Sprachausgabe „Lisü"

**Datum:** 2026-06-21 (Analyse) · 2026-06-22 (Umsetzung)  ·  **Status:** ✅ IMPLEMENTIERT
**Ziel:** Beim Boot ein kurzes Wort („Lisü") als „Roboterstimme" (80er-Stil) ausgeben.
Die ursprüngliche Analyse optimierte auf **minimalen Logik- und ROM-Verbrauch** und empfahl
1-Bit-Delta-Modulation. In der Umsetzung erwies sich deren Rauschen als zu stark → final
**8-Bit-PCM @ 8 kHz** (siehe Abschnitt **„Umsetzung"** unten). Das Modul ist wiederverwendbar
über mehrere Platinen (FPGA + RC-Tiefpass + TDA7267).

> **TL;DR Umsetzung:** Nicht Delta (Empfehlung der Analyse), sondern **PCM 8-Bit @ 8 kHz**,
> 4 M9K, `speech.vhd`/`speech_rom.vhd`, ROM `rom/lisy.mif`. Grund: Delta-Quantisierungsrauschen
> bei der nötigen kurzen Wortlänge zu hörbar (zu geringe Überabtastung). Details: §11.

---

## 1. Anforderungen & Randbedingungen

| Punkt | Wert |
|---|---|
| Wort | „Lisy" (≈ /ˈlɪzi/), 1 Silbe + Auslaut |
| Aktive Dauer | **≈ 0,5 s** (Annahme; 0,4–0,6 s realistisch) |
| Qualität | „Roboterstimme", nur **erkennbar**, keine HiFi-Anforderung |
| Bandbreite | ≈ 2–3 kHz reicht für ein bekanntes Einzelwort |
| Logik | **so klein wie möglich** (oberste Priorität) |
| ROM | **so klein wie möglich** (zweite Priorität) |
| Portabilität | eigenständiges Modul, ROM per `altsyncram` (init aus `.mif`/`.hex`) |

---

## 2. Bestehende Hardware — was wiederverwendet wird

Die Sound-Emulation (`sound.vhd`) liefert bereits eine **komplette 1-Bit-Audio-Ausgabekette**,
die das Sprachmodul **unverändert mitbenutzen** kann:

```
 8-Bit-PCM ──► First-Order-Sigma-Delta-DAC @ 50 MHz ──► snd_pwm ──► SB_Sound ──► RC 3k3/4n7 ──► TDA7267 ──► LS
              (sound.vhd:133-149)                       (AtariFA.vhd:449)        fc ≈ 10 kHz
```

- Der Sigma-Delta-Akku (`sd_acc`, 9 Bit, `sound.vhd:145`) wandelt einen 8-Bit-PCM-Wert mit
  50-MHz-Oversampling in ein sauberes 1-Bit-PWM-Signal. **Genau dieser Wandler ist die
  „teure" Audio-Komponente — und er existiert schon.**
- **Konsequenz:** Das Sprachmodul muss intern nur einen **8-Bit-PCM-Strom** (oder etwas, das
  sich billig dorthin dekodieren lässt) erzeugen. Der DAC, Filter und Verstärker sind „kostenlos".
- Die RC-Eckfrequenz (≈10 kHz) deckt jede Sprach-Samplerate bis ~8 kHz problemlos ab.

**Integration ist trivial vorbereitet:** Es gibt bereits ein Boot-Fenster — `boot_phase(2)`
hält die CPU für `INFO_SHOW_CYCLES` = 5 s zurück, während die Versions-/Config-Infoanzeige läuft
(`AtariFA.vhd:276`, `:463-476`). Das Wort wird in genau diesem Fenster abgespielt und `SB_Sound`
per Mux umgeschaltet (siehe §6).

---

## 3. Codec-Optionen im Vergleich (für „Lisy" ≈ 0,5 s)

ROM-Rechnung: `Bits = Samplerate × Dauer × Bit/Sample`. M9K-Block der Cyclone 10 LP = **8192
nutzbare Datenbits**. Derzeit belegt: **22/30 M9K → 8 M9K (64 kbit) frei**. Device hat 6272 LE,
aktuell ~1834 LE (29 %) belegt → Logik ist unkritisch, ROM ist die knappere Ressource.

| # | Verfahren | Bit/Sa | Rate | Rohdaten | **M9K** | **Decoder-LE** | Klang | Bewertung |
|---|---|--:|--:|--:|:--:|:--:|---|---|
| 1 | PCM 8-Bit | 8 | 8 kHz | 32,0 kbit | **4** | ~40 | gut | ROM zu groß |
| 2 | PCM 8-Bit | 8 | 6 kHz | 24,0 kbit | **3** | ~40 | gut | simpel, aber ROM-hungrig |
| 3 | PCM 4-Bit (companded) | 4 | 6 kHz | 12,0 kbit | **2** | ~50 | ok/rau | brauchbar |
| 4 | **ADPCM 4-Bit (IMA)** | 4 | 8 kHz | 16,0 kbit | **2** | ~200 + Tab. | gut | beste Qualität/Größe |
| 5 | ADPCM 2-Bit | 2 | 8 kHz | 8,0 kbit | **1** | ~150 + Tab. | rau | gut komprimiert |
| 6 | **Delta-Mod, fester Schritt** | 1 | 16 kHz | 8,0 kbit | **1** | **~25** | „robotisch" | **Min-Logik + Min-ROM** |
| 6b | Delta-Mod, fester Schritt | 1 | 24 kHz | 12,0 kbit | 2 | ~25 | etwas klarer | |
| 7 | **CVSD (adaptiver Schritt)** | 1 | 16 kHz | 8,0 kbit | **1** | ~100 | besser verständlich | bester 1-Bit-Klang |
| 8 | PDM-Passthrough (vorgerechnet) | 1 | 128 kHz | 64,0 kbit | **8** | ~15 | gut | ROM gigantisch |
| 9 | LPC (TMS5220-Stil) | — | ~2,4 kbit/s | ~1,2 kbit | <1 | ~400–600 + 1 DSP | „echter" Speak&Spell | ROM winzig, **Logik/Aufwand groß** |

**Lesehilfe der Eckpunkte:**
- **Logik-Minimum** = PDM-Passthrough (nur Zähler) → aber 8 M9K ROM, fällt raus.
- **ROM-Minimum** = LPC → aber 400–600 LE + Multiplizierer + hoher Entwurfs-/Tuning-Aufwand für
  ein einzelnes Wort → unwirtschaftlich.
- **Schnittmenge „beides klein"** = **Delta-Modulation / CVSD** (Zeilen 6/7): 1 M9K **und**
  ~25–100 LE. Klanglich ist genau das die gesuchte 80er-Roboterstimme.

---

## 4. Bewertung der drei Top-Kandidaten

### A) Delta-Modulation, fester Schritt (1-Bit DPCM) — **Logik- & ROM-Minimum**
Decoder = ein **Auf/Ab-Akkumulator**: pro Sample-Takt ein ROM-Bit; `1` → `acc += step`,
`0` → `acc -= step` (mit Clamping). `acc` (8 Bit) geht direkt in den vorhandenen Sigma-Delta-DAC.
- **Logik:** Sample-Ratenteiler (~12 Bit) + Adresszähler (~13 Bit) + 8-Bit-Akku + Endeerkennung ≈ **25–40 LE**.
- **ROM:** 1 Bit × 8000 ≈ **8 kbit = 1 M9K** (altsyncram im 8192×1-Modus).
- **Klang:** körnig/buzzig durch Slope-Overload — **passt exakt zur Roboterstimme**.
- **Encoder:** ~10 Zeilen Python (offline), siehe §7.

### B) CVSD (Continuously Variable Slope Delta) — **bester 1-Bit-Klang**
Wie A, aber mit **syllabischer Schrittweiten-Anpassung**: ein 3–4-Bit-Schieberegister erkennt
Bitläufe (`000`/`111`); bei langem Lauf wird `step` erhöht (Slope-Overload vermeiden), sonst
zerfällt es (Leck-Integrator). Das ist das klassische 80er-Sprach-/Funk-Verfahren (CVSD-ICs).
- **Logik:** A + Lauf-Detektor + Schritt-Register/Leck ≈ **~100 LE**.
- **ROM:** identisch zu A (**1 M9K** @16 kHz).
- **Klang:** deutlich verständlicher als fester Schritt, weiterhin „retro".

### C) PCM 8-Bit @ 6 kHz — **absolut simpelste Logik, wenn ROM egal**
Reine Wertabspielung: Adresszähler → ROM-Wert (8 Bit) → Sigma-Delta-DAC. Kein Codec.
- **Logik:** Adresszähler + Ratenteiler ≈ **~40 LE** (kein Akku/Adaption).
- **ROM:** **3 M9K** — der Preis für „kein Codec".
- **Klang:** am saubersten, aber 3× so viel ROM wie A/B.

---

## 5. Empfehlung

> **Primär: Delta-Modulation mit festem Schritt (Kandidat A), 1 Bit @ 16 kHz.**
> Sie ist als einzige Option **gleichzeitig** Logik-minimal (~25–40 LE) **und** ROM-minimal
> (1 M9K / 8 kbit) und trifft den gewünschten Roboterstimmen-Klang ohne Zusatzaufwand.
>
> **Upgrade-Pfad bei zu schlechter Verständlichkeit: CVSD (Kandidat B)** — gleicher ROM-Bedarf,
> nur ~+60–80 LE. Der Wechsel A→B ändert **nur den Decoder-Prozess**, nicht die Schnittstelle
> oder das ROM-Format-Prinzip (beides 1 Bit/Sample).

PCM (C) nur wählen, wenn 3 M9K akzeptabel sind und maximale Klangtreue erwünscht ist. LPC (9)
und PDM-Passthrough (8) sind für diesen Anwendungsfall **nicht** empfohlen (Aufwand bzw. ROM).

**Beide Achsen-Budgets sind bei A/B unkritisch:** +1 M9K (→ 23/30) und ≤100 LE (von 6272).

---

## 6. Vorgeschlagene Modul-Architektur

Eigenständiges, portables Modul `speech.vhd` — minimal, ohne Bus-Anbindung, rein über
Start-Trigger gesteuert.

```
                         speech.vhd
   start ──►┌───────────────────────────────────────────┐
   clk_50 ─►│ Ratenteiler 50MHz→16kHz  (sample_tick)     │
   reset ──►│ Adresszähler 0..N-1 ──► altsyncram (1×8192) │──► rom_bit
            │ Delta-Akku: ±step (clamp)  ──► pcm[7:0]     │──► pcm
            │ Sigma-Delta-DAC @50MHz (wie sound.vhd)      │──► speech_pwm
            │ busy = '1' während Abspielen                │──► busy
            └───────────────────────────────────────────┘
```

**Entity-Vorschlag:**
```vhdl
entity speech is
  generic (
    INIT_FILE   : string  := "lisy.mif";  -- 1-Bit-Delta-Strom
    N_SAMPLES   : integer := 8000;         -- Wortlänge in Samples
    CLK_HZ      : integer := 50_000_000;
    SAMPLE_HZ   : integer := 16_000;
    STEP        : integer := 6             -- Delta-Schrittweite (Tuning)
  );
  port (
    clk_50  : in  std_logic;
    reset   : in  std_logic;
    start   : in  std_logic;   -- 1 Puls -> Wort einmal abspielen
    busy    : out std_logic;
    pwm_out : out std_logic    -- direkt auf SB_Sound muxbar
  );
end entity;
```

**Integration in `AtariFA.vhd` (analog zum bestehenden Sound-Mux, `:449`):**
```vhdl
-- Start an der Vorderflanke von boot_phase(1) (DIP-Read fertig, Info-Fenster beginnt):
speech_start <= boot_phase(1) and not boot_phase(1_d1);  -- 1-Takt-Puls

-- Ausgabe-Mux: im Boot spricht das Sprachmodul, danach normale Sound-Emulation.
SB_Sound <= speech_pwm when speech_busy = '1'
       else snd_pwm    when options(3) = '0'
       else '0';
```
Das Wort fällt damit in die ohnehin vorhandenen ~5 s Info-Anzeige (`INFO_SHOW_CYCLES`,
`AtariFA.vhd:276`) — kein zusätzliches Boot-Delay, keine CPU-Beeinflussung.

---

## 7. Offline-Erzeugung der ROM-Daten (Toolchain)

Passend zur 80er-Roboterstimme bietet sich **`espeak`** als Quelle an — es klingt von Haus aus
„maschinell" und ist deterministisch reproduzierbar.

```bash
# 1) Wort robotisch erzeugen, mono, auf Ziel-Samplerate
espeak -v en "Lisy" -w lisy_raw.wav
sox lisy_raw.wav -r 16000 -c 1 -b 16 lisy_16k.wav   # downsample, mono

# 2) Delta-Encode -> .mif  (Python, ~10 Zeilen, Kern):
#    acc=128; for s in samples: bit = 1 if s>acc else 0
#             acc += STEP if bit else -STEP; acc=clamp(acc,0,255); emit(bit)
#    (STEP identisch zur Generic STEP im VHDL setzen!)
```
Python-Encoder-Kern:
```python
STEP, acc, bits = 6, 128, []
for s in pcm8:                       # pcm8 = 0..255, 16 kHz, mono
    bit = 1 if s > acc else 0
    acc = max(0, min(255, acc + (STEP if bit else -STEP)))
    bits.append(bit)
# bits -> Quartus .mif (DEPTH=len(bits), WIDTH=1) schreiben
```
- **Wichtig:** `STEP` im Encoder == `STEP`-Generic im VHDL, sonst stimmt die Rekonstruktion nicht.
- `.mif`/`.hex` wird wie bei `game_rom.vhd` per `altsyncram`-`init_file` eingebunden — gleiche,
  bereits erprobte Projekt-Konvention.
- Für CVSD (Kandidat B) wird derselbe Loop um die Schrittweiten-Adaption ergänzt; Encoder und
  Decoder müssen die Adaptions-Regel teilen.

---

## 8. Budget-Check gegen 10CL006YE144C8G

| Ressource | Verfügbar | Aktuell | + Sprachmodul (A) | Ergebnis |
|---|---|---|---|---|
| M9K (BRAM) | 30 | 22 | **+1** | 23/30 (77 %) ✓ |
| Logikzellen | 6272 | ~1834 | **+25…40** | < 30 % ✓ |
| Multiplizierer | 15 | 1 | +0 | ✓ |
| PLL | 2 | 1 | +0 | ✓ |
| Pins | 89 | 85 | +0 (nutzt `SB_Sound`) | ✓ |

Kein zusätzlicher Pin nötig (Mitnutzung des vorhandenen `SB_Sound`-Pfads). Selbst CVSD (+~100 LE)
oder PCM (+2 M9K) blieben im Budget.

---

## 9. Risiken & HW-Vorbehalte

1. **Pegel/Lautstärke:** Der Delta-/CVSD-Akku sollte um 128 (Mittelpegel) zentriert bleiben;
   `STEP` ist der einzige Tuning-Hebel für Aussteuerung vs. Slope-Overload. Empirisch einstellen.
2. **Knackser beim Mux-Umschalten** Boot→Spiel: `SB_Sound` am Wortende sauber auf den Mittelwert
   (`pwm` aus „acc=128") bzw. auf `'0'` führen, bevor umgeschaltet wird.
3. **Wortlänge ↔ ROM:** Tabelle rechnet mit 0,5 s. Jede +0,1 s kostet bei 16 kbit/s ≈ 1,6 kbit;
   ab ~0,5 s (8 kbit) ist 1 M9K voll, danach 2 M9K. `N_SAMPLES`-Generic nachziehen.
4. **TDA7267 / Verstärker-Verhalten beim Boot:** Falls der Amp eine Einschalt-/Mute-Phase hat,
   kann der Wortanfang abgeschnitten werden → ggf. 100–200 ms Stille als Vorlauf ins ROM legen.
5. **Verständlichkeit bei fester Schrittweite:** Wenn „Lisy" zu undeutlich klingt, zuerst Rate
   auf 24 kHz (Zeile 6b, 2 M9K) erhöhen; bringt das nichts → auf CVSD (B) wechseln.

---

## 10. Fazit

Die Boot-Sprachausgabe ist mit der vorhandenen Hardware **klar machbar und günstig**: Der teure
Teil (Sigma-Delta-DAC + RC + TDA7267) existiert bereits und wird mitbenutzt. Für „Lisy" als
Roboterstimme ist **1-Bit-Delta-Modulation @ 16 kHz** die Lösung mit dem **gemeinsamen Minimum aus
Logik (~25–40 LE) und ROM (1 M9K / 8 kbit)**; CVSD ist der low-cost Qualitäts-Upgrade-Pfad bei
identischem ROM-Bedarf. Das Modul ist als eigenständiges `speech.vhd` (ROM per `altsyncram`)
über andere Platinen hinweg wiederverwendbar und fügt sich verlustfrei in das bestehende
`boot_phase`-/`SB_Sound`-Konzept ein.

---

## 11. Umsetzung (2026-06-22) — final: 8-Bit-PCM statt Delta

Die Analyse empfahl 1-Bit-Delta-Modulation (Logik-/ROM-Minimum). In der praktischen Umsetzung
klang das **deutlich verrauscht**. Ursache: Delta-Modulation braucht hohe **Überabtastung**
(OSR), um leise zu sein; bei der für „Lisü" nötigen kurzen Wortlänge und ~3 kHz Sprachbandbreite
lag die OSR zu niedrig (bei 10 kHz nur ~1,7×). Eine **niedrigere** Rate verschlechtert das Delta-
Rauschen sogar (weniger OSR). Höhere Rate (16/24/32 kHz) half hörbar, kostet aber ROM — und da
**Speicher nicht der Engpass war** (7 M9K frei), fiel die Wahl auf den saubersten, einfachsten Weg:

> **Final: 8-Bit-PCM @ 8 kHz.** Sauberster Klang, **einfacherer** Decoder (kein Delta-Akku),
> Preis = 4 M9K statt 1.

**Vergleich (gemessen, gleiche Quelle „Lisü", ~0,46 s):**

| Verfahren | Rauschen | ROM | Entscheidung |
|---|---|--:|---|
| Delta 10 kHz (1 Bit) | stark | 1 M9K | verworfen (zu verrauscht) |
| Delta 16/24/32 kHz | ↓ mit Rate | 1–2 M9K | besser, aber PCM klarer |
| **PCM 8-Bit @ 8 kHz** | **am saubersten** | **4 M9K** | **✅ gewählt** |
| PCM 8-Bit @ 16 kHz | sehr sauber | 8 M9K | unnötig (BRAM fast voll) |

**Konkrete Umsetzung:**
- **`speech.vhd`** — Adresszähler + Sample-Ratenteiler + First-Order-Sigma-Delta-DAC (identisch
  zu `sound.vhd`). Generics `N_SAMPLES=3687` (0,461 s), `CLK_DIV=6250` (=50e6/8000). Kein `STEP`.
- **`speech_rom.vhd`** — `altsyncram` 4096×8 (12-Bit-Adresse) = **4 M9K**.
- **`rom/lisy.mif`** — 8-Bit-PCM (WIDTH=8); ungenutzte Worte = **128 (Stille)**, NICHT 0
  (=-128 = DC-Knall). Wortende per **Fade-Out 35 ms** auf ~128 ausgeblendet (espeak kappt Vokale
  hart bei ~60 % → sonst „abgeschnitten"/Klick).
- **Integration `AtariFA.vhd`** (Instanz `SPEECH_INST`): `reset => not boot_phase(0)` —
  **wichtig:** NICHT `por_active`/`reset_h`, die sind während des gesamten Info-Fensters aktiv
  und würden Speech bei der Wiedergabe im Reset halten. `start => boot_phase(1)` (Pegel; internes
  Edge-Detect). Ausgabe-Mux mit Vorrang:
  `SB_Sound <= speech_pwm when speech_busy='1' else snd_pwm when options(3)='0' else '0'`.
- **Encoder `tools/make_speech_mif.py`** (pure stdlib; `tools/` ist gitignored): erzeugt das `.mif`
  aus einer WAV. Relevante Optionen: `--pcm`, `--fade-out-ms`, `--smooth` (Moving-Avg-LPF),
  `--trim-thresh`, `--pad-ms`, `--pcm-preview`. Quelle via espeak (deutsch):
  `espeak -v de -s 135 "[[l'i:zy]]"` (= /liːzy/, langes i, kurzes ü).
- **Finaler Erzeugungs-Befehl:**
  ```sh
  espeak -v de -s 135 -w speech_source_shortU.wav "[[l'i:zy]]"
  python tools/make_speech_mif.py --in speech_source_shortU.wav --out rom/lisy.mif \
         --rate 8000 --pcm --fade-out-ms 35 --depth 4096
  ```

**Ergebnis Compile (2026-06-22):** 0 Fehler / 0 Critical Warnings, **BRAM 26/30 M9K** (−1 Delta
+4 PCM), LE 30 % (sogar weniger als Delta — PCM-Decoder ist simpler), Timing erfüllt.

**Offen (HW):** Klangtest am echten Board; falls der TDA7267 eine Mute-/Einschaltphase hat und den
Wortanfang kappt → `--lead-ms` Vorlauf-Stille ins ROM legen (Risiko-Punkt §9.4).
