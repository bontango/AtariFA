# Switch-Reading-Analyse — 0x200B Testschalter-Polarität (2026-07-06)

Diagnose der spielabhängigen Switch-/Selbsttest-Probleme nach dem NMI-Fix (244 Hz). Methode:
ROM-Disassembly (`tools/dis6800.py`) von **Middle Earth** (608/609) und dem funktionierenden
**Airborne Avenger** (Kontrolle), Vergleich gegen PinMAME `dipg1_r` (`doc/atari.c`).

## Root Cause: 0x200B war invertiert
Beide ROMs werten **Bit 7 von 0x200B** als Testschalter aus und erwarten **Bit7 = 1 = Test gedrückt**:

- **Middle Earth @ `7F9C`** (aufgerufen im Boot @ `7061`):
  ```
  7F9C LDAA $200B      ; A = neues 0x200B
  7F9F LDAB $C4        ; B = altes 0x200B (RAM 0xC4)
  7FA1 STAA $C4
  7FA3 TSTB / BMI      ; altes Bit7 gesetzt -> return
  7FA6 TSTA / BPL      ; neues Bit7 klar   -> return
  7FA9 CLRA            ; alt=0 & neu=1  => STEIGENDE FLANKE Bit7 -> JSR 7EC7 (Test/Init)
  ```
  ⇒ löst auf **steigender Flanke Bit7 (0→1)** aus = Testschalter-Druck.

