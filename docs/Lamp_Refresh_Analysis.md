# Lamp Refresh Analysis — Original Atari Gen1 vs. AtariFA (2026-07-10)

> **Question that triggered this analysis:** On the original Atari, lamp replacement with LEDs
> does not work — the LEDs are always faintly lit ("pre-glow" / *Vorglühen*). This is commonly
> attributed to a **refresh routine deliberately injecting short "on" phases even for lamps that
> are switched off**, in order to keep the incandescent filaments warm. That claim is not a forum
> invention: it comes from **Atari's own service literature** — the *Atari Pinball Troubleshooting
> Guide* calls it the "keep-alive routine" (§3). On AtariFA, LEDs used as test lamps work perfectly
> (cleanly on/off), which suggested a different refresh mechanism.
> This document establishes **definitively** how the original refresh works and why AtariFA behaves
> differently — and clears the concern that the AtariFA refresh logic might over-drive 5 V test LEDs.

---

## TL;DR / Verdict

**The Atari Gen1 lamp refresh is pure hardware (DMA). The CPU / game software does *not* refresh
the lamps at all — it only maintains a static on/off image in RAM `0x30–0x3F`.**

Consequently the keep-alive claim ("the refresh routine injects on-phases for off-lamps") **does not
apply to Atari Gen1** — there is no software refresh loop into which on-phases could be injected.
**Measured and confirmed on 2026-08-09** with a logic-analyser capture on the prototype: with a ball
sitting in the shooter lane the CPU wrote to lamp RAM *not once in 25.7 s* while the matrix kept
driving lit lamps — see §6. The
"pre-glow" is therefore a **hardware artifact** of the strobed lamp matrix — **row data live while
the wrong column still conducts** (§3.3) — invisible on a hot incandescent filament but above an
LED's turn-on threshold.

> **Update 2026-08-10 — measured on the playfield, and it corrects this document.** The artifact is
> **not** confined to the original: an Airborne Avenger fitted with LED retrofits showed it on
> **AtariFA** too, and in exactly the predicted pattern ("same row, previous column"). §3.3 is
> therefore **proven rather than merely argued** — but the sentence that used to stand here, "AtariFA
> blanks hard and does not reproduce this artifact", was **wrong**, and §4/§6.7 have been corrected
> accordingly. What was measured in §6.7 is that AtariFA blanks cleanly **at the FPGA pins**; the
> overlap happens *behind* the connector, because the Aux board's saturated 2N5883 column driver
> needs tens of microseconds to turn off. Full write-up:
> [`Lamp_Preglow_Experiment.md`](Lamp_Preglow_Experiment.md) §3. Fixed in SW 0.1.6, with the original
> timing still selectable at run time via **Options DIP 5** (ibid. §4).

