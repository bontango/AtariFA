# AtariFA

**Atari Generation 1 MPU, based on FPGA**

**Hardware version v1.x**

**Software Version 0.1.4**

**user manual**

ralf@lisy.dev

v1.0 06.08.2026

> Eine deutsche Fassung gibt es unter `AtariFA_HWv1_x_Bedienungsanleitung.md`.
> A German version is available as `AtariFA_HWv1_x_Bedienungsanleitung.md`. The chapter
> numbering is the same in both.

## Table of contents

- [Important remark](#important-remark)
- [1. Introduction](#1-introduction)
- [2. Quickstart](#2-quickstart)
- [3. Installation](#3-installation)
  - [3.1. What AtariFA replaces and what it does not](#31-what-atarifa-replaces-and-what-it-does-not)
  - [3.2. The box connectors](#32-the-box-connectors)
  - [3.3. Fuses](#33-fuses)
- [4. Dip Switch Settings](#4-dip-switch-settings)
  - [4.1. The 4 switch bank: game select and free play](#41-the-4-switch-bank-game-select-and-free-play)
  - [4.2. The 6 switch bank: options](#42-the-6-switch-bank-options)
    - [4.2.1. Option 3 -> where the sound comes out](#421-option-3---where-the-sound-comes-out)
    - [4.2.2. Option 4 -> let FA-Control take over](#422-option-4---let-fa-control-take-over)
    - [4.2.3. Options 1, 2, 5, 6 -> reserved](#423-options-1-2-5-6---reserved)
  - [4.3. Six of the ten DIPs are read once, at boot](#43-six-of-the-ten-dips-are-read-once-at-boot)
- [5. Boot sequence](#5-boot-sequence)
  - [5.1. Phase 1: reading the DIP switches](#51-phase-1-reading-the-dip-switches)
  - [5.2. Phase 2: the info display](#52-phase-2-the-info-display)
  - [5.3. Phase 3: program execution](#53-phase-3-program-execution)
- [6. Game settings and self test](#6-game-settings-and-self-test)
  - [6.1. The programming DIP banks and the replay switch](#61-the-programming-dip-banks-and-the-replay-switch)
  - [6.2. The self test](#62-the-self-test)
  - [6.3. Credits and high scores are not kept](#63-credits-and-high-scores-are-not-kept)
- [7. Free play](#7-free-play)
- [8. Sound](#8-sound)
  - [8.1. What is rebuilt](#81-what-is-rebuilt)
  - [8.2. The two audio paths](#82-the-two-audio-paths)
  - [8.3. The boot announcement](#83-the-boot-announcement)
- [9. The FA-Control interface (ESP32)](#9-the-fa-control-interface-esp32)
  - [9.1. The permission: option 4](#91-the-permission-option-4)
  - [9.2. What happens while it has control](#92-what-happens-while-it-has-control)
  - [9.3. How control is handed back](#93-how-control-is-handed-back)
  - [9.4. What the web interface learns from the board](#94-what-the-web-interface-learns-from-the-board)
  - [9.5. Connecting it](#95-connecting-it)
- [10. The status LEDs](#10-the-status-leds)
- [11. Programming the FPGA](#11-programming-the-fpga)
- [12. Board variants](#12-board-variants)
- [13. Not implemented yet](#13-not-implemented-yet)
- [Appendix A 'game select'](#appendix-a-game-select)
- [Appendix B Quick reference](#appendix-b-quick-reference)

## Important remark

By using AtariFA it is possible to damage your pinball machine. As this is a private project with NO commercial interest the author accepts no liability for any damage that may arise by using AtariFA!

## 1. Introduction

AtariFA replaces the MPU of an Atari Generation 1 pinball machine with an FPGA board. It emulates the MC6800 processor, provides the ram and the game roms, and rebuilds the TTL logic around them - the address latches, the display multiplexer, the switch matrix decoders, the lamp drivers and the solenoid drivers.

The FPGA is a Cyclone 10 LP (10CL006) on a piggy-back board that sits on the AtariFA PCB. The PCB carries the original Atari edge connectors, so the board goes in where the Atari MPU came out.

**Five games are supported and all five are in the FPGA at the same time:**

The Atarians, Time 2000, Airborne Avenger, Middle Earth and Space Riders. Which one runs is set with three DIP switches - there is no SD card and nothing to download per game. Free play is a fourth DIP switch, not a different rom set.

**What do you need?**

- A PC with a USB port and a USB Blaster in order to be able to program the FPGA

That is all. No SD card, no card reader, no battery.

**Two things are worth knowing before you begin:**

- **Six of the ten DIP switches are read once, during boot.** Changing them while the game runs has no effect. See chapter 4.3.

- **Credits and high scores are lost when you switch the machine off.** That is not a limitation of AtariFA - the original Atari Generation 1 MPU has no battery backup either. See chapter 6.3.

## 2. Quickstart

1.  Download the latest FPGA program for **AtariFA** from lisy.dev

2.  Program the FPGA (chapter 11)

3.  Set 'game select' according to your pinball (Appendix A)

4.  Decide where the sound should come out - option 3, see chapter 4.2.1. For an unmodified machine with its Auxiliary Board in place, leave it **OFF**

5.  Replace your original Atari MPU with AtariFA

6.  Switch the game ON

7.  Watch the info display for about 5 seconds and check that game select and version are what you expect (chapter 5.2)

8.  Enjoy

There is no 'first boot' procedure and nothing to initialise - the board has no non volatile memory that would need it.

## 3. Installation

AtariFA has the same edge connectors as the original Atari Generation 1 MPU and goes in at its place. Switch the machine off, pull the original MPU, put AtariFA in, done.

### 3.1. What AtariFA replaces and what it does not

**Replaced:** the MPU board, including the display driver logic, the switch matrix decoders, the lamp drivers and the solenoid drivers. Those all live on the AtariFA PCB now - 12 ULN2003A for the lamp matrix, 20 IRL540 MOSFETs for the solenoids.

**Still needed: the Atari Auxiliary Board.** Two things come from there and are not rebuilt on AtariFA:

- **the four lamp strobes.** The lamp matrix is 21 x 4; AtariFA drives the 21 rows, the Auxiliary Board makes the four column strobes at +20 V out of the two select lines AtariFA sends it.
- **the audio output path**, unless you switch the sound to the on-board amplifier - see chapter 8.2.

The coin door counter and lockout coils are driven through the Auxiliary Board as well.

So: leave the Auxiliary Board in the machine.

### 3.2. The box connectors

Next to the original Atari edge connectors the PCB carries two 25 pin 'box connectors'. They bring the same signals out on a connector that is easier to probe, for testing on the bench without a playfield attached.

The box connectors also carry the four lamp strobes, made on the board by four P-channel MOSFETs. **Those are for test LEDs only** - they are not built to drive the 20 V lamp matrix of a real playfield. On a machine the strobes come from the Auxiliary Board.

### 3.3. Fuses

The board has its own fuse holders for the solenoid supply. Use **2 A slow blow**.

Two of the twenty solenoid drivers, Q14 and Q18, are not fitted - depending on the game those outputs do not exist on the original either. There is simply no MOSFET there, and the game cannot drive them anyway.

## 4. Dip Switch Settings

AtariFA has **ten DIP switches** in two banks: a bank of four and a bank of six.

Throughout this manual, and on the info display, a switch that is **'ON' counts**, and switch 1 of a bank is always the one that counts 1.

### 4.1. The 4 switch bank: game select and free play

| DIP  | Function                    | Weight |
|------|-----------------------------|--------|
| Dip1 | game select, bit 0          | 1      |
| Dip2 | game select, bit 1          | 2      |
| Dip3 | game select, bit 2          | 4      |
| Dip4 | **free play** - ON = active | -      |

The three game select switches give a number from 0 to 7. Numbers 0 to 4 are the five games, see Appendix A. **Numbers 5, 6 and 7 are not used and fall back to Middle Earth** - so a wrongly set switch never leaves the board without a game.

Free play is described in chapter 7.

### 4.2. The 6 switch bank: options

Default setting is **all 'OFF'** - that is the right setting for a standard machine.

| DIP  | Function                                              | read        |
|------|-------------------------------------------------------|-------------|
| Dip1 | reserved                                              | at boot     |
| Dip2 | reserved                                              | at boot     |
| Dip3 | **sound: OFF = Auxiliary Board, ON = on-board amplifier** | continuously |
| Dip4 | **let FA-Control take over** - ON = allowed            | continuously |
| Dip5 | reserved                                              | continuously |
| Dip6 | reserved                                              | continuously |

#### 4.2.1. Option 3 -> where the sound comes out

- **'OFF'** - **the original path.** AtariFA feeds the Atari Auxiliary Board exactly as the original MPU does: the four audio lines and the four volume latch lines. The sound is then made by the Auxiliary Board and goes to the amplifier of your machine. **This is the setting for an unmodified pinball.**

- **'ON'** - **the on-board path.** The sound is generated inside the FPGA, filtered and sent to the small amplifier (TDA7267) on the AtariFA PCB. Use this on the bench, or in a machine whose Auxiliary Board audio section is defective. The Auxiliary Board outputs are held in their idle state while this is selected.

**This switch may be changed while the game is running** - it is read continuously. The sound moves over immediately.

#### 4.2.2. Option 4 -> let FA-Control take over

- **'OFF'** - **nobody interferes.** A plugged in FA-Control module can watch the displays and switches, but it cannot switch anything. This is the setting for normal play, and it is the default.

- **'ON'** - **FA-Control may drive the machine.** Only then does AtariFA hand over control when asked, and the game is stopped while it does. Everything else is in chapter 9.

This switch is read continuously as well: turning it 'OFF' while FA-Control is in charge takes control away **immediately** and restarts the game. That is the emergency stop for a test tool that has locked up.

#### 4.2.3. Options 1, 2, 5, 6 -> reserved

Not used, leave them 'OFF'. They are wired, they are shown on the info display, and they are there for later software versions.

Option 1 was used by an experimental credit/high score save feature that is currently on hold, see chapter 13. It has no effect in this software version.

### 4.3. Six of the ten DIPs are read once, at boot

**This is the one thing that catches people out.**

The first six switches - the three game select switches, free play, and options 1 and 2 - do not have six wires of their own. They are read through a small 3 x 2 matrix, and that matrix borrows three lines that belong to the lamp drivers. Reading it continuously would flicker the lamps, so it is read exactly once, during the boot phase, before the game starts. Afterwards the three lines go back to the lamps.

**So: after changing game select, free play or option 1 / 2, switch the machine off and on again.** A change while the game runs has no effect.

The remaining four switches - options 3 to 6 - have their own lines and are read continuously. They can be changed at any time.

## 5. Boot sequence

### 5.1. Phase 1: reading the DIP switches

Immediately after switching on, and after the internal clock has locked, the board reads the first six DIP switches through the strobe matrix. This takes microseconds; you will not see it. The displays are dark up to this point.

### 5.2. Phase 2: the info display

When the DIP read is done the displays come on and show the configuration for **about 5 seconds**. The CPU is still held in reset during this time - the game has not started yet.

| Display        | Shows                                                    |
|----------------|----------------------------------------------------------|
| **Player 1**   | version of the FPGA program, three digits: `<board> <sub1> <sub2>` |
| **Player 2**   | value of game select, two digits, 00 to 07               |
| **Player 3**   | the six option switches, option 1 on the left, option 6 on the right - `1` = ON |
| **Player 4**   | free play: `1` = active, `0` = not active                |
| **Credit/Ball**| dark                                                     |

Everything stands right aligned, the unused digits stay dark.

Example: player 1 showing `012`, player 2 showing `02`, player 3 showing `000000`, player 4 showing `0` is software 0.1.2 on the standard board, running Airborne Avenger, no options set, no free play.

**The leading digit of the version tells you which board variant you have**, see chapter 12. `0` is the standard AtariFA board.

About two seconds into this window the board says its name over the on-board amplifier - see chapter 8.3.

**Use this display.** It is the quickest way to see whether the DIP switches are what you think they are, and since six of them are only read here, it is the only place where you can check them at all.

### 5.3. Phase 3: program execution

After the info window the CPU is released and the game starts. From here on the displays belong to the game and behave exactly as with an original Atari MPU.

The game roms are inside the FPGA; there is nothing to load and no waiting.

## 6. Game settings and self test

Settings are made exactly as on the original Atari MPU. AtariFA rebuilds the original setting hardware 1:1, it does not replace it with a menu.

### 6.1. The programming DIP banks and the replay switch

The board carries the two banks of 8 programming DIP switches and the rotary 'replay' switch that the original Atari MPU has, at the same place in the address map. Set them following the manual of your pinball machine - AtariFA presents them to the game code exactly as the original does.

**Do not confuse these with the ten configuration DIPs from chapter 4.** The ten switches configure *AtariFA*; the two banks of eight and the replay switch configure *the game*.

In addition there are three push buttons on the board, wired in parallel to the machine: **'Atari Test', 'Coin 2' and 'Start'**. They make it possible to run and test the board on the bench without a coin door.

### 6.2. The self test

Press the test switch - either the one in the coin door or the one on the board. The game enters its self test, and you can step through switch tests, lamp tests, solenoid tests and displays following the manual of your pinball machine.

**Exception: The Atarians.** Atari's first game has no documented self test, and it does not react to the test switch. That is not a fault of AtariFA.

### 6.3. Credits and high scores are not kept

When the machine is switched off, credits and scores are gone. **The original Atari Generation 1 MPU behaves the same way** - unlike later machines it has no battery buffered memory at all.

The PCB does carry a FRAM chip to change that, but the feature is not finished and is switched off in this software version. See chapter 13.

If you want the machine to start without needing coins, use free play - chapter 7.

## 7. Free play

Switch 4 of the four switch bank, **ON = free play active**. Remember that this switch is read at boot only, so switch the machine off and on after changing it.

Free play works for **all five games**. Atari sold the free play version as a different set of roms; AtariFA has those differences built in and overlays them on the game rom when the switch is on. Only 42 bytes differ across all five games, which is why this fits without a second set of roms in the FPGA.

The result is byte for byte the same code the original free play roms contain.

## 8. Sound

### 8.1. What is rebuilt

The Atari Generation 1 tone generation, as it sits on the MPU board and the Auxiliary Board:

- **a waveform rom** with 16 waveforms of 32 samples, selected by the game
- **a pitch divider**, giving the note
- **a volume latch**, driving the attenuator on the Auxiliary Board

The game writes to three latches for waveform, pitch and volume, exactly as it does on the original, and AtariFA reproduces the resulting tone digitally.

This is the complete sound of an Atari Generation 1 machine - these games have no separate sound board and no speech.

### 8.2. The two audio paths

Set with option 3, see chapter 4.2.1: either the original Auxiliary Board path (switch OFF) or the on-board amplifier (switch ON). Both produce the same tones; they differ in where the analog signal is made.

**A note on how the games switch sound off.** The game code does not set the volume to zero when a sound should stop - it pulls the 'audio reset' line and leaves the volume latch where it was. AtariFA reproduces that: audio reset freezes the tone generation, which makes the output a constant level, which the Auxiliary Board blocks. If you hear a continuous tone that never stops, you are looking at a wiring problem on the audio lines to the Auxiliary Board, not at a volume problem.

### 8.3. The boot announcement

About two seconds after switch-on, during the info display window, the board says **"Lisü"** over the on-board amplifier. It is a fixed announcement, it plays once, and it tells you that the FPGA is running and the on-board audio chain works.

It always comes out of the **on-board amplifier**, regardless of option 3 - it is not part of the game sound and never reaches the Auxiliary Board.

If you hear nothing here, check the on-board amplifier and its speaker connection before you look anywhere else.

## 9. The FA-Control interface (ESP32)

The board has a socket prepared for an **ESP32-C3 Super Mini**. It runs **FA-Control** - a small firmware that opens a WLAN and serves a test interface in your browser: switch every lamp individually, pulse every solenoid, watch all switches live, write digits to the displays, play sounds.

This is a **tool for the bench and for fault finding**, not an accessory for normal play. If you plug nothing in, you will never notice this interface - the board behaves exactly as it does without.

> This feature is new in software version 0.1.3 and has been tried on a real machine.

### 9.1. The permission: option 4

A test tool must not be able to interfere with a running game unasked. So **two things** have to come together:

1. The ESP32 module actively asks ("I would like to take over").
2. **Option DIP 4 is ON.**

With option 4 OFF, the web interface says in plain words *"control refused - set option DIP 4 to ON"*, and the game carries on undisturbed. Reading is still allowed: you can follow switch states during a running game without giving anything up.

### 9.2. What happens while it has control

**The game is stopped.** The processor is held in reset, and everything - lamps, solenoids, displays, sound - now comes from the web interface. It has to work that way: if the game kept running it would overwrite every lamp you set by hand within a few milliseconds.

**The game then starts over.** It cannot be paused and resumed. A game in progress is lost, so only take control in attract mode or on the bench.

### 9.3. How control is handed back

Three ways, and all three make every output drop and the game restart immediately:

- **In the web interface**, press "hand back control".
- **Set option DIP 4 to OFF.** The switch is read continuously - this is the emergency stop.
- **Do nothing.** If the module goes quiet for two seconds, AtariFA hands back by itself. That is the safety net for a module that locks up, reboots or loses contact - the machine does not stay stuck in the handover, it comes back as an ordinary pinball.

### 9.4. What the web interface learns from the board

On connecting, FA-Control asks the board what it is made of and configures itself - nothing has to be typed in. AtariFA answers:

| | |
|---|---|
| Identification | `AtariFA` |
| Software version | the same one the info display shows, e.g. `0.1.4` |
| Lamps | 84 |
| Solenoids | 22 (20 playfield + coin counter + lockout coil) |
| Switches | 80 |
| Sounds | 16 |
| Displays | 5 (status with 4 digits, four players with 6 each) |

The numbering follows the board: switches carry the same number as in the game's self test, and solenoids 0 to 19 are the twenty playfield outputs in schematic order.

### 9.5. Connecting it

The ESP32 module simply plugs in; there is nothing to solder. The board powers it - **no USB cable is needed in normal operation.** You only plug one in to load the FA-Control firmware or to read the boot log. For the initial WLAN setup FA-Control opens its own access point on first start - see the FA-Control documentation for that.

## 10. The status LEDs

The board has three status LEDs, wired in parallel to the LEDs of the piggy-back board. They are the fastest diagnosis without a logic analyser.

| LED    | Meaning                                                                  |
|--------|--------------------------------------------------------------------------|
| **D1** | watchdog: lights up and stays lit once the internal watchdog has timed out at least once. **Dark is the normal state.** |
| **D2** | CPU is fetching instructions from rom - blinks at about 0.6 Hz. **Steady means the CPU is halted or stuck.** |
| **D3** | the NMI timer runs - blinks at about 0.48 Hz. This is free running hardware and does not depend on the CPU. |

Read them together:

- **D2 and D3 blinking** - board and game are alive. This is what you want to see.
- **D3 blinking, D2 steady** - the hardware runs but the CPU is not executing. Check game select and the reset switch.
- **Nothing blinking at all** - the FPGA is not configured or has no clock. Reprogram it (chapter 11).

## 11. Programming the FPGA

Everything you need to get the software onto the board is described on my website, and it is kept up to date there:

> **<https://lisy.dev/documentation-01.html>**

You will find there the latest FPGA program for download, which programmer software you need, how to install the driver for the USB Blaster, and how to program the FPGA.

**Make sure you take the AtariFA version** and, if there is more than one, the one for your board variant - see chapter 12. The board variant is the leading digit of the version on the info display.

There is no SD card image for AtariFA. The game roms are part of the FPGA program.

## 12. Board variants

The same design runs on two piggy-back boards. The FPGA program is **not** interchangeable between them - the pin assignment differs.

| Variant | Board | Version starts with |
|---|---|---|
| `cyclone_10_pcb` | AtariFA PCB v1.x with the lisy.dev Cyclone 10 piggy-back board | **0** |
| `cyclone_10_dev_open` | AtariFA PCB v1.x with the 'dev_open' Cyclone 10 board | **1** |

**The info display tells you which program is running:** the first of the three version digits on player display 1 is the board number. If you loaded the wrong one, the displays will most likely stay dark or show nonsense - check that digit first.

Apart from the pin assignment the two are identical, with two small differences on the piggy-back board itself: the `dev_open` board has its reset switch and all four of its status LEDs on the piggy-back board (the fourth is a spare and stays dark), and it brings 3 instead of 8 debug lines to the logic analyser header.

**The `dev_open` variant has not been tested on a machine.**

## 13. Not implemented yet

These are on the PCB, wired, and not used by this software version. They do nothing, and they do no harm - the FPGA holds all of them in a safe idle state.

- **FRAM (credits and high scores over a power cycle).** The chip is fitted and the low level driver works, but making it reliable across all five games turned out to need more reverse engineering of the game roms than expected. The feature is switched off; option switch 1, which used to control it, has no effect. Chapter 6.3.
- **The MP3 background player.** A second, independent audio path on the PCB. Not driven by this software version; it has nothing to do with the game sound of chapter 8.

## Appendix A 'game select'

Switches of the **4 switch bank**. Dip4 of that bank is free play and is not part of the game number.

| **No** | **Dip1** | **Dip2** | **Dip3** | **Game**            | **Year** |
|-------:|----------|----------|----------|---------------------|----------|
|      0 | off      | off      | off      | The Atarians        | 1976     |
|      1 | on       | off      | off      | Time 2000           | 1977     |
|      2 | off      | on       | off      | Airborne Avenger    | 1977     |
|      3 | on       | on       | off      | Middle Earth        | 1978     |
|      4 | off      | off      | on       | Space Riders        | 1978     |
|    5-7 | –        | –        | –        | not used, falls back to Middle Earth | |

All five run with free play as well (chapter 7).

**The Atarians** has no self test - see chapter 6.2.

## Appendix B Quick reference

**The ten configuration switches**

```
bank of 4                          bank of 6
 1  game select bit 0  (+1)         1  reserved              read at boot
 2  game select bit 1  (+2)         2  reserved              read at boot
 3  game select bit 2  (+4)         3  sound path            live
 4  free play, ON = active          4  FA-Control allowed    live
                                    5  reserved              live
 all four read at boot only         6  reserved              live
```

**Sound path, option 3:** OFF = Auxiliary Board (standard) · ON = on-board amplifier

**FA-Control, option 4:** OFF = nobody interferes (standard) · ON = the ESP32 test tool may drive the machine (chapter 9)

**After changing a switch that is read at boot: power off, power on.**

**The info display, first 5 seconds after power on**

```
Player 1   0 1 2      version, first digit = board variant
Player 2      0 2     game select  (Appendix A)
Player 3   000000     options 1..6, left to right, 1 = ON
Player 4        0     free play, 1 = active
Credit     (dark)
```

**LEDs:** D1 watchdog (dark = good) · D2 CPU running (blinks ~0.6 Hz) · D3 NMI timer (blinks ~0.48 Hz)

**No credits or scores are kept over a power cycle** - as on the original Atari MPU.
