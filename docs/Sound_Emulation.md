# Atari Gen1 Sound — Schaltungsanalyse & FPGA-Emulation

> Analyse-Session 2026-06-21. Vermisst die **originale Tonerzeugung** der Atari-Gen1-MPU aus den
> Schaltplänen (Prozessor-PCB + Auxiliary-PCB) und leitet daraus das neue Modul
> [`sound.vhd`](../sound.vhd) ab.
>
> Zugehörige Schaltbilder:
> [`Display_Logic.png`](Display_Logic.png) (Processor PCB, Section H, Sheet 15B) und
> [`Auxiliary_PCB.png`](Auxiliary_PCB.png) (Auxiliary PCB 006407-01, Sheet 15A)
> (*The Atarians / Time 2000 / Airborne Avenger, 1978*).

---

## 1. Ausgangslage

Die AtariFA-Platine ersetzt die **Prozessor-PCB** vollständig. Auf der Original-Prozessor-PCB
sitzt das Sound-ROM **`D12`** mitsamt Zählern und Latches, das die Tonerzeugung übernimmt. Über
den Konnektor **J10 → J12** gehen **8 Soundsignale** zur **Auxiliary-PCB**, wo im Wesentlichen
die D/A-Wandlung und Verstärkung stattfinden.

Ziel dieser Session: die Funktion der beteiligten Signale aus den Schaltplänen verifizieren und
ein **vereinfachtes, klanggleiches** FPGA-Modell bauen — kein 1:1-Gatternachbau.

---

## 2. Die Originalschaltung

### 2.1 Prozessor-PCB (Sheet 15B)

| Block | Bauteil | Funktion |
|---|---|---|
| **Sound-ROM** | `D12` (82S130, 512×4) | Wellenformspeicher; 4 Datenausgänge `O1–O4` → `AUDIO 0–3`. |
| **Pitch-Teiler** | `D13` (74LS9316 = 74163, synchron) | Mit `Latch 1088` per `P0–P3` vorgeladen; zählt `AUDIO CLK`, `TC` bei Überlauf → Teiler `(16 − Latch1088)`. |
| **Sample-Zähler** | `E12`/`E13` (74LS93) | Von `D13`-`TC` getaktet; treibt die unteren ROM-Adressen `A0–A4`. |
| **Master-Takt** | `7493`-Kette (oben links, erzeugt auch NMI/DMA) | `AUDIO CLK` = `Ø1 ÷ 2` (≈ 500 kHz). |

**Die drei Sound-Latches** (jeweils nur **Bits 0–3** = Sound; Bits 4–7 dienen den Solenoiden):

| Adresse | Ziel | Funktion |
|---|---|---|
| **Latch 1080** Bit 0–3 | `D12` Adresse `A5–A8` | **Wellenform-Auswahl** (16 Wellenformen) |
| **Latch 1088** Bit 0–3 | `D13` Preset `P0–P3` | **Tonhöhe** (Teiler `16 − Wert`) |
| **Latch 1084** Bit 0–3 | über J10 → Aux-PCB | **Lautstärke** (s. 2.2) |

D12-Datenausgänge (verifiziert): `O4`(Pin 9)→AUDIO 3, `O3`(Pin 10)→AUDIO 2,
`O2`(Pin 11)→AUDIO 1, `O1`(Pin 12)→AUDIO 0.

### 2.2 Auxiliary-PCB (Sheet 15A)

| Block | Bauteil | Funktion |
|---|---|---|
| **Eingangspuffer Audio** | `C2` (7407, Open-Collector) | Puffert `AUDIO 0–3` vom J12. |
| **Wandler (DAC)** | gewichtete Widerstände → Summierpunkt Op-Amp | 4-Bit-D/A: `AUDIO 0–3` → analoge Stufe. |
| **Eingangspuffer Latch** | `D3` (7407) | Puffert `Latch 1084 Bit 0–3`. |
| **Lautstärke** | `D2` (CD4016, Analogschalter) + gewichtete R | `Latch 1084` schaltet R in den Verstärkerzweig = 4-Bit-Attenuator. |
| **Ausgangsstufe** | `5K`-Poti „VOL" → Op-Amp → Endstufe | → Lautsprecher. |

**Gewichteter R-DAC `AUDIO 0–3` (verifiziert, über `C2` 7407):**