**What the Troubleshooting Guide got right and wrong:** its *explanation* — that this is a deliberate
routine — is not correct. Nothing in the machine can pulse an individual off-lamp except the RAM
image, and the RAM image demonstrably does not do it (§6.6). The Aux board, the only other candidate,
cannot do it either: it never sees a lamp, only a column (§3.2). Its *observation* ("a faint pulsing
of the lamp filament") turns out to be shaky as well: on the 2026-08-10 playfield test **incandescent
lamps showed nothing at all**, and the effect only became visible after fitting LEDs. The energy per
event is orders of magnitude below what a hot filament would register — so whatever the service
department saw, it was not a pulsing filament.

---

## 1. How the original refreshes lamps: DMA, not software

In Atari Gen1 the display **and** the lamps are refreshed by a **DMA mechanism**: a hardware timing
chain periodically halts the 6800 (HALT/DMA) and autonomously scans the low RAM (`0x00–0x3F`). During
this scan the RAM bytes are latched into the peripheral drivers:

- `0x00–0x1F` → score/status **display** (7-segment multiplex).
- `0x30–0x3F` → **lamp** latches (schematic Sheet 18A: `9334` addressable latches selected by address
  bits A2/A3/A7; the four column strobes **SA/SB/SC/SD** multiplex the 21×4 matrix). One column per
  digit slot ⇒ the lamp matrix is scanned twice per display frame, 2.048 ms per lamp frame — see §3.1.

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

### 2.4 Second ROM checked — Middle Earth 608/609 (2026-08-12)

Airborne alone leaves the possibility that another game does it differently, so the disassembly was
repeated for the game the field report came from:

```
python tools/dis6800.py 609.hex 608.hex --name "Middle Earth 608/609" --out me_listing.txt --full
```

**The 244 Hz NMI handler does nothing at all.** Read straight out of the ROM image: vector `$7FFC`
= `$7EC6`, and the byte at `$7EC6` is `3B` = **`RTI`**. Middle Earth does not even do Airborne's
sentinel check — the only periodic interrupt in the machine returns immediately. Whatever refreshes
the lamps, it is not interrupt code.

**Lamp control is the same single-bit read-modify-write**, here factored into two subroutines:

```
7C09  STX  $DB          ; LAMP ON      save X
7C0B  BSR  $7C14        ;              decode lamp id in A
7C0D  ORAA $00,X        ;              set the bit
7C0F  STAA $00,X        ;              write back
7C11  LDX  $DB / RTS

7C2A  STX  $DB          ; LAMP OFF     save X
7C2C  BSR  $7C14        ;              same decode
7C2E  COMA              ;              invert the mask
7C2F  ANDA $00,X        ;              clear the bit
7C31  BRA  $7C0F        ;              share the write-back

7C14  BSR  $7C22        ; DECODE       high nibble of the lamp id -> B
7C16  ADDB #$30         ;              *** base = page-0 $30 ***
7C18  STAB $24 / CLR $0023 / LDX $23   ; X = $0030 + n
7C1F  ANDA #$0F         ;              low nibble selects the bit
```

Callers pass a lamp id and call once (`LDAA #$A2 / JSR $7C09`), i.e. **event-driven**, exactly as in
§2.3. `ADDB #$30` also settles a second question in passing: the game addresses lamp RAM in **page 0**,
not through the `0x1000` RAM mirror — which is the region AtariFA's `lamp_sniffer` watches.

**Only two pieces of code ever walk all of `0x30–0x3F`**, and neither is periodic:

| | |
|---|---|
| `$77CC` | `LDX #$0030 / CLR $00,X / INX / CPX #$0040 / BNE` — clear all lamps, once, during init |
| `$7F0D` | `LDX #$0030 / LDAA #$FF / STAA $00,X / INX / CPX #$0040 / BNE` — all lamps **on** for the lamp self-test, afterwards stepped off again |

There is no refresh table in the game code, hence no wrap-around to its first entry and no waiting for
a next refresh cycle. Two of the five Gen1 games have now been read; both agree with §1.

---

## 3. Where the "keep-alive" claim comes from — and what it really describes

The claim is not folklore. It is printed in Atari's own service literature, the **Atari Pinball
Troubleshooting Guide** (`N:\Projekte\FPGA Atari\Manuals\Atari Troubleshooting guide.pdf`), section
*Lamp Strobes*, scanned here as [`Lamp_Strobes_Manual.png`](Lamp_Strobes_Manual.png):

![Lamp Strobes, Atari Pinball Troubleshooting Guide](Lamp_Strobes_Manual.png)

> "The Auxiliary PCB also generates 4 mutually exclusive lamp strobe outputs. These strobes are
> controlled by the LAMP BIT 0 and LAMP BIT 1 control bits from the Processor PCB. The 4 lamp strobes
> should each consistently pulse at a rate of every 2 milliseconds and each pulse should last for a
> duration of about 500 microseconds. […] Since each strobe has an 'on' duty cycle of only 25 %, even
> lamps which appear to be on all the time are really only being supplied with power about one-fourth
> of the time. […] As a point of general interest, the Atari 'keep-alive' routine might also be
> mentioned at this time. If one would observe carefully any lamps which are supposedly in their 'off'
> condition, you could observe a faint pulsing of the lamp filament. This is because these lamps are
> being turned on and off very quickly at a very low frequency. The effect of this procedure is to
> prolong lamp life, since it prevents sudden current surges through the lamp filament."

The guide is written for Gen1 in general, not for one particular game, so the statement nominally
covers all five target titles. Two things follow from it, and they pull in opposite directions:
its **timing figures independently confirm** the DMA model of §1 (§3.1), while its **causal claim**
survives neither the schematic (§3.2) nor the measurement (§6.6). §3.3 reconciles the two.

For context: systems that **software-multiplex** their lamps (Gottlieb System 1, various Bally
generations) do run the lamp scan in a CPU loop, and there a refresh loop *can* briefly energize
off-lamps. Atari Gen1 is architecturally different — the CPU does not scan the lamps, the DMA
hardware does — so there is no loop into which on-phases could be injected.

### 3.1 The guide's own numbers confirm the DMA model (and correct one of ours)

| | Troubleshooting Guide | derived from the DMA chain | AtariFA ≤ SW 0.1.4, measured (§6.7) | AtariFA ≥ SW 0.1.5, design value |
|---|---|---|---|---|
| Strobe pulse | "about 500 µs" | 512 µs = **one digit slot** | 250.04 µs | 512.0 µs (502 µs visible + 10 µs blank) |
| Strobe period | "every 2 ms" | 2.048 ms = 4 digit slots = **½ display frame** | 1.039 ms | 2.048 ms |
| Duty per lamp | "only 25 %" | 25 % | 24.04 % | 24.5 % |
| Lamp frame rate | ~500 Hz | 488.3 Hz | 961.4 Hz | 488.3 Hz |

The last column is **calculated, not yet measured** — `DWELL_CYCLES` went 12500 → 25100 in SW 0.1.5
so that the phase *including* the shift overhead lands on the original's 512 µs digit slot. The
arithmetic is exact because the overhead is: the blanking window measured 10.000 µs = 500 clocks
after the `St_ShiftLast` fix (§6.7.1), so 25100 + 500 = 25600 × 20 ns = 512.00 µs. The
re-measurement that turns it into a measured column is the `DBG_MODE = 5` run described in §6.7.

The digit slot of 512 µs and the 4.10 ms display frame are measured values from
[`Display_Timing.md`](Display_Timing.md) (§ "Digit-Periode" / "Frame-Periode"). The lamp strobes
land on exactly four of those slots, i.e. the lamp matrix is scanned **twice per display frame** —
one column per digit slot. That is the same DMA timing chain seen from the lamp side, and it
matches the address decode: within RAM `0x30–0x3F` the low two address bits select the strobe
(`LAMP BIT 0/1`) and bits 2/3 select the row latch, so one strobe phase corresponds to exactly the
four bytes `0x30+s`, `0x34+s`, `0x38+s`, `0x3C+s` being written to the four row latches
`0x1000/1004/1008/100C`.

**This corrects §5(a)**, which used to compare AtariFA against "the original ~244 Hz": that is the
**display** frame. The original *lamp* frame is ~488 Hz, so AtariFA up to SW 0.1.4 ran 2× faster than
the original, not 4×. The duty cycle, which is what actually sets brightness, was identical anyway
(25 % vs. 24 %) and is now confirmed verbatim by Atari — brightness was never the reason to change
anything. **SW 0.1.5 nevertheless moved AtariFA onto the original raster** (512 µs column, 2.048 ms
frame): it costs nothing, and it makes the side-by-side comparison of the two MPUs on one playfield —
the pre-glow observation of [`Lamp_Preglow_Experiment.md`](Lamp_Preglow_Experiment.md) — a comparison
of one variable instead of two.

### 3.2 Is there a keep-alive circuit on the Aux board? No — and there cannot be one

The lamp section of the Auxiliary PCB ([`Auxiliary_PCB.png`](Auxiliary_PCB.png), Sheet 10A) is a
plain 1-of-4 column driver:

```
LAMP BIT 0 (J12-L) ─┐
LAMP BIT 1 (J12-K) ─┴─► 6× 7402 NOR (A3/B2: two as inverters, four as the 1-of-4 decode)
                        ─► MC1413 (A1) Darlington sink
                           ─► 39 Ω 2 W (R40/41/46/47) into the base of
                              4× 2N5883 PNP high-side (Q6…Q9), 8.2 K base-emitter (R42…R45)
                              ─► STROBE A (J13-1), B (J13-2), C (J15-3), D (J15-4 + J15-10 coin door)
```

The common emitter rail "LAMP PWR" (J11-5) is set by Q5, a 2N6282 Darlington whose base is
referenced by R35 390 Ω / CR19 1N5242B (12 V zener) — i.e. the strobes do **not** carry the raw
+20 V but roughly 10–11 V, which at 25 % duty gives ~5.3 V RMS across a #44/#47 lamp. (Read off the
sheet, not measured; it does not affect the argument below, only the wording "20 V matrix".)

