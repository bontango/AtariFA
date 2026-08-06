# Atari Gen1 Display — Timing-Analyse & FSM-Umsetzung

> Analyse-Session 2026-06-20. Ermittelt das **originale Display-Multiplex-Timing** der
> Atari-Gen1-MPU aus einer realen Logic-Analyzer-Aufzeichnung und leitet daraus die
> Anpassung der FSM in [`display_control.vhd`](../display_control.vhd) ab.
>
> Zugehöriges Schaltbild: [`Display_Logic.png`](Display_Logic.png)
> (*The Atarians, Processor PCB 006020-01/-05 F, Section H, Sheet 15B, März 1978*).

---

## 1. Ausgangslage

`display_control.vhd` erzeugt die Steuersignale für die echte Atari-Display-Platine
(`LOAD`, `DISPLAY DATA`, `DISPLAY ADRS`, `CATHODE/ANODE BLANK`). Das Timing war ursprünglich
**selbst entworfen** (grob nach PinMAME `atari.c` orientiert) und wich vom Original ab.
Ziel dieser Session: das **echte Hardware-Timing** ermitteln und die FSM darauf abgleichen —
ohne die Architektur (Shadow-Buffer, siehe §3) zu ändern.

---

## 2. Die Originalschaltung (Sheet 15B)

Das Blatt ist das I/O-Blatt der MPU und enthält weit mehr als das Display. Display-relevant
sind drei Blöcke:

| Block | Bauteil(e) | Funktion |
|---|---|---|
| **DMA-Adresszähler** | `9316` (74161, synchron) | Läuft im DMA-Fenster über die Score-RAM-Adressen; Ausgänge → `MC14050` → **DISPLAY ADRS** (7 Bit). |
| **Datenpfad** | `74157` (Quad-2:1-Mux) + `RES PACK` + `MC14050` | Wählt High-/Low-Nibble des adressierten RAM-Bytes → **DISPLAY DATA** (4 Bit). |
| **Load/Blank-Sequenzer** | `7420/7474/7427/7408` | Erzeugt **LOAD DISPLAY**, **CATHODE BLANK**, **ANODE BLANK** aus den Zählerbits. |

Die `MC14050` sind reine Pegelwandler (5 V TTL ↔ Display-HV), im FPGA bedeutungslos.

### Originaler Mechanismus: DMA
Im Original wird das Display per **DMA** aufgefrischt: Die Timing-Kette (`7493`-Teiler, oben links,
erzeugt auch NMI) **hält die 6800 an** (HALT/DMA), der `9316` treibt den RAM-Adressbus, die
RAM-Daten fließen durch den `74157` in die Display-Latches, `LOAD` taktet sie ein. Die CPU ist
während des Refreshs eingefroren.

### Adress-Kodierung (aus LA-Bus-Gruppen verifiziert, siehe §4)
`DISPLAY ADRS` = 7 Bit `adr0..adr6`:

| Bits | Name | Wertebereich | Bedeutung |
|---|---|---|---|
| adr0–adr2 | `digit` | 0..7 | Ziffernposition (Multiplex-Stelle) |
| adr3–adr4 | `player` | 0..3 | eines der 4 Score-Displays |
| adr5–adr6 | `select` | 0..3 | Score- vs. Status/Credit-Gruppe |

→ Pro Digit scannt die Hardware `player`×`select` = **4×4 = 16 Loads** (die „16 loads", von denen
die meisten am Display ignoriert werden).

---

## 3. FPGA-Ansatz vs. Original

Der FPGA macht **kein DMA**, sondern einen **Write-Sniffer / Shadow-Buffer**: Die CPU schreibt ins
Score-RAM, ein Prozess belauscht 0x00–0x1F und kopiert die BCD-Nibbles nach `display1..4`/`status_d`.
`display_control.vhd` multiplext daraus mit eigener FSM aus. Der `halt`-Eingang der CPU bleibt `'0'`.

**Konsequenz für dieses Vorhaben:** Das Display-Board interessiert nur die **Wellenform** an seinen
Eingängen, nicht deren Erzeugung. Es genügt also, die **Zeitkonstanten** der FSM ans Original
anzugleichen — kein Eingriff in CPU-Bus/DMA. Das ist der bewusst gewählte, risikoarme Weg.

