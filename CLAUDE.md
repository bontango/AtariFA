# AtariFA — Claude Code Projektkontext

## Projekt
FPGA-Nachbau der Atari Gen1 Pinball-MPU (MC6800 / John Kent cpu68).
Quartus Prime **22.1std.2 Lite Edition**. GitHub: https://github.com/bontango/AtariFA

## Ordnerstruktur — gemeinsamer Sourcebaum (Umbau 2026-08-06)
Seit 2026-08-06 liegt das Repo in **`N:\Projekte\FPGA Atari\FPGA_source`** (vorher der flache
Projektordner `AtariFA\`). Grund: eine **zweite Board-Variante** kam dazu, und mit zwei
handgepflegten `.qsf` müsste jede Änderung doppelt portiert werden. **Doku: `README.md`
(öffentlich), `WORKFLOW.md` (wie man hier arbeitet), `VARIANTEN.md` (Boards + HW-Teststand),
`PLAN_Zielstruktur.md` (warum die Struktur so aussieht).**

```
top/AtariFA.vhd     DAS eine Top-Level für alle Boards
rtl/common/         alle Module + version_pkg (SW_SUB1/2) + display_pkg + lamp_map_pkg
rtl/fa_control/     ESP32-/LISY-Schnittstelle, self-contained zum Kopieren in andere Projekte
rtl/cyclone_10/     Megafunctions der Chipfamilie (RAM, cpu_clock, sound_rom)
rom/  docs/  archive/  bin/
variants/<name>/    variant_pkg.vhd (BOARD_ID) · device.tcl · pins.tcl · AtariFA.sdc
                    AtariFA.qpf · AtariFA.cof · AtariFA.qsf (GENERIERT)
scripts/            gen_qsf.ps1 · check.ps1 · build.ps1 · release.ps1 · baseline.csv
                    common_header.tcl · files_common.tcl · files_cyclone_10.tcl
```

**Keine Feature-Flags je Variante.** Neue Module kommen in `scripts/files_common.tcl` und werden
unbedingt instanziiert — beide Boards bekommen alles. Ein `HAS_*`-Schalter in `variant_pkg.vhd`
plus `Options`-Eintrag, eigener `files_*.tcl` und zwei komplementären `if generate` kostet mehr
als das Feature überall zu bauen und führt die Doppelpflege wieder ein, gegen die dieser Baum
angetreten ist. (WillFA7 hat mit `HAS_MONITOR` so einen Schalter — dort gibt es aber eine
Cyclone-II-Variante, die die LEs wirklich nicht frei hat. Hier gibt es keinen solchen Fall.)

**Zwei Varianten, beide 10CL006YE144C8G:** `cyclone_10_pcb` (BOARD_ID 0, Leitvariante,
HW-getestet bis SW 0.1.2) und `cyclone_10_dev_open` (BOARD_ID 1, **nie HW-getestet**;
anderes Piggy-back-Board: 4 statt 3 LEDs, eigener Reset-Taster, nur 3 statt 8 Debug-Pins).
Unterschied im Code = **null**: nur `pins.tcl` + `BOARD_ID`; `LED_D4` und `debug_signal[3..7]`
stehen in beiden Portlisten und bekommen dort, wo sie fehlen, `VIRTUAL_PIN` aus `variant.psd1`.

**Harte Regeln:**
- **`variants/<n>/AtariFA.qsf` ist erzeugt — nie von Hand editieren.** Ändern:
  `device.tcl` / `pins.tcl` / `variant.psd1` / `scripts/files_*.tcl`, dann `gen_qsf.ps1`.
  Quartus schreibt aus der IDE in die Datei zurück; `check.ps1`/`build.ps1` regenerieren
  deshalb vorher (`gen_qsf.ps1 -Check` zeigt, was Quartus hineingeschrieben hat).
- **Alle Pfade sind projektverzeichnisrelativ, Projektverzeichnis = `variants/<n>/`.**
  Quellen `../../rtl/...`, `init_file` in den ROM-Wrappern und die 10 `generic map` im
  Top-Level `../../rom/...`, `.cof`-Pfade `output_files/...` (**nicht absolut!**).
  Ausnahme: `.qip` nutzen `$::quartus(qip_path)` und sind ortsunabhängig.
- **Version an genau einer Stelle:** `rtl/common/version_pkg.vhd` (`SW_SUB1`/`SW_SUB2`);
  die führende Ziffer ist `BOARD_ID` aus `variants/<n>/variant_pkg.vhd`. Anzeige =
  `BOARD_ID.SW_SUB1.SW_SUB2` (pcb `0.1.2`, dev_open `1.1.2`).
- **Alte Ordner `AtariFA\` und `AtariFA_dev_open\` bleiben als Backup liegen** bis zum
  HW-Test — **von dort nicht mehr committen/pushen**. `AtariFA_dev_open` hatte nie ein Git;
  Sicherung: `AtariFA_dev_open_BACKUP_2026-08-06.zip` im Elternordner.

## Build / Compile (Claude kann das selbst ausführen)
- **Bevorzugt die Skripte** (aus dem Repo-Root, PowerShell):
  `scripts\check.ps1` (Synthese beider Varianten, schnell) · `scripts\check.ps1 -Fit`
  (+ Fitter/Timing + Baseline-Vergleich) · `scripts\build.ps1 cyclone_10_pcb` (Full Compile
  + `.jic`) · `scripts\release.ps1 -Note "…"`. Laufen Minuten → `run_in_background`.
- **Direkt (falls nötig):** `& "C:\intelFPGA_lite\22.1std\quartus\bin64\quartus_sh.exe" --flow compile AtariFA`
  **mit CWD `variants/<n>/`**. `quartus_sh` liegt **nicht im PATH**; immer den vollen Pfad
  nutzen. Andere gefundene Installs (`C:\intelFPGA\23.1std\...`, `C:\altera\...`) sind
  nur **qprogrammer** (kein Compile-Flow) bzw. falsche Version → **nicht** verwenden.
- **Verifikation der Reports** (in `variants/<n>/output_files/`): `AtariFA.map.rpt`
  (Analysis & Synthesis), `AtariFA.fit.rpt` (Fitter/Pins), `AtariFA.sta.rpt`
  (TimeQuest/Slack), `AtariFA.flow.rpt` (Flow-Status). Auf Warnings und negative Slacks prüfen.
- **Abnahmekriterium = die SYNTHESE-Zahlen** (`map.rpt`: Total combinational functions /
  Total registers / Total memory bits), exakt gegen `scripts/baseline.csv`. Die
  **LE-Zahl des Fitters taugt dafür nicht**: beim Umbau 2026-08-06 blieb die Synthese Byte
  für Byte gleich (2433/935/202752) und der Fitter ging trotzdem 2554 → 2545, nur weil ein
  einziger zusätzlicher `VIRTUAL_PIN` die LE-Packung ändert. Slack schwankt ebenfalls
  (Toleranz 1,5 ns in `check.ps1`); der enge Pfad ist **`cpu_clk`**, nicht `clk_50`.
- **Erwartete, harmlose Warnungen** (nicht „beheben"): 113009 (Intel-HEX-Records),
  14320 (`sound_rom q[7:4]` wegoptimiert), 3× 10036 (`dma_clk`/`audio_clk`/`nvram_wren`
  zugewiesen, nie gelesen). **`solenoids[14]/[18] stuck at VCC` gibt es seit SW 0.1.3 NICHT
  mehr** — die beiden unbestückten Ausgänge sind nicht mehr konstant, seit FA-Control alle 20
  Spulenpositionen adressieren kann.
- **Zielplatine (AtariFA-PCB):** Cyclone 10 LP **10CL006YE144C8G** (E144) — „piggy-back"-Replacement-CPU mit RAM/ROM + TTL-Ersatz, parallel zu den Atari-Edge-Connectors plus „Box-Connectors". Migriert 2026-06; nur Display-Routinen übernommen, Rest (Switch/Lamps/Solenoide/Audio/FRAM/ESP32) step-by-step (Phase B/C).
- **Testplatine (vorher):** GottFA3 / Cyclone IV E EP4CE6F17C8 — Bring-up abgeschlossen 2026-06-06.
- **Dritte Ausprägung, bewusst außen vor:** `N:\Projekte\FPGA Atari\AtariFA - on SYS3 Test PCB`
  (Cyclone IV EP4CE6F17C8, Stand 2026-06-06, eigenes Git ohne Remote). Nicht Teil des Baums;
  Nachrücken hieße `variants/cyclone_iv_sys3/` + `rtl/cyclone_iv/` + `files_cyclone_iv.tcl`.

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
  (siehe `variants/<n>/pins.tcl`). **✓ Erledigt:** `variants/<n>/AtariFA.sdc(39)` auf `reset_sw` korrigiert (Warning 332174/332049
  behoben, `set_false_path` greift wieder). Zusätzlich `NUM_PARALLEL_PROCESSORS 14` in der QSF gesetzt
  (Warning 18236 weg). **Achtung:** Quartus erkennt auf dieser Maschine nur **14** Prozessoren (Windows
  meldet 20 logisch) → Wert >14 löst Warning **20031** (Über-Subskription) aus; daher 14, nicht 16.

## Wichtige Konventionen
- VHDL: `use ieee.std_logic_unsigned.all` — kein `numeric_std` (würde Konflikte erzeugen)
- Taktstrategie: `clk_50` = 50 MHz Systemtakt; `cpu_clk` = 1 MHz via PLL (`cpu_clock.vhd`, altpll ÷50)
- RAM-Write-Strobe immer in `clk_50`-Domain (fallende cpu_clk-Flanke per Edge-Detect auf `cpu_clk_d1/d2`)
- Open-Bus-Default: `cpu_din <= x"FF"` wenn keine CS aktiv
- Display-Outputs sind **invertiert** wegen 74HCT540-Treiber: `disp_* <= not i_disp_*`
- **`io_live` statt `reset_l_stable` für Peripherie** (seit SW 0.1.3): `reset_l_stable` ist nur noch
  die CPU-Freigabe. Wer ein Modul anschließt, das auch bei FA-Control-Übernahme laufen muss
  (Schalter, Lampen, Spulen, Ton), nimmt **`io_live`** — s. Abschnitt „FA-Control-Schnittstelle".
- **Sichere Inaktiv-Pegel:** noch nicht implementierte Ausgänge werden in `AtariFA.vhd` **explizit** getrieben (nicht undriven lassen!) — Quartus-Default `'0'` würde über den invertierenden 74HCT540 die Solenoide EINschalten. Solenoide/`solenoids_enable`/`aux_sol_latch` sind seit 2026-07-04 vom `solenoid_driver` getrieben; **Lampen** (`oe_595`/`serin_595`/`clk_595`/`rclk_595`/`aux_lamp_strobe`) seit 2026-07-04 vom `lamp_matrix` (bei Reset/Boot sicher AUS: `enable=0` → `oe_595='1'`). Block direkt nach den `disp_*`-Zuweisungen.
- **FRAM:** `fram_i2c_sda` ist `inout` (open-drain, idle `'Z'`, externer Pull-up) — I2C braucht bidirektionale SDA für ACK/Read; `fram_i2c_scl` bleibt `out`.
- SDC-Datei: `AtariFA.sdc`; `cpu_clk` (PLL clk[0]) wird als Datensignal in `clk_50` gesampled → `set_false_path` auf `cpu_clk_d1` (verhindert falsche Hold-Violations durch „clock-used-as-data")

## Architektur-Entscheidungen (nicht rückgängig machen ohne Grund)
- **Shadow-Buffer statt Dual-Port-RAM**: Schreibzugriffe auf RAM 0x00–0x1F werden per Write-Sniffer in `display1..4`/`status_d` kopiert (Single-Port-RAM bleibt für CPU)
- **DMA-Toggle**: `dma_toggle` flippt alle 2 NMI-Pulse (Edge-Detect auf `nmi_level`, Modulo-2 in clk_50-Prozess); Bit 6 von 0x2000 — Game-Code braucht diesen Wechsel zum Fortlaufen
- **Synchroner 12-Bit-Zähler** statt 3× SN7493-Ripple-Kaskade; NMI-Periode = 4096 cpu_clk = 4096 µs
  = **244 Hz** (PinMAME `ATARI_NMIFREQ=244`, entspricht der gemessenen Frame-Periode, s. `docs/Display_Timing.md`).
  **War früher 9-Bit ÷512 = 1953 Hz (8× zu schnell)** → Switch-Scan im NMI-Handler registrierte jeden Tastendruck
  mehrfach; 2026-07-06 auf ÷4096 korrigiert (`dma_counter(11 downto 0)`, `nmi_level = Bit10 and Bit11`).

## Offene Bugs (bewusst zurückgestellt)
- **B4**: ✓ behoben (2026-07-02) — der 2-FF-Synchronizer liegt jetzt im **`switch_matrix.vhd`**-Scan
  (alle Matrix-Schalter über `sw_com_in`); die toten `sw_meta`/`sw_sync` (GottFA3-Erbe) sind entfernt,
  Warning 10540 ist weg. Noch offen nur `options[]`/`dip_*`-SDC-Feinheiten (Phase D).
- **B5**: ✓ adressiert — unimplementierte Ausgänge auf sicheren Inaktiv-Pegel getrieben (s.o. „Sichere Inaktiv-Pegel"). Solenoide/Münztür/`solenoids_enable` haben jetzt **echte Logik** (`solenoid_driver.vhd`, 2026-07-04); Lampen jetzt ebenfalls echte Logik (`lamp_matrix.vhd`, 2026-07-04).
- **B10–B12**: ✓ Teil-Cleanup — `DIAG_SEL`+`hex7seg` (GottFA3-SEG7-Reste) entfernt, `cpu_clk_gen.vhd` aus `.qsf` (toter Code; PLL `cpu_clock` wird genutzt). Display-Signal-Ownership noch offen.
- **B13 — Switch-Test ROM-abhängig (✓ behoben 2026-07-06, HW-getestet alle 5 Spiele):** Ursache waren
  **zwei Fehler** (Root-Cause via ROM-Disassembly, `tools/dis6800.py` + `docs/Switch_Reading_Analysis.md`):
  **(1) NMI 8× zu schnell** (÷512=1953 Hz statt ÷4096=244 Hz) → Switch-Scan registrierte jeden Druck
  mehrfach; auf 244 Hz korrigiert (s.o. „Architektur-Entscheidungen"). **(2) 0x200B-Testschalter war
  invertiert:** ME @7F9C und Airborne @7AB4 werten **Bit7=1 = Test gedrückt**; unser `not sw_state(11)`
  ließ den Ruhezustand wie „gedrückt" aussehen → Level-Spiele booteten sofort in den Selbsttest, ME
  reagierte spurious. **Fix:** 0x200B **nicht** invertieren (fällt mit allg. DIP-Zweig zusammen); ME
  (`game_idx=3`, PinMAME ATARI1A `testSwBits=0x0F`) = Basis XOR 0x0F.
  **HW-Test 2026-07-06 (alle 5 Spiele):** booten normal, Credits aufbuchbar, Spiel startbar; Freispiel-
  ROMs starten ohne Credit. Testschalter betritt Selbsttest auf Druck, Werte korrekt angezeigt, **keine
  Phantomschalter**. **Ausnahme Atarians:** keine Reaktion auf den Testschalter — Atarians (Ataris erstes
  Spiel) hat laut Manual **keinen dokumentierten Selbsttest** (vermutlich gar keiner vorhanden). Nur als
  Kommentar festgehalten, kein Defekt. **Grundfunktionen aller 5 Spiele abgehakt; nur Soundtest steht noch aus.**

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
- **Phase B**: ✓ **Switch-Matrix** (2026-07-02, `switch_matrix.vhd`) + ✓ **Solenoide** (2026-07-04,
  `solenoid_driver.vhd`, HW-getestet OK) + ✓ **Lamp-Matrix** (2026-07-04, `lamp_matrix.vhd`,
  HW-getestet OK, Lampen-Selbsttest) implementiert. **Phase B damit abgeschlossen.**
  - **Switch-Matrix real** (`switch_matrix.vhd`): freilaufender Scan der 10×8-Matrix (CPU 0x2000–0x204F,
    offset 0..79) @clk_50; treibt `sw_strobe`/`sw_com` → inv. 74HCT540 → E11a 74LS42 (Spalte) + 10×
    SN74LS145N (Zeile), liest den einen Rückkanal `sw_com_in` (inv. 74HC4049), 2-FF-Sync (B4) + 2-Pass-
    Debounce → `sw_state(0..79)` (`'1'`=geschlossen). Codierung **schaltplan-verifiziert** aus
    `../doc/AtariFA_07_Final_Switches_SCH.PDF` (Eltern-Ordner `N:\Projekte\FPGA Atari\doc\`, Geschwister: Main/Lamps/Solenoids) (s. „Bekannte HW-Feintuning-Stellen"). CPU-Read: `sw_value`
    @0x2010–0x204F (PinMAME swg1_r, geschlossen=0xFF), `dip_value` @0x2000–0x200F volles 1:1 aus Matrix
    (SW1/SW2-Programmier-DIPs + Replay-Hex) — **Ausnahmen** 0x2000 (DMA-Sync/BPL, synthetisiert) und
    0x200B (Testschalter, **NICHT** invertiert; ME `game_idx=3` = Basis XOR 0x0F, s. B13/`docs/Switch_Reading_Analysis.md`).
    **Start-Bug behoben** (war 0x2013, korrekt **0x2012**). Compile 0 Fehler/
    0 Critical, Timing ok (Setup ≈+2,8 ns / Hold ≈+0,45 ns), LE 36 %, BRAM unverändert. **HW-getestet OK
    alle 5 Spiele (2026-07-06, SW 0.0.6)** — Selbsttest/Switch-Werte korrekt, keine Phantomschalter (außer
    Atarians: kein Selbsttest im Manual dokumentiert, s. B13).
  - ✓ **Lamp-Matrix implementiert** (`lamp_matrix.vhd`, 2026-07-04, s. eigener Abschnitt „Lamps"):
    21×4-Multiplex (84 Lampen), 12× ULN2003A + drei 74HC595 + 4 Aux-Strobes; RAM-0x30–0x3F-Sniffer
    → `lamp_state`. Der alte `lamp_driver.vhd` (TPIC6B595-Entwurf) wurde **gelöscht**.
  - ✓ **Solenoide implementiert** (`solenoid_driver.vhd`, s. eigener Abschnitt „Solenoids").
  - **Sound-Überlappung (erledigt):** 0x1080/84/88 sind geteilte Latches — **Bits 0–3 = Sound**
    (s. „Sound"), **Bits 4–7 = Solenoide** + **0x108C voll = Solenoide** (s. „Solenoids"). Sound- und
    Solenoid-Decode teilen sich den `sound_cs`-Write-Strobe (untere vs. obere Nibbles), kein Doppel-Treiben.
- **Phase C**: ✓ **Audio implementiert** (`sound.vhd`, s. eigener Abschnitt); offen: generische
  Spiel-Konfiguration per Generic. *(Roadmap nannte früher 0x3000/0x6000 — falsch; schaltplan-
  verifiziert sind die Sound-Latches **0x1080/1084/1088**.)*
  ✓ **ESP32-Anbindung implementiert** (`rtl/fa_control`, 2026-08-08, s. eigener Abschnitt) —
  damit ist der letzte offene Punkt der Phase-B/C-Liste („Switch/Lamps/Solenoide/Audio/FRAM/ESP32")
  abgearbeitet, bis auf das zurückgestellte FRAM. **HW-Test steht noch aus.**
- **Phase D**: Cleanup, SDC weiter vervollständigen (B4 switch[5..16]/options[], IO-Delays), Test-Module hinter Generic
  - ✓ Hold-Violations behoben (`set_false_path` cpu_clk_d1), SDC → `AtariFA.sdc` umbenannt

## Display-Timing (display_control.vhd v2.0, 2026-06-20)
Multiplex-Timing aus realer LogicPort-Aufzeichnung des Original-Boards vermessen und FSM darauf
abgeglichen. **Ausführliche Doku: `docs/Display_Timing.md`** (inkl. Schaltbild `docs/Display_Logic.png`,
Sheet 15B, und Messmethodik). Kernwerte: Blank ~129 µs / Show ~383 µs → 512 µs/Digit, 8 Digits,
4,10 ms/Frame, ~244 Hz, Duty ~75 %. Timing in Konstanten `C_BLANK_PAD/C_SHOW/C_LAST_DIGIT`.
Wichtigster Fidelity-Hebel = Blank:Show-Verhältnis (vorher ~95 % an = ~25 % zu hell). Zwei
index-sichere Funktionen `display_nibble/status_nibble` (entschärfen latenten `status_d(digit>3)`-Überlauf).

## Sound (sound.vhd, 2026-06-21)
Digitale Nachbildung der Original-Tonerzeugung (Prozessor-PCB Sheet 15B + Aux-PCB), aus den
Schaltplänen `docs/Display_Logic.png` + `docs/Auxiliary_PCB.png` verifiziert. **Drei geteilte
Latches (Bits 0–3 = Sound; Bits 4–7 = Solenoide, s. „Solenoids"):**
- **0x1080 = Wellenform-Auswahl** → D12-ROM Adr A5–A8 (16 Wellenformen).
- **0x1088 = Tonhöhe** → D13 (74LS9316) Teiler `(16 − wert)` von AUDIO CLK (≈ cpu_clk/2 = 500 kHz).
- **0x1084 = Lautstärke** → Aux-PCB CD4016-Attenuator (gewichtete R 68/33/18/8.2 K ≈ linear).

**ROM-Befund (`rom/82s130.hex`, 512×4, nur untere 4 Bit):** 16 zusammenhängende 32-Byte-Blöcke =
**16 Wellenformen × 32 Samples**. ROM-Adresse = `"0" & snd_select(4) & sample_cnt(5)`.
Tonfrequenz ≈ `AUDIO_CLK / ((16 − pitch)·32)`. **Vereinfachungen:** synchrone Zähler statt
74163/7493-Ripple; Wellenform-Neustart bei Auswahl-Wechsel. `C_AUDIO_DIV` (Generic, Default 100)
= einziger Tonhöhen-Tuning-Hebel.

**AUDIO ENABLE/RESET (`snd_enable`, aus 0x3000/0x6000) gilt für BEIDE Pfade — Fix 2026-08-03, SW 0.1.1:**
`snd_enable='0'` hält Pitch- **und** Sample-Zähler auf 0 (wie im Original `CET` an D13 + `R01/R02` an
E12/E13, Sheet 15B) ⇒ ROM-Adresse konstant ⇒ AUDIO 0–3 statisch ⇒ DC ⇒ Aux-PCB koppelt über `C9` weg
= still, **unabhängig vom Lautstärke-Latch**; zusätzlich `eff_volume`=0, jetzt als Port `volume_out`
auch für den Aux-Attenuator. **Vorher wirkte `snd_enable` NUR über `eff_volume` und damit nur auf
`sb_pwm`** → der Aux-Pfad lief frei weiter = lauter Dauerton am Aux-Board. Grund: das Spiel schaltet
den Ton **nur** über AUDIO RESET ab und lässt `0x1084` stehen (Airborne `$79A2` = `STAA $6000 / RTS`,
sonst nichts). Details: `docs/Sound_Emulation.md` §6.3.

**Ausgabe-Mux per `options(3)`** (active-low, im Spiel dynamisch umschaltbar; in `AtariFA.vhd`):
- `'1'` (DIP OFF) = **Original**: `aux_audio <= not snd_sample`, `aux_audio_latch <= not snd_volume_eff`
  (**4 Bit**, nicht 6) ans echte Aux-Board (dortiger R-DAC + 4016 + Verstärker). **Invertiert wg.
  74HCT540** — schaltplan-bestätigt: `F_Audio0..3`/`F_L1084_B0..3` laufen über 540 (IC6/IC7 Main +
  einer auf dem Solenoid-Blatt); nur `F_Sol_Enable` über den nicht invertierenden 74HCT541 (IC14).
- `'0'` (DIP ON) = **Emulation**: `SB_Sound <= snd_pwm` (1-Bit Sigma-Delta von `(sample−8)·volume`,
  @clk_50) → Onboard-RC (3k3/4n7, fc≈10 kHz) + TDA7267. `SB_Audio` = separater MP3-Pfad, unangetastet.
  Aux-Ausgänge im Idle auf **`(others => '1')`** → Aux-Board sieht AUDIO=0/LATCH1084=0; früher `'0'`
  ⇒ über den invertierenden 540 Voll-DAC bei max. Attenuator (falscher „Aus"-Zustand, Offset am 741).

**Compile (2026-08-03, SW 0.1.1):** 0 Fehler / 0 Critical, Timing ok (Setup +2,40 ns / Hold +0,44 ns),
LE 41 %, BRAM 73 % (unverändert); `aux_audio`/`aux_audio_latch` nicht „stuck". Warnung 14320 (ROM
`q[7:4]` wegoptimiert) harmlos. **HW-Vorbehalt:** Adress-/Volume-Bit-Reihenfolge bei „falschem"
Klang 1-zeilig tauschbar.

## Lamps (lamp_matrix.vhd, 2026-07-04, HW-getestet OK)
84 Lampen als **21×4-Multiplex-Matrix** (ersetzt den gelöschten `lamp_driver.vhd`/TPIC6B595-Entwurf).
Reale Prototyp-HW: 12× **ULN2003A** (A20…B15; A14/B14/A13/B13/A12/B12 unbestückt) als Zeilen/Sink,
getrieben von einer **Kaskade aus drei 74HC595** (24 Bit, 21 genutzt) = 21 „Lampengruppen"; die
4 Strobes SA/SB/SC/SD (Spalten, +20 V) erzeugt das **Aux-Board** aus 2 Bit (`aux_lamp_strobe`, extern
7402-NOR+MC14xx 1-of-4-dekodiert). Schaltplan: `docs/Lamp_Logic.png` (18D) + `docs/Lamp_Logic2.png`
(18A, 9334-Decode) + `docs/Auxiliary_PCB.png` (10A) + `docs/AtariFA_Lamps.xlsx`.
- **Datenquelle:** RAM **0x30–0x3F**-Write-Sniffer → `lamp_state(127:0)` (in `AtariFA.vhd`, Prozess
  `lamp_sniffer`, analog Display-Shadow-Buffer; nur Page-0, nicht der Mirror). Die CPU schreibt Lampen
  nach 0x30–0x3F — **nicht** 0x1000–0x100C (das ist RAM-Mirror → Score-Bytes, würde sonst korrumpieren).
- **Mapping (HW-abgeleitet):** 595-Gruppe `N` je (Latch `L` 0=1000..3=100C, Bit `b`) als **Tabelle
  `GRP_OF`** in `lamp_matrix.vhd` — direkte Abschrift von `docs/AtariFA_Lamps.xlsx`, Mappe **`aktuell`**
  (korrigiert 2026-08-05, SW 0.1.2). Die frühere Formel `N = 4*b + L + 1` entspricht der Mappe **`alt`**
  und gilt **nicht mehr** (neue Zuordnung ist eine Permutation ohne geschlossene Form; belegt weiter
  Bits 0..4 aller 4 Latches + Bit 5 nur bei 1000 = 21 Gruppen). RAM-Offset `= L*4 + s` (aus
  9334-Adressbits A2/A3/A7 beim DMA-Read von 0x30–0x3F: A7=0=Lampen, `offset[3:2]`=Latch,
  `offset[1:0]`=Strobe s) — **unverändert** ⇒ `ser_bit(N,s) = lamp_state[(L*4+s)*8 + b]`.
  84 unabhängige Lampen (21 Gruppen × 4 Strobes).
- **Scan-FSM (`lamp_matrix.vhd`, @clk_50):** je Strobe-Phase: blanken (`oe_595`='1') → 24 Bit MSB-first
  in die Kaskade schieben → `rclk`-Latch → `aux_lamp_strobe`=enc(s) → `oe_595`='0' → Dwell
  (`DWELL_CYCLES`≈250 µs → ~1 kHz Frame, native ~25 % Duty wie Original). Blank-während-Umschalten =
  Anti-Ghost. **595-Signale über 74HCT541 (NICHT invertiert)**; `aux_lamp_strobe` über **74HCT540
  (invertiert)** → Top: `aux_lamp_strobe <= not lamp_strobe_sel`.
- **Integration:** Instanz `LAMP`; `reset/enable => reset_l_stable` (Lampen erst mit CPU live,
  Boot/Reset sicher AUS: `enable=0` → `oe_595='1'`). Ersetzt die früheren Safe-Defaults.
- **Compile (2026-07-04):** 0 Fehler/0 Critical, Timing ok (Setup ≈+2,94 ns / Hold ≈+0,45 ns),
  LE 40 %, BRAM unverändert (73 %; `lamp_state` sind Register, kein M9K). Lamp-Pins nicht „stuck".
- **HW-TUNBAR (bei falscher Lampe/Strobe am Prototyp NUR in `lamp_matrix.vhd`):** `STROBE_ENC`
  (Strobe-Code ↔ SA/SB/SC/SD-Permutation, deckt auch die 540-Invertierung), `offset[3:2]=Latch`/
  `offset[1:0]=Strobe`, 595-Shift-Reihenfolge (welcher 74HC595 zuerst / vec(23)=MSB).

## Solenoids (solenoid_driver.vhd, 2026-07-04, HW-getestet OK)
20 Solenoide + 2 Münztür-Spulen. Statische Latches (wie Original 74LS175), @clk_50. Latch-Adressen
schaltplan-verifiziert (`docs/Switch_Sol_Logic.png` Sheet 15C + `docs/Auxiliary_PCB.png` Sheet 10A):
- **Solenoid-Bits:** `0x1080[7:4]` + `0x1084[7:4]` + `0x1088[7:4]` + `0x108C[7:0]` = **20 Bits**
  (untere Nibbles 1080/84/88 = Sound). **Münztür (Aux-PCB):** `COIN_CNTREN=0x1080 bit4`,
  `LOCKOUT_EN=0x1080 bit5` (→ `aux_sol_latch(0/1)`).
- **Integration `AtariFA.vhd`:** Instanz `SOL`; Write-Strobe `sol_wr` = `sound_cs`-Edge (derselbe
  Write-Prozess wie die Sound-Latches, obere vs. untere Nibbles); `latch_sel=cpu_addr(3:2)`.
  Ausgänge invertiert (74HCT540): `solenoids <= not sol_ah`, `aux_sol_latch(0/1) <= not coin/lockout`.
  `solenoids_enable <= not reset_l_stable` (Freigabe erst mit CPU; Boot/Reset disabled=sicher; gibt
  auch den Original-Audio-Aux-Pfad frei, da am selben 540). `reset/enable => reset_l_stable`.
- **Sicherheit:** bei Reset ODER `enable=0` alle Solenoide/Münztür AUS (Defense-in-depth + physisches
  540-Gate). Kein Auto-Timeout (LOCKOUT ist Dauerstrom-Coil; Puls-Timing macht der Game-Code).
- **Bit→Ausgang-Zuordnung nutzer-vorgegeben** (aus AtariFA-Schaltplan, `solenoid_mapping.txt`),
  Doppelbelegung geprüft (keine): Münztür (1080 bit4/5) disjunkt vom Playfield (nutzt 1080 nur bit6/7);
  **`F_Q14`/`F_Q18` unbestückt** (`sol_i(14)/(18)='0'`, passt zu Doc „Q14,Q18 fehlen je nach Spiel").
  **HW-tunbar:** bei falscher Reihenfolge NUR den Zuordnungsblock in `solenoid_driver.vhd` anpassen.
- **Compile:** 0 Fehler/0 Critical, LE 36 %, BRAM 26/30 unverändert, Timing ok. Warnungen
  `solenoids[14]/[18] stuck at VCC` = erwartet (unbestückt, AUS).
- **OFFEN (bei Time-2000-Test klären):** PinMAME modelliert `0x508C` als separates Zusatz-Latch
  (8 Solenoide, „Time 2000 only"), aber der Time-2000-Schaltplan zeigt das laut Nutzer nicht →
  evtl. Mirror/Alias von 0x108C. Board hat nur 20 MOSFETs; ein evtl. 0x508C ist unabgedeckt.

## Boot-Sprachausgabe „Lisü" (speech.vhd, 2026-06-22)
Beim Boot wird einmalig das Wort „Lisü" (deutsche Roboterstimme) über die vorhandene Onboard-
Audiokette ausgegeben (Sigma-Delta-PWM `SB_Sound` → RC 3k3/4n7 → TDA7267). Machbarkeitsanalyse +
Umsetzungs-Ergebnis: **`docs/Speech_Boot_Feasibility.md`**.
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
  **`generic map( START_DELAY => 100000000 )`** = ~2s Wartezeit nach der Start-Flanke (100e6 clk_50 @50MHz),
  damit „Lisü" NICHT ins TDA7267-Einschalt/Mute-Fenster fällt (s. HW-Test unten). Ausgabe-Mux mit **Vorrang**:
  `SB_Sound <= speech_pwm when speech_busy='1' else snd_pwm when options(3)='0' else '0'`.
  Fällt komplett ins vorhandene ~5s-Info-Fenster (`boot_phase(2)`), kein zusätzliches Boot-Delay.
- **Encoder `tools/make_speech_mif.py`** (pure stdlib; die beiden `.py` in `tools/` sind getrackt,
  Binaries und generierte Listings dort nicht — s. `.gitignore`): erzeugt das
  `.mif` aus einer WAV. Optionen u.a. `--pcm` (8-Bit-PCM statt Delta), `--fade-out-ms`, `--smooth`
  (Moving-Avg-LPF), `--trim-thresh`, `--pad-ms`, `--pcm-preview`. Quelle via espeak (klassisch,
  `C:\Program Files (x86)\eSpeak\command_line\espeak.exe`): `espeak -v de -s 135 "[[l'i:zy]]"`.
  Finaler Aufruf steht im `speech.vhd`-Header. ROM-Neu-Erzeugung: Quelle `speech_source_shortU.wav`
  (lokal, untracked) durch den Encoder.
- **Compile (2026-06-22):** 0 Fehler/0 Critical, **BRAM 26/30 M9K** (−1 Delta +4 PCM), LE 30 % (sogar
  weniger als Delta), Timing ok.
- **✓ HW-getestet OK (2026-07-07, SW 0.0.7):** „Lisü" war zunächst **komplett stumm** (LED1-Diagnose zeigte:
  FSM lief durch, ROM ok, Ausgabepfad durch Töne bewiesen) — Ursache war das **TDA7267-Einschalt/Mute-Fenster**:
  das 0,46-s-Wort spielte ~0,3s nach Power-on und lag damit voll im Totfenster (kein FPGA-Mute-Pin vorhanden →
  nur Timing steuerbar). **Fix = `START_DELAY` (speech.vhd, Generic)** statt `--lead-ms` (0 ROM/BRAM statt +4 M9K):
  bei ~2,5s hörbar bestätigt, final auf **~2s** (`100000000`) gesetzt. Der `--lead-ms`-Weg bleibt Alternative,
  ist aber unterlegen (nur ~50ms passen in die 4096-Wort-Tiefe). **Tunbar:** knackiger ~1,2s = `60000000`.

## FRAM-Persistenz — Credits/Highscore (fram_i2c.vhd + Injection-FSM, 2026-07-09)
> **⚠ DEAKTIVIERT (2026-07-10):** Die NVRAM/FRAM-Thematik ist **zurückgestellt** (Ausweitung auf alle 5
> Spiele scheiterte — empirischer CRED_PROBE unzuverlässig, Airborne-Anker 240≠213; Root-Cause in
> `docs/FRAM_Persistence.md`). Das **I²C-Modul ist aus dem Build genommen** (Dateiliste `scripts/files_common.tcl` ohne
> `fram_i2c.vhd`; Top-Level treibt die Pins auf sicheren Leerlauf `fram_i2c_sda<='Z'`/`fram_i2c_scl<='1'`),
> die **Source `fram_i2c.vhd` bleibt** erhalten. Aktueller Build **SW 0.1.0**; der HW-verifizierte
> Airborne-Stand bleibt als **SW 0.0.9 (`959ff6b`)** in der git-History. Der folgende Abschnitt beschreibt
> die (committete, aber aktuell inaktive) Implementierung — Reaktivierung: `fram_i2c.vhd` wieder in die
> `.qsf` + Top-Level-Feature. **Zukunftsweg = RE statt Probe** (s. `docs/FRAM_Persistence.md`).

Rettet **Credits + Scores des letzten Spiels** über Power-Cycle im externen I²C-FRAM (Atari Gen1 hat
**kein natives NVRAM**). **Ausführliche Doku: `docs/FRAM_Persistence.md`** (RE-Adressen, Mechanik,
Atari-Verhalten). Bisher nur **Airborne** (`game_idx=2`). SW-Version **0.0.9**.
- **`fram_i2c.vhd`:** Bit-Banging-I²C-Master @clk_50 für **FM24CL64B** (Slave **0x51**, A0=3V/A1=A2=GND;
  `CLK_DIV=125`≈100 kHz; Block-Read/Write; SDA open-drain `inout` / SCL out). **Read-Bug-Fix (wichtig):**
  `P_RX` sampelt `shreg` jetzt **genau 1×/Bit** (`if phase_last then …`) statt `CLK_DIV`× (las sonst nur
  8×-LSB → 0x42→0x00). HW-bestätigt (Loopback byte-exakt; FRAM ACKt an 0x51, /WP=GND, Vdd 3,3V, 4k7-PU).
- **FRAM-Record @Adr0:** `[0]`Magic 0xA5, `[1]`game_idx, `[2]`Credit(`$D5`), `[3..12]`Scores(`$81–$8A`).
  Gültig wenn Magic==0xA5 **und** game_idx==aktuelles Spiel (`restore_valid`).
- **Airborne-Adressen (RE):** Credits `$D5`, Player-Scores `$81–$8A` (BCD), Outhole-Latch `0x2043`
  → `sw_state`-Offset **67**. (Outhole andere Spiele: Atarians 19, Time 53, ME 56, Space 56.)
- **Stufe 1 (Save/Restore ins FRAM, HW-OK):** `save_trig` = Outhole-Flanke armiert → Scores
  `STABLE_CYCLES`(~3 s) stabil + `game_played` + `game_idx=2` + `options(1)=ON` → `save_request` →
  FRAM-Write von `persist_buf` (Page-0-Sniffer `$D5`/`$81–$8A`). `fram_ctrl`-FSM beim Boot
  (`boot_phase(1)`): ON=Read→`fram_shadow`+`restore_valid`, OFF=Erase. Boot-Info zeigt Valid+Credit+`$81`.
  **Status-Display-Dreher „24↔42":** Status-/Credit-Ball-Display läuft in Digit-Reihenfolge
  **entgegengesetzt** zu Display 1–4 → in `bi_status` hi→Idx2/lo→Idx3 (rein kosmetisch). CD4511 nur 0–9.
- **Stufe 2 (Bus-Injection-Restore ins Spiel-RAM):** `injection`-FSM + RAM-Port-Mux (`ram_p_*`) +
  cpu68-`halt` (`cpu_halt`). Ablauf `INJ_ARM`(reset_h=0 + restore_valid + game_idx=2) → `INJ_WAIT_CLEAR`
  (`DELAY_CLEAR`≈20 ms, Boot-Clear abwarten) → `INJ_HALT`(`HALT_SETTLE`≈82 µs) → `INJ_WRITE`
  (`inj_active` muxt Port, Bytes aus `fram_shadow`) → `INJ_DONE` (One-Shot `injected`). **Credit-Restore
  HW-verifiziert** (2 Credits restauriert, Coin→3; CPU läuft sauber weiter).
- **⚠ Score-Anzeige ZURÜCKGESTELLT** (`INJ_SCORES := false`, Mechanik bleibt, `true` reaktiviert):
  Atari zeigt nach dem Boot **fix `888888` ~20–30 s** und **blankt dann die Player-Displays**; **Scores
  erst nach dem ersten Spiel**, Status wechselt von `8888` erst bei Coin/Start. Die injizierten
  `$81–$8A` sind daher im Cold-Boot-Attract **unsichtbar** (Credit-Restore ist NICHT betroffen, wird beim
  Coin/Start aus `$D5` angezeigt). Sichtbar erst mit dem **„Spiel-gespielt"-Flag** (ROM-RE offen) →
  mit-injizieren; alternativ Display-Region `$05/$06/$09/$0A/$0D/$0E` direkt (fragil).
- **HW-Tuning-Hebel (`AtariFA.vhd`):** `DELAY_CLEAR`, `HALT_SETTLE`, `INJ_SCORES`, `INJ_DEBUG_LED`
  (LED_D1 = `injected` statt `save_seen`).

## FA-Control-Schnittstelle (rtl/fa_control, 2026-08-08, SW 0.1.3, **noch nicht HW-getestet**)
LISY-Slave am ESP32-C3, Gegenstelle zu `N:\Projekte\FA_Control` (Weboberfläche zum Testen).
**Ausführliche Doku: `docs/FA_Control_Interface.md`** — dort stehen Protokoll, Nummerierung,
HW-Tuning-Stellen und die Inbetriebnahme-Reihenfolge.
- **Protokoll = LISY API 0.12 unverändert** (`N:\Projekte\lisy_5_28\src\lisy\lisy_api.h`), keine
  Eigenerfindung. FA_Control sprach das schon, nur die **Info-Gruppe 0..9** fehlte auf beiden
  Seiten — genau die ist jetzt der **Connect-Handshake**: der Host fragt Bestückung (84 Lampen,
  22 Spulen, 80 Schalter, 16 Sounds, 5 Displays), Kennung und Version ab, statt sie geraten zu
  bekommen. `G_LISY_VER` (Op 1) liefert `BOARD_ID.SW_SUB1.SW_SUB2` aus `version_pkg`.
- **Pin-Richtungswechsel (kein HW-Umbau):** `ESP32_sig : out` → **`ESP32_ctrl_req : in`**
  (PIN_11 pcb / PIN_84 dev_open, `WEAK_PULL_UP_RESISTOR ON`, active low). GPIO10 ist auf der
  ESP-Seite ein Push-Pull-**Ausgang** — der alte, fest auf `'0'` getriebene FPGA-Ausgang hat mit
  gestecktem Modul dagegengetrieben. Kein ESP gesteckt = high = keine Anforderung ⇒ Verhalten
  ohne ESP exakt wie vorher. **Portnamen sind aus ESP-Sicht:** `ESP32_ser_tx` ist ein FPGA-*Eingang*.
- **Freigabe = `ESP32_ctrl_req` low UND Options-DIP 4 = ON**, umgeschaltet erst durch Opcode 100
  (`LISY_INIT`); dessen Antwort nennt den Grund (0 gewährt / 1 DIP aus / 2 Anforderung fehlt).
  Fällt eine Bedingung weg (DIP wirkt fortlaufend!) oder kommt **2 s kein Byte** (Totmann,
  Reset bei JEDEM Byte, nicht nur beim Watchdog-Opcode) → Kontrolle sofort weg, alle Sollwerte
  gelöscht.
- **Übernahmemodell: CPU wird angehalten.** `reset_l_stable <= boot_phase(2) and not fa_ctrl_active`.
  **Neu und wichtig: `io_live <= reset_l_stable or fa_ctrl_active`** — Schaltermatrix,
  Lampenmatrix, `sound.vhd` und `solenoids_enable` hängen jetzt an `io_live`, NICHT mehr an
  `reset_l_stable`. Sonst stünde bei angehaltener CPU die ganze Peripherie und nichts wäre
  testbar (der 74HCT540 bliebe gesperrt = keine Spule). Beim Loslassen startet das Spiel neu.
  `LED_D4` zeigt `fa_ctrl_active`.
- **`GRP_OF` ist nach `rtl/common/lamp_map_pkg.vhd` gewandert**, weil das Top-Level die Lampen-
  zuordnung jetzt auch braucht — dort **umgekehrt**. Die Umkehrtabelle `FA_LAMP_BIT` wird zur
  Elaborationszeit aus `GRP_OF` **berechnet**; es gibt bewusst keine zweite Tabelle, die driften
  könnte. GRP_OF bleibt die eine HW-Tuning-Stelle.
- **Ressourcen:** Comb 2433 → **4326**, Reg 935 → **1434**, LEfit 2545 → **4402 (70 %)**,
  Slack sogar besser (2,304 → 3,142 ns). **BRAM unverändert 202752** — das war das
  Abnahmekriterium, denn mit 73 % ist der Speicher die knappe Ressource. **Kein neuer Pin**
  (85/89). Das Modul selbst: 1700 ALUTs / 499 Reg.
- **`MAX_*`-Generics knapp setzen!** Sie bestimmen die Vektorbreiten; „großzügig statt genau"
  (128/32/128/8 statt 84/22/80/6) hat hier **~900 LEs** gekostet.
- **Wiederverwendbar:** `rtl/fa_control/` ist self-contained (Paket + nandland-UART + Slave),
  VHDL-93, alle Anlagengrößen als Generics. Port nach WillFA/GottFA = Ordner kopieren + vier
  Zeilen Dateiliste + Instanz. **Achtung WillFA7:** dort liegen `uart_rx`/`uart_tx` schon unter
  `rtl/serial_api/` — nicht doppelt eintragen.

## Bekannte HW-Feintuning-Stellen
- **Switch-Matrix-Codierung — schaltplan-verifiziert (2026-07-02, `switch_matrix.vhd`):** aus
  `../doc/AtariFA_07_Final_Switches_SCH.PDF` (Eltern-Ordner `N:\Projekte\FPGA Atari\doc\`, Geschwister: Main/Lamps/Solenoids). 74HCT540 invertiert alle Ausgänge; E11a 74LS42-Spalten-Map
  `SW_Strobe` 0→F3,1→F5,2→F7,3→F6,4→F8,5→F9,6→F10,7→F11,8→F12,9→F13 (reproduziert Original-Ā3-Swap);
  74HC4049 invertiert den Rückkanal (`sw_com_in='1'`=geschlossen). Ergibt (offset=addr−0x2000):
  `sw_strobe(0)=offset(3)`, `sw_strobe(1)=¬offset(4)`, `sw_strobe(2)=¬offset(5)`, `sw_strobe(3)=¬offset(6)`;
  `sw_com(0)=offset(0)`, `sw_com(1)=offset(1)`, `sw_com(2)=¬offset(2)`. **Einzige Rest-Annahme
  (First-Boot-Check):** Netz `F_SW_Strobe_A..D`/`F_SW_COM_A..C` ↔ Port-Index `sw_strobe(0..3)`/`sw_com(0..2)`
  (A=Bit0). Falls Spalten/Zeilen im Switch-Test daneben → nur diese Bit-Index-Zuordnung 1-zeilig tauschen
  (Codierung selbst sicher). Debounce/Scan-Rate via Generic `DWELL_CYCLES` (~1 ms/Pass @640).
- **Ziffernreihenfolge — ✓ HW-korrigiert (2026-07-03, Prototyp):** Die Digit-Adresse ist gegenläufig
  zur logischen Ziffernreihenfolge verdrahtet (**Adresse 0 = physisch RECHTS, Adresse 5 = LINKS**);
  ohne Umkehr erschien die Version `   002` als `200   `. **Wichtig:** Die Umkehr sitzt **nur** in der
  **Boot-Info-Erzeugung** (`boot_info`-Prozess in `AtariFA.vhd`), **nicht** zentral in `display_control.vhd`.
  Grund (HW-Test 2026-07-03): der **Spiel-Shadow-Buffer** (`display1..4`/`status_d`, RAM-Sniffer) liegt
  bereits in HW-Adressreihenfolge vor (Index 0 = rechts); eine zentrale Umkehr in `display_control`
  **spiegelte die Spielanzeige doppelt** (Scores verkehrt herum, sobald Atari die Displaykontrolle
  übernimmt). Daher: `display_nibble`/`status_nibble` **linear** (`d(idx)`/`s(idx)`, Revert von `ddc27e8`);
  in `boot_info` werden nur die Boot-Info-Ziffern gespiegelt abgelegt (Version/Game/Options rechtsbündig
  auf Index 0..2 bzw. Options-Loop `bi_display3(6-i)`). `display_control` zählt weiter linear 0..7.
  *Boot-Info-Status ist blank; Spiel-Status (`status_nibble` linear) bei aktivem Spiel gegen Match/Credit
  gegenprüfen — falls doch gespiegelt, separat behandeln.*
- **Player-Reihenfolge — ✓ HW-korrigiert (2026-07-03, Prototyp):** Auch das **Player-Select-Feld**
  (`disp_Adr(5..3)` in `display_control.vhd`) ist gegenläufig verdrahtet — analog zur Ziffernreihenfolge.
  Ohne Umkehr erschien der **Player-4-Score physisch auf Player 1** (alle 4 Player-Displays spiegel-
  verschoben). Fix **nur im Spiel-Shadow-Buffer-Sniffer** (`AtariFA.vhd`): PinMAME-RAM-Player gespiegelt
  aufs Display-Signal gemappt (**Player1→display4, P2→display3, P3→display2, P4→display1**); RAM-Offsets
  folgen weiter PinMAME. `display_control` **und** `boot_info` bleiben unverändert (Boot-Info war korrekt
  und ist nicht betroffen). Status/Credit-Ball (Select `"111"`) unberührt.
- **Nibble-Paar-Tausch je Score-Byte — ✓ HW-korrigiert (2026-07-03, Prototyp):** Innerhalb jedes
  Score-Bytes sind die 2 BCD-Ziffern paarweise vertauscht (`200000`→`020000`, Selbsttest-Nr. `     1`
  →`    1 `). Fix **nur im Spiel-Sniffer** (`AtariFA.vhd`): **Low-Nibble (3..0) → gerader/rechter Index,
  High-Nibble (7..4) → ungerader/linker Index** (LSD rechts) für alle 4 Player-Scores. **NICHT** getauscht:
  Player-up-LED (Index 6), **Status/Credit-Ball** (0x1C/1D — dort ist die HW-Darstellung bereits korrekt,
  Status-Konvention weicht also vom Score ab) und **Boot-Info/Version** (unberührt, bleibt korrekt).
- **Lamp-Matrix-Zuordnung** (seit SW 0.1.3 in `rtl/common/lamp_map_pkg.vhd`, s. Abschnitt „Lamps"):
  595-Gruppe↔(Latch,Bit) steht als
  Tabelle **`GRP_OF`** im Code = Abschrift von `AtariFA_Lamps.xlsx`, Mappe **`aktuell`** (Mappe `alt`
  = Vorgängerstand mit der alten Formel). **HW-tunbar am Prototyp NUR dort:** `GRP_OF` (Gruppen-
  zuordnung), `STROBE_ENC` (2-Bit-Code ↔ SA/SB/SC/SD + 540-Invertierung), `offset[3:2]=Latch`/
  `offset[1:0]=Strobe`, 595-Shift-Reihenfolge. Im Lampen-Selbsttest prüfen, welche physische
  Lampe/Strobe aufleuchtet — liegen nur **Spalten** daneben, ist es `STROBE_ENC`, nicht `GRP_OF`.
- Treiber sind **ULN2003A** (Original-Design, kein TPIC): nur die 12 bestückten ICs A20…B15 genutzt;
  #44/#47-Glühlampen unkritisch (Original-Auslegung).

## Referenz
- **User Manual: `docs/AtariFA_HWv1_x_user_manual.md` (EN) und
  `docs/AtariFA_HWv1_x_Bedienungsanleitung.md` (DE)** — die nutzerseitige Sicht (DIP-Bedeutung,
  Boot-Ablauf/Info-Anzeige, Sound-Pfade, LEDs, Freispiel, Board-Varianten, „noch nicht implementiert").
  **Bei Änderungen an DIP-Belegung, Boot-Info-Anzeige, Options oder LED-Bedeutung BEIDE mitziehen** —
  das sind die einzigen Dateien, die diese Dinge aus Anwendersicht beschreiben. Die **Kapitelnummerierung
  ist in beiden identisch** (ein Verweis „siehe Kapitel 4.3" passt auf beide) — beim Ergänzen eines
  Kapitels also nicht in nur einer Fassung umnummerieren. Aufbau/Tiefe analog
  `N:\Projekte\WillFA7\FPGA_source\docs\WillFA7S_HWv1_x_user_manual.md`.
- PinMAME `src/wpc/atari.c`: maßgeblich für Speicher-Map, Display-Mapping, Switch/DIP-Handler
  (Referenzkopien der PinMAME-Quellen liegen zur Analyse in `docs/atari.c`/`docs/atari.h`/`docs/atarigames.c`)
- **Display-Timing-Analyse: `docs/Display_Timing.md`** (gemessen aus Original-Board, Schaltbild Sheet 15B)
- **Switch-Reading-Analyse: `docs/Switch_Reading_Analysis.md`** (0x200B-Testschalter-Polarität, ROM-Disassembly ME/Airborne)
- **Lamp-Refresh-Analyse (EN): `docs/Lamp_Refresh_Analysis.md`** (Original-Refresh = DMA-Hardware, NICHT Software;
  Vorglühen = HW-Artefakt der 20-V-Matrix, kein SW-„on-phase injection"; belegt via PinMAME `ram_w` +
  Airborne-ROM-Disasm + NMI-ISR; LEDs auf AtariFA sicher, Refresh ändert nur Duty/Timing, nicht Spannung)
- **FA-Control-Schnittstelle: `docs/FA_Control_Interface.md`** (LISY-Protokoll, Nummerierung von
  Lampen/Spulen/Schaltern/Displays, Übernahmemodell, Übernahme in andere FPGA-Projekte, Inbetriebnahme)
- **Boot-Sprachausgabe: `docs/Speech_Boot_Feasibility.md`** (Codec-Analyse + Umsetzung PCM 8 kHz)
- **FRAM-Persistenz: `docs/FRAM_Persistence.md`** (Credits/Highscore-Save/Restore, RE-Adressen Airborne,
  Bus-Injection-Mechanik, Atari-Attract-Anzeigeverhalten, zurückgestellte Score-Anzeige)
- ROM-Disassembler `tools/dis6800.py` (game-parametrierbar: `<rom@0x7000> <rom@0x7800> --name --out`)
- Vollständiger Code-Review: `N:\Projekte\FPGA Atari\AtariFA_Code_Review.md`