| Signal | 7407-Pins | Widerstand | Gewicht |
|---|---|---|---|
| AUDIO 3 (MSB) | 13→12 | **R19 = 8.2 kΩ** | ×8 |
| AUDIO 2 | 5→6 | **R18 = 18 kΩ** | ×4 |
| AUDIO 1 | 11→10 | **R17 = 33 kΩ** | ×2 |
| AUDIO 0 (LSB) | 9→8 | **R16 = 68 kΩ** | ×1 |

Die Widerstände halbieren sich jeweils (68/33/18/8.2 kΩ) → klassischer **binär gewichteter DAC**:
der Summenstrom in den Op-Amp ∝ Binärwert von `AUDIO 0–3`. Der `D2`-Lautstärke-Zweig (`Latch 1084`)
nutzt dieselben Gewichte (R3=68K/R5=33K/R2=18K/R4=8.2K) → Verstärkung ≈ **linear** im `Latch1084`-Wert.

### 2.3 Signalfluss (Original)

```
            AUDIO CLK (Ø1/2)
                 │
   Latch 1088 ─► D13 (74163)  Teiler (16-pitch)
                 │ TC
   E12/E13 (74LS93) Sample-Zähler ─► A0..A4
                 │                              Latch 1080 ─► A5..A8
                 ▼
            D12 Sound-ROM (512×4) ─► O1..O4 = AUDIO 0..3
                 │  J10 ─► J12
   ── Aux-PCB ───┼──────────────────────────────────────────
                 ▼
   C2(7407) ─► R-DAC (68/33/18/8.2K) ─► Summierpunkt ─► Op-Amp
                                            ▲
   Latch 1084 ─► D3(7407) ─► D2(4016) ─► gewichtete R (Volume)
                 │
                 ▼  5K VOL ─► Endstufe ─► Lautsprecher
```

---

## 3. ROM-Analyse (`rom/82s130.hex`)

| | |
|---|---|
| Größe | 16 Intel-HEX-Records à 32 Byte = **512 Byte** (`0x000–0x1FF`) |
| Datenbreite | alle Werte `0x0–0xF` ⇒ **nur untere 4 Bit** genutzt (`82S130` = 512×4) |
| Struktur | **16 zusammenhängende 32-Byte-Blöcke** |

Jeder 32-Byte-Block ist eine **in sich geschlossene Wellenform** (eine volle Schwingung).
Beispiel Block 0 (`0x000–0x01F`):

```
06 05 04 02 01 01 00 00  00 01 01 02 04 05 06 08
0A 0B 0C 0E 0F 0F 0F 0F  0F 0F 0F 0E 0C 0B 0A 08
```

→ steigt von 6 ab auf 0 (Sample 6–8), auf 0xF (Sample 20–27), zurück auf 8 — ein voller Zyklus.

**Schlüsselerkenntnis:** **16 Wellenformen × 32 Samples**.
`Latch 1080` (4 Bit) = obere Adressbits (Wellenform), Sample-Zähler (5 Bit) = untere (Sample-Index).
⇒ **ROM-Adresse = `"0" & snd_select(4) & sample_cnt(5)`** (10 Bit, oberstes = 0 da 512 < 1024).

---

## 4. FPGA-Modell vs. Original

Wie beim Display interessiert das Aux-Board nur die **Wellenform an seinen Eingängen**, nicht deren
Erzeugung. Es genügt also, `AUDIO 0–3` + `Latch 1084` zeitrichtig zu **regenerieren**.

Vereinfachungen (bewusst, klangneutral):

| Original | FPGA (`sound.vhd`) |
|---|---|
| `D13`/`E12`/`E13` Ripple-Zähler | **synchrone Zähler** (Strategie wie 9-Bit-DMA-Zähler statt 7493-Kette) |
| `AUDIO ENABLE`/`AUDIO RESET` Logik | `snd_enable` **hält Pitch- und Sample-Zähler auf 0** (wie `CET` an `D13` + `R01/R02` an `E12`/`E13`) **und** zwingt die effektive Lautstärke auf 0 — beides für **beide** Ausgabepfade (s. §6.3) |
| analoger R-DAC auf Aux-PCB | im **Original-Pfad** beibehalten; im **Emulations-Pfad** 1-Bit-Sigma-Delta |
| `AUDIO CLK = Ø1/2` aus 7493-Kette | `clk_50 / C_AUDIO_DIV` (Default 100 → 500 kHz) |

**Tonfrequenz** ≈ `AUDIO_CLK / ((16 − pitch) · 32)` (≈ 977 Hz … 15.6 kHz).
`C_AUDIO_DIV` (Generic) ist der **einzige Tonhöhen-Tuning-Hebel**.

