# AtariFA — Claude Code Projektkontext

## Projekt
FPGA-Nachbau der Atari Gen1 Pinball-MPU (MC6800 / John Kent cpu68).
Quartus Prime **22.1std.2 Lite Edition**. GitHub: https://github.com/bontango/AtariFA

## Build / Compile (Claude kann das selbst ausführen)
- **Full Compile (CLI):** `& "C:\intelFPGA_lite\22.1std\quartus\bin64\quartus_sh.exe" --flow compile AtariFA`
  (aus dem Projekt-Root; läuft ~Minuten — am besten `run_in_background`). `quartus_sh` liegt **nicht im PATH**;
  immer den vollen Pfad nutzen. Andere gefundene Installs (`C:\intelFPGA\23.1std\...`, `C:\altera\...`) sind
  nur **qprogrammer** (kein Compile-Flow) bzw. falsche Version → **nicht** verwenden.
- **Verifikation der Reports** (alle in `output_files/`): `AtariFA.map.rpt` (Analysis & Synthesis),
  `AtariFA.fit.rpt` (Fitter/Pins), `AtariFA.sta.rpt` (TimeQuest/Slack), `AtariFA.flow.rpt` (Flow-Status).
  Auf Warnings (z. B. 332174/332049/18236) und negative Slacks prüfen.
- **Zielplatine (AtariFA-PCB):** Cyclone 10 LP **10CL006YE144C8G** (E144) — „piggy-back"-Replacement-CPU mit RAM/ROM + TTL-Ersatz, parallel zu den Atari-Edge-Connectors plus „Box-Connectors". Migriert 2026-06; nur Display-Routinen übernommen, Rest (Switch/Lamps/Solenoide/Audio/FRAM/ESP32) step-by-step (Phase B/C).
- **Testplatine (vorher):** GottFA3 / Cyclone IV E EP4CE6F17C8 — Bring-up abgeschlossen 2026-06-06.

## Zielspiele
Generische Gen1-Basis: Atarians, Time 2000, Airborne Avenger, Middle Earth, Space Riders.
**Game-Select implementiert:** alle 5 Spiele liegen gleichzeitig im BRAM (je ROM1+ROM2 = 2K×8),
Auswahl per `game_select` (3-Bit-DIP, **active-low**). Generischer Wrapper `game_rom.vhd`
(altsyncram, init_file per Generic) 10× instanziiert; Ausgang per `game_idx = not game_select`
gemuxt (`AtariFA.vhd`). BRAM 21/30 M9K (70 %). Sound-ROM 82s130 separat.
- Decode: 0=Atarians, 1=Time, 2=Airborne, 3=Middle Earth (608/609, auch Fallback für 5–7),
  4=Space Riders. **HW-Vorbehalt:** Schalter↔Bit-Reihenfolge (Annahme Schalter1=game_select[0]=LSB)
  und Spielzuordnung auf Platine prüfen, im `case` leicht anzupassen.