Two independent reasons why this cannot produce a keep-alive:

1. **No enable, no timer, no one-shot.** The decoder inputs are `LAMP BIT 0/1` and nothing else —
   verified at full zoom on the scan. Four NOR outputs cover all four input combinations, so
   **exactly one strobe is always active**; the guide says the same ("4 mutually exclusive") and its
   own numbers confirm it (4 × 500 µs = the full 2 ms, no gap). The Aux board can therefore neither
   blank nor insert an extra pulse.
2. **It has no idea what a lamp is.** It receives two bits — a *column*. Any pulse it could generate
   would be column-wide, i.e. it would light every lamp whose row driver happens to be on. Per-lamp
   state exists only in the eight **9334** addressable latches on the Processor PCB
   ([`Lamp_Logic2.png`](Lamp_Logic2.png), Sheet 18A — one 9334 per data bit, addressed by A2/A3/A7),
   and those are loaded exclusively by the DMA from RAM `0x30–0x3F`.

### 3.3 What actually produces the pre-glow

Combining the two: a short "on" pulse for an individually selected off-lamp can only originate from
(i) the RAM image — measured absent in §6.6 — or (ii) a **row/column mismatch while a column is
live**. And (ii) is structurally unavoidable in the original:

- one column is powered at all times (§3.2), there is no blanking window;
- during that phase the DMA reloads the four row latches with the *new* pattern.

Whichever of the two switches first, there is an interval in which live outputs see a row pattern
belonging to a different column: every lamp that shares a row with a lit lamp of the neighbouring
phase gets a short pulse, every 2 ms. Order of magnitude: four DMA write cycles at ~1 µs against a
512 µs slot ⇒ well under 1 % duty — far too little to change a hot filament visibly, far more than
an LED needs to conduct. Add the leakage of the three un-driven PNP high-side drivers (R42…R45 hold
them firmly off, so only collector leakage reaches the column) and the picture is complete.

**Confirmed on the playfield, 2026-08-10** — and with a source this section had missed. Driving a
single lamp `n` over FA-Control made **exactly** the LED at "same row, previous column" glow, and
nothing else: lamp 22 lit ⇒ 21 glowed, 58 ⇒ 57, while the other two neighbours of the four-block
stayed dark. That selectivity is the tell. A column that stayed charged for the whole phase would
light all three neighbours; only the **just-deselected** column does, because it is the only one with
an active source still feeding it.

And that source needs no latch reload at all: **the column driver's turn-off delay alone opens the
window**. Q6…Q9 (2N5883) are driven hard into saturation — the MC1413 pulls the base through 39 Ω,
i.e. ~0.2 A of base current — and are turned off by nothing but the 8.2 K base-emitter resistors
(R42…R45). That is a storage time in the tens of microseconds. The original has this on top of its
latch-reload overlap; **AtariFA had it even though it blanks**, because up to SW 0.1.5 it released the
rows ~20 ns after switching the column (see §4).