---

## 5. Modul `sound.vhd`

```
 clk_50 / C_AUDIO_DIV ─► audio_en (500 kHz)
                            │
   snd_pitch ─► Pitch-Teiler: cmp = 15 - pitch; step alle (cmp+1) audio_en
                            │ step
                 5-Bit Sample-Zähler (+1 je step, mod 32)         snd_select
                   └─ Neustart bei Wechsel von snd_select ◄────────────┘
                            │
   rom_addr = "0" & snd_select & sample_cnt ─► sound_rom (D12) ─► nibble(4)
                            │                                         │
            ┌── sample  = nibble  ────────────────► (Aux-Pfad, Top)   │
            └── pcm = 128 + (nibble-8)·snd_volume ─► Sigma-Delta ─► sb_pwm
```

| Element | Umsetzung |
|---|---|
| **D12-ROM** | `entity work.sound_rom` (`rom/82s130.hex`), Adresse s. o. |
| **AUDIO CLK** | Teiler `clk_50 / C_AUDIO_DIV`, 1-clk-Enable-Puls |
| **Pitch-Teiler** | `cmp := 15 − snd_pitch`; `step` wenn `pitch_cnt ≥ cmp` (Periode `16 − snd_pitch`) |
| **Sample-Zähler** | `unsigned(4 downto 0)`, `+1` je `step` (wrap mod 32); Reset bei `snd_select`-Wechsel |
| **Volume + DAC** | `pcm = 128 + (nibble−8)·volume`; 1.-Ordnung-Sigma-Delta @ clk_50 → `sb_pwm` |

Sigma-Delta: 50 MHz Oversampling gegen Onboard-RC (3k3 / 4n7, fc ≈ 10 kHz) ⇒ saubere Wandlung.
`volume = 0` ⇒ `pcm = 128` konstant ⇒ DC ⇒ AC-gekoppelt stumm.

Bibliotheks-Hinweis: `sound.vhd` nutzt **ausschließlich `numeric_std`** (Multiplikation
`signed·signed`) — der Konflikt mit `std_logic_unsigned` entsteht nur bei gleichzeitigem Import,
hier vermieden (eigenständiges Modul).

---

## 6. Integration in `AtariFA.vhd`

### 6.1 Latch-Dekodierung
- `sound_cs <= '1' when cpu_addr(15 downto 4) = x"108"` (0x1080–0x108F).
- Im clk_50-Write-Strobe-Prozess (fallende `cpu_clk`-Flanke, analog `ram_wren`) werden **Bits 3..0**
  je Adresse gelatcht: `0x1080→snd_select`, `0x1084→snd_volume`, `0x1088→snd_pitch`.
- **Überlappung RAM-Mirror** (`ram_cs_mirror` 0x1000–0x11FF): unkritisch — die I/O-Latches sind
  write-only, das Spiel liest sie nicht als RAM zurück.

### 6.2 Ausgabe-Mux per `options(3)` (active-low, im Spiel dynamisch umschaltbar)

| `options(3)` | DIP | Modus | Treibt |
|---|---|---|---|
| `'1'` | OFF | **Original** | `aux_audio <= not snd_sample`, `aux_audio_latch <= not snd_volume_eff` (Aux-PCB) |
| `'0'` | ON | **Emulation** | `SB_Sound <= snd_pwm` (Onboard RC + TDA7267); Aux-Ausgänge auf `(others => '1')` = Aux-Board sieht 0/0 |

`aux_audio`/`aux_audio_latch` sind **invertiert** wegen des 74HCT540 auf der AtariFA-Platine
(Konvention wie `disp_*`). Schaltplan-bestätigt (2026-08-03) aus `AtariFA_07_Final_Main_SCH.PDF`
und `..._Solenoids_SCH.PDF`: `F_Audio0..3` und `F_L1084_B0..3` laufen über **74HCT540**
(IC6/IC7 auf dem Main-Blatt, ein weiterer 540 auf dem Solenoid-Blatt für `F_Audio0`, `F_Audio2`,
`F_L1084_B0`, `F_L1080_B5`); nur `F_Sol_Enable` geht über den nicht invertierenden 74HCT541 (IC14).
`SB_Audio` = separater MP3/Background-Pfad — seit SW 0.3.0 die UART-Steuerleitung zum DFPlayer Mini
(Hintergrundmusik, s. [`Background_Music.md`](Background_Music.md)); mit der Ton-Emulation hier hat er
nichts zu tun.

