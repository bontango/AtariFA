# Lamp Refresh Analysis — Original Atari Gen1 vs. AtariFA (2026-07-10)

> **Question that triggered this analysis:** On the original Atari, lamp replacement with LEDs
> does not work — the LEDs are always faintly lit ("pre-glow" / *Vorglühen*). Some pinball forums
> attribute this to the **refresh routine deliberately injecting short "on" phases even for lamps
> that are switched off**, in order to keep the incandescent filaments warm. On AtariFA, LEDs used
> as test lamps work perfectly (cleanly on/off), which suggested a different refresh mechanism.
> This document establishes **definitively** how the original refresh works and why AtariFA behaves
> differently — and clears the concern that the AtariFA refresh logic might over-drive 5 V test LEDs.

---

## TL;DR / Verdict

**The Atari Gen1 lamp refresh is pure hardware (DMA). The CPU / game software does *not* refresh
the lamps at all — it only maintains a static on/off image in RAM `0x30–0x3F`.**

Consequently, the forum claim ("the refresh routine injects on-phases for off-lamps") **does not apply
to Atari Gen1** — there is no software refresh loop into which on-phases could be injected. The
"pre-glow" is therefore a **hardware artifact** of the original strobed 20 V lamp-matrix driver
(leakage / half-select current), invisible on a hot incandescent filament but above an LED's turn-on
threshold. AtariFA re-implements the driver cleanly (with hard blanking) and does not reproduce this
artifact — which is exactly why LEDs work as test lamps.

---

## 1. How the original refreshes lamps: DMA, not software

In Atari Gen1 the display **and** the lamps are refreshed by a **DMA mechanism**: a hardware timing
chain periodically halts the 6800 (HALT/DMA) and autonomously scans the low RAM (`0x00–0x3F`). During
this scan the RAM bytes are latched into the peripheral drivers:

- `0x00–0x1F` → score/status **display** (7-segment multiplex).
- `0x30–0x3F` → **lamp** latches (schematic Sheet 18A: `9334` addressable latches selected by address
  bits A2/A3/A7; the four column strobes **SA/SB/SC/SD** multiplex the 21×4 matrix).

The CPU is frozen during the refresh. **The game code never runs a per-lamp refresh loop** — it simply
writes the desired on/off state to RAM `0x30–0x3F`, and the DMA hardware re-reads and re-drives that
image every frame.

> This is the same architecture as the display refresh, documented in
> [`Display_Timing.md`](Display_Timing.md) §2 ("Originaler Mechanismus: DMA").

---

## 2. Evidence

Three independent sources agree.

### 2.1 PinMAME model — lamp state == RAM content

`doc/atari.c`, Gen1 RAM write handler `ram_w` (lines 233–244):

```c
} else if (offset > 0x2f && offset < 0x40) {
    /* lamps (128 of them!) */
    int col;
    offset -= 0x30;
    col = (offset%4)*2 + offset/8;
    if (offset % 8 < 4) {
        coreGlobals.lampMatrix[col]   = (coreGlobals.lampMatrix[col]   & 0xf0) | (data & 0x0f);
        coreGlobals.lampMatrix[col+8] = (coreGlobals.lampMatrix[col+8] & 0xf0) | (data >> 4);
    } else {
        coreGlobals.lampMatrix[col]   = (coreGlobals.lampMatrix[col]   & 0x0f) | (data << 4);
        coreGlobals.lampMatrix[col+8] = (coreGlobals.lampMatrix[col+8] & 0x0f) | (data & 0xf0);
    }
}
```

The lamp matrix is set **exclusively** by CPU writes to RAM `0x30–0x3F`. Nothing else touches it; there
is no refresh routine and no on-phase injection. (AtariFA's `lamp_sniffer` in `AtariFA.vhd` mirrors this
exactly: it snoops the same RAM writes into `lamp_state`.)

### 2.2 PinMAME Gen1 interrupts do not handle lamps

`doc/atari.c`:

- `ATARI1_nmihi` (line 52): the NMI handler only pulses the NMI line and toggles the DMA counter —
  nothing to do with lamp values.
- `ATARI1_vblank` (line 81): handles solenoids and display smoothing, but has **no lamp handling** at
  all.

> Note: the `ATARI_LAMPSMOOTH` copy at line 103 belongs to **`ATARI2_vblank` (Gen 2)**, which uses a
> separate `lamp_w` handler and `tmpLampMatrix`. It is **not** used by the five Gen1 games
> (Atarians, Time 2000, Airborne, Middle Earth, Space Riders).

### 2.3 Real ROM disassembly (Airborne Avenger)

Generated with:

```
python tools/dis6800.py airborne.e00.hex airborne.e0.hex --name "Airborne Avenger" --out airborne_listing.txt
```

**Lamp control is a clean read-modify-write of a single bit** (`0x7BB1–0x7BC6`):

```
7BB1  LDAA #$10        ; single-bit mask
7BB3  TSTB
7BB4  BGE  $7BB7
7BB6  COMA             ; optionally invert the mask  -> $EF
7BB7  STAA $14         ; scratch
7BB9  LDX  $12
7BBB  LDAA $30,X       ; read current lamp RAM byte (0x30 + X)
7BBD  TSTB
7BBE  BGE  $7BC4
7BC0  ANDA $14         ; lamp OFF -> clear the bit
7BC2  BRA  $7BC6
7BC4  ORAA $14         ; lamp ON  -> set the bit
7BC6  STAA $30,X       ; write back to lamp RAM
```

