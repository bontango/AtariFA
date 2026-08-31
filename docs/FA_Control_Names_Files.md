# Namensdateien für FA_Control — Kochbuch für die Atari-Gen1-Spiele

Wie man eine `names/AtariFA/<spiel>.cfg` für FA_Control erstellt: woher die Nummern
kommen, welche Umrechnung je Gewerk gilt, und was davon **spielunabhängig** ist und
deshalb nur einmal hergeleitet werden musste.

Entstanden beim Bau von `AtariFA/002.cfg` (Airborne Avenger, 08.2026). Die vier
übrigen Spiele — Atarians (000), Time 2000 (001), Middle Earth (003), Space Riders
(004) — sind damit im Wesentlichen Fleißarbeit; die Rechenregeln stehen alle hier.

Schwesterdokument: **`FA_Control_Interface.md`** (Protokoll, Übernahmemodell,
Nummerierung aus Sicht des FPGAs). Dieses Dokument ist die Anwendung davon auf die
fünf konkreten Spiele.

---

## 1. Was eine Namensdatei ist und wo sie liegt

Ablage = Maschinen-ID: `<HARDWARE>/<SPIEL>.cfg`, also `AtariFA/002.cfg`. `HARDWARE`
ist der String aus LISY-Opcode 0 (`AtariFA`), `SPIEL` die Spielnummer aus Opcode 8,
dreistellig. Auf AtariFA ist das die Game-Select-DIP-Bank:

| Nr | Spiel | Datei |
|---|---|---|
| 000 | The Atarians | `AtariFA/000.cfg` |
| 001 | Time 2000 | `AtariFA/001.cfg` |
| 002 | Airborne Avenger | `AtariFA/002.cfg` ✅ fertig |
| 003 | Middle Earth | `AtariFA/003.cfg` |
| 004 | Space Riders | `AtariFA/004.cfg` |

Hochladen im Menü **07 NAMES** oder ablegen unter
`https://lisy.dev/swrep/misc/FA_Control/names/AtariFA/`.

### Format — die eine Falle

Der Parser sitzt im Browser (`FA_Control/main/web/index.html`, `parseNames()`) und ist
bewusst simpel:

* Abschnitte müssen exakt `^\[[A-Za-z]+\]$` sein.
* Schlüssel muss rein numerisch sein, sonst wird die Zeile verworfen.
* **Alles hinter dem ersten `=` ist der Name — es gibt KEINE Kommentare am Zeilenende.**
  Ein `20=Bonus 5K   # J1-2` erzeugt den Namen „Bonus 5K   # J1-2".
* Ganze Kommentarzeilen mit `#` oder `;` am Zeilenanfang sind erlaubt und werden für
  die Querverweistabellen genutzt.
* Maximal 32 kB. Die Airborne-Datei liegt bei ~6,9 kB inklusive aller Kommentare.

---

## 2. Spulen — `[coils]`

**FA-Control-Nummer = Treiber-Nummer `Qn` des Schaltplans.** 1…20 = `solenoids(1..20)`,
**21** = Münzzähler (`COIN_CNTREN`), **22** = Sperrspule Münztür (`LOCKOUT_EN`), beide
auf dem Aux-Board. Als einziges Gewerk 1-basiert (LISY zählt Spulen ab 1).

