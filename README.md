# AtariFA

**FPGA replacement for the Atari Generation 1 pinball MPU.**

AtariFA is an FPGA-based recreation of the Atari Gen1 pinball CPU board, built around a
MC6800-compatible soft core (John Kent's `cpu68`). It is designed as a "piggy-back"
replacement that plugs into the original Atari edge connectors and replaces the CPU, RAM,
ROMs and TTL glue logic, while a single FPGA bitstream supports the whole Gen1 generation.

> Status: hardware design verified, prototype-ready. The CPU core, clocking, memory map,
> game selection, free-play option and sound are implemented and compile clean; switch
> matrix, lamps and solenoids are being added step by step (see [Roadmap](#roadmap)).

## Supported games

A single build hosts all five Atari Gen1 titles; the active game is chosen at power-up via
the `game_select` DIP switches:

| `game_select` (sw1,sw2,sw3) | Game | ROM1 (E0) | ROM2 (E00) |
|---|---|---|---|
| OFF,OFF,OFF | Atarians | `atarian.e0` | `atarian.e00` |
| ON,OFF,OFF | Time 2000 | `time.e0` | `time.e00` |
| OFF,ON,OFF | Airborne Avenger | `airborne.e0` | `airborne.e00` |
| ON,ON,OFF | Middle Earth | `608` | `609` |
| OFF,OFF,ON | Space Riders | `spacel` | `spacer` |

Unused switch combinations fall back to Middle Earth. All five games reside in BRAM
simultaneously and are multiplexed — no reconfiguration needed to switch games.

## Free play

A free-play variant of each game is supported via the `freeplay` DIP (active-low).
Instead of storing six additional 2 KB ROMs (which would not fit on the device), the few
bytes that differ between the stock and free-play ROMs (42 bytes total across all games)
are overlaid combinationally onto the ROM data path. This costs **zero additional block
RAM**. The free-play ROM images live in `rom/freeplay/` as reference only; the patch table
in `AtariFA.vhd` is generated and verified by `rom/freeplay/gen_patches.py`.

## DIP configuration (10 switches)

Configuration uses **10 DIP switches**: a 4-switch block (3× game select + 1× free-play) and a
6-switch block (6× options).

- The **first 6 DIPs** (3× game select + free-play + options 1–2) are read once at boot through a
  3×2 strobe matrix. The FSM in `read_the_dips.vhd` temporarily repurposes the lamp shift-register
  IOs `serin_595 / clk_595 / rclk_595` as matrix strobes (returns on `dip_ret`), then hands the pins
  back to the lamp logic once boot is complete.
- DIPs **7–10** (`options(3..6)`) are read directly from `dip_opt` and may be changed live during a game.
- Boot is sequenced by `boot_phase`: phase 0 reads the DIPs, phase 1 (read done) turns the displays
  on, phase 2 shows the configuration for ~5 s (see below) and then releases the CPU from reset.

### Boot info display

Once the DIPs are latched and before the game ROM starts, the displays show the current
configuration for about 5 seconds (right-justified, blanks where unused):

| Display | Shows |
|---|---|
| 1 | Firmware version `SW_MAIN SW_SUB1 SW_SUB2` |
| 2 | Selected game index (0–7), two-digit decimal with leading zero |
| 3 | The six `options` bits (option 1 leftmost), `1` = ON / `0` = OFF |
| 4 | Free-play state: `1` when enabled, `0` otherwise |
| Status | blank |

## Sound

The Atari Gen1 sound hardware (sound PROM `D12` + counters on the CPU board, weighted-resistor
DAC + amplifier on the auxiliary board) is recreated digitally in [`sound.vhd`](sound.vhd).
The PROM holds **16 waveforms × 32 samples** (4-bit); a programmable divider sets the pitch and a
4-bit value sets the volume, written through three shared latches:

| Latch | Bits | Function |
|---|---|---|
| `0x1080` | 0–3 | waveform select |
| `0x1088` | 0–3 | pitch (divider `16 − value`) |
| `0x1084` | 0–3 | volume |

The output path is switchable live via `options(3)` (DIP, active-low):

- **OFF** (`'1'`) — *original*: 4-bit `AUDIO 0–3` + volume latch drive the **real auxiliary board**
  (its resistor DAC, CD4016 attenuator and amplifier do the analog work).
- **ON** (`'0'`) — *emulation*: the full waveform incl. volume is synthesized and output as a 1-bit
  sigma-delta stream on `SB_Sound` to the **on-board sound card** (RC low-pass + TDA7267).

The implementation is intentionally simplified (synchronous counters, sigma-delta DAC) — see
[`doc/Sound_Emulation.md`](doc/Sound_Emulation.md) for the full schematic analysis and model.

## Target hardware

- **FPGA:** Intel/Altera Cyclone 10 LP **10CL006YE144C8G** (E144 package)
- **Board:** AtariFA-PCB — replacement CPU with RAM/ROM + TTL substitutes, parallel to the
  Atari edge connectors plus "box connectors" for bench testing
- Displays driven via 74HCT540, lamps via TPIC6B595N, solenoids via IRL540 MOSFETs through
  74HCT540 drivers, I²C FRAM (FM24CL64B) for high-score storage, optional ESP32-C3 link

Resource usage (full compile): logic 29 %, block RAM 22/30 M9K (73 %), 1/2 PLL, timing met.

## Architecture highlights

- **Clocking:** 50 MHz system clock; 1 MHz CPU clock via PLL (`cpu_clock`, ÷50).
- **NMI/DMA:** synchronous 9-bit counter, 512 µs NMI period; DMA toggle on bit 6 of `0x2000`
  (the game code requires this display-sync handshake).
- **Display:** multiplexed refresh whose timing (blank/show phases, ~512 µs/digit, ~244 Hz,
  ~1:3 blank:show duty) is matched to the original hardware — measured from a logic-analyzer
  capture of a real board, see [`doc/Display_Timing.md`](doc/Display_Timing.md).
- **Memory map:** RAM `0x0000–0x01FF` (+ mirror `0x1000`); sound latches `0x1080/84/88`
  (low nibble; high nibble reserved for solenoids); ROM2 `0x7000`, ROM1 `0x7800`/`0xF800`
  (reset/IRQ vectors); DIP/DMA `0x2000`; switch matrix `0x2010–0x204F`; watchdog `0x4000`.
  Open-bus default `0xFF`. Consistent with PinMAME `src/wpc/atari.c`.
- **ROMs:** generic `game_rom.vhd` wrapper (`altsyncram`, 2 K×8, init file as a generic),
  instantiated per game/slot and muxed by `game_select`.
- **Safe inactive levels:** all not-yet-implemented outputs are driven to their inactive
  level explicitly so the solenoid/lamp drivers stay off before the corresponding logic is
  wired up.

## Building

Requires **Intel Quartus Prime 22.1std.2 Lite Edition**.

```sh
# Command-line full compile (Analysis & Synthesis -> Fitter -> Assembler -> Timing)
quartus_sh --flow compile AtariFA
```

Or open `AtariFA.qpf` in the Quartus GUI and run a full compilation. The output bitstream is
written to `output_files/`.

## Repository layout

| Path | Description |
|---|---|
| `AtariFA.vhd` | Top level: CPU integration, memory map, game select, free-play overlay |
| `cpu68.vhd` | MC6800-compatible CPU core (John Kent) |
| `game_rom.vhd` | Generic 2 K×8 ROM wrapper (init file via generic) |
| `read_the_dips.vhd` | Boot-time DIP read FSM (3×2 strobe matrix on the lamp IOs) |
| `cpu_clock.vhd` | PLL (50 MHz → 1 MHz CPU clock) |
| `watchdog.vhd`, `slow_to_fast_clock.vhd`, `display_control.vhd` | Support modules |
| `sound.vhd` | Sound emulation (PROM playback + pitch divider + sigma-delta DAC) |
| `lamp_driver.vhd` | Lamp matrix driver (TPIC6B595N) — present, activated in Phase B |
| `AtariFA.qsf` / `AtariFA.sdc` | Pin/assignment and timing constraints |
| `rom/` | Game ROM images (Intel HEX) + `82s130` sound PROM |
| `rom/freeplay/` | Free-play ROM variants (reference) + `gen_patches.py` |
| `doc/` | Schematics (`Display_Logic.png` Sheet 15B, `Auxiliary_PCB.png` Sheet 15A) + analyses (`Display_Timing.md`, `Sound_Emulation.md`) |

## Roadmap

- **Implemented:** CPU integration, clocking, NMI/DMA, memory map, display routines,
  5-game selection, free-play option, boot configuration display, 4 test-board inputs,
  safe driver default levels, sound emulation (switchable original aux board / on-board card).
- **Phase B:** full switch matrix (`0x2010–0x204F`), solenoid latches (high nibble of
  `0x1080/84/88`), lamp matrix (`lamp_driver.vhd` activation).
- **Phase C:** ✓ audio done (`sound.vhd`); remaining: generic per-game configuration.
- **Phase D:** cleanup, SDC completion, input synchronizers.
- Watchdog reset is intentionally decoupled until the in-game `0x4000` kick is characterized.

## Credits & references

- CPU core: **`cpu68`** by John Kent.
- Memory map / display / switch / DIP behavior referenced from **PinMAME** (`src/wpc/atari.c`).
- FPGA pinball replacement design by **bontango** — https://github.com/bontango/AtariFA