**How much is "tens of microseconds"? Possibly a good deal more — and that changes how the field
reports have to be read.** Charge goes into the base at ~0.2 A and has to come back out through
8.2 K, i.e. at ~85 µA: roughly one two-thousandth of the rate it went in. The storage time can
therefore reach hundreds of microseconds, in the worst case more than one strobe phase. And the
lighter the column load, the deeper the saturation and the longer the tail — an LED-populated column
is the worst case of all. The consequence for diagnosis is uncomfortable but unavoidable:
**"more dead time changed nothing" does not acquit the column.** The SW 0.1.7 field feedback (DIP 6 =
ON ⇒ ~110 µs, no visible difference — [`Lamp_Preglow_Experiment.md`](Lamp_Preglow_Experiment.md) §6;
the tester has since confirmed it really was 0.1.7, so the report stands) is not yet a verdict; only a
step an order of magnitude further out decides it. That is what **SW 0.1.9** provides: the dead time
is now a four-position ladder on Options DIP 5 + 6 — ~65 µs series (duty 21.8 %), ~250 µs (12.8 %),
~400 µs (5.5 %) and the original timing with no dead time at all (24.5 %), see
[`Lamp_Preglow_Experiment.md`](Lamp_Preglow_Experiment.md) §6.6. ~492 µs is the hard ceiling, because
dwell and settle share one 512 µs phase. Two consequences: the mechanism of this section is
now measured rather than argued, and the open question of §6.5 ("which of the two switches first")
turns out not to matter — the slow column makes the window either way.

That is precisely the "faint pulsing" the guide describes — except that on real filaments there was
nothing to see (TL;DR). It is a side effect of an unblanked, slow-switching column stage that Atari's
service department rationalised as a feature.

---

## 4. What AtariFA does — and why LEDs work

- **Data source:** `lamp_sniffer` (`AtariFA.vhd`) snoops CPU writes to RAM `0x30–0x3F` into
  `lamp_state(127:0)` — identical in spirit to PinMAME's `ram_w`. It captures only the *true* static
  on/off image.
- **Scan / multiplex:** `lamp_matrix.vhd` re-creates the 21×4 matrix (three cascaded 74HC595 →
  12× ULN2003A rows, four SA/SB/SC/SD strobes) with a free-running FSM. It blanks all rows while
  shifting and while the column changes, so an off-lamp bit contributes **no drive current of its
  own**.

**But blanking the rows is not enough, and this is where the earlier version of this section was
wrong.** It claimed "exactly 0 mA — no sneak path, no pre-glow". Two corrections from the 2026-08-10
playfield test ([`Lamp_Preglow_Experiment.md`](Lamp_Preglow_Experiment.md) §3):

1. **The blanking window sat on the wrong side of the strobe change.** Up to SW 0.1.5 the sequence was
   *blank → shift 24 bits (~10 µs) → latch → switch column → un-blank 20 ns later*. So the 10 µs of
   blanking protected the shifting, and the column change got none of it — the rows went live
   essentially together with the new column, while the old one was still conducting (§3.3). Fixed in
   **SW 0.1.6**: the column now switches at the *start* of the blank, ~20 µs before the rows go live.
   Options **DIP 5 = ON** restores the old, original-faithful timing for A/B comparison.
2. **`oe_n = '1'` is not "0 mA", it is high-Z.** The 595 outputs float, and so do the Darlington
   inputs behind them — µA of leakage, which is nothing for a filament and plenty for an LED retrofit.
   The original never had this state: its row inputs come from **9334** addressable latches, i.e.
   permanently driven totem-pole outputs, so an off-row there is a hard `'0'` 100 % of the time. Also
   fixed in SW 0.1.6, in **both** timing modes, by blanking through *latching zeros* instead of
   `/OE` — this makes AtariFA more faithful, not less. `oe_n` is now only the reset/boot blank, where
   the 595 content is unknown and high-Z is the only safe state.

**Empirical cross-check (still decisive, and unaffected):** AtariFA executes the *original* game ROM.
If the pre-glow were a software effect (the ROM writing on-patterns into `0x30–0x3F`), the sniffer
would faithfully reproduce it — measured absent in §6.6, and the pattern actually observed on the
playfield (§3.3: strictly "same row, previous column") is not something a RAM image could produce
selectively. The original pre-glow is a **hardware** artifact, consistent with the ROM disassembly
above.

---

## 5. Brightness & voltage — no risk to 5 V test LEDs

Two concerns raised, both resolved:

**(a) Are the original incandescent lamps driven too hard / too bright by AtariFA?** No.
- Incandescent brightness depends on **average power**; the filament's thermal time constant (many ms)
  integrates over many pulses, so the **refresh frequency is irrelevant** to brightness.
- Duty cycle is what matters: AtariFA runs **~22 %** per lamp in the series setting (one of four
  strobe phases; since SW 0.1.9 `DWELL_CYCLES = 21847` plus the ~10 µs zero-shift pass during which
  the lamp is still lit ⇒ 21.8 %, and 24.5 % in the original-timing position, where no settle window
  is spent; it was 24.0 % at 0.1.6, 24.5 % at 0.1.5 and 24.04 % up to 0.1.4). The longer dead-time
  steps trade duty for decay time on purpose: 12.8 % at ~250 µs and 5.5 % at ~400 µs. All of it is
  structurally capped at ~25 % because only one strobe is ever active at a
  time. The original 4-fold multiplex is likewise **~25 %** — stated verbatim in the Troubleshooting
  Guide ("each strobe has an 'on' duty cycle of only 25 %", §3.1). → essentially identical average
  power → same brightness (if anything marginally dimmer on AtariFA due to shift overhead). Since
  SW 0.1.5 the lamp frame rate matches the original at **~488 Hz** (2.048 ms, §3.1 — the 244 Hz
  figure is the *display* frame, not the lamp frame); up to 0.1.4 it was ~961 Hz, which changed
  flicker frequency only, not average power. **Changing `DWELL_CYCLES` from 12500 to 25100 therefore
  did not make the lamps brighter** — duty moved by half a percentage point, the frame rate halved.