- **Airborne @ `7AB4`** (PinMAME-„ROL on DIP"):
  ```
  7AB4 ROL $200B       ; Bit7 -> Carry
  7AB7 ROL $00CF       ; Carry in Debounce-Schieberegister
  7ABA LDAA $CF / ANDA #$0F / CMPA #$03   ; Muster 0011 = 0->1-Übergang (2 Samples)
  7AC0 BNE ... else JMP $7CF5  ; Test betreten
  ```
  ⇒ betritt Test bei **0→1-Übergang Bit7** = Testschalter-Druck.

**PinMAME `dipg1_r`:** `0x200B = DIP(S1/1) XOR testSwBits XOR (Test?0xFF:0)`. Mit S1/1=0:
nicht gedrückt → `0x00` (Bit7=0), gedrückt → `0xFF` (Bit7=1). Middle Earth: `testSwBits=0x0F` →
nicht gedrückt `0x0F` (Bit7=0), gedrückt `0xF0` (Bit7=1). **Bit7=1 = gedrückt** in beiden Fällen.

**Unser FPGA (vorher):** `0x200B = not sw_state(11)` → Test **offen** (nicht gedrückt) → `0xFF`,
Bit7=**1**. Also sah der Ruhezustand aus wie „Test gedrückt":
- Level-basierte Spiele (Atarians/Time2000/SpaceRiders) → **booten sofort in den Selbsttest**.
- Flanken-basiertes Middle Earth → spurious Boot-Trigger bzw. verpasste echte Drücke
  („reagiert einmal / falsche Werte"). Ein echter Druck (Bit7 1→0) ist die falsche Flanke → keine Reaktion.

Airborne „funktionierte" nur, weil sein Debounce-Muster `0011` bei invertierter Polarität zufällig
beim **Loslassen** (statt Drücken) triggerte.

## Fix (in `AtariFA.vhd`, `dip_value`)
0x200B **nicht** mehr invertieren — wie jede andere DIP-Position (geschlossen/gedrückt → 0xFF/Bit7=1);
für Middle Earth `testSwBits=0x0F` auf die **nicht-invertierte** Basis:
- non-ME: `0x200B = sw_state(11)` (fällt mit dem allgemeinen DIP-Zweig zusammen).
- ME (game_idx=3): `(7..4 => sw_state(11), 3..0 => not sw_state(11))` = Basis XOR 0x0F →
  offen `0x0F` (Bit7=0), gedrückt `0xF0` (Bit7=1).

Damit: **kein Boot-in-Selbsttest** mehr; Testschalter (Matrix-Pos 11) betritt den Test auf Druck;
Airborne betritt den Test jetzt korrekt beim **Drücken** (statt Loslassen). Fix ist global für alle
Gen1-Spiele plausibel (alle werten Bit7 gleich), nur die ME-testSwBits-Sonderbehandlung bleibt game-gated.

## Voraussetzung / HW-Bezug
Matrix-Position 11 (0x200B) repräsentiert auf dem AtariFA-Board die kombinierte S1/1-XOR-Test-Leitung
(Nutzer simuliert sie per einzelnem DIP; beim Boot offen = S1/1=0, Test nicht gedrückt). Falls DIP S1/1
real auf 1 gesetzt wird, invertiert sich der Ruhepegel wie im Original — dann Test-Logik am Board prüfen.

## Nachtrag SW 0.2.1: 0x2000 ist ein DIP, nicht nur der DMA-Sync

Aufgefallen beim Editieren der FA-Control-Name-Files: **Kachel 0** (`0x2000`, im Name-File
„SW2-4") zeigt den Schaltzustand richtig an — FA-Control bekommt `fa_sw_state` roh aus der
Matrix —, **das Spiel sah den Schalter aber nie**. Der CPU-Lesepfad lieferte für genau diese
eine Adresse ein synthetisiertes Byte:

```vhdl
dip_value <= ("0" & dma_toggle & "111111") when cpu_addr = x"2000" else …   -- bis 0.2.0
```

Bit 7 fest `'0'`, Bit 5..0 fest `'1'`, `sw_state(0)` unbenutzt.

**PinMAME** (`src/wpc/atari.c`, `dipg1_r`) macht es anders: das ganze Byte kommt aus dem DIP
(geschlossen → `0xFF`), und **nur Bit 6** wird vom Toggle überschrieben:

```c
if (offset) return dipram[offset];
return toggle ? (dipram[offset] | 0x40) : (dipram[offset] & 0xbf);
```

**ROM-Gegenprobe** (`tools/listing.txt`, Middle Earth 608/609) — eindeutig:

```
  7215:  F6 20 07   LDAB   $2007
  7218:  2A 01      BPL    $721B      ; Bit7 = DIP-Wert
  721A:  4C         INCA
  721B:  49         ROLA
  721C:  F6 20 00   LDAB   $2000      ; <- 0x2000 ist Teil derselben Schleife
  721F:  2A 01      BPL    $7222
  7221:  4C         INCA
  7222:  49         ROLA
  7223:  F6 20 01   LDAB   $2001
```

Die Schleife `0x7200–0x7229` schiebt **Bit 7** von `0x2000…0x2007` zu einem DIP-Byte
zusammen — `0x2000` ist dort eine ganz normale DIP-Position, Bit 7 **muss** der DIP sein.
Bit 6 dagegen ist der Display-Sync:

```
  78BE:  B6 20 00   LDAA   $2000
  78C1:  84 40      ANDA   #$40       ; nur Bit 6
  78C3:  27 F9      BEQ    $78BE
```

Der frühere Kommentar im Top-Level deutete `0x721C` als „BPL-Check, der Bit7=0 erwartet" —
das war die falsche Lesart derselben Fundstelle.

**Fix (SW 0.2.1):**

```vhdl
dip_value <= (6 => dma_toggle, others => sw_state(0)) when cpu_addr = x"2000" else …
```

`sw_state(0)` ist derselbe Index, den der allgemeine Zweig gewählt hätte
(`cpu_addr(6 downto 0) = 0`) — die Basis ist also exakt der DIP, Bit 6 liegt darüber.

**Warum es bis 0.2.0 nicht auffiel:** die Spiele werten an `0x2000` nur Bit 7 und Bit 6 aus.
Bei DIP **OFF** (Coin/Credit-Werkseinstellung) liefert das synthetisierte `0x3F`/`0x7F` in
diesen zwei Bits dasselbe wie PinMAMEs `0x00`/`0x40`. Nur eine **geschlossene** DIP 0 hätte
`0xFF`/`0xBF` ergeben müssen — die war für das Spiel unsichtbar.

## Noch offen (nach HW-Bestätigung des Fixes)
- Middle Earth Switchtest „Schalter 1 geschlossen": nach sauberem Test-Eintritt erneut prüfen (evtl.
  Folge des vorher korrupten Eintritts, sonst Switch-Offset-Mapping / Replay-DIP-Injektion 0x204D-0x204F).
- Atarians (ATARI0) Tilt auf 0x2014/15 statt 0x2020/21; gameSpecific1-Sound (ME+SpaceRider); Time2000 0x508C.
