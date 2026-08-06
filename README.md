# AtariFA

An Atari Gen1 pinball MPU on a low cost FPGA — a piggy-back replacement CPU board that
sits on the original Atari edge connectors, emulates the MC6800, provides RAM and ROM and
replaces most of the TTL around it.

Covers **Atarians, Time 2000, Airborne Avenger, Middle Earth and Space Riders**: all five
game ROMs live in the FPGA at once and are picked with a 3-bit DIP switch, with a free-play
option overlaid on top.

Ralf Thelen ('bontango') · <https://lisy.dev>

---

## Boards

The same design runs on two piggy-back boards. They share **one** top level
(`top/AtariFA.vhd`) and one source tree; what differs per board is a handful of pin
locations and one constant.

| Variant | Board | FPGA | Status |
|---|---|---|---|
| `cyclone_10_pcb` | AtariFA PCB v1.0 with the lisy.dev Cyclone 10 piggy-back board | 10CL006YE144C8G | lead variant, hardware tested through SW 0.1.2 |
| `cyclone_10_dev_open` | AtariFA PCB v1.0 carrying the 'dev_open' Cyclone 10 board | 10CL006YE144C8G | **not** hardware tested |

The version on the boot info display reads `<BoardId>.<SW_SUB1>.<SW_SUB2>`, so the leading
digit tells you which board you are looking at: `0.1.2` is the PCB board, `1.1.2` the
dev_open one.

Differences between the two boards, in full: pin-out; the dev_open board has four on-board
status LEDs instead of three (D4 spare) and its own reset switch; and it routes 3 of the 8
debug lines to the logic analyser header instead of all 8.

## Layout

```
top/            the one top level, shared by every variant
rtl/common/     all functional modules + the version and type packages
rtl/cyclone_10/ the megafunctions generated for this FPGA family
rom/            game ROMs, the sound ROM and the speech PCM
variants/<name>/  variant_pkg.vhd  BOARD_ID
                  device.tcl       FAMILY / DEVICE / Quartus version
                  pins.tcl         the pin locations
                  AtariFA.sdc      timing constraints
                  AtariFA.qpf      Quartus project file
                  AtariFA.cof      .sof -> .jic conversion setup
                  AtariFA.qsf      GENERATED - do not edit
scripts/        gen_qsf.ps1, check.ps1, build.ps1, release.ps1 + the .qsf fragments
bin/            release artefacts per board + changelog.txt
docs/           analyses, schematics, PinMAME reference sources
archive/        historic modules, in no build
```

## Build

```powershell
scripts\check.ps1              # analysis & synthesis of every variant, fast
scripts\check.ps1 -Fit         # + fitter and timing, compared against scripts\baseline.csv
scripts\build.ps1 cyclone_10_pcb   # full compile + .jic
scripts\release.ps1 -Note "..."    # build all, copy to bin\, write changelog
```

Quartus Prime 22.1std.2 Lite Edition, `C:\intelFPGA_lite\22.1std\`. `quartus_sh` is not on
the PATH; the scripts know where it lives.

**Never edit `variants/<name>/AtariFA.qsf`** — it is generated. Change `device.tcl`,
`pins.tcl`, `variant.psd1` or the `scripts/files_*.tcl` lists and rerun `gen_qsf.ps1`
(`check.ps1` and `build.ps1` do that for you). Quartus writes into the file by itself when
the project is open in the IDE, which is exactly why it is regenerated before every build.

## Repository note

This repository used to be the single flat project folder `N:\Projekte\FPGA Atari\AtariFA`.
Its history moved here on 06.08.2026 when the second board variant made one shared tree
necessary. The two old folders `AtariFA\` and `AtariFA_dev_open\` are kept as a backup until
the rebuilt design has been on hardware — **do not commit or push from them.**

## Third party

CPU core `rtl/common/cpu68.vhd` by John Kent. Memory map, display mapping and the
switch/DIP handlers follow PinMAME `src/wpc/atari.c` (reference copies in `docs/`).