**(b) Can the refresh logic over-voltage the 5 V test LEDs?** No.
- The FPGA refresh logic only controls **timing (on/off), never voltage**. The peak voltage across a
  lamp when on is set purely by hardware: strobe-rail voltage − driver drop − series resistor.
- The 5 V test LEDs sit on a **physically separate path**: the "Box connectors" provide the four lamp
  strobes via **four P-channel MOSFETs, for test LEDs only** (`AtariFA.vhd` header, section 4),
  independent of the Aux board's incandescent strobes (the `LAMP PWR` rail, §3.2). Whatever rail
  voltage feeds that test path is a hardware choice; the refresh FSM cannot raise it.
- The only software-side brightness knob is `DWELL_CYCLES` in `lamp_matrix.vhd` (duty), not voltage.

---

## 6. Measurement-based verification (8-channel logic analyser)

Sections 1–4 are a paper argument (PinMAME model, ROM disassembly, architecture). This section
turns it into a measurement on the AtariFA prototype. The lever: **AtariFA executes the very same
game ROM as the original machine**, and the only way software can influence lamps at all is a write
into RAM `0x30–0x3F`. Capture those writes without gaps and the software side is settled.

`DBG_MODE = 4` in `AtariFA.vhd` provides the channel assignment. The whole trace logic lives inside
the `gen_dbg4` / `gen_dbg5` generate blocks, so with the default `DBG_MODE = 0` nothing of it is
elaborated and the synthesis baseline (`scripts/baseline.csv`) is unaffected.

### 6.1 `DBG_MODE = 4` — long capture (main measurement)

Designed for 500 kHz…1 MHz sampling over seconds to minutes on a simple 8-channel LA. The three
event channels are stretched to ~1 ms (`DBG_STRETCH_CYCLES`) so they survive that sample raster;
the matrix channels are raw (250 µs / ~10 µs, comfortably visible at 1 MHz).

| Ch | Pin (`cyclone_10_pcb`) | Signal | What it proves |
|---|---|---|---|
| 0 | PIN_66 | `lamp_wr` — CPU write to RAM `0x30–0x3F`, stretched | Are there periodic lamp writes at all? No pulse over seconds ⇒ no software refresh, end of discussion. |
| 1 | PIN_68 | `lamp_wr_chg` — written value differs from the stored byte | Separates a real change from re-writing the same value. |
| 2 | PIN_75 | `lamp_wr_set` — at least one bit goes 0→1 | **The key channel.** The keep-alive claim requires periodic 0→1 edges for lamps that are off. |
| 3 | PIN_59 | `watch_state` — `lamp_state` bit of `DBG_WATCH_LAMP` | Software-side state of the chosen off-lamp: must stay flat `'0'`. |
| 4 | PIN_55 | `watch_drive` — drive of that lamp (row bit AND strobe phase AND not blanked) | Shows *when* that lamp would be due, and catches short blips in channel 3. **Do not over-read it:** inside the FPGA it is derived from channel 3, so a flat channel 3 forces a flat channel 4. It cannot reveal a sneak path — there is none here (see §6.5). |
| 5 | PIN_53 | `any_drive` — **any** of the 84 lamps currently driven | Counter-check against the negative-proof trap: ~250 µs pulse every ~1.04 ms (~24 % duty). Without it, channels 3/4 are worthless. Deliberately not tied to a named reference lamp, so the counter-check needs no lamp number and holds in any state where something is lit. |
| 6 | PIN_51 | `lamp_oe_n` | The blanking window: high during shift/latch (~10 µs), low during dwell. |
| 7 | PIN_49 | 244 Hz NMI pulse | Time base. If the lamp writes sit on this raster, it *is* a refresh. |

`DBG_WATCH_LAMP` is a lamp number in the FA-Control numbering (`n = (595 group − 1) × 4 + strobe`,
0…83, see `rtl/common/lamp_map_pkg.vhd`). It is the only lamp number the trace needs, and it only
feeds channels 3/4 — the channels that decide the question (0/1/2/7) do not depend on it at all.
Channel 3 tells you directly whether the chosen lamp really is off during the capture; if it blinks,
pick another number and repeat.

`cyclone_10_dev_open` only routes three debug lines; the measurement needs `cyclone_10_pcb`.

**Deliberate detail:** channels 0–2 qualify on the RAM-decoded address
(`ram_wren = '1' and cpu_addr(8 downto 4) = "00011"`), *not* on the sniffer condition
`cpu_addr(15 downto 4) = x"003"`. That also catches writes through the RAM mirror
(`0x1030–0x103F`), which the sniffer would miss — otherwise "no pulse" would not be a complete
proof. (Channel 0 firing without a corresponding page-0 write would itself be a finding: the
sniffer would then not see the lamps.)

