# AtariFA

**FPGA replacement for the Atari Generation 1 pinball MPU.**

AtariFA is an FPGA-based recreation of the Atari Gen1 pinball CPU board, built around a
MC6800-compatible soft core (John Kent's `cpu68`). It is designed as a "piggy-back"
replacement that plugs into the original Atari edge connectors and replaces the CPU, RAM,
ROMs and TTL glue logic, while a single FPGA bitstream supports the whole Gen1 generation.

> Status: running on prototype hardware. The CPU core, clocking, memory map, game selection,
> free-play option, sound, a boot speech announcement, the switch matrix, the solenoid drivers,
> the lamp matrix and FRAM credit persistence are implemented and hardware-tested (see
> [Roadmap](#roadmap)). All five games
> boot, accept credits, start a game (including from the free-play ROMs) and — except Atarians,
> which has no documented self-test — enter the self-test and report switches correctly. Only the
> sound bench test is still outstanding.

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

## Solenoids

The 20 playfield solenoids (IRL540 MOSFETs via inverting 74HCT540 drivers) and the two coin-door
coils (coin counter, coin lockout) are driven by [`solenoid_driver.vhd`](solenoid_driver.vhd). It
latches the four original solenoid latches — high nibble of `0x1080/84/88` plus all of `0x108C`
(20 bits) — while the low nibbles of `0x1080/84/88` stay with the sound path:

| Latch | Bits | Function |
|---|---|---|
| `0x1080` | 4 / 5 | coin counter / coin lockout (coin door, via aux board) |
| `0x1080` | 6–7 | solenoids |
| `0x1084` / `0x1088` | 4–7 | solenoids |
| `0x108C` | 0–7 | solenoids |

The bit-to-output mapping is taken from the AtariFA board schematic (two board positions are
unpopulated). Outputs are held off on reset and during boot, and `solenoids_enable` releases the
drivers only once the CPU is running — so the coils are safe before and during power-up.

## Lamps

The 84 playfield lamps are driven as a **21 × 4 multiplexed matrix** by
[`lamp_matrix.vhd`](lamp_matrix.vhd), reproducing the original Atari scheme: twelve ULN2003A sink
drivers (rows) fed by a cascade of **three 74HC595** shift registers (21 used outputs = 21 "lamp
groups"), and four column strobes SA–SD generated on the auxiliary board from a 2-bit select
(`aux_lamp_strobe`, decoded 1-of-4 there). Lamp state is sniffed from CPU writes to RAM `0x30–0x3F`
into a 128-bit shadow buffer (analogous to the display) and scanned out continuously.

The group/strobe assignment is derived from the board schematics — the 9334 addressable-latch decode
([`doc/Lamp_Logic2.png`](doc/Lamp_Logic2.png)) plus the 74HC595 wiring table (`doc/AtariFA_Lamps.xlsx`):
lamp group `N = 4·b + L + 1` and RAM offset `= L·4 + s`. The scanner blanks the outputs (`oe_595`)
while shifting and switching strobes to avoid ghosting, giving the native ~25 % per-lamp duty of a
4-way multiplex. The 595 control lines run through a non-inverting 74HCT541; the strobe select runs
through the inverting 74HCT540 and is enabled with the CPU, so the lamps are safely off during boot
and reset.

## Boot speech

At power-up the board speaks a short word ("Lisü", a retro robot voice) once, during the ~5 s
boot configuration window, reusing the on-board sound path (sigma-delta PWM on `SB_Sound` →
RC low-pass → TDA7267). [`speech.vhd`](speech.vhd) plays back **8-bit PCM at 8 kHz** from a
4096×8 ROM ([`speech_rom.vhd`](speech_rom.vhd), 4 M9K) straight into the same sigma-delta DAC;
the speech output takes priority over the game sound while it is playing. The ROM image
[`rom/lisy.mif`](rom/lisy.mif) is generated offline from a text-to-speech WAV (the encoder and
the full codec rationale — why PCM rather than 1-bit delta — are in
[`doc/Speech_Boot_Feasibility.md`](doc/Speech_Boot_Feasibility.md)). The module is self-contained
and reusable across boards: it needs only a clock, a reset and a start trigger.

## FRAM persistence (credits / high score)

Atari Gen1 has **no native NVRAM** — RAM `0x0000–0x01FF` is cleared on boot, so credits and the last
game's scores are lost on power-down. AtariFA persists them in an external I²C FRAM (**FM24CL64B**,
slave `0x51`) driven by [`fram_i2c.vhd`](fram_i2c.vhd), a bit-banging I²C master. Currently implemented
for **Airborne Avenger** only; enabled via `options(1)` (ON = restore, OFF = erase on boot).

- **Stage 1 — save/restore to FRAM (hardware-tested):** the game-end is detected from the **outhole
  switch**; once the scores have been stable for ~3 s (bonus count finished), credits (`$D5`) and player
  scores (`$81–$8A`) are written to the FRAM together with a validity signature. On the next boot they
  are read back into an FPGA shadow and shown in the boot-info window for verification.
- **Stage 2 — bus-injection restore (credit restore hardware-verified):** to make the restored values
  take effect *in the game*, the FPGA briefly asserts the CPU core's `halt`, muxes the RAM port and
  writes the shadow bytes straight into game RAM just after the boot clear, then resumes the CPU.
  Credit restore is confirmed on hardware (two restored credits, coin → three).

**Score display is intentionally deferred:** after a cold boot Atari shows `888888` on all displays for
~20–30 s and then blanks the player displays — scores are only shown *after a game has been played*.
The restored scores are correctly injected into RAM but stay invisible in the cold-boot attract until
Atari is also put into its "game played" state (a RAM flag, found via ROM disassembly — not yet done).
Score injection is therefore switched off by default (`INJ_SCORES = false`; the mechanism remains in
place). See [`doc/FRAM_Persistence.md`](doc/FRAM_Persistence.md) for the reverse-engineered addresses,
the injection mechanism and the full Atari attract-display analysis.

## Target hardware

- **FPGA:** Intel/Altera Cyclone 10 LP **10CL006YE144C8G** (E144 package)
- **Board:** AtariFA-PCB — replacement CPU with RAM/ROM + TTL substitutes, parallel to the
  Atari edge connectors plus "box connectors" for bench testing
- Displays driven via 74HCT540, lamps via 12× ULN2003A (three 74HC595 shift registers), solenoids
  via IRL540 MOSFETs through 74HCT540 drivers, I²C FRAM (FM24CL64B) for high-score storage, optional
  ESP32-C3 link

Resource usage (full compile): logic 40 %, block RAM 26/30 M9K (87 %), 1/2 PLL, timing met.

## Architecture highlights

- **Clocking:** 50 MHz system clock; 1 MHz CPU clock via PLL (`cpu_clock`, ÷50).
- **NMI/DMA:** synchronous 12-bit counter, 4096 µs NMI period (**244 Hz**, matching PinMAME's
  `ATARI_NMIFREQ` and the measured display frame rate); DMA toggle on bit 6 of `0x2000` (the game
  code requires this display-sync handshake).
- **Display:** multiplexed refresh whose timing (blank/show phases, ~512 µs/digit, ~244 Hz,
  ~1:3 blank:show duty) is matched to the original hardware — measured from a logic-analyzer
  capture of a real board, see [`doc/Display_Timing.md`](doc/Display_Timing.md).
- **Memory map:** RAM `0x0000–0x01FF` (+ mirror `0x1000`); lamp RAM `0x30–0x3F` (sniffed to the
  lamp matrix); sound latches `0x1080/84/88` (low nibble); solenoid latches `0x1080/84/88` (high
  nibble) + `0x108C`; ROM2 `0x7000`, ROM1 `0x7800`/`0xF800` (reset/IRQ vectors); DIP/DMA `0x2000`;
  switch matrix `0x2010–0x204F`; watchdog `0x4000`. Open-bus default `0xFF`. Consistent with
  PinMAME `src/wpc/atari.c`.
- **ROMs:** generic `game_rom.vhd` wrapper (`altsyncram`, 2 K×8, init file as a generic),
  instantiated per game/slot and muxed by `game_select`.
- **Safe inactive levels:** every output is driven to a defined inactive level explicitly
  (rather than left undriven), so the solenoid and lamp drivers stay off before and during
  boot — released only once the CPU is running.

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
| `speech.vhd` / `speech_rom.vhd` | Boot speech ("Lisü"): 8-bit PCM player + 4096×8 ROM |
| `solenoid_driver.vhd` | Solenoid + coin-door latches (20 IRL540 via 74HCT540) |
| `lamp_matrix.vhd` | Lamp matrix scanner (21×4 multiplex: 12× ULN2003A + three 74HC595 + aux strobes) |
| `fram_i2c.vhd` | I²C master for the FM24CL64B FRAM (credit / high-score persistence) |
| `AtariFA.qsf` / `AtariFA.sdc` | Pin/assignment and timing constraints |
| `rom/` | Game ROM images (Intel HEX) + `82s130` sound PROM |
| `rom/freeplay/` | Free-play ROM variants (reference) + `gen_patches.py` |
| `doc/` | Schematics (`Display_Logic.png` Sheet 15B, `Auxiliary_PCB.png` Sheet 15A) + analyses (`Display_Timing.md`, `Sound_Emulation.md`, `Speech_Boot_Feasibility.md`, `Switch_Reading_Analysis.md`, `FRAM_Persistence.md`) |

## Roadmap

- **Implemented:** CPU integration, clocking, NMI/DMA, memory map, display routines,
  5-game selection, free-play option, boot configuration display, boot speech announcement,
  4 test-board inputs, safe driver default levels, sound emulation (switchable original aux
  board / on-board card), switch matrix, solenoid + coin-door drivers, lamp matrix.
- **Phase B:** ✓ switch matrix (`0x2010–0x204F`), ✓ solenoid latches (high nibble of
  `0x1080/84/88` + `0x108C`, `solenoid_driver.vhd`), ✓ lamp matrix (`lamp_matrix.vhd`, 21×4
  multiplex) — all hardware-tested. **Phase B complete.**
- **Phase C:** ✓ audio done (`sound.vhd`); remaining: generic per-game configuration.
- **FRAM persistence:** ✓ credit save/restore hardware-verified (`fram_i2c.vhd` + injection FSM,
  Airborne). Deferred: making restored **scores** visible in attract (needs the "game played" RAM flag)
  and extending the addresses to the other four games.
- **Phase D:** cleanup, SDC completion, input synchronizers.
- Watchdog reset is intentionally decoupled until the in-game `0x4000` kick is characterized.

## Credits & references

- CPU core: **`cpu68`** by John Kent.
- Memory map / display / switch / DIP behavior referenced from **PinMAME** (`src/wpc/atari.c`).
- FPGA pinball replacement design by **bontango** — https://github.com/bontango/AtariFA