> **`aux_audio_latch` ist 4 Bit**, nicht 6 — der frühere Hinweis auf `"00" & not snd_volume` und
> „Bit 5/4 prüfen" war veraltet (Port `AtariFA.vhd`, QSF-Pins nur `[3:0]`).

### 6.3 AUDIO ENABLE/RESET gilt für **beide** Pfade (Fix 2026-08-03, SW 0.1.1)

Bis SW 0.1.0 wirkte `snd_enable` nur über `eff_volume` und damit **ausschließlich auf `sb_pwm`**.
Der Aux-Pfad (`sample`, `snd_volume`) lief ungegated weiter ⇒ **lauter Dauerton am Aux-Board**,
sobald das Spiel einmal eine Lautstärke gesetzt hatte.

Ursache ist das Spielverhalten: **die „Sound aus"-Routine schreibt nur AUDIO RESET und lässt
`0x1084` stehen.** Airborne (`tools/airborne_listing.txt`):

```
7979:  STAA $6000     ; AUDIO ENABLE/RESET
797F:  ... STAA $1080 ; Wellenform
798D:  ... STAA $1088 ; Tonhoehe
7999:  ... STAA $1084 ; Lautstaerke
79A1:  RTS
79A2:  STAA $6000     ; "Sound aus" -- NUR AUDIO RESET, $1084 bleibt stehen!
79A5:  RTS
```

Im Original ist das unkritisch, weil `AUDIO ENABLE`/`AUDIO RESET` an `CET` von `D13` und an
`R01/R02` von `E12`/`E13` hängen (Sheet 15B): Zähler stehen ⇒ ROM-Adresse konstant ⇒ `AUDIO 0–3`
statisch ⇒ reines DC ⇒ auf der Aux-PCB über `C9` weggekoppelt = still, **unabhängig vom
Lautstärke-Latch**. `sound.vhd` bildet das jetzt nach (Zähler-Freeze) und führt zusätzlich
`eff_volume` als `volume_out` heraus, das im Top den Aux-Attenuator speist.

---

## 7. Verifikation (Quartus Full Compile, 2026-06-21)

| | |
|---|---|
| Fehler | **0** (57 Warnings, alle vorbestehend bzw. `14320` = ROM `q[7:4]` wegoptimiert) |
| Timing | erfüllt: Setup-Slack ≥ **3,0 ns**, Hold ≥ **0,16 ns**, TNS 0,0 |
| BRAM | **22/30 M9K** (+1 für D12) |
| Logic | 29 % (1834 LE) |
| Mux | `aux_audio[3:0]`/`SB_Sound` = echte Logik (nicht stuck); nur `aux_audio_latch[4/5]` = gewollt Idle |

---

## 8. Offene HW-Feintuning-Punkte

- **Original-Pfad braucht aktiven 74HCT540** (`solenoids_enable`): solange disabled (Idle `'1'`),
  erreicht der Sound das Aux-Board nicht. Seit Phase B durch `solenoids_enable <= not reset_l_stable`
  freigegeben, sobald die CPU läuft.
- **`AUDIO ENABLE/RESET`**: ✓ erledigt, s. §6.3 — gilt seit SW 0.1.1 für beide Pfade. Falls ein Spiel
  Sounds jetzt *zu früh* abschneidet oder gar nicht mehr spielt, die per-Spiel-Semantik in
  `AtariFA.vhd` gegen `doc/atari.c` (`soundg1_w`/`audiog1_w`) und das ROM-Listing gegenprüfen.
- **Tonhöhe**: bei zu hohem/tiefem Klang `C_AUDIO_DIV` anpassen (Original ≈ cpu_clk/2).
- **Adress-/Volume-Bit-Reihenfolge**: bei „falschem" Klang 1-zeilig im ROM-Adress- bzw.
  Volume-Mapping tauschbar (PinMAME-Segment-/Bit-Indizes sind teils absteigend).

---

## 9. Quellen

- Schaltbilder: `Display_Logic.png` (Sheet 15B, Prozessor-PCB), `Auxiliary_PCB.png` (Sheet 15A) — dieses Verzeichnis
- Sound-ROM: `rom/82s130.hex` (D12, 512×4)
- Umsetzung: `../sound.vhd`, Integration in `../AtariFA.vhd`
- Speicher-Map-Referenz: PinMAME `src/wpc/atari.c`