**Die Zahl im Spiel-Manual ist nicht die Spulennummer.** Die Manuals führen eine
„Credit Display Number" 1…13 — das ist die Nummer, die der Selbsttest im Credit-Display
anzeigt, nicht der Treiber. Tabelle 5 („Solenoid Identification") des jeweiligen Manuals
liefert die Übersetzung. Für Airborne:

| Credit-Display-Nr | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **Qn = FA-Nummer** | 12 | 16 | 11 | 5 | 15 | 17 | 13 | 4 | 7 | 6 | 2 | 8 | 1 |

Diese Übersetzung ist **je Spiel neu nachzuschlagen** — sie ergibt sich aus der
Verdrahtung des jeweiligen Spielfelds, nicht aus der MPU.

**Q14 und Q18 sind auf der AtariFA-Platine nicht bestückt.** FA-Control nimmt die
Befehle an, es passiert nur nichts. Nummern, die ein Spiel nicht benutzt, lässt man
in der Datei einfach weg.

Mögliche Abkürzung für die übrigen vier Spiele:
`Manuals\Atari Spulentreiberbelegung Gen1.pdf` sieht nach genau dieser Tabelle für alle
Gen1-Spiele aus (beim nächsten Spiel prüfen — der Text ließ sich nicht extrahieren, das
PDF muss man ansehen).

---

## 3. Schalter — `[switches]`

**FA-Control-Nummer = CPU-Offset = `Adresse − 0x2000`, 0-basiert.**
`sw_state(i)` im Top-Level ist genau die Matrixzelle des Offsets `i`, und
`fa_control` reicht alle 80 durch (`top/AtariFA.vhd:843`) — auch die 16 des
DIP-Bereichs `0x2000–0x200F`.

**Umrechnung aus der Manual-Nummer: `FA-Nummer = Manual-Nummer + 15`.**

Die Manuals nummerieren Schalter 1…64 als Matrixposition (Achterblöcke = Strobe-Zeilen).
Der AtariFA-Offsetraum beginnt 15 höher, weil die beiden DIP-Strobes `0x2000–0x200F`
vorne liegen.

### Die Abkürzung: es gibt eine fertige Tabelle für alle fünf Spiele

`Manuals\Atari Schalterzuordnungen und Kontakttestcodes.csv` (Semikolon) enthält
**Steckerpin (J7/J10), CPU-Adresse und Schalternummer + Bezeichnung für alle fünf
Spiele nebeneinander**. Damit entfällt jede Rechnerei: Spalte `Adresse` minus `0x2000`
ist direkt die FA-Nummer.

```
Stecker;Zeile;Adresse;Space Riders SW-Nr;… ;Airborne Avenger SW-Nr;Airborne Avenger Bezeichnung;…
J7;W;2043;52;Right Captive Ball Target;52;Out Hole Kicker;…      -> FA-Nummer 0x43 = 67
J7;1;2020;17;Tilt Cabinet;17;Tilt Cabinet;…                      -> FA-Nummer 0x20 = 32
J10;F;2010;1;Coin 1;1;Coin 1;…                                   -> FA-Nummer 0x10 = 16
```

Die Spalte `Zeile` ist der Steckerpin auf J7 bzw. J10 — und genau das steht auch in der
Spalte „AtariFA Switch Test" der `Airborne Avenger Assignments.xlsx`. Die beiden Quellen
decken sich vollständig.

### Nicht vergessen: die Schalter außerhalb des Spielfelds

| FA-Nr | Adresse | Bedeutung |
|---|---|---|
| 11 | `0x200B` | Testschalter (liegt auf derselben Leitung wie DIP 1/1) |
| 16 / 17 | `0x2010` / `0x2011` | Münzschalter 1 / 2 (J10-F / J10-H) |
| 18 / 19 | `0x2012` / `0x2013` | Start-Taster / Slam Tilt (J10-7 / J10-6) |
| 76…79 | `0x204C`…`0x204F` | Hex-Decode-Schalter (Replay-Stufen), J7-S/T/U/V |

Diese fünf Blöcke sind **für alle Gen1-Spiele identisch** und können 1:1 in jede neue
Datei übernommen werden. J7-5 und J7-6 sind SW-COMMON, keine Schalter.

### Gegenprobe am ROM (falls die CSV mal nicht reicht)

Der Disassembler zeigt, welche Adressen ein Spiel wirklich liest — damit erkennt man
sofort, ob eine Offset-Annahme um 1 danebenliegt:

```bash
cd "N:/Projekte/FPGA Atari/FPGA_source/rom"
python ../tools/dis6800.py airborne.e00.hex airborne.e0.hex --name aavenger --out aav.txt
grep -oE '\$20[0-9A-F]{2}' aav.txt | sort -u
```

Für Airborne kommt heraus: `$2010–$2013`, `$2020–$2027`, `$2031–$204B`, `$204C`, `$204F`
— exakt der Satz aus der CSV. Wertvoll ist vor allem das **Negativ-Ergebnis**: die im
Manual unbenannten Nummern 33/53/54/55 (= FA 48/68/69/70) werden nicht gelesen, sind
also wirklich unbelegt und nicht nur unbeschriftet.

**Reihenfolge der ROM-Argumente beachten:** `dis6800.py <rom@0x7000> <rom@0x7800>`.
Bei falscher Reihenfolge kommen unsinnige Vektoren heraus (`RESET=$8E39`); richtig ist
für Airborne `airborne.e00.hex` zuerst.

---

## 4. Lampen — `[lamps]`

Das ist der Teil, der Arbeit gemacht hat — und der nun **ein für alle Mal erledigt** ist.

### Die Formel

```
FA-Nummer = (595-Gruppe − 1) × 4 + Strobe        Strobe SA=0, SB=1, SC=2, SD=3
```

Gruppe = Ausgang der 74HC595-Kaskade = eine ULN2003A-Zeile; Strobe = Spalte vom
Aux-Board. Die Zuordnung Gruppe ↔ (Latch, Bit) steht als `GRP_OF` in
`rtl/common/lamp_map_pkg.vhd` und ist die einzige Stellschraube.

### Der Weg vom Schaltplan zur Nummer

Das Lampenblatt der Prozessor-Platine (**Sheet 18D**, für Airborne als
`docs/Lamp_Logic.png` im Repo) beschriftet jeden ULN-Ausgang mit
`LAMP <RAM>-B<bit>-S<strobe>` und nennt den Steckerpin. Daraus:

```
offset = RAM − 0x30          Latch L = offset / 4      Strobe s = offset mod 4
Gruppe = GRP_OF(L*6 + bit)   FA-Nummer = (Gruppe − 1) * 4 + s
```

Beispiel `LAMP 31-B0-SB` an J1-C: offset 1 → L=0, s=1 (SB ✓), Bit 0 →
`GRP_OF(0)` = Gruppe 6 → Nummer `(6−1)*4 + 1` = **21**. (Genau die Lampe aus dem
Vorglüh-Feldbericht, s. `Lamp_Preglow_Experiment.md` §6.)

### Und jetzt der Punkt: die Tabelle gilt für alle fünf Spiele

Die Ausgänge sind auf Sheet 18D streng **fortlaufend** über die Steckerpins verteilt —
Index `i = bit*16 + offset`, und die Pins laufen in fester Reihenfolge:

```
je Stecker:  B C D E F H J | 2 3 4 5 6 7 8 | K L M N P R S | 9 10 11 12 13 14 15 | T U V W X Y Z | 16 17 18 19 20 21 22
             (Pin 1 und Pin A sind die Beleuchtung, nicht in der Matrix)
```

J1 nimmt Index 0…41, J2 nimmt 42…83 — zusammen genau die 84 Lampen, die AtariFA
bedienen kann. (Das Original führt an J3 noch die Bits 5…7 weiter, insgesamt bis 128
Lampen; die 6 ULN-Positionen A14…B12 sind auf der AtariFA-Platine nicht bestückt.)

**AtariFA hat genau ein Layout für alle Spiele**, also ist die Zuordnung
*Steckerpin → FA-Lampennummer* spielunabhängig. Für ein neues Spiel braucht man nur
noch dessen Spielfeld-Lampenblatt („welche Funktion hängt an welchem Pin") und schlägt
die Nummer hier nach:

| Pin | Sheet-18D-Label | Grp | St | **Nr** | Pin | Sheet-18D-Label | Grp | St | **Nr** |
|---|---|---|---|---|---|---|---|---|---|
| J1-B  | 30-B0-SA  |  6 | A | **20** | J2-B  | 3A-B2-SC  | 16 | C | **62** |
| J1-C  | 31-B0-SB  |  6 | B | **21** | J2-C  | 3B-B2-SD  | 16 | D | **63** |
| J1-D  | 32-B0-SC  |  6 | C | **22** | J2-D  | 3C-B2-SA  | 19 | A | **72** |
| J1-E  | 33-B0-SD  |  6 | D | **23** | J2-E  | 3D-B2-SB  | 19 | B | **73** |
| J1-F  | 34-B0-SA  |  7 | A | **24** | J2-F  | 3E-B2-SC  | 19 | C | **74** |
| J1-H  | 35-B0-SB  |  7 | B | **25** | J2-H  | 3F-B2-SD  | 19 | D | **75** |
| J1-J  | 36-B0-SC  |  7 | C | **26** | J2-J  | 30-B3-SA  | 17 | A | **64** |
| J1-2  | 37-B0-SD  |  7 | D | **27** | J2-2  | 31-B3-SB  | 17 | B | **65** |
| J1-3  | 38-B0-SA  |  8 | A | **28** | J2-3  | 32-B3-SC  | 17 | C | **66** |
| J1-4  | 39-B0-SB  |  8 | B | **29** | J2-4  | 33-B3-SD  | 17 | D | **67** |
| J1-5  | 3A-B0-SC  |  8 | C | **30** | J2-5  | 34-B3-SA  | 18 | A | **68** |
| J1-6  | 3B-B0-SD  |  8 | D | **31** | J2-6  | 35-B3-SB  | 18 | B | **69** |
| J1-7  | 3C-B0-SA  |  2 | A | **4**  | J2-7  | 36-B3-SC  | 18 | C | **70** |
| J1-8  | 3D-B0-SB  |  2 | B | **5**  | J2-8  | 37-B3-SD  | 18 | D | **71** |
| J1-K  | 3E-B0-SC  |  2 | C | **6**  | J2-K  | 38-B3-SA  | 10 | A | **36** |
| J1-L  | 3F-B0-SD  |  2 | D | **7**  | J2-L  | 39-B3-SB  | 10 | B | **37** |
| J1-M  | 30-B1-SA  |  3 | A | **8**  | J2-M  | 3A-B3-SC  | 10 | C | **38** |
| J1-N  | 31-B1-SB  |  3 | B | **9**  | J2-N  | 3B-B3-SD  | 10 | D | **39** |
| J1-P  | 32-B1-SC  |  3 | C | **10** | J2-P  | 3C-B3-SA  | 21 | A | **80** |
| J1-R  | 33-B1-SD  |  3 | D | **11** | J2-R  | 3D-B3-SB  | 21 | B | **81** |
| J1-S  | 34-B1-SA  |  4 | A | **12** | J2-S  | 3E-B3-SC  | 21 | C | **82** |
| J1-9  | 35-B1-SB  |  4 | B | **13** | J2-9  | 3F-B3-SD  | 21 | D | **83** |
| J1-10 | 36-B1-SC  |  4 | C | **14** | J2-10 | 30-B4-SA  | 20 | A | **76** |
| J1-11 | 37-B1-SD  |  4 | D | **15** | J2-11 | 31-B4-SB  | 20 | B | **77** |
| J1-12 | 38-B1-SA  |  5 | A | **16** | J2-12 | 32-B4-SC  | 20 | C | **78** |
| J1-13 | 39-B1-SB  |  5 | B | **17** | J2-13 | 33-B4-SD  | 20 | D | **79** |
| J1-14 | 3A-B1-SC  |  5 | C | **18** | J2-14 | 34-B4-SA  |  1 | A | **0**  |
| J1-15 | 3B-B1-SD  |  5 | D | **19** | J2-15 | 35-B4-SB  |  1 | B | **1**  |
| J1-T  | 3C-B1-SA  | 13 | A | **48** | J2-T  | 36-B4-SC  |  1 | C | **2**  |
| J1-U  | 3D-B1-SB  | 13 | B | **49** | J2-U  | 37-B4-SD  |  1 | D | **3**  |
| J1-V  | 3E-B1-SC  | 13 | C | **50** | J2-V  | 38-B4-SA  | 12 | A | **44** |
| J1-W  | 3F-B1-SD  | 13 | D | **51** | J2-W  | 39-B4-SB  | 12 | B | **45** |
| J1-X  | 30-B2-SA  | 14 | A | **52** | J2-X  | 3A-B4-SC  | 12 | C | **46** |
| J1-Y  | 31-B2-SB  | 14 | B | **53** | J2-Y  | 3B-B4-SD  | 12 | D | **47** |
| J1-Z  | 32-B2-SC  | 14 | C | **54** | J2-Z  | 3C-B4-SA  | 11 | A | **40** |
| J1-16 | 33-B2-SD  | 14 | D | **55** | J2-16 | 3D-B4-SB  | 11 | B | **41** |
| J1-17 | 34-B2-SA  | 15 | A | **56** | J2-17 | 3E-B4-SC  | 11 | C | **42** |
| J1-18 | 35-B2-SB  | 15 | B | **57** | J2-18 | 3F-B4-SD  | 11 | D | **43** |
| J1-19 | 36-B2-SC  | 15 | C | **58** | J2-19 | 30-B5-SA  |  9 | A | **32** |
| J1-20 | 37-B2-SD  | 15 | D | **59** | J2-20 | 31-B5-SB  |  9 | B | **33** |
| J1-21 | 38-B2-SA  | 16 | A | **60** | J2-21 | 32-B5-SC  |  9 | C | **34** |
| J1-22 | 39-B2-SB  | 16 | B | **61** | J2-22 | 33-B5-SD  |  9 | D | **35** |

> **Wenn `GRP_OF` je geändert wird, ist diese Tabelle Makulatur.** Sie ist ein Abzug,
> keine zweite Quelle — im Zweifel neu aus `lamp_map_pkg.vhd` erzeugen (Skript-Schnipsel
> in Abschnitt 7).

### Wo die Lampennamen herkommen

Das Spielfeld-Lampenblatt des jeweiligen Spiels (Steckerpin → Funktion → DS-Nummer).
Im Repo liegen bisher `doc/Lamp_Strobes_Airborne.png` und `doc/Lamp_Strobes_Atarians.png`;
für die übrigen drei steht das Blatt in den Manuals unter `Manuals\<Spiel>\`.

**Die Strobe-Spalte solcher Blätter ist ein guter Selbsttest.** Sie muss zum Strobe des
Sheet-18D-Labels passen (sonst könnte die Lampe gar nicht leuchten). Beim Airborne
stimmten 62 von 65 Angaben; drei waren beim Abtippen verrutscht:

| Lampe | Pin | Tabelle | Sheet 18D |
|---|---|---|---|
| 54 Rollover #5 | J1-Z | D | **C** (`32-B2-SC`) |
| 66 Rollover #6 | J2-3 | D | **C** (`32-B3-SC`) |
| 81 Rollover „B" | J2-R | A | **B** (`3D-B3-SB`) |

Da die Nummer am Strobe hängt, sind das drei falsche Kacheln — deshalb lohnt die
Gegenprobe. Im Konfliktfall gilt der Schaltplan.

### Wie viele Lampen ein Spiel benutzt

Airborne belegt J1 komplett (bis auf F, L, W) und J2 nur bis Pin 13 / R → **62 der 84**.
Unbelegt bleiben 0-3, 7, 24, 32-35, 39-47, 51, 78, 82. Andere Spiele werden andere
Teilmengen benutzen; unbenutzte Nummern lässt man in der Datei weg.

---

## 5. Sounds und Displays

Beides ist **für alle fünf Spiele gleich** und kann kopiert werden.

**`[displays]`** — LISY-Konvention, *nicht* die Reihenfolge, die man intuitiv erwartet:

```
0=Credits / Ball      (4 Stellen)
1=Player 1            (je 6 Stellen)
2=Player 2
3=Player 3
4=Player 4
```

Die erste Fassung von `002.cfg` hatte das umgekehrt (0 = Player 1 … 4 = Credits) — das
war falsch, s. `FA_Control_Interface.md` Kapitel 5.

**`[sounds]`** — der Atari kennt keine Sound-Nummern. FA-Control spielt die 16
Wellenformen des 82s130-ROMs mit fester Tonhöhe. Sprechende Namen gibt es dafür nicht;
`0=Waveform 0` … `15=Waveform 15` ist ehrlicher als geratene Spielgeräusche
(die Vorlage `example.cfg` suggeriert „Bumper", „Slingshot" usw. — das ist generischer
LISY-Beispieltext und trifft auf Atari Gen1 nicht zu). S. `Sound_Emulation.md`.

---

## 6. Arbeitsablauf für ein weiteres Spiel

1. **Schalter:** `Manuals\Atari Schalterzuordnungen und Kontakttestcodes.csv` öffnen,
   Spalte des Spiels nehmen, `Adresse − 0x2000` = FA-Nummer. Die fünf spielunabhängigen
   Blöcke aus Abschnitt 3 dazu.
2. **Spulen:** Tabelle 5 des Spiel-Manuals (Credit-Display-Nr → Qn); Qn ist die
   FA-Nummer. Ggf. `Atari Spulentreiberbelegung Gen1.pdf` als Sammelquelle prüfen.
3. **Lampen:** Spielfeld-Lampenblatt (Pin → Funktion) und die Tabelle aus Abschnitt 4
   (Pin → Nummer). Strobe-Spalte als Gegenprobe.
4. **Sounds/Displays** aus `002.cfg` kopieren.
5. **Gegenprobe am ROM**, wenn irgendwo eine Nummer unsicher ist (Abschnitt 3).
6. Datei nach `N:\Projekte\FA_Control\names\AtariFA\<nnn>.cfg`, dann über Menü 07 NAMES
   hochladen oder auf `lisy.dev/swrep/misc/FA_Control/names/AtariFA/` legen.

Am Automaten fällt sofort auf, wenn etwas nicht stimmt: falsche **Spalte** bei den
Lampen ⇒ `STROBE_ENC`, falsche **einzelne** Lampe ⇒ `GRP_OF` — nicht die Namensdatei
(s. `FA_Control_Interface.md` Kapitel 9).

---

## 7. Werkzeuge

**xlsx ohne Excel lesen** (die Assignments-Tabelle ist ein ZIP):

```bash
unzip -o "Airborne Avenger Assignments.xlsx" -d xl/
# xl/xl/sharedStrings.xml  = alle Texte, xl/xl/worksheets/sheetN.xml = Zellen mit Index darauf
```
Achtung auf Sonderzeichen: in der Airborne-Tabelle standen `®` und `€` dort, wo
`(r)` und `(e)` gemeint waren (`Ai®borne` = `Ai(r)borne`).

**Lampen-Pin-Tabelle neu erzeugen**, falls `GRP_OF` sich ändert:

```python
GRP_OF=[6,3,14,17,20,9, 7,4,15,18,1,0, 8,5,16,10,12,0, 2,13,19,21,11,0]
PIN=['B','C','D','E','F','H','J','2','3','4','5','6','7','8',
     'K','L','M','N','P','R','S','9','10','11','12','13','14','15',
     'T','U','V','W','X','Y','Z','16','17','18','19','20','21','22']
for i in range(84):
    conn = 'J1' if i < 42 else 'J2'
    b, off = i//16, i%16
    L, s = off//4, off%4
    g = GRP_OF[L*6 + b]
    print(conn, PIN[i%42], '3%X-B%d-S%s' % (off, b, 'ABCD'[s]), 'Grp', g, '->', (g-1)*4 + s)
```

**ROM-Disassembly:** `tools/dis6800.py` (Abschnitt 3).

---

## 8. Verwandte Dateien

| Datei | Inhalt |
|---|---|
| `docs/FA_Control_Interface.md` | Protokoll, Übernahmemodell, Nummerierung im FPGA |
| `rtl/common/lamp_map_pkg.vhd` | `GRP_OF` — die eine Quelle der Lampenzuordnung |
| `docs/Lamp_Logic.png` | Sheet 18D, Airborne Processor PCB — Ausgang → Steckerpin |
| `docs/solenoid_mapping.txt` | Latch-Bit → `F_Qn` (Bestückung der AtariFA) |
| `../doc/Lamp_Strobes_Airborne.png`, `../doc/Lamp_Strobes_Atarians.png` | Spielfeld-Lampen je Steckerpin |
| `../Manuals/Atari Schalterzuordnungen und Kontakttestcodes.csv` | **Schalter aller 5 Spiele mit CPU-Adresse** |
| `../Manuals/Atari Spulentreiberbelegung Gen1.pdf` | vermutlich Spulen aller 5 Spiele (noch prüfen) |
| `../Manuals/<Spiel>/` | Spiel-Manuals mit Tabelle 5 und Lampenblatt |
| `N:\Projekte\FA_Control\names\example.cfg` | Formatbeschreibung |
