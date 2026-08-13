# Vorglühen („pre-glow"): Beobachtung am Flipper und Gegenexperiment

> **Stand 2026-08-13.** Schritt 1 ist gefahren — das **Ergebnis steht in §3**, und es hat die Sache
> entschieden: das Artefakt ist da, es ist reproduzierbar, und es entstand auf der AtariFA aus einer
> Ursache, die in `Lamp_Refresh_Analysis.md` §3.3 nur als Möglichkeit benannt war. Was daraus gebaut
> wurde, steht in §4; der ursprünglich geplante Kunstgriff `PREGLOW_CYCLES` ist damit überholt (§5).
> **Neu: §6** — die Feldrückmeldung zu SW 0.1.7 von zwei Maschinen. Der Fix wirkt, **eine** Lampe
> bleibt offen (Lampe 21 / A20, auf Airborne *und* Middle Earth dieselbe Nummer); dort steht der
> Messplan dazu. Gehört zu [`Lamp_Refresh_Analysis.md`](Lamp_Refresh_Analysis.md) — dort steht die
> Analyse.

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
| Fix aus §4 wirkt am Spielfeld | **ja**, zwei Maschinen, SW 0.1.7 (§6.1): DIP 5 = OFF sauber, DIP 5 = ON bringt es zurück |
| Längere Totzeit behebt das Glimmen | **ja** — Middle Earth mit 0.1.7 **behoben** (§6.1). Damit ist der Mechanismus aus §3.3 auch durch die Gegenmaßnahme bestätigt |
| Restfall Airborne, Lampe 21 / A20 | **offen**, aber eingekreist: Datenpfad am Bauteil **freigemessen** (§6.3.1). **Vorher zu klären: lief dort wirklich 0.1.7?** (Kasten in §6.1) |

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

| | DIP 5 = OFF (Serienstand) | DIP 5 = ON | DIP 6 = ON (Reserve, seit 0.1.7) |
|---|---|---|---|
| `strobe_sel` wechselt | beim **Clear**-Latch, Zeilen sind aus | beim **Daten**-Latch, gleichzeitig mit den Zeilen | wie DIP 5 = OFF |
| Totzeit Spalte → Zeilen scharf | `St_Settle` + Datendurchlauf ≈ **60 µs** (0.1.6: 20 µs) | ~20 ns (Original-Zeitverhalten) | ≈ **110 µs** in 0.1.7, ≈ **400 µs** in 0.1.8 |
| Vorglühen bei LED-Retrofits | weg | da | weg |
| Phasendauer | 512,0 µs | 512,0 µs | 512,0 µs |
| Duty | 22,1 % | 24,5 % | 19,6 % (0.1.7) / **5,0 %** (0.1.8) |

**DIP 5 sticht DIP 6** (im Original-Modus gibt es keine Totzeit, die DIP 6 verlängern könnte).