### 6.2 `DBG_MODE = 5` — detail capture (optional)

`ser` / `srck` / `rck` / `oe_n` / `strobe_sel(1:0)` / `watch_drive` / `lamp_wr` (stretched to
~200 ns). Shows one complete multiplex phase at 24 MHz. The same signals are also available at the
board pins — `oe_595` (PIN_38), `clk_595` (PIN_39), `rclk_595` (PIN_42), `aux_lamp_strobe` — this
mode merely bundles them on the LA header and adds the reconstructed lamp drive.

### 6.3 Procedure

1. Set `DBG_MODE := 4` plus `DBG_WATCH_LAMP`, run
   `scripts\build.ps1 cyclone_10_pcb`, program the prototype.
2. LA on PIN_66/68/75/59/55/53/51/49 + GND, 500 kHz…1 MHz, 30–60 s, free-run in attract mode.
3. **Counter-check first:** channel 5 must show the ~250 µs / ~1.04 ms pattern and channel 6 the
   blanking window. Without that the rest is not interpretable.
4. Capture **during a game** and **in attract**, both are needed:
   - *During a game* few lamps are lit, so a stable off-lamp is easy to pick. The quietest moment is
     the ball sitting in the shooter lane right after start — play state, few lamps, no events.
     This is the better capture for channels 3/4.
   - *In attract* many lamps blink, which makes the lamp choice awkward — but this is the state the
     keep-alive claim is actually about, so it cannot be skipped. The lamp choice matters less here:
     channels 0/1/2/7 (the ones that decide the question) do not depend on it at all, and channel 3
     tells you directly whether the chosen watch lamp is really off — if it blinks, pick another
     number and repeat.
   - Optionally the lamp self-test as a contrast capture.
5. Afterwards set `DBG_MODE` back to `0` and run `scripts\check.ps1 -Fit` against the baseline
   before committing anything.

### 6.4 Reading the result

| Observation | Interpretation |
|---|---|
| **Ch 0 silent while ch 5 keeps pulsing** | Decisive. Lamps stay lit with *zero* CPU writes ⇒ the lit state comes from the static RAM image alone, there is no software refresh. |
| Ch 3 and 4 flat `'0'` throughout while ch 5 pulses cleanly | The watch lamp stays off for the whole capture — and ch 5 proves the capture was live while it did |
| Ch 0 periodic, but ch 1 pulses with it | Periodic writes that *change* the byte every time = an animation stepping on a timer, **not** a refresh. A refresh rewrites identical values, which would show as ch 0 without ch 1. |
| Ch 0 periodic **and ch 1 mostly silent** | That would be a genuine rewrite loop — then look at ch 3 to see whether an off-lamp bit is part of it. |
| Ch 3 shows short spikes during its off period, spaced on the ch 0 raster | **This document would be wrong** — that is the claimed keep-warm injection; revise sections 1–4. |

Note that "ch 0 is periodic" alone proves nothing. Attract animations are stepped by a timer derived
from the 244 Hz NMI, so their lamp writes are strictly periodic *by construction* — see the measured
result in §6.6, where they land on exactly every 20th NMI. The refresh question is decided by ch 1
(does the value actually change?) and by the in-play capture (are there any writes at all?).

### 6.5 What this trace does *not* cover

It settles the **software** side — the falsification of the keep-alive claim — because the same ROM
code runs here as on the original machine. What remained open, and what became of it:

- ~~It does **not** positively prove the driver-side cause of the original pre-glow.~~ **Closed
  2026-08-10** by observation on the playfield instead of by capture: driving single lamps over
  FA-Control reproduced the artifact on AtariFA with the exact signature §3.3 predicts ("same row,
  previous column", and only that one neighbour) — see
  [`Lamp_Preglow_Experiment.md`](Lamp_Preglow_Experiment.md) §3. The controlled counter-experiment
  that was planned for this — a switchable blanking — exists now as the production fix plus **Options
  DIP 5** for the original timing (ibid. §4), so the A/B test can be repeated at any time without a
  rebuild.
- Only **Airborne Avenger** was captured, and the same game was used for the 2026-08-10 observation.
  The Troubleshooting Guide is written for Gen1 in general, so strictly speaking the other four ROMs
  are untested. Re-running §6.3 for each is cheap (one build with `DBG_MODE = 4`, then switch
  `game_select`), and the decisive channel 0 needs no lamp number. For the *hardware* artifact the
  game does not matter at all — it lives in the driver stage.
- ~~The exact ordering inside a strobe phase of the original — strobe switch first or latch reload
  first — is not established.~~ **Moot** (§3.3): the column driver's turn-off delay opens the window
  regardless of the order, so nothing hangs on it any more.

### 6.6 Results — measured 2026-08-09, `DBG_MODE = 4`, `DBG_WATCH_LAMP = 8`

**Airborne Avenger** (`game_idx = 2`) on the prototype, SW 0.1.3. Two captures, Saleae-style edge
export, 25.7 s (in play) and 27.5 s (attract).

**Sanity of the capture itself** (identical in both, and matching the design):
`oe_n` blanking 9.8 µs, dwell 250 µs ⇒ 260 µs per strobe phase, 1.04 ms per lamp frame;
NMI period 4096.9 µs = **244.1 Hz**, exactly the value `Display_Timing.md` derives.

| State | Ch 0 (writes) | Ch 1 (changed) | Ch 2 (0→1) | Ch 3 (lamp 8) | Ch 5 (any lamp) |
|---|---|---|---|---|---|
| **In play**, ball in shooter lane, 25.7 s | **none at all** | none | none | flat `'0'` | pulsing the whole time |
| **Attract**, 27.5 s | 203 bursts, every **81.94 ms** | 203 — identical to ch 0 | 139 | clean 1.31 s on / 1.72 s off | pulsing |

**Verdict: the keep-alive claim is refuted as a software mechanism; sections 1–4 hold.**

1. *In play the CPU does not touch lamp RAM at all* — not one write in 25.7 s, while ch 5 shows the
   matrix driving lit lamps throughout. A software refresh that is absent for 25 seconds is not a
   refresh. The lit state comes from the static RAM image alone, exactly as sections 1–4 describe.
2. *The attract writes are an animation, not a refresh.* They are strictly periodic —
   81.94 ms = **exactly 20 NMI periods** (12.2 Hz), phase-locked to ch 7 with a spread of 0.001 —
   which is what a timer-stepped attract animation looks like. What rules out a refresh is ch 1:
   it fires on **every single** one of the 203 bursts, i.e. every write actually changes the byte.
   A keep-warm refresh would rewrite identical values and leave ch 1 silent.
3. *No on-phase injection for an off lamp.* Lamp 8's own bit is a clean square wave (9 pulses,
   1.31 s on, 1.72 s off) with no short spikes during its off periods — no 81.94 ms blips, nothing.
   Had the ROM injected keep-warm pulses, they would appear right here.