---

## 4. Messung

| | |
|---|---|
| Quelle | `../../_debug/Atari_Display_org - Kopie (2).LPF` (Intronix LogicPort, außerhalb Repo) |
| Format | Textbasiert, RLE-kodiert (`Count`-Spalte = Sample-Anzahl); direkt mit Python parsebar |
| Auflösung | `AcquiredSamplePeriod = 1e-8` → **10 ns/Sample** |
| Aufnahmelänge | 670 606 Samples = **6,706 ms** (≈ 1,6 Frames) |

**Aufgezeichnete & benannte Kanäle** (= exakt das Display-Interface):

| LA-Kanal | Signal | Bedeutung |
|---|---|---|
| D0–D3 | `Data0..3` | DISPLAY DATA (Nibble) |
| D8–D14 | `adr0..6` | DISPLAY ADRS |
| D16 | `load` | LOAD DISPLAY |
| D17 | `cath_bl` | CATHODE BLANK |
| D18 | `anod_bl` | ANODE BLANK |

Die Bus-Gruppen in der LPF (`digit=adr0..2`, `player=adr3..4`, `credit=adr5..6`) bestätigen die
Adress-Kodierung aus §2.

---

## 5. Messergebnisse (verifiziert)

### LOAD-Puls (`load`)
| Größe | Wert |
|---|---|
| low (aktiv) | **1,23 µs** |
| high | 2,77 µs |
| Periode | **4,0 µs** (sauber, durchgehend) |

### Pro Digit-Periode (`cath_bl` / `anod_bl`)
| Phase | Pegel | Dauer |
|---|---|---|
| **Blank/Setup** (Display AUS) | `cath_bl=0`, `anod_bl=1` | **129 µs** |
| **Show** (Display AN) | `cath_bl=1`, `anod_bl=0` | **383 µs** |
| **Digit-Periode** | | **512 µs** (129+383) |
| **Duty** | | **25 % aus / 75 % an ≈ 1:3** |

- **16 Loads pro Digit**, exakt alle 4 µs, im Blank-Fenster bei +6,9 µs … +67,0 µs; danach ~62 µs
  reines Leer-Blank (Loads füllen also nur die erste Hälfte des Blank-Fensters).

### Pro Frame
| Größe | Wert |
|---|---|
| Digits/Frame | **8** (adr0–2 = 0..7) |
| Scan-Reihenfolge | **0, 2, 4, 6, 1, 3, 5, 7** (adr0 = *langsamstes* Bit) |
| Frame-Periode | 8 × 512 µs = **4,10 ms** |
| **Refresh** | **≈ 244 Hz** |
| Helligkeit/phys. Digit | 383 µs / 4096 µs ≈ **9,4 %** Einschaltdauer |

`digit 6` = Player-up-LEDs, `digit 7` trägt bei diesen Spielen **Leerdaten** (unbenutzter 8. Slot).

---

## 6. Vergleich Original ↔ alt ↔ neu

| Parameter | Original (gemessen) | alt (selbst entworfen) | neu (diese Umsetzung) |
|---|---|---|---|
| LOAD low | 1,23 µs | ~1 µs | ~1 µs (1 µs = nächster sauberer Wert @1 MHz) |
| Loads/Digit | 16 | 5 | 5 (Rest am Display ohnehin ignoriert) |
| **Blank-Phase** | **129 µs** | ~11 µs ❌ | **~129 µs** ✅ |
| **Show-Phase** | **383 µs** | ~232 µs ❌ | **~383 µs** ✅ |
| Digit-Periode | 512 µs | ~244 µs | **~512 µs** ✅ |
| Digits/Frame | 8 | 7 | **8** (Digit 7 = Leer-Slot) ✅ |
| Refresh | 244 Hz | ~585 Hz | **~244 Hz** ✅ |
| **Duty (an)** | **75 %** | ~95 % ❌ | **~75 %** ✅ |

---

## 7. Schlüsselerkenntnis

