# AtariFA

**FPGA replacement for the Atari Generation 1 pinball MPU.**

AtariFA is an FPGA-based recreation of the Atari Gen1 pinball CPU board, built around a
MC6800-compatible soft core (John Kent's `cpu68`). It is designed as a "piggy-back"
replacement that plugs into the original Atari edge connectors and replaces the CPU, RAM,
ROMs and TTL glue logic, while a single FPGA bitstream supports the whole Gen1 generation.

> Status: hardware design verified, prototype-ready. The CPU core, clocking, memory map,
> game selection and free-play option are implemented and compile clean; switch matrix,
> lamps, solenoids and audio are being added step by step (see [Roadmap](#roadmap)).

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

A free-play variant of each game is supported via the `options(3)` DIP (active-low).
Instead of storing six additional 2 KB ROMs (which would not fit on the device), the few
bytes that differ between the stock and free-play ROMs (42 bytes total across all games)
are overlaid combinationally onto the ROM data path. This costs **zero additional block
RAM**. The free-play ROM images live in `rom/freeplay/` as reference only; the patch table
in `AtariFA.vhd` is generated and verified by `rom/freeplay/gen_patches.py`.

## Target hardware

- **FPGA:** Intel/Altera Cyclone 10 LP **10CL006YE144C8G** (E144 package)
- **Board:** AtariFA-PCB — replacement CPU with RAM/ROM + TTL substitutes, parallel to the
  Atari edge connectors plus "box connectors" for bench testing
- Displays driven via 74HCT540, lamps via TPIC6B595N, solenoids via IRL540 MOSFETs through
  74HCT540 drivers, I²C FRAM (FM24CL64B) for high-score storage, optional ESP32-C3 link

Resource usage (full compile): logic 26 %, block RAM 21/30 M9K (70 %), 1/2 PLL, timing met.

## Architecture highlights

- **Clocking:** 50 MHz system clock; 1 MHz CPU clock via PLL (`cpu_clock`, ÷50).
- **NMI/DMA:** synchronous 9-bit counter, 512 µs NMI period; DMA toggle on bit 6 of `0x2000`
  (the game code requires this display-sync handshake).
- **Memory map:** RAM `0x0000–0x01FF` (+ mirror `0x1000`); ROM2 `0x7000`, ROM1 `0x7800`/`0xF800`
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
| `cpu_clock.vhd` | PLL (50 MHz → 1 MHz CPU clock) |
| `watchdog.vhd`, `slow_to_fast_clock.vhd`, `boot_message.vhd` | Support modules |
| `lamp_driver.vhd` | Lamp matrix driver (TPIC6B595N) — present, activated in Phase B |
| `AtariFA.qsf` / `AtariFA.sdc` | Pin/assignment and timing constraints |
| `rom/` | Game ROM images (Intel HEX) + `82s130` sound PROM |
| `rom/freeplay/` | Free-play ROM variants (reference) + `gen_patches.py` |

## Roadmap

- **Implemented:** CPU integration, clocking, NMI/DMA, memory map, display routines,
  5-game selection, free-play option, 4 test-board inputs, safe driver default levels.
- **Phase B:** full switch matrix (`0x2010–0x204F`), solenoid latches, lamp matrix
  (`lamp_driver.vhd` activation).
- **Phase C:** audio (internal sound card + Atari aux board), generic per-game configuration.
- **Phase D:** cleanup, SDC completion, input synchronizers.
- Watchdog reset is intentionally decoupled until the in-game `0x4000` kick is characterized.

## Credits & references

- CPU core: **`cpu68`** by John Kent.
- Memory map / display / switch / DIP behavior referenced from **PinMAME** (`src/wpc/atari.c`).
- FPGA pinball replacement design by **bontango** — https://github.com/bontango/AtariFA