Die Phasendauer ist in allen Stellungen gleich (was die Totzeit nicht braucht, schlägt auf den Dwell
auf) — sonst vergleicht man am Spielfeld zwei Variablen statt einer. Der Helligkeitsunterschied von
2,4 Prozentpunkten zwischen Serienstand und DIP 5 = ON ist am Spielfeld nicht zu sehen; die
0.1.7-Feldrückmeldung bestätigt das ausdrücklich („Wer es nicht weiss merkte nicht").

`SETTLE_CYCLES` / `SETTLE_LONG_CYCLES` (0.1.7: 2500 ≈ 60 µs bzw. 5000 ≈ 110 µs; 0.1.6: 497 ≈ 10 µs)
sind der Feintuning-Hebel. **Achtung bei der Auswertung** — die frühere Formulierung „bleibt es auch
bei 50 µs, ist die Spalten-Abschaltzeit nicht die Ursache" war zu scharf: Einschalten zieht ~0,2 A in
die Basis, Ausschalten räumt sie über 8,2 K mit ~85 µA aus, die Speicherzeit kann also Hunderte von
Mikrosekunden erreichen (Rechnung in [`Lamp_Refresh_Analysis.md`](Lamp_Refresh_Analysis.md) §3.3).
„110 µs ändern nichts" heißt daher **noch nicht** „die Spalte ist unschuldig". Genau darum ist
**SW 0.1.8** gebaut: dort steht `SETTLE_LONG_CYCLES` auf **20000** (≈400 µs, Duty ~5 %, sichtbar
dunkler — Messfassung, kein Serienstand), und DIP 6 = ON entscheidet die Frage am Spielfeld. Den
Aufschlag fängt der Dwell selbst auf, solange `SETTLE_LONG_CYCLES` unter
`DWELL_CYCLES + SETTLE_CYCLES` = 24597 bleibt (bei 20000 bleiben 4597 clk = 92 µs Dwell). Erst wenn
auch 400 µs nichts ändern, muss §3.3 zurück auf den Tisch.

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

## 6. Feldrückmeldung SW 0.1.7 (08.2026) — Middle Earth behoben, Airborne noch offen

### 6.1 Was gemeldet wurde

Airborne Avenger, SW 0.1.7, Wortlaut des Testers:

> Dip5 ON => Vorglühen/Flackern ist da · Dip5 OFF => bis auf Lampe 21 gelesen OK · Dip 6 ON => kein
> Unterschied · Helligkeitsunterschied ist minimal. Wer es nicht weiss merkte nicht. · Bei mir glimmt
> Lampe 21 (LED) immer noch. Egal ob Spiel oder Test oder wenn alle Lampen aus sind im Testmode…

Das **Middle Earth** hatte **dieselbe Gruppe** gemeldet — allerdings **auf dem Stand 0.1.6**
(Rückmeldung 2026-08-12, die zu 0.1.7 geführt hat): FA-Control-**Nummer 22** = A20 Ausgang Pin 14 =
J1-D = „LAMP 32-B0-SC", also Gruppe 6, Strobe 2 — Nachbarnummer von 21, **gleiche 595-Gruppe,
gleicher Treiber-IC**. Der ME-Nutzer hat zusätzlich am ULN-*Eingang* gemessen: **2,3 V aus / 3,4 V
an** — das ist der Multiplex-Mittelwert der Gruppenleitung (2 bzw. 3 von 4 Phasen High), d. h. an
dieser Gruppe brennen dauernd Lampen.

**Und mit 0.1.7 ist das Middle Earth behoben** (Rückmeldung 2026-08-13, Wortlaut):

> I loaded 017 software and the lighting issue is fixed. The lights all work as they should, that
> extra timing delay to make up for my original auxiliary board seems to have worked.

Das ist der Beweis, auf den §3.3 gewartet hat: **die verlängerte Totzeit behebt das Glimmen an einer
echten Maschine.** Der Mechanismus ist damit nicht mehr nur gemessen (§3.3), sondern durch die
Gegenmaßnahme bestätigt — und der Hebel ist der richtige. *Offen dabei: stand DIP 6 auf ON oder OFF?*
Davon hängt ab, ob die **60 µs** des Serienstands genügen oder erst die **110 µs** von DIP 6 — und
damit, welcher Wert Serienstand wird. Nachfragen.

> **⚠ Zu prüfen beim Airborne-Tester: lief dort wirklich 0.1.7?** Sein Bericht liest sich Zeile für
> Zeile wie **0.1.6**-Verhalten, denn dort ist Options-DIP 6 **gar nicht implementiert** („reserviert")
> — „Dip 6 ON => kein Unterschied" ist auf 0.1.6 also der *erwartete* Befund, während dieselbe Aussage
> auf 0.1.7 bedeutet, dass 110 µs nicht reichen. Nichts in seinem Text ist 0.1.7-spezifisch, beide
> Lesarten passen, und die Auswertung hängt genau daran. Prüfen kann er es in zehn Sekunden: die
> **Info-Anzeige** beim Einschalten (Display 1, letzte Ziffer = `7`) und die **Versionsmeldung von
> FA-Control** beim Verbinden. Bis das geklärt ist, ist die Aussage „110 µs ändern am Airborne nichts"
> **nicht belastbar**, und damit auch nicht die Notwendigkeit von 0.1.8.

Damit ist bestätigt: (a) der A/B-Schalter DIP 5 arbeitet und reproduziert das Artefakt auf Kommando —
die Diagnose aus §3.3 ist am zweiten Spielfeld
bestanden; (b) das Grundglimmen aus §3.4 ist an den früher betroffenen Lampen 9, 15, 57 weg, Fix (a)
wirkt; (c) der Duty-Verlust von 2,4 Prozentpunkten ist unsichtbar; (d) DIP 6 ändert nichts — was nach
`Lamp_Refresh_Analysis.md` §3.3 **noch keine** Entlastung der Spalte ist, s. §4.

### 6.2 Wo Lampe 21 sitzt — und was das ausschließt

Lampe 21 (FA-Control, 0-basiert) → Gruppe `21 div 4 + 1` = **6**, Strobe `21 mod 4` = **1**.
`GRP_OF` (`rtl/common/lamp_map_pkg.vhd`): Gruppe 6 = (Latch 0x1000, Bit 0) ⇒ `lamp_state`-Bit
`(0*4+1)*8+0` = **Bit 8 = RAM 0x31 Bit 0**. Im Original-Schaltplan
([`Lamp_Logic.png`](Lamp_Logic.png), Sheet 18D) ist das das Netz **„LAMP 31-B0-SB" = A20 Ausgang
Pin 15, J1-C**. A20 Pin 1–4 hängen alle am *selben* Netz: Gruppe 6 = Lampen 20/21/22/23 =
RAM 0x30…0x33 Bit 0 (Ausgänge 16/15/14/13). A20 Pin 5–7 = Gruppe 7 = Lampen 24/25/26, davon 24/25 in
Airborne „NOT USED".

Damit ist die naheliegende Vermutung „die Routine, die die Latch-Adressen scannt" als Erklärung für
ein **dauerndes Glimmen bei Datenwort 0** ausgeschlossen, aus drei unabhängigen Gründen:

1. Bei `lamp_state` = 0 latchen **beide** Durchläufe Nullen und `oe_n` liegt fest auf `'0'` — die
   595-Ausgänge stehen 100 % der Zeit aktiv auf 0 V. Es gibt kein Hi-Z-Fenster mehr und keine
   Schiebereihenfolge, die aus 24 Nullen Strom machen könnte.
2. Ein Mapping-Fehler wäre **global**: `GRP_OF`, `STROBE_ENC` und die Zerlegung `offset[3:2]`=Latch /
   `offset[1:0]`=Strobe gelten für alle 84 Lampen. Er würde Vierer- oder Gruppenblöcke verschieben und
   sich als *falsche Lampe hell* zeigen — nie als Glimmen genau einer Lampe. 83 von 84 stimmen.
3. Der Sniffer kann keine Phantom-Pulse erzeugen: `ram_wren` ist ein Ein-Takt-Puls auf der fallenden
   `cpu_clk`-Flanke (`top/AtariFA.vhd`), Adresse und Daten sind dabei stabil, die Übernahme erfolgt
   genau einmal je CPU-Write. Dazu die Messung in
   [`Lamp_Refresh_Analysis.md`](Lamp_Refresh_Analysis.md) §6.6: **0 Lampen-RAM-Writes in 25,7 s im
   Spiel**, und §2.4: beide gelesenen ROMs schalten Lampen als einzelnes Read-Modify-Write, nicht
   periodisch.

**Warum beide Maschinen dieselbe Gruppe gezeigt haben — und das ist die Leithypothese:** Gruppe 6
ist die **Bonus-Gruppe**, dort brennen im Spiel wie im Attract dauernd Lampen (vom ME-Nutzer am
ULN-Eingang gemessen, s. §6.1: 2 von 4 Phasen High). Genau das braucht das Artefakt aus §3.3: ein
**dauerhaft leuchtender Gruppen-Nachbar**, dessen Zeilenmuster die gerade abgeschaltete, noch
leitende Spalte sieht. Damit ist das Glimmen an Gruppe 6 nicht Streuung, sondern der einzige Ort im
Spielfeld, an dem die Voraussetzung *permanent* erfüllt ist — auf jeder Maschine, in jedem Spiel, und
je nach lit-Muster an Nummer 21 oder 22. A20 ist also nicht elektrisch besonders, sondern
**statistisch**. Genau diese Gruppe ist am Middle Earth mit 0.1.7 verschwunden (§6.1) — die Erklärung
trägt also. Bleibt sie am Airborne bestehen, heißt das nach `Lamp_Refresh_Analysis.md` §3.3 entweder
„110 µs sind dort zu wenig" **oder** es lief nicht 0.1.7 (Kasten in §6.1) — und diese Reihenfolge
ist einzuhalten: erst die Version klären, dann die Totzeit weiter hochdrehen.

**Zu klären bleibt genau eine Lesart des Berichts**, und sie trennt die beiden Restursachen:

- **(A)** Der Nachbar leuchtet weiter, wenn der Tester „alle Lampen aus" sagt — im **Spiel-Selbsttest**
  ist das gut möglich, der garantiert nichts. Dann ist es §3.3, und der Hebel ist die Totzeit.
  ⇒ **Nach der Schreibtischmessung (§6.3.1) der Hauptverdächtige**, weil der Datenpfad am Bauteil
  freigemessen ist und der Schreibtisch (schnelle MOSFET-Spalten) das Artefakt nicht zeigt.
- **(B)** Auch bei **FA-Control-Übernahme mit allen Lampen auf 0** (CPU angehalten, `lamp_state_mux`
  beweisbar 0) glimmt 21 weiter. Dann kann es §3.3 nicht sein, und übrig bleibt der analoge Reststrom
  (ULN-Kollektor-Restströmung, §4 „was bleiben darf") — der ist eine **Typeigenschaft, kein Defekt**,
  also auf jeder Platine da und nur an LEDs sichtbar, aber softwareseitig nicht abstellbar.
  ⇒ Am Schreibtisch bei 5 V **0,0 µA** gemessen (§6.3.1); für die ~20 V am Spielfeld damit nicht
  ausgeschlossen, aber unwahrscheinlicher geworden.

Deshalb ist der FA-Control-Nullzustand die erste Frage an den Tester (§6.4) und Fall 2 der
Schreibtischmessung (§6.3) — „alles aus" muss *bewiesen* aus sein, nicht *geglaubt* aus.

Nebenbei: „zwei Maschinen ⇒ kein Hardwareproblem" trägt als Schluss ohnehin nicht — der ICEX ist auf
jeder Platine gleich. Nur erklärt er die *Gruppe* nicht, und die Bonus-Gruppe erklärt sie.

### 6.3 Schreibtischmessung (LA + DMM, ohne Spielfeld) — gefahren 2026-08-13, Ergebnis in §6.3.1

Diagnosebuild: `DBG_MODE := 5`, `DBG_WATCH_LAMP := 21` in `top/AtariFA.vhd`, dann
`scripts\build.ps1 cyclone_10_pcb` (nur diese Variante routet alle 8 Debug-Pins,
`Lamp_Refresh_Analysis.md` §6.1). **Wichtig: `DBG_MODE` vor dem Commit auf `0` zurück** und
`scripts\check.ps1 -Fit` gegen `scripts/baseline.csv` fahren.

Tastköpfe: `debug_signal` 0…6 = `ser`/`srck`/`rck`/`blank`/`strobe_sel(0)`/`strobe_sel(1)`/
`watch_drive` (Pins in §6.1 dort); **zusätzlich extern A20 Pin 2** (= Gruppen-Netz) **und A20 Pin 15**
(= Rückleitung), Trigger auf `rclk_595` (PIN_42).

| Fall | Vorgehen | Erwartung / Bedeutung |
|---|---|---|
| 1 | FA-Control: **nur Lampe 21** setzen | Test-LED 21 hell, A20 Pin 2 genau im SB-Fenster high. Falsche Phase ⇒ `STROBE_ENC`/offset-Zerlegung (dann mit 20/22/23 gegenprüfen — es wären alle betroffen). LED bleibt dunkel/glimmt nur ⇒ Fall (B) |
| 2 | FA-Control: **alle Lampen 0**, Oszi DC 50 mV/div über Minuten auf A20 Pin 2 | < 50 mV, keine Pulse. Jeder Puls ⇒ Datenpfad: dann `DBG_MODE := 4` mit `DBG_WATCH_LAMP := 21` und Kanal 3 (`watch_state`) / Kanal 2 (`lamp_wr_set`) nach §6.3/§6.4 dort auswerten |
| 3 | alles aus: **Strom** durch Test-LED 21 messen (µA-DMM in Reihe, oder 1 kΩ einschleifen und Spannung messen) | Die Zahl entscheidet. µA ⇒ ICEX, kein SW-Fix, und der Messwert liefert direkt den Shunt. mA ⇒ echter Pfad. Vergleich mit 2–3 anderen A20-Kanälen und einem Kanal eines anderen ULN |
| 4 | dunkler Raum, alles aus | Glimmt LED 21 am Schreibtisch überhaupt? Gegenprobe zu §3.1, dort war der Effekt „nicht nachstellbar" — aber nicht gezielt an Lampe 21 gesucht |

Fall 2/3 laufen bewusst **unter FA-Control**: die CPU steht, `lamp_state_mux` kommt aus
`fa_lamp_state` und ist beweisbar 0 — der saubere Nullzustand, den der Spiel-Selbsttest nicht
garantiert.

**Ohne Oszilloskop geht das genauso** (so ist es gefahren worden): der Multiplex-Mittelwert am
Gruppen-Netz ist genau das, was ein DMM anzeigt, und beide Instrumente greifen komplementär —
**das DMM begrenzt die Energie** (Duty = U/4,6 V, daraus die Pulsbreite je 2,048-ms-Frame), **der LA
begrenzt die Breite** (Tastkopf auf A20 Pin 1, Trigger auf steigende Flanke, 1 MHz, Minuten laufen
lassen: triggert er nicht, ist alles ≥ 1 µs ausgeschlossen — und weniger als 1 µs kann keine LED
sichtbar machen). Umrechnungstabelle: 10 mV ≙ 0,22 % ≙ ~4,5 µs/Frame · 25 mV ≙ 11 µs · 50 mV ≙ 22 µs ·
1,0 V ≙ 22,1 % = eine ganze Phase (Lampe an).

#### 6.3.1 Ergebnis (2026-08-13, cyclone_10_pcb, `.sof` per JTAG, Info-Anzeige `017`)

| Prüfung | Messwert | Bedeutung |
|---|---|---|
| Zeitraster (LA) | Phase **512 µs**, Austastfenster **≈ 60 µs**, DIP-5-Sprung des `strobe_sel`-Wechsels vom Blank- auf den Daten-Latch **sichtbar** | 0.1.7-Zeitverhalten an den Pins bestätigt, Schalter greift im Betrieb |
| Fall 1, nur Lampe 21 | Test-LED **hell**; A20 Pin 1 = **1,0 V** DC | Vorhersage für 22,1 % Duty war 1,0 V ⇒ Gruppen-Netz wird korrekt in **einer von vier** Phasen getrieben. **Fall (B) ist damit erledigt** |
| Fall 2, alles aus | A20 Pin 1 = **0,2 mV** (Null-Referenz 0,0 mV); LA triggert über Minuten **nicht** | Duty ≤ **0,004 %** = höchstens ~90 ns/Frame (1/23000 der Einschalthelligkeit, unsichtbar; realistisch DMM-Offset), und alles ≥ 1 µs ausgeschlossen |
| Fall 3, Reststrom | **0,0 µA** in der Rückleitung von Lampe 21 (und an den Vergleichskanälen) | am Box-Connector, also bei **5 V** Spaltenspannung — Untergrenze, s. Einschränkung unten |
| Fall 4, dunkler Raum | **kein Glimmen** | reproduziert §3.5: am Schreibtisch ist der Effekt nicht nachstellbar |

**Was damit erledigt ist:** der Datenpfad, und zwar gemessen statt argumentiert — am **Bauteil**, nicht
am FPGA-Pin (das war die Lehre aus §3.3). Ein Scan-, Mapping- oder Sniffer-Fehler kann das Glimmen
nicht erzeugen: bei „alles aus" liegt das Gruppen-Netz hart auf 0 V, und die Gegenprobe an derselben
Messstelle zeigt 1,0 V, sobald die Lampe gesetzt ist — die Messung ist also nicht taub.

**Was der Schreibtisch NICHT klären kann, und warum das Ergebnis trotzdem etwas sagt:** die Testspalten
der Box-Connectors kommen von vier P-Kanal-MOSFETs bei **5 V** (§3.5), das Spielfeld von den 2N5883 bei
~**20 V**. Der Kollektor-Reststrom wächst mit Spannung und Temperatur, 0,0 µA bei 5 V ist also nur eine
Untergrenze für den Spielfeldfall. Aber: **derselbe ULN-Typ, dieselbe Logik, dieselbe Lampe — und hier
glimmt nichts.** Der Unterschied zwischen Schreibtisch und Spielfeld ist genau die Spalten-Domäne. Per
Ausschluss bleibt damit der Spalten-Nachlauf (§3.3) als Hauptverdächtiger, und **das entscheidet
SW 0.1.8 am Spielfeld** (§4, §6.5) — nicht mehr der Schreibtisch.

**Grenze des Aufbaus, sonst wird das Ergebnis falsch gelesen:** am Schreibtisch kommen die Spalten
von den vier P-Kanal-MOSFETs der Box-Connectors (§3.5, ns-schnell, nA-Leckstrom), **nicht** von den
2N5883 des Aux-Boards. Der Spalten-Nachlauf aus §3.3 ist hier also prinzipiell nicht reproduzierbar —
„am Schreibtisch nichts gefunden" ist **kein Freispruch**, wohl aber ein vollständiger Test des
Digitalpfads und des ULN-Reststroms.

### 6.4 Fragen und Handgriffe für die Tester (DMM, löten/klemmen)

In dieser Reihenfolge; jede Zeile hat einen eigenen Aussagewert:

0. **Welche Version läuft wirklich?** Info-Anzeige beim Einschalten (Display 1, dritte Ziffer) und die
   Versionsmeldung von FA-Control beim Verbinden. Das steht hier an erster Stelle, weil ein Bericht
   über einen Schalter, den die geladene Version nicht hat, systematisch in die Irre führt — und weil
   es zehn Sekunden kostet. Für das Middle Earth ist zusätzlich nachzufragen, ob **DIP 6 ON oder OFF**
   war, als es behoben war (entscheidet 60 µs gegen 110 µs als künftigen Serienstand).
1. **Der Nullzustand — die wichtigste Frage:** in FA-Control die Kontrolle übernehmen (Options-DIP 4
   = ON, Verbinden, `LISY_INIT`), **alle Lampen auf 0**, damit steht die CPU und keine Lampe kann
   getrieben sein. Glimmt 21 **dann** noch? (entscheidet (A) gegen (B), s. §6.2 — im Spiel-Selbsttest
   ist „alles aus" nicht garantiert)
2. Im selben Zustand: **20 / 22 / 23 einzeln** setzen. Wird das Glimmen von 21 dabei deutlich stärker
   (erwartet vor allem bei 22)? Und: leuchtet 21 selbst hell, wenn man sie einzeln setzt?
   (Nachbar-Komponente aus §3.3; die vier Nummern einer Gruppe sind 20/21/22/23)
3. **LED von 21 mit einer dunklen Fassung tauschen** (z. B. 13): wandert das Glimmen mit der LED oder
   bleibt es an der Fassung? (Leuchtmittel gegen Treiberkanal — steht seit §3.6 offen)
4. **Glühlampe** in Fassung 21 → Glimmen weg? (Erwartung ja, §3.1)
5. **2,2 kΩ / ≥ ½ W parallel zur Fassung 21** → Glimmen weg? Dann ist der Feld-Fix gefunden: 100 µA
   Reststrom erzeugen daran 0,22 V, weit unter der LED-Schwelle; bei eingeschalteter Lampe sind es
   ~37 mW mittlere Verlustleistung (22 % Duty).
6. **µA-DMM in Reihe** in die Rückleitung von 21, alles aus → Zahl; derselbe Messwert an einer
   dunklen Fassung als Vergleich.
7. Dieselben Punkte am **Middle Earth**, plus Bestätigung, dass die „21" dort ebenfalls aus der
   FA-Control-Oberfläche kommt und nicht aus der Handbuch-Nummerierung.

### 6.5 Fixpfade je Ergebnis

- **Schritt 0, vor allem anderen: Version des Airborne-Testers klären** (Kasten in §6.1). Lief dort
  0.1.6, ist sein „DIP 6 ändert nichts" gegenstandslos, und der nächste Schritt ist schlicht
  **0.1.7 mit DIP 6 = ON** — nicht 0.1.8.
- **Nachbar-abhängig / Fall (A)** — nach §6.2 der wahrscheinlichste Ausgang, weil Gruppe 6 die
  Bonus-Gruppe ist, und am Middle Earth mit 0.1.7 bestätigt: **dafür ist SW 0.1.8 gebaut**
  (`SETTLE_LONG_CYCLES = 20000`,
  ≈400 µs auf DIP 6, Duty ~5 %, sichtbar dunkler — s. §4). Das ist der **erste** Schritt, nicht der
  letzte Ausweg: 60/110 µs sind nach der Abschaltzeit-Rechnung möglicherweise einfach zu kurz.
  Abnahme im Feld: 0.1.8 programmieren, Info-Anzeige muss `018` zeigen, dann DIP 6 im laufenden Spiel
  OFF↔ON schalten. Wird das Glimmen mit ON schwächer oder verschwindet es, war es die Spalte — dann
  wird der **kleinste** noch wirksame Wert zum Serienstand für DIP 6 (mit dem Helligkeitsverlust als
  bewusstem Preis), und 0.1.8 bleibt nicht, wie es ist. Ändert sich nichts, ist die Spalte erledigt.
- **Reststrom / Fall (B)** (Glimmen auch im FA-Control-Nullzustand, 5/6 im µA-Bereich): kein RTL-Fix
  möglich und keiner nötig — das ist der in §4 vorab benannte Rest, den auch die Original-MPU hat.
  Empfehlung an den Nutzer: 2,2 kΩ parallel, Glühlampe oder „ghost-free"-LED; gehört dann in **beide**
  Handbücher. Der Shunt hilft übrigens in **beiden** Fällen und ist damit der robusteste Feld-Fix.
- **Digitaler Befund** (Fall 2 zeigt Pulse, oder Fall 1 falsche Phase): Reparatur in `STROBE_ENC` /
  offset-Zerlegung / `GRP_OF` — und dann global, nicht für Lampe 21 allein.
- **Platinenbefund:** vor dem Löten im Feld das Lampen-Blatt unter `N:\Projekte\FPGA Atari\doc\`
  prüfen — (a) liegt **Pin 9 (COM)** der ULN2003A irgendwo an Spannung? Im Original ist COM offen
  (Sheet 18D zeigt nur Pin 8 an Masse); läge COM z. B. auf +5 V, führt die interne Klemmdiode jedes
  Ausgangs Strom von der Lampenspannung nach 5 V — ein Pfad ganz ohne FPGA, auf **jeder** Platine
  gleich, und er passt zur Middle-Earth-Beschreibung „blieb halb an" besser als zu „glimmt".
  (b) Hängen A20 Pin 1–4 wirklich am selben Netz, und ist an Gruppe 6 irgendetwas anders bestückt
  als an den übrigen 20?

## 7. Querverweise

- [`Lamp_Refresh_Analysis.md`](Lamp_Refresh_Analysis.md) — §3.2/§3.3 (Mechanismus **und** die
  Abschaltzeit-Abschätzung, auf die §4/§6 sich stützen), §2.4 (Middle-Earth-ROM), §6.5 (offene
  Punkte), §6.6 (0 Lampen-Writes im Spiel), §6.7 (Blanking-Messung), §6.1/§6.3 (LA-Kanäle und
  -Prozedur, `DBG_MODE 4/5`)
- [`Lamp_Logic.png`](Lamp_Logic.png) — Sheet 18D: welcher Latch-Bit-Netz an welchem ULN2003A hängt
  (Grundlage von §6.2: Gruppe 6 = A20 Pin 1–4)
- [`Lamp_Strobes_Manual.png`](Lamp_Strobes_Manual.png) — die Handbuchstelle
- `rtl/common/lamp_matrix.vhd` (Scan-FSM, `SETTLE_CYCLES`), `rtl/common/lamp_map_pkg.vhd`
  (`GRP_OF`, Nummerierung)
- [`FA_Control_Interface.md`](FA_Control_Interface.md) — Einzellampen über die Weboberfläche setzen
- Bedienungsanleitung Kapitel 4.2.4 — Options-DIP 5 aus Anwendersicht