Nicht der LOAD-Puls war das Problem (der passte), sondern das **Blank:Show-Verhältnis**.
Die alte FSM ließ das Display ~95 % der Zeit an, das Original nur 75 % → die Anzeige war real
**~25 % heller** als das Original und lief mit 2,4-fachem Refresh. Der dominante Fidelity-Hebel ist
daher die **Verlängerung der Blank-Phase** (11 → 129 µs) bei gleichzeitig längerer Show-Phase
(232 → 383 µs); der Rest (Loads/Digit, exakte 4-µs-Kadenz) ist für das Display-Board irrelevant.

---

## 8. FSM-Umsetzung in `display_control.vhd`

Takt = **1 MHz** ⇒ **1 count = 1 µs**. Struktur der bestehenden FSM bleibt; geändert/ergänzt:

```
St_Disp_off ─► St_Load1 ─► St_Push1 ─► … ─► St_Load5 ─► St_Push5 ─► St_Blank ─► St_Show ─► (digit++) ─► St_Disp_off
   (AUS)         5 Loads (je 1µs low / 1µs high)  ≈11µs        Pad-AUS      Display AN
                                                              auf 129µs      383µs
```

**Phasen-Bilanz (AUS-Zeit):** `St_Disp_off` (1 µs) + 5×(Load+Push) (10 µs) + `St_Blank`-Pad
(~118 µs) = **~129 µs Blank**. Danach `St_Show` = **~383 µs**.

**Neue/­geänderte Elemente:**
- **`St_Blank`** — neuer Zustand: hält Display AUS (`cath=0`/`anod=1`) und padded die Blank-Phase
  auf 129 µs (Konstante `C_BLANK_PAD`).
- **`St_Show`** — ersetzt `St_Wait1`+`St_Wait2`: Display AN (`cath=1`/`anod=0`) für 383 µs
  (Konstante `C_SHOW`); danach Digit-Inkrement.
- **`C_LAST_DIGIT = 7`** — 8 Runden (0..7). Digit 7 ist der unbenutzte 8. Scan-Slot des Originals
  und wird **leer** (`x"F"`) geladen. Auf `6` setzen ⇒ 7 Runden wie früher.
- **`digit_nibble()`** — Hilfsfunktion mit *geklemmtem* Index: liefert für `digit ≤ 6` das echte
  Nibble, für `digit = 7` Blank (`x"F"`). Vermeidet Index-Überlauf von `DISPLAY_T` (Bereich 0..6).

**Konstanten** (alle in µs, oben in der Architecture):

| Konstante | Wert | Wirkung |
|---|---|---|
| `C_BLANK_PAD` | 116 | Pad-AUS nach den Loads → Blank gesamt ≈ 129 µs |
| `C_SHOW` | 381 | Show-Dauer ≈ 383 µs |
| `C_LAST_DIGIT` | 7 | letzte Digit-Runde (8 Runden 0..7) |

> Zähl-Semantik wie im bestehenden Code: `count > N` belegt den Zustand für ≈ N+2 Takte
> (count = 0..N+1). Daher `C_SHOW=381` ⇒ ≈383 µs, `C_BLANK_PAD=116` ⇒ ≈118 µs Pad.

---

## 9. Offene HW-Feintuning-Punkte

- **Digit-Reihenfolge:** Original scannt `0,2,4,6,1,3,5,7` (adr0 langsamstes Bit). Die FSM zählt
  linear 0..7. Falls die physische Verdrahtung die Original-Reihenfolge erwartet, hier oder im
  Shadow-Buffer-Demux (`AtariFA.vhd`) anpassen. Für das **Timing** irrelevant.
- **LOAD low = 1 µs vs. 1,23 µs:** bei 1-MHz-Granularität ist 1 µs der nächste saubere Wert und für
  die Latch-Flanke der Display-Platine ausreichend. Bei Bedarf auf 2 µs (überschießt) erweiterbar.
- **5 statt 16 Loads:** funktional ausreichend (nur 4 Player + Status existieren physisch).

---

## 10. Quellen

- Schaltbild: `Display_Logic.png` (Sheet 15B, dieses Verzeichnis)
- Messung: `../../_debug/Atari_Display_org - Kopie (2).LPF` (Intronix LogicPort, 10 ns; außerhalb Repo)
- Umsetzung: `../display_control.vhd`
