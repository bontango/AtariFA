# AtariFA — Claude Code Projektkontext

## Projekt
FPGA-Nachbau der Atari Gen1 Pinball-MPU (MC6800 / John Kent cpu68) auf **Cyclone IV E EP4CE6F17C8**.
Quartus Prime **22.1std.2 Lite Edition**. GitHub: https://github.com/bontango/AtariFA

## Zielspiele
Generische Gen1-Basis: Atarians, Time 2000, Airborne Avenger, Middle Earth, Space Riders.
Aktuell ROM: Middle Earth 608/609 + 82s130 Sound-ROM.

## Wichtige Konventionen
- VHDL: `use ieee.std_logic_unsigned.all` — kein `numeric_std` (würde Konflikte erzeugen)
- Taktstrategie: `clk_50` = 50 MHz Systemtakt; `cpu_clk` = 1 MHz via PLL (`cpu_clock.vhd`, altpll ÷50)
- RAM-Write-Strobe immer in `clk_50`-Domain (fallende cpu_clk-Flanke per Edge-Detect auf `cpu_clk_d1/d2`)
- Open-Bus-Default: `cpu_din <= x"FF"` wenn keine CS aktiv
- Display-Outputs sind **invertiert** wegen 74HCT240-Treiber: `disp_* <= not i_disp_*`
- SDC-Datei: `AtariFA.sdc`; `cpu_clk` (PLL clk[0]) wird als Datensignal in `clk_50` gesampled → `set_false_path` auf `cpu_clk_d1` (verhindert falsche Hold-Violations durch „clock-used-as-data")

## Architektur-Entscheidungen (nicht rückgängig machen ohne Grund)
- **Shadow-Buffer statt Dual-Port-RAM**: Schreibzugriffe auf RAM 0x00–0x1F werden per Write-Sniffer in `display1..4`/`status_d` kopiert (Single-Port-RAM bleibt für CPU)
- **DMA-Toggle**: `dma_toggle` flippt alle 2 NMI-Pulse (Edge-Detect auf `nmi_level`, Modulo-2 in clk_50-Prozess); Bit 6 von 0x2000 — Game-Code braucht diesen Wechsel zum Fortlaufen
- **Synchroner 9-Bit-Zähler** statt 3× SN7493-Ripple-Kaskade; NMI-Periode = 512 cpu_clk = 512 µs

## Offene Bugs (bewusst zurückgestellt)
- **B4**: Async-Inputs ohne Synchronizer — `switch[1..4]` haben jetzt 2-FF-Sync (`sw_meta`/`sw_sync`, clk_50); `switch[5..16]` und `options[]` noch ohne (Phase D)
- **B5**: Open Outputs / Tristate-Defaults (BUFFER_*, SRAM_*, SPI, Audio)
- **B10–B12**: Toter Code, Non-Standard-Libs, Display-Signal-Ownership

## Watchdog-Status (offen)
- `reset_h` enthält **kein** `wd_reset` (bewusst entfernt): Game kickt 0x4000 nicht im Attract Mode → WD würde CPU resetten
- WD-Instanz bleibt aktiv (LED_D1 zeigt intern-Timeouts via `wd_seen`)
- Klären bei aktivem Spiel: ROM-Disassembly oder Schaltplan prüfen, ob/wann 0x4000 geschrieben wird
- **Nicht reaktivieren** bis Kick-Mechanismus verstanden

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