The 0→1 events on ch 2 (139 of them) are other lamps in the animation being switched on; they are
byte-wide events and carry no information about a specific lamp, which is what ch 3 is for.

### 6.7 Overlap window — `DBG_MODE = 5`, 10 s at 24 MHz, attract (measured on SW 0.1.4)

The one thing §6.6 cannot answer: is there an instant at which the row data has already been
switched while the column strobe still belongs to the previous phase *and the outputs are live*?
That is the half-select mechanism the original's pre-glow is attributed to. Capture: 10.005 s,
1.9 M edges, **38 503 complete strobe phases**.

| Quantity | Measured | Design value |
|---|---|---|
| Blanking window (`oe_n` high) | 9.792 µs [9.791 … 9.834] | 24 × 400 ns shift + latch ≈ 9.8 µs |
| Visible window (`oe_n` low) | 250.042 µs [250.041 … 250.084] | `DWELL_CYCLES` 12500 × 20 ns = 250 µs |
| Phase period / frame | 259.8 µs / 1.039 ms | ~962 Hz frame rate |
| ↑ both of these doubled in SW 0.1.5 | not re-measured yet | `DWELL_CYCLES` 25100 → 502 µs visible, 512.0 µs phase, 2.048 ms frame |
| Shift bit clock | 416 ns → 2.40 MHz | `SHIFT_DIV` 10 → 2.5 MHz |
| `rck` → output enable | 208 ns [166 … 209] | one shift tick |
| strobe change → output enable | 208 ns [166 … 209] | same tick — `rck` and strobe switch together |

**Violations (event while `oe_n` = 0, i.e. outputs live), over 38 503 phases:**

| Event | Count |
|---|---|
| `rck` (latch) while live | **0** |
| strobe change while live | **0** (see note) |
| `srck` (shifting) while live | **0** |

*Note on the strobe count:* the raw scan reports exactly one hit — at **row 1 of the file**, the
first recorded transition, at t = 85.333 µs. That is 2048 samples at 24 MHz, i.e. the capture
device's first block boundary; the `t = 0` row is the placeholder initial state, and `Aufnahme1`
shows its first transition at the identical 85.333 µs. It is a capture-start artifact, not a signal
event — a real strobe glitch during dwell would not occur exactly once in 10 s, precisely on the
first block boundary. Every one of the 38 503 genuine phase changes is blanked.

**Result, as far as this capture reaches:** `rck` and the strobe switch happen in the *same* clock
edge, 208 ns before the outputs are released, and the outputs were already blanked 9.8 µs earlier. At
the **FPGA pins** there is no window in which live outputs see a row/column mismatch.

> **Correction, 2026-08-10 — the conclusion drawn from this was too strong.** The table above already
> contains the problem; it was simply not read as one. *"strobe change → output enable: 208 ns"* means
> the column is told to switch **208 ns before the rows go live** — and behind the connector sits a
> saturated 2N5883 that needs *tens of microseconds* to stop conducting (§3.3). The entire 9.8 µs of
> blanking sits on the wrong side of that edge. So the correct reading of this measurement is: the
> FPGA does exactly what it was told, and what it was told was wrong. An 8-channel capture of FPGA
> outputs structurally cannot see this — it would take a probe on a strobe line at the lamp panel.
> The playfield observation of [`Lamp_Preglow_Experiment.md`](Lamp_Preglow_Experiment.md) §3 did see
> it. **SW 0.1.6** moves the strobe change to the *start* of the blanking window, so that row of the
> table should read ~20 µs, and adds a second correction the table cannot show at all: `oe_n = '1'` is
> high-Z, not 0 mA (§4). Since 0.1.6, channel 3 of `DBG_MODE = 5` carries the real blanking window
> (`blank`) rather than `oe_n`, which now stays low during operation, and there are **two** `rck`
> pulses per phase — the first latches zeros, the second the pattern.