A lamp that is switched off has its bit cleared to 0 and **stays 0** in RAM. All other lamp bits are
preserved. There is no injection of "on" states for off-lamps. These writes are **event-driven** (only
when a lamp actually changes state), not periodic.

Furthermore, the **244 Hz NMI ISR** (`0x7DBE`) is only a RAM-integrity / watchdog check — it never
writes lamp RAM:

```
7DBE  LDAA $D9 / CMPA #$AA / BNE reboot   ; sentinel 1
7DC4  LDAA $DA / CMPA #$55 / BNE reboot   ; sentinel 2
7DCA  TSX / LDAA $05,X / range-check      ; stacked PC sanity
7DD5  RTI                                 ; ... else JMP $7000 (reboot)
```

---

## 3. Why the "software pre-glow" claim exists but does not apply here

Systems that **software-multiplex** their lamps (e.g. Gottlieb System 1, various Bally generations)
run the lamp scan in a CPU loop. On those platforms it is technically possible for the refresh loop to
briefly energize off-lamps ("keep-warm"). The forum description most likely originates from such a
system and was carried over to Atari by analogy.

Atari Gen1 is architecturally different: **the CPU does not scan the lamps — the DMA hardware does.**
There is no software refresh loop, so there is nowhere to inject on-phases. Any residual glow on the
original must come from the **driver electronics** of the strobed 20 V matrix (leakage / half-select
current / capacitive coupling), which is below the visible threshold for an incandescent filament but
above the forward-conduction threshold of an LED.

---

## 4. What AtariFA does — and why LEDs work

- **Data source:** `lamp_sniffer` (`AtariFA.vhd`) snoops CPU writes to RAM `0x30–0x3F` into
  `lamp_state(127:0)` — identical in spirit to PinMAME's `ram_w`. It captures only the *true* static
  on/off image.
- **Scan / multiplex:** `lamp_matrix.vhd` re-creates the 21×4 matrix (three cascaded 74HC595 →
  12× ULN2003A rows, four SA/SB/SC/SD strobes) with a free-running FSM. During shifting and strobe
  switching it **hard-blanks all rows** (`oe_n = '1'`), so an off-lamp bit produces exactly **0 mA** —
  no sneak path, no pre-glow.

**Empirical cross-check (decisive):** AtariFA executes the *original* game ROM. If the pre-glow were a
software effect (the ROM writing on-patterns into `0x30–0x3F`), the sniffer would faithfully reproduce
it and the test LEDs would glow. They do not (HW-tested, `lamp_matrix.vhd`, Phase B). This is a direct
empirical confirmation that the original pre-glow is a **hardware** artifact, consistent with the ROM
disassembly above.

---

## 5. Brightness & voltage — no risk to 5 V test LEDs

Two concerns raised, both resolved:

**(a) Are the original incandescent lamps driven too hard / too bright by AtariFA?** No.
- Incandescent brightness depends on **average power**; the filament's thermal time constant (many ms)
  integrates over many pulses, so the **refresh frequency is irrelevant** to brightness.
- Duty cycle is what matters: AtariFA runs **~24 %** per lamp (one of four strobe phases,
  `DWELL_CYCLES = 12500` ≈ 250 µs of ~1040 µs/frame), structurally capped at ~25 % because only one
  strobe is ever active at a time. The original 4-fold multiplex is likewise **~25 %**. → essentially
  identical average power → same brightness (if anything marginally dimmer on AtariFA due to shift
  overhead). AtariFA's frame rate is ~960 Hz vs. the original ~244 Hz, but that only changes flicker
  frequency, not average power.

**(b) Can the refresh logic over-voltage the 5 V test LEDs?** No.
- The FPGA refresh logic only controls **timing (on/off), never voltage**. The peak voltage across a
  lamp when on is set purely by hardware: strobe-rail voltage − driver drop − series resistor.
- The 5 V test LEDs sit on a **physically separate path**: the "Box connectors" provide the four lamp
  strobes via **four P-channel MOSFETs, for test LEDs only** (`AtariFA.vhd` header, section 4),
  independent of the Aux-board's 20 V incandescent strobes. Whatever rail voltage feeds that test path
  is a hardware choice; the refresh FSM cannot raise it.
- The only software-side brightness knob is `DWELL_CYCLES` in `lamp_matrix.vhd` (duty), not voltage.

---

## 6. Sources

- PinMAME reference: `doc/atari.c` (`ram_w` lamp handler, `ATARI1_nmihi`, `ATARI1_vblank`).
- ROM disassembly: `tools/dis6800.py airborne.e00.hex airborne.e0.hex` (Airborne Avenger; routine
  `0x7BB1–0x7BC6`, NMI ISR `0x7DBE`).
- Original DMA refresh mechanism: [`Display_Timing.md`](Display_Timing.md) §2 (same DMA chain drives
  display and lamps).
- AtariFA implementation: `lamp_matrix.vhd` (scan FSM, blanking) + `AtariFA.vhd` (`lamp_sniffer`,
  box-connector test-strobe path, header section 4).
