# AtariFA — Claude Code Projektkontext

## Projekt
FPGA-Nachbau der Atari Gen1 Pinball-MPU (MC6800 / John Kent cpu68).
Quartus Prime **22.1std.2 Lite Edition**. GitHub: https://github.com/bontango/AtariFA
- **Zielplatine (AtariFA-PCB):** Cyclone 10 LP **10CL006YE144C8G** (E144) — „piggy-back"-Replacement-CPU mit RAM/ROM + TTL-Ersatz, parallel zu den Atari-Edge-Connectors plus „Box-Connectors". Migriert 2026-06; nur Display-Routinen übernommen, Rest (Switch/Lamps/Solenoide/Audio/FRAM/ESP32) step-by-step (Phase B/C).
- **Testplatine (vorher):** GottFA3 / Cyclone IV E EP4CE6F17C8 — Bring-up abgeschlossen 2026-06-06.

## Zielspiele
Generische Gen1-Basis: Atarians, Time 2000, Airborne Avenger, Middle Earth, Space Riders.
Aktuell ROM: Middle Earth 608/609 + 82s130 Sound-ROM.

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
- **B4**: Async-Inputs ohne Synchronizer — `switch[1..4]` haben jetzt 2-FF-Sync (`sw_meta`/`sw_sync`, clk_50); `switch[5..16]` und `options[]` noch ohne (Phase D)
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
- **Phase C**: Audio (0x3000/0x6000), generische Spiel-Konfiguration per Generic
- **Phase D**: Cleanup, SDC weiter vervollständigen (B4 switch[5..16]/options[], IO-Delays), Test-Module hinter Generic
  - ✓ Hold-Violations behoben (`set_false_path` cpu_clk_d1), SDC → `AtariFA.sdc` umbenannt

## Bekannte HW-Feintuning-Stellen
- Ziffernreihenfolge im Shadow-Buffer-Demux (case-Zweige in `AtariFA.vhd`) — PinMAME-Segment-Indizes sind absteigend, physische Verdrahtung muss auf Hardware geprüft werden
- Lampennummer↔Bit-Mapping im Lamp-Sniffer (`AtariFA.vhd`, derzeit linear) — PinMAME `col=(offset%4)*2+offset/8`, physische Zuordnung auf Hardware prüfen
- TPIC6B595N nur ~150 mA Dauer/Ausgang — bei #44/#47-Glühlampen schwächer als ULN2003A (Paketverlustleistung prüfen), mit LEDs unkritisch

## Referenz
- PinMAME `src/wpc/atari.c`: maßgeblich für Speicher-Map, Display-Mapping, Switch/DIP-Handler
- Vollständiger Code-Review: `N:\Projekte\FPGA Atari\AtariFA_Code_Review.md`
