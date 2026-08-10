# Vorglühen („pre-glow"): Beobachtung am Flipper und Gegenexperiment

> **Stand 2026-08-10.** Schritt 1 ist gefahren — das **Ergebnis steht in §3**, und es hat die Sache
> entschieden: das Artefakt ist da, es ist reproduzierbar, und es entstand auf der AtariFA aus einer
> Ursache, die in `Lamp_Refresh_Analysis.md` §3.3 nur als Möglichkeit benannt war. Was daraus gebaut
> wurde, steht in §4; der ursprünglich geplante Kunstgriff `PREGLOW_CYCLES` ist damit überholt (§5).
> Gehört zu [`Lamp_Refresh_Analysis.md`](Lamp_Refresh_Analysis.md) — dort steht die Analyse.

## 1. Worum es geht

Das Handbuch (*Atari Pinball Troubleshooting Guide*, Abschnitt „Lamp Strobes") beschreibt, dass
Lampen im Aus-Zustand schwach pulsen, und verkauft das als absichtliche „keep-alive routine".
`Lamp_Refresh_Analysis.md` zeigt: die **Beobachtung** stimmt, die **Erklärung** nicht.

| | Stand |
|---|---|
| Software-Ursache | **ausgeschlossen** (LA-Messung 2026-08-09: kein einziger Lampen-RAM-Schreibzugriff in 25,7 s im Spiel; §6.6) |
| Aux-Board-Schaltung | **ausgeschlossen** (1-aus-4-Dekoder ohne Enable, kennt nur Spalten; §3.2) |
| Ursache = Zeilen/Spalten-Versatz bei lebender Spalte | **belegt** (2026-08-10 am Spielfeld, §3.3 hier) |
| AtariFA zeigt das Artefakt | **ja** — an den FPGA-Pins blankt sie sauber, an der Lampenfassung nicht (§3.3) |
| Glühlampen zeigen es | **nein** (§3.1) — es ist ein LED-Retrofit-Phänomen |

## 2. Schritt 1 — Beobachten, ohne irgendetwas zu ändern

*(Gefahren am 2026-08-10 an einem Airborne Avenger. Der Gegentest an der Original-MPU war nicht
möglich; er ist damit auch nicht mehr nötig — s. §3.)*

Kein Build, kein Eingriff. Ziel war eine Aussage darüber, **welche** Lampen glimmen — daran hing die
ganze Beweisführung.

**Die entscheidende Vorhersage aus §3.3:** das Artefakt trifft **nicht** beliebige Aus-Lampen,
sondern genau die, die sich eine **595-Gruppe (= Zeile)** mit einer leuchtenden Lampe einer
**anderen Strobe-Phase** teilen. In der FA-Control-Nummerierung
(`rtl/common/lamp_map_pkg.vhd`, `n = (595-Gruppe − 1) × 4 + Strobe`) sind das die vier Nummern
eines Viererblocks: `4k, 4k+1, 4k+2, 4k+3` gehören zur selben Zeile.

- Leuchtet Lampe `n`, sind die Kandidaten die drei Nachbarn im selben Viererblock.
- Ist ein kompletter Viererblock aus, darf dort **nichts** glimmen.

Genau dieser Unterschied trennt „Zeilen/Spalten-Versatz" (§3.3) von „allgemeiner Leckstrom"
(gleichmäßiges Glimmen überall, unabhängig von den Nachbarn).

**Protokoll:**

1. Dunkler Raum, Augen ein paar Minuten adaptieren lassen. LED-Retrofits zeigen es, Glühlampen
   praktisch nie — wo möglich also an LED-bestückten Fassungen beobachten.
2. Am **Original-MPU** (falls das Spielfeld damit noch läuft): Attract-Modus, eine sicher
   leuchtende Lampe suchen, ihre drei Viererblock-Nachbarn ansehen. Dann einen komplett dunklen
   Viererblock ansehen. Notieren: glimmen die Nachbarn stärker als der dunkle Block?
3. Dasselbe im **Spiel** (wenige Lampen an) — dort ist die Zuordnung eindeutiger als im Attract.
4. Mit **AtariFA** im selben Spielfeld gegenprüfen. Ab **SW 0.1.5** scannt die AtariFA im selben
   Zeitraster wie das Original (512 µs Spalte, 488 Hz Frame) — der Vergleich hängt damit nur noch
   am Blanking, nicht mehr zusätzlich an einer doppelten Frequenz.
5. Wenn möglich Handyvideo mit kurzer Belichtung / hoher ISO — auf dem Standbild sieht man
   schwaches Glimmen oft besser als mit dem Auge, und es ist dokumentierbar.
6. Notieren, **welche** Lampennummern (nicht nur „eine Lampe hinten links") — sonst lässt sich
   die Viererblock-Vorhersage hinterher nicht prüfen.

**Bequemer Sonderfall mit FA-Control:** über die Weboberfläche lässt sich eine **einzelne** Lampe
setzen. Damit ist der Test isoliert durchführbar — eine Lampe an, die drei Gruppen-Nachbarn
beobachten. Genau so ist §3 entstanden.

## 3. Ergebnis Schritt 1 (2026-08-10, Airborne Avenger, AtariFA + FA-Control)

### 3.1 Rohbeobachtung

* **Glühlampen glimmen erkennbar nicht.** Erst nach dem Ersetzen durch **LED-Retrofits** (Lampen
  9, 13, 15, 21, 53, 57, 65, 69) war überhaupt etwas zu sehen.
* Beim Betreten des Tests glimmen **9, 15, 21, 57** erkennbar, **obwohl keine Lampe angesteuert
  wird**.
* Im Lampentest glimmt eine LED **sehr deutlich**, wenn die **nächsthöhere** Lampennummer
  angesteuert wird (21 bei 22, 57 bei 58) — **und nur bei dieser**.
* Beim Ansteuern der Lampen **73, 77, 81** ist das Glimmen **verschwunden**.
* Auf der AtariFA selbst, mit LED-Lampentester an den Box-Connectors, ist der Effekt **nicht
  nachstellbar**: alle LEDs einzeln schaltbar, keine glimmenden Nachbarn.
* Gefahren mit **SW 0.1.3, 0.1.4 und 0.1.5** — **alle drei zeigen dasselbe Verhalten.**

### 3.2 Dekodierung der Nummern

Die FA-Control-Weboberfläche beschriftet die Lampenfelder **0-basiert** (`main/web/index.html`,
`mkgrid`), es gilt also direkt `Gruppe = n div 4 + 1`, `Strobe = n mod 4`:

| Nr | 9 | 13 | 15 | 21 | 53 | 57 | 65 | 69 | 73 | 77 | 81 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Gruppe (595 / Zeile) | 3 | 4 | 4 | 6 | 14 | 15 | 17 | 18 | 19 | 20 | 21 |
| Strobe (Spalte) | 1 | 1 | **3** | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 |
| glimmt | ja | – | ja | ja | – | ja | – | – | (angesteuert) | | |

Damit sind **21↔22** und **57↔58** jeweils *dieselbe Gruppe*, Strobe s↔s+1. Das beobachtete Muster
ist also nicht „Nachbarnummer", sondern **gleiche Zeile, vorhergehende Spalte** — die Vorhersage aus
§2 trifft zu. Zwei Effekte lassen sich sauber trennen: das *deutliche* Glimmen beim angesteuerten
Nachbarn (§3.3) und das *Grundglimmen* ohne jede Ansteuerung (§3.4).

### 3.3 Befund A — gleiche Zeile, vorhergehende Spalte

Dass **nur** dieser eine Nachbar glimmt und nicht alle drei des Viererblocks, sagt zusätzlich,
woher der Versatz kommt: nicht aus einem über die ganze Phase geladenen Spaltendraht (dann müssten
alle drei Nachbarn glimmen), sondern aus der **gerade abgeschalteten Spalte, die noch nachhängt**.

Der Ablauf in `lamp_matrix.vhd` bis SW 0.1.5 machte genau das:

```
Dwell zu Ende  ->  oe_n = 1 (blanken)  ->  24 Bit schieben (~10 us)  ->  rck-Latch
                                                                     ->  strobe_sel = neue Spalte
                                                                     ->  oe_n = 0   (20 ns spaeter!)
```

Das 10-µs-Blankfenster lag damit **komplett vor** dem Spaltenwechsel; Zeilen und Spalte wurden
praktisch gleichzeitig scharf. Auf der anderen Seite des Connectors sitzt der Spaltentreiber des
Aux-Boards: **2N5883-PNP, hart in Sättigung getrieben** (MC1413 zieht die Basis über 39 Ω, also
~0,2 A Basisstrom), **Abschalten nur über 8,2 K Basis-Emitter** (`Lamp_Refresh_Analysis.md` §3.2).
Das ist eine Speicherzeit im zweistelligen Mikrosekundenbereich. Die noch leitende **alte** Spalte
sieht deshalb bereits das **neue** Zeilenmuster — und die Lampe „gleiche Zeile, vorhergehende
Spalte" bekommt einen Stromstoß von ein paar Mikrosekunden, alle 2 ms.

Für einen Glühfaden ist das nichts (§3.1 bestätigt es), für eine LED reichlich.

**Drei Software-Versionen, gleiches Verhalten — und das ist ein eigenes Indiz.** 0.1.3 und 0.1.4
scannen mit **961 Hz** (`DWELL_CYCLES` 12500, 260 µs Phase), 0.1.5 mit **488 Hz** (512 µs). Wäre das
Glimmen an unserem Zeitraster aufgehängt, müsste es sich zwischen den Versionen ändern; es tut es
nicht. Passt genau: die Fensterbreite bestimmt die **Abschaltzeit des Spaltentreibers** (fest, in µs),
nicht die Phasendauer. Was sich mit dem Frame ändert, ist nur die *Wiederholrate* der Ereignisse —
das ist am glimmenden LED-Sockel mit dem Auge nicht zu unterscheiden, ein Faktor 2 in einem gerade
eben sichtbaren Glimmen erst recht nicht. Nebenbei: das Artefakt steckt damit in **jeder bisher
ausgelieferten Version**, es ist nichts, was 0.1.5 eingeschleppt hat.

**Damit ist der Mechanismus aus `Lamp_Refresh_Analysis.md` §3.3 gemessen statt hergeleitet** — mit
einer Ergänzung, die dort fehlte: der Versatz muss nicht aus dem Nachladen der Zeilen-Latches
kommen. Die **Abschaltzeit der Spalte allein genügt**, und die hat das Original genauso. Die
Messung „0 Verletzungen in 38 503 Phasen" (§6.7) bleibt richtig — sie hat die **FPGA-Pins**
gemessen, und dort ist alles sauber. Die Verzögerung sitzt hinter dem Connector.

### 3.4 Befund B — Grundglimmen aus hochohmigen Zeilen

Das Glimmen **ohne jede Ansteuerung** ist ein zweiter, unabhängiger Effekt. Es ist immer eine Spalte
aktiv (1-aus-4-Dekoder ohne Enable, §3.2), jede Lampe hat also dauernd Spannung auf der einen Seite.
Auf der anderen Seite standen die 595-Ausgänge während des Blankens auf **Hi-Z** — die
MC1413-/ULN-Eingänge floaten dann, und die µA Leckstrom genügen einer LED-Retrofit.

**Das Original hat diesen Zustand nicht:** dort hängen die Zeilentreiber an den **9334**-Latches
(Sheet 18A), also an permanent treibenden Totem-Pole-Ausgängen — eine Aus-Zeile ist dort 100 % der
Zeit eine harte `'0'`. Das Hi-Z-Fenster war eine reine AtariFA-Eigenheit, und zwar eine Abweichung
*vom* Original, nicht eine Nachbildung.

Dass 4 von 8 LEDs glimmen und 4 nicht, hat kein Gruppen- und kein Spaltenmuster (13 und 15 liegen
in derselben Gruppe, nur eine glimmt) — das ist Streuung der Treiberkanäle bzw. der Leuchtmittel.

### 3.5 Warum der Effekt auf der AtariFA-Platine selbst fehlt

Der LED-Lampentester hängt an den **Box-Connectors**, und dort erzeugen **vier P-Kanal-MOSFETs** die
Spalten (`Lamp_Refresh_Analysis.md` §5b) — nanosekundenschnelles Abschalten, nA-Leckstrom, wenige
Zentimeter Leitung statt Kabelbaum. Beide Ursachen aus §3.3 und §3.4 fehlen dort. Das ist kein
Widerspruch zur Spielfeld-Beobachtung, sondern die Kontrollmessung dazu: der Effekt sitzt in der
Aux-Board-/Spielfeld-Domäne, nicht in der FPGA-Logik.

### 3.6 Noch offen — billig prüfbar, am besten mit Options-DIP 5 = ON

* **Lampe 12 ansteuern muss LED 15 zum Glimmen bringen.** 15 ist Gruppe 4 / Strobe 3, die
  Vorgängerphase von Strobe 0 — der Partner ist also Nummer **+3**, nicht −1 (Wrap-around). Trifft
  das zu, ist die Regel „gleiche Gruppe, Phase (s−1) mod 4" wasserdicht. **Lampe 16 darf LED 15
  nicht zum Glimmen bringen** (andere Gruppe).
* **Warum hört das Glimmen bei 73/77/81 auf?** Alle drei liegen auf **Strobe 1** — derselben Spalte
  wie die glimmenden LEDs 9, 21, 57. Leithypothese: ein echter Glühfaden auf dieser Spalte zieht den
  hochohmigen Leckstrompfad tot. Prüfen: jede andere Lampe mit `Nr mod 4 = 1` (1, 5, 25, 29 …) muss
  dasselbe tun — und **LED 15 (Strobe 3) müsste dabei weiterglimmen**. Bliebe der Effekt auf die
  Gruppen 19–21 beschränkt (dann tut es auch 76 oder 78, andere Spalte), wäre es keine Spalten-,
  sondern eine Gruppen-Eigenschaft, und die Erklärung müsste neu gesucht werden.
* **LED tauschen** zwischen einer glimmenden (21) und einer dunklen Fassung (13): wandert das
  Glimmen mit der LED, ist es das Leuchtmittel; bleibt es an der Fassung, ist es der Treiberkanal.
  Entscheidet §3.4 endgültig.

## 4. Was daraus gebaut wurde — SW 0.1.6

Zwei Änderungen in `rtl/common/lamp_matrix.vhd`, beide direkt aus §3.3 und §3.4:

**(a) Blanken durch Nullen-Latchen statt `/OE`-Hi-Z — in beiden Modi.** Je Strobe-Phase laufen zwei
Schiebedurchläufe (Register `pass`): erst 24 Nullen + `rck` (alle Zeilen **aktiv** auf `'0'`), dann
das Muster der Phase + `rck`. `oe_n` ist nur noch der Reset-/Boot-Blank — da ist der Inhalt der 595
unbekannt, und Hi-Z ist der einzige sichere Zustand — und geht mit dem ersten Datenlatch dauerhaft
auf `'0'`. Das gilt **auch** bei DIP 5 = ON, weil aktives Treiben der Zeilen dem 9334-Original
*entspricht* (§3.4): es entfernt eine Abweichung, statt eine hinzuzufügen. Kostet keine Helligkeit —
die Nullen werden geschoben, *während* die Lampe noch leuchtet; die Ausgänge ändern sich erst mit
`rck`.

**(b) Der Spaltenwechsel wandert ins Austastfenster, umschaltbar über Options-DIP 5.**

| | DIP 5 = OFF (Serienstand) | DIP 5 = ON |
|---|---|---|
| `strobe_sel` wechselt | beim **Clear**-Latch, Zeilen sind aus | beim **Daten**-Latch, gleichzeitig mit den Zeilen |
| Totzeit Spalte → Zeilen scharf | `St_Settle` + Datendurchlauf ≈ **20 µs** | ~20 ns (Original-Zeitverhalten) |
| Vorglühen bei LED-Retrofits | weg | da |
| Phasendauer | 512,0 µs | 512,0 µs |
| Duty | 24,0 % | 24,5 % |

Die Phasendauer ist in beiden Modi gleich (im Original-Modus schlägt die übersprungene Settle-Zeit
auf den Dwell auf) — sonst vergleicht man am Spielfeld zwei Variablen statt einer. Der
Helligkeitsunterschied von 0,5 Prozentpunkten ist unsichtbar.

`SETTLE_CYCLES` (Default 497 ≈ 10 µs) ist der Feintuning-Hebel: glimmt die Nachbarlampe trotz
DIP 5 = OFF weiter, ist die PNP-Speicherzeit länger als angenommen → 1250 (25 µs), dann 2500
(50 µs), `DWELL_CYCLES` jeweils um denselben Betrag senken. Bleibt es auch bei 50 µs, ist die
Spalten-Abschaltzeit nicht die Ursache und §3.3 muss zurück auf den Tisch.

**Abnahme am Spielfeld:** DIP 5 = OFF, Lampe 22 setzen → LED 21 darf nicht mehr deutlich glimmen;
DIP 5 = ON (im Spiel, ohne Neustart) → es muss zurückkommen. Das ist der A/B-Test, der die Diagnose
beweist und gleichzeitig den Schalter prüft.

**Was bleiben darf:** bei (b) muss das Glimmen verschwinden. Bei (a) entfernen wir nur **unseren**
Beitrag; was von der **Kollektor-Restströmung** der ULN/MC1413 kommt, kann keine Software abstellen,
und die hat das Original genauso. Wenn 9, 15, 21, 57 also weiter ganz schwach glimmen, ist das kein
offener Punkt, sondern das Ergebnis: was übrig bleibt, ist exakt das, was die Original-MPU auch
zeigt. Ein Pulldown an den 595-Ausgängen bei einer künftigen Platinenrevision wird durch (a)
**überflüssig** — nur der Reset-Zustand ist noch Hi-Z, und da sind die Lampen ohnehin aus.

**Messtechnisch nachprüfbar** mit `DBG_MODE = 5` (§6.3): Kanal 3 ist jetzt das echte Austastfenster
(nicht mehr `oe_n`, das im Betrieb dauerhaft `'0'` ist), und je Phase sind **zwei** `rck`-Pulse zu
sehen. Der Abstand zwischen der `strobe_sel`-Flanke und dem Ende des Austastfensters ist die
gesuchte Totzeit: ~20 µs bei DIP 5 = OFF, ~20 ns bei DIP 5 = ON.

## 5. Überholt: der ursprüngliche Entwurf `PREGLOW_CYCLES`

Geplant war, das Artefakt **künstlich nachzubilden** — ein Generic `PREGLOW_CYCLES`, das ein Fenster
„neue Spalte, alte Zeilen, Ausgänge live" einfügt, um §3.3 zu beweisen. Das ist erledigt: das
Artefakt war ohnehin da (§3.3), es musste nicht erzeugt, sondern erklärt und abgeschaltet werden.
Den Gegenschalter macht jetzt **DIP 5**, und der ist besser als ein Synthese-Generic — er erlaubt den
A/B-Vergleich am Spielfeld ohne Neustart.

Der damalige Hinweis bleibt gültig und ist der Grund, warum (a) nicht einfach „`oe_n` weglassen"
heißt: das Original schreibt seine Zeilen-Latches **parallel** (vier DMA-Schreibzyklen), die AtariFA
schiebt 24 Bit **seriell** durch die 595er. Ohne Blank liefen alle 24 Zwischenzustände sichtbar über
die Matrix — ein viel gröberes Artefakt als das Original. Deshalb blankt SW 0.1.6 weiter, nur eben
aktiv statt hochohmig.

## 6. Querverweise

- [`Lamp_Refresh_Analysis.md`](Lamp_Refresh_Analysis.md) — §3.2/§3.3 (Mechanismus), §6.5 (offene
  Punkte), §6.7 (Blanking-Messung), §6.3 (LA-Prozedur, `DBG_MODE 4/5`)
- [`Lamp_Strobes_Manual.png`](Lamp_Strobes_Manual.png) — die Handbuchstelle
- `rtl/common/lamp_matrix.vhd` (Scan-FSM, `SETTLE_CYCLES`), `rtl/common/lamp_map_pkg.vhd`
  (`GRP_OF`, Nummerierung)
- [`FA_Control_Interface.md`](FA_Control_Interface.md) — Einzellampen über die Weboberfläche setzen
- Bedienungsanleitung Kapitel 4.2.4 — Options-DIP 5 aus Anwendersicht