The longer dwell of SW 0.1.5 does not weaken this: blanking happens *at the switch*, not during the
dwell, so the blanking window, the bit clock, the `rck`→enable delay and above all the violation
counts are independent of `DWELL_CYCLES`. Only the visible window and the frame period scale.

**The original has no blanking at all** — and that is not an assumption but follows from two
independent sources (§3.2/§3.3): the Aux board decodes `LAMP BIT 0/1` with a 7402 NOR array that has
**no enable input**, so exactly one of the four strobes is powered at every instant; and the
Troubleshooting Guide's own figures leave no room for a gap (4 × ~500 µs in a 2 ms period). Its 9334
row latches are therefore reloaded by the DMA while a column is live. AtariFA's blanking narrows that
window but, up to SW 0.1.5, did not close it — the slow column stage is shared hardware and does not
care which MPU drives it.

#### 6.7.1 Side finding: the 24th shift pulse is only 20 ns wide

The `srck` count per blanking window splits **23 (20 008 windows) / 24 (18 495)**. Cause: in
`lamp_matrix.vhd` the `St_Latch` state clears `srck` on the very next `clk_50` edge instead of
waiting for a shift tick, so the final (24th) `SRCK` high pulse lasts **one clock period = 20 ns**
instead of 200 ns. Against the analyser's 41.7 ns sampling grid such a pulse is caught with
probability 20/41.7 = 48.0 % — and it was caught in 18 495 / 38 503 = **48.0 %** of windows. The
agreement confirms the width to be exactly one `clk_50` period.

It worked on this board (lamps HW-tested OK, and a missed 24th pulse would shift the whole cascade by
one group, which would be unmissable), but 20 ns sits right at the 74HC595's minimum clock pulse
width (~20 ns at 4.5 V, more over temperature) — there was no margin.

**Fixed 2026-08-09:** `lamp_matrix.vhd` got one extra FSM state, `St_ShiftLast`, which waits for a
shift tick with `srck` still high before entering `St_Latch`. The 24th pulse is now 220 ns wide,
like the other 23. Cost: +1 register (one-hot), +6 combinational, memory unchanged, slack
3.142 → 2.683 ns (inside the 1.5 ns tolerance); `scripts/baseline.csv` updated accordingly.

**Verified on hardware the same day** (`DBG_MODE = 5`, 1.813 s, 6973 windows, attract):

| Quantity | before the fix | after |
|---|---|---|
| `srck` edges per window | 23 / 24 split 52 : 48 | **24 in all 6972 genuine windows** |
| Blanking window | 9.792 µs | **10.000 µs** (+208 ns, as predicted) |
| Visible window (dwell) | 250.042 µs | 250.042 µs — unchanged to the nanosecond |
| Bit clock / release margin | 2.40 MHz / 208 ns | unchanged |
| Violations (latch/strobe/shift while live) | 0 | 0 |

The single window reported with 22 edges, an 8.916 µs blank and a 130 µs dwell sits at
t = 0.076…0.085 ms — the truncated first window at the capture-start block boundary, the same
artifact discussed in §6.7. Per-lamp duty went 24.06 % → 24.04 %, frame rate 962.2 → 961.4 Hz;
both differences are 0.08 % and cannot be seen.

Those are SW 0.1.4 figures. The 10.000 µs blanking window measured here is what makes the SW 0.1.5
timing exact: it is 500 clocks, so `DWELL_CYCLES = 25100` puts the phase at 25600 clocks = 512.00 µs,
the original's digit slot (§3.1). Everything else in this table is independent of the dwell and
carries over unchanged.

---

## 7. Sources

- **Atari Pinball Troubleshooting Guide**, section *Lamp Strobes* — the origin of the "keep-alive"
  claim and the source of the original's lamp timing figures. Scan:
  [`Lamp_Strobes_Manual.png`](Lamp_Strobes_Manual.png); full document
  `N:\Projekte\FPGA Atari\Manuals\Atari Troubleshooting guide.pdf`.
- Aux-board lamp strobe generator: [`Auxiliary_PCB.png`](Auxiliary_PCB.png) (Section H, Sheet 10A —
  7402 decode, MC1413, 4× 2N5883, `LAMP PWR` via Q5/CR19).
- Processor-PCB lamp latches: [`Lamp_Logic2.png`](Lamp_Logic2.png) (Sheet 18A, eight 9334 addressable
  latches, one per data bit, addressed by A2/A3/A7) and [`Lamp_Logic.png`](Lamp_Logic.png)
  (Sheet 18D, ULN2003A row drivers).
- PinMAME reference: `doc/atari.c` (`ram_w` lamp handler, `ATARI1_nmihi`, `ATARI1_vblank`).
- ROM disassembly: `tools/dis6800.py airborne.e00.hex airborne.e0.hex` (Airborne Avenger; routine
  `0x7BB1–0x7BC6`, NMI ISR `0x7DBE`).
- Original DMA refresh mechanism: [`Display_Timing.md`](Display_Timing.md) §2 (same DMA chain drives
  display and lamps).
- AtariFA implementation: `lamp_matrix.vhd` (scan FSM, blanking) + `AtariFA.vhd` (`lamp_sniffer`,
  box-connector test-strobe path, header section 4).