- **HEX-Init-Warnung 113009** („data too wide … wrapping to subsequent addresses") ist
  **harmlos/format-inhärent**: Intel-HEX 32-Byte-Records (`:20…`) in 8-Bit-Speicher → korrekte
  byteweise Befüllung. Tritt für ALLE rom/*.hex auf (auch das HW-erprobte 608/609).
- **Freispiel-Option** (Signal `freeplay`, active-low; früher `options(3)`): statt 6 zweite ROMs
  (=+12 M9K, passt nicht) werden die nur **42 geänderten Bytes** kombinatorisch überlagert
  (`fp_overlay`-Prozess + Konstante `FP_PATCHES` in `AtariFA.vhd`) → **0 zusätzliches BRAM** (bleibt 21/30 M9K).
  Quelle der Patches: Diff `rom/<orig>` vs `rom/freeplay/<orig+f>.hex` (Freeplay-Hex nur Referenz,
  NICHT synthetisiert). Validiert: Basis+Patch == Freeplay-ROM byte-exakt. Ersetzte ROM je Spiel:
  Atarians/Time/MiddleEarth=ROM2, Airborne=ROM1, Space Riders=ROM1+ROM2.

## DIP-Konfiguration (10 Schalter, 2026-06-17)
Von 6 auf **10 DIPs** erweitert: **4er-Block** = 3× `game_select` + 1× `freeplay`; **6er-Block** = 6× `options`.
- **Boot-Read-Matrix:** die **ersten 6 DIPs** (3 game_select + freeplay + options(1..2)) werden im Boot
  über eine 3×2-Strobe-Matrix eingelesen — FSM in `read_the_dips.vhd`, die die Lampen-IOs
  `serin_595/clk_595/rclk_595` als Strobes **zweckentfremdet** (`dip_ret(0..1)` = Rückleitungen).
- **Direkt-Read:** DIPs 7–10 = `options(3..6)` über Top-Port `dip_opt(1..4)` direkt (im Spiel dynamisch änderbar).
- **Boot-Phasen** (`boot_phase`, 4 Bit, weitere geplant): `boot_phase(0)` = sync. `reset_sw` **und** FSM-Reset;
  `boot_phase(1)` = FSM-`done` (DIP-Read fertig) → treibt `disp_show` (Display an); `boot_phase(2)` = Info-Anzeige
  fertig → `reset_l_stable` (CPU-Release). Strobe-Mux gated auf **`boot_phase(1)='0'`**
  (DIP-Read-Fenster), danach gehen die Pins an die Lampen-Logik. FSM-Start zusätzlich über `por_active`
  gated (Read erst nach PLL-Lock). **`SW_MAIN/SUB1/SUB2`** werden jetzt in der Info-Phase angezeigt;
  `options` ansonsten noch reserviert.
- **`boot_phase(2)` — Version/Config-Infoanzeige (~5s):** nach dem DIP-Read und **vor** CPU-Start zeigt
  `display_control` für `INFO_SHOW_CYCLES`=5 000 000 cpu_clk (=5s @1MHz) die Konfiguration (rechtsbündig,
  `x"F"`=blank, Digit 6=Player-up-LED aus): **Disp1**=Version `SW_MAIN SW_SUB1 SW_SUB2`, **Disp2**=Game-Select
  `game_idx` (0–7) 2-stellig dezimal, **Disp3**=`options(1..6)` binär (Option1 links; ON wird als `'0'` gelesen
  → Anzeige `1`), **Disp4**=Freeplay (`'1'` wenn aktiv), **Status**=blank. Timer + `boot_info`-Prozess + DC-Eingangs-Mux
  (`bi_*`/`dc_*`) in `AtariFA.vhd`. `disp_show <= boot_phase(1)` (Display aktiv durch Info-Phase bis ins Spiel),
  `reset_l_stable <= boot_phase(2)`. **HW-Vorbehalt:** Ziffern-/Options-Reihenfolge (Index 5=rechts angenommen)
  bei Bedarf 1-zeilig im `boot_info`-Prozess tauschbar.
- **Pin-Umbenennung:** Top-Ports `game_select`/`options`/`reset_l` → `dip_ret`/`dip_opt`/`reset_sw`
  (siehe `AtariFA.qsf`). **✓ Erledigt:** `AtariFA.sdc(39)` auf `reset_sw` korrigiert (Warning 332174/332049
  behoben, `set_false_path` greift wieder). Zusätzlich `NUM_PARALLEL_PROCESSORS 14` in der QSF gesetzt
  (Warning 18236 weg). **Achtung:** Quartus erkennt auf dieser Maschine nur **14** Prozessoren (Windows
  meldet 20 logisch) → Wert >14 löst Warning **20031** (Über-Subskription) aus; daher 14, nicht 16.

## Wichtige Konventionen
- VHDL: `use ieee.std_logic_unsigned.all` — kein `numeric_std` (würde Konflikte erzeugen)
- Taktstrategie: `clk_50` = 50 MHz Systemtakt; `cpu_clk` = 1 MHz via PLL (`cpu_clock.vhd`, altpll ÷50)
- RAM-Write-Strobe immer in `clk_50`-Domain (fallende cpu_clk-Flanke per Edge-Detect auf `cpu_clk_d1/d2`)
- Open-Bus-Default: `cpu_din <= x"FF"` wenn keine CS aktiv
- Display-Outputs sind **invertiert** wegen 74HCT540-Treiber: `disp_* <= not i_disp_*`
- **Sichere Inaktiv-Pegel:** noch nicht implementierte Ausgänge werden in `AtariFA.vhd` **explizit** getrieben (nicht undriven lassen!) — Quartus-Default `'0'` würde über den invertierenden 74HCT540 die Solenoide EINschalten. Kern: `solenoids <= (others => '1')` (= MOSFET AUS), `oe_595 <= '1'` (aktiv-low). Block direkt nach den `disp_*`-Zuweisungen.
- **FRAM:** `fram_i2c_sda` ist `inout` (open-drain, idle `'Z'`, externer Pull-up) — I2C braucht bidirektionale SDA für ACK/Read; `fram_i2c_scl` bleibt `out`.
- SDC-Datei: `AtariFA.sdc`; `cpu_clk` (PLL clk[0]) wird als Datensignal in `clk_50` gesampled → `set_false_path` auf `cpu_clk_d1` (verhindert falsche Hold-Violations durch „clock-used-as-data")

## Architektur-Entscheidungen (nicht rückgängig machen ohne Grund)
- **Shadow-Buffer statt Dual-Port-RAM**: Schreibzugriffe auf RAM 0x00–0x1F werden per Write-Sniffer in `display1..4`/`status_d` kopiert (Single-Port-RAM bleibt für CPU)
- **DMA-Toggle**: `dma_toggle` flippt alle 2 NMI-Pulse (Edge-Detect auf `nmi_level`, Modulo-2 in clk_50-Prozess); Bit 6 von 0x2000 — Game-Code braucht diesen Wechsel zum Fortlaufen
- **Synchroner 9-Bit-Zähler** statt 3× SN7493-Ripple-Kaskade; NMI-Periode = 512 cpu_clk = 512 µs

## Offene Bugs (bewusst zurückgestellt)
- **B4**: Async-Inputs ohne Synchronizer — `sw_meta`/`sw_sync` (2-FF, clk_50) sind deklariert und werden
  gelesen (Test/Coin1/Coin2/Start), aber der **Sync-Prozess fehlt aktuell** → `sw_sync` bleibt konstant
  `'1'` (idle), Switch-Eingänge wirkungslos (Warning 10540, nur als Kommentar vermerkt). Switch-Design
  wird ohnehin an die neue AtariFA-HW angepasst (Phase B); `switch[5..16]`/`options[]`/`dip_*` ebenfalls offen.
- **B5**: ✓ adressiert — alle unimplementierten Ausgänge auf sicheren Inaktiv-Pegel getrieben (s.o. „Sichere Inaktiv-Pegel"). Offen nur noch echte Logik in Phase B/C.
- **B10–B12**: ✓ Teil-Cleanup — `DIAG_SEL`+`hex7seg` (GottFA3-SEG7-Reste) entfernt, `cpu_clk_gen.vhd` aus `.qsf` (toter Code; PLL `cpu_clock` wird genutzt). Display-Signal-Ownership noch offen.

## Watchdog-Status (offen)
- `reset_h` enthält **kein** `wd_reset` (bewusst entfernt): Game kickt 0x4000 nicht im Attract Mode → WD würde CPU resetten
- WD-Instanz bleibt aktiv (LED_D1 zeigt intern-Timeouts via `wd_seen`)
- Klären bei aktivem Spiel: ROM-Disassembly oder Schaltplan prüfen, ob/wann 0x4000 geschrieben wird
- **Nicht reaktivieren** bis Kick-Mechanismus verstanden

## Design-Verifikation Zielplatine (2026-06-13, vor Prototyp-Fertigung)
- Quartus Full Compile **0 Fehler**: Pins **85/89 (96 %)** — passt, nur ~4 Reserve; LEs 23 %, BRAM 13 %, 1/2 PLL.
- Timing erfüllt, keine negativen Slacks (Setup ≈5,97 ns, Hold ≈0,45 ns); PLL aus `clk_50` (PIN_23) sauber geroutet (÷50 → 1 MHz).
- **✓ Geklärt (2026-06-13):**
  - `solenoids_enable`-Polarität: `solenoids_enable`, `oe_595`, `clk_595`, `rclk_595`, `serin_595` laufen über den **74HCT541 (nicht invertierend)**; alle Datentreiber (Solenoide UND Aux-Board) sind **74HCT540 (invertierend)**. `solenoids_enable` → active-low `/OE` der 540 ⇒ **`solenoids_enable <= '1'`** = 540 disabled (Inaktiv-Pegel, in `AtariFA.vhd` korrigiert). Kommentar `:46` auf „74HCT540 (inverter)" gefixt.
  - 540-/OE-Default in Config: FPGA-Pins sind „input mit weak pull-up" → 541-Eingang high → 540 disabled; zusammen mit Gate-Pulldowns ausreichend, **kein** externer Pull am `solenoids_enable` nötig. Nur Device-&-Pin-Option „weak pull-up during configuration" (Default) bestätigen.
  - AN447 / 3,3-V-Interfacing: `sw_com_in` über **74HC4049 @ 3,3 V** = Level-Shifter (HC4049 hat keine Input-Clamp gegen VCC, 5-V-Eingang zulässig) ✅. `reset_l`/`game_select`/`options`: je **10 K Pull-up an 3,3 V, gegen GND geschaltet** (active-low) → reine 3,3-V-Domäne, kein 5-V-Pfad ✅. Damit alle FPGA-Eingänge ≤ VCCIO (10CL006 nicht 5-V-tolerant).

## Noch nicht implementiert (Roadmap)
- **Phase B**: Switch-Matrix real (0x2010–0x204F), Solenoid-Latches (0x1080/84/88/8C), Lamp-Matrix (RAM 0x30–0x3F)
  - ✓ 4 Switch-Eingänge verdrahtet (Commit `2d3cdd1`): `switch[1]`=Test→$200B, `[2]`=Coin1→$2010, `[3]`=Coin2→$2011, `[4]`=Start→$2013; auf GottFA3-Testboard verifiziert (Test/Coin1/Coin2 ✅, Start braucht Kugel-Erkennung)
  - ✓ Lamp-Driver gebaut: `lamp_driver.vhd` (84 Lampen → 11× TPIC6B595N, statisch gelatcht, Double-Buffer + Shift-FSM @ clk_50, ersetzt 9334+ULN2003A). RAM-0x30–0x3F-Sniffer analog Display-Shadow-Buffer.
  - Lamp-Driver in `AtariFA.vhd` noch **komplett auskommentiert** (Ports, `lamp_state`-Signal, Sniffer-Prozess, `LD`-Instanz) — auf Prototyp-HW gemeinsam mit vollständiger Switch-Matrix aktivieren + Pins in `.qsf`.
  - Noch offen: restliche Switch-Matrix (0x2014–0x204F), Solenoid-Latches
  - **Achtung Sound-Überlappung:** 0x1080/84/88 sind geteilte Latches — **Bits 0–3 = Sound**
    (bereits implementiert, s. „Sound"), **Bits 4–7 = Solenoide** (noch offen). Solenoid-Logik
    nur auf die oberen Nibbles legen, Sound-Decode (`sound_cs`) nicht doppelt treiben.
- **Phase C**: ✓ **Audio implementiert** (`sound.vhd`, s. eigener Abschnitt); offen: generische
  Spiel-Konfiguration per Generic. *(Roadmap nannte früher 0x3000/0x6000 — falsch; schaltplan-
  verifiziert sind die Sound-Latches **0x1080/1084/1088**.)*
- **Phase D**: Cleanup, SDC weiter vervollständigen (B4 switch[5..16]/options[], IO-Delays), Test-Module hinter Generic
  - ✓ Hold-Violations behoben (`set_false_path` cpu_clk_d1), SDC → `AtariFA.sdc` umbenannt

## Display-Timing (display_control.vhd v2.0, 2026-06-20)
Multiplex-Timing aus realer LogicPort-Aufzeichnung des Original-Boards vermessen und FSM darauf
abgeglichen. **Ausführliche Doku: `doc/Display_Timing.md`** (inkl. Schaltbild `doc/Display_Logic.png`,
Sheet 15B, und Messmethodik). Kernwerte: Blank ~129 µs / Show ~383 µs → 512 µs/Digit, 8 Digits,
4,10 ms/Frame, ~244 Hz, Duty ~75 %. Timing in Konstanten `C_BLANK_PAD/C_SHOW/C_LAST_DIGIT`.
Wichtigster Fidelity-Hebel = Blank:Show-Verhältnis (vorher ~95 % an = ~25 % zu hell). Zwei
index-sichere Funktionen `display_nibble/status_nibble` (entschärfen latenten `status_d(digit>3)`-Überlauf).

## Sound (sound.vhd, 2026-06-21)
Digitale Nachbildung der Original-Tonerzeugung (Prozessor-PCB Sheet 15B + Aux-PCB), aus den
Schaltplänen `doc/Display_Logic.png` + `doc/Auxiliary_PCB.png` verifiziert. **Drei geteilte
Latches (Bits 0–3, Bits 4–7 = Solenoide/Phase B):**
- **0x1080 = Wellenform-Auswahl** → D12-ROM Adr A5–A8 (16 Wellenformen).
- **0x1088 = Tonhöhe** → D13 (74LS9316) Teiler `(16 − wert)` von AUDIO CLK (≈ cpu_clk/2 = 500 kHz).
- **0x1084 = Lautstärke** → Aux-PCB CD4016-Attenuator (gewichtete R 68/33/18/8.2 K ≈ linear).

**ROM-Befund (`rom/82s130.hex`, 512×4, nur untere 4 Bit):** 16 zusammenhängende 32-Byte-Blöcke =
**16 Wellenformen × 32 Samples**. ROM-Adresse = `"0" & snd_select(4) & sample_cnt(5)`.
Tonfrequenz ≈ `AUDIO_CLK / ((16 − pitch)·32)`. **Vereinfachungen:** synchrone Zähler statt
74163/7493-Ripple; AUDIO ENABLE/RESET als „Dauerton, Wellenform-Neustart bei Auswahl-Wechsel",
„Aus" via Volume=0. `C_AUDIO_DIV` (Generic, Default 100) = einziger Tonhöhen-Tuning-Hebel.

**Ausgabe-Mux per `options(3)`** (active-low, im Spiel dynamisch umschaltbar; in `AtariFA.vhd`):
- `'1'` (DIP OFF) = **Original**: `aux_audio <= not snd_sample`, `aux_audio_latch <= "00" & not snd_volume`
  ans echte Aux-Board (dortiger R-DAC + 4016 + Verstärker). **Invertiert wg. 74HCT540** (Konvention `disp_*`).
- `'0'` (DIP ON) = **Emulation**: `SB_Sound <= snd_pwm` (1-Bit Sigma-Delta von `(sample−8)·volume`,
  @clk_50) → Onboard-RC (3k3/4n7, fc≈10 kHz) + TDA7267. `SB_Audio` = separater MP3-Pfad, unangetastet.

**Compile (2026-06-21):** 0 Fehler, Timing ok (Setup ≥3,0 ns / Hold ≥0,16 ns); BRAM 22/30 M9K (+1 für
D12). Warnung 14320 (ROM `q[7:4]` wegoptimiert) harmlos. **HW-Vorbehalte (im Code kommentiert):**
(1) Original-Pfad erreicht das Aux-Board erst mit aktivem 74HCT540 (`solenoids_enable`, Phase B/C);
(2) `aux_audio_latch` Bit 5/4 auf Idle '0' (HW-Zuordnung der oberen 2 Bit prüfen);
(3) Adress-/Volume-Bit-Reihenfolge bei „falschem" Klang 1-zeilig tauschbar.

## Boot-Sprachausgabe „Lisü" (speech.vhd, 2026-06-22)
Beim Boot wird einmalig das Wort „Lisü" (deutsche Roboterstimme) über die vorhandene Onboard-
Audiokette ausgegeben (Sigma-Delta-PWM `SB_Sound` → RC 3k3/4n7 → TDA7267). Machbarkeitsanalyse +
Umsetzungs-Ergebnis: **`doc/Speech_Boot_Feasibility.md`**.
- **Codec = 8-Bit-PCM @ 8 kHz** (nicht Delta!). Ursprünglich war 1-Bit-Delta-Modulation geplant
  (Logik-/ROM-Minimum, 1 M9K), klang aber **stark verrauscht** — Ursache: zu geringe Überabtastung
  (Delta braucht hohe OSR; niedrigere Rate verschlimmert es). Daher PCM: **sauberster Klang,
  einfacherer Decoder** (kein Akku), Preis = mehr ROM (war kein Engpass, 7 M9K frei).
- **`speech.vhd`** = Adresszähler + Ratenteiler + First-Order-Sigma-Delta-DAC (identisch zu sound.vhd).
  Generics: `N_SAMPLES=3687` (0,461 s), `CLK_DIV=6250` (=50e6/8000). **`speech_rom.vhd`** = altsyncram
  4096×8 (12-Bit-Adresse) = **4 M9K**.
- **`rom/lisy.mif`** = 8-Bit-PCM (WIDTH=8), ungenutzte Worte mit **128 = Stille** gefüllt
  (NICHT 0 = -128 = lauter DC-Knall am ROM-Ende). Wortende per **Fade-Out 35 ms** auf ~128 ausgeblendet
  (espeak kappt Vokale hart bei ~60 % → sonst „abgeschnitten"/Klick).
- **Integration in `AtariFA.vhd`** (Instanz `SPEECH_INST`): `reset => not boot_phase(0)`
  (= synchronisiertes reset_sw; **NICHT `por_active`/`reset_h`** — die sind über `if reset_l_stable='0'`
  während des GANZEN Info-Fensters aktiv und würden Speech bei der Wiedergabe im Reset halten!).
  `start => boot_phase(1)` (Pegel; internes `start_d`-Edge-Detect in speech.vhd löst Einmal-Wiedergabe aus).
  Ausgabe-Mux mit **Vorrang**: `SB_Sound <= speech_pwm when speech_busy='1' else snd_pwm when options(3)='0' else '0'`.
  Fällt komplett ins vorhandene ~5s-Info-Fenster (`boot_phase(2)`), kein zusätzliches Boot-Delay.
- **Encoder `tools/make_speech_mif.py`** (pure stdlib, **gitignored** wie ganzes `tools/`): erzeugt das
  `.mif` aus einer WAV. Optionen u.a. `--pcm` (8-Bit-PCM statt Delta), `--fade-out-ms`, `--smooth`
  (Moving-Avg-LPF), `--trim-thresh`, `--pad-ms`, `--pcm-preview`. Quelle via espeak (klassisch,
  `C:\Program Files (x86)\eSpeak\command_line\espeak.exe`): `espeak -v de -s 135 "[[l'i:zy]]"`.
  Finaler Aufruf steht im `speech.vhd`-Header. ROM-Neu-Erzeugung: Quelle `speech_source_shortU.wav`
  (lokal, untracked) durch den Encoder.
- **Compile (2026-06-22):** 0 Fehler/0 Critical, **BRAM 26/30 M9K** (−1 Delta +4 PCM), LE 30 % (sogar
  weniger als Delta), Timing ok. **HW-Vorbehalt:** falls TDA7267 eine Mute-/Einschaltphase hat und den
  Wortanfang kappt → `--lead-ms` Vorlauf-Stille ins ROM legen (am echten Board testen).

## Bekannte HW-Feintuning-Stellen
- Ziffernreihenfolge im Shadow-Buffer-Demux (case-Zweige in `AtariFA.vhd`) — PinMAME-Segment-Indizes sind absteigend, physische Verdrahtung muss auf Hardware geprüft werden. **Original-Scan-Reihenfolge der Digits = 0,2,4,6,1,3,5,7** (adr0 langsamstes Bit, aus LPF gemessen, siehe `doc/Display_Timing.md` §9); `display_control` zählt linear 0..7 — bei Bedarf hier oder im Demux anpassen.
- Lampennummer↔Bit-Mapping im Lamp-Sniffer (`AtariFA.vhd`, derzeit linear) — PinMAME `col=(offset%4)*2+offset/8`, physische Zuordnung auf Hardware prüfen
- TPIC6B595N nur ~150 mA Dauer/Ausgang — bei #44/#47-Glühlampen schwächer als ULN2003A (Paketverlustleistung prüfen), mit LEDs unkritisch

## Referenz
- PinMAME `src/wpc/atari.c`: maßgeblich für Speicher-Map, Display-Mapping, Switch/DIP-Handler
- **Display-Timing-Analyse: `doc/Display_Timing.md`** (gemessen aus Original-Board, Schaltbild Sheet 15B)
- **Boot-Sprachausgabe: `doc/Speech_Boot_Feasibility.md`** (Codec-Analyse + Umsetzung PCM 8 kHz)
- Vollständiger Code-Review: `N:\Projekte\FPGA Atari\AtariFA_Code_Review.md`
