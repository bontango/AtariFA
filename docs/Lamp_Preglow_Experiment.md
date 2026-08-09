# Vorglühen („pre-glow"): Beobachtung am Flipper und mögliches Gegenexperiment

> **Stand 2026-08-09.** Vorgehensvorschlag, noch nichts davon umgesetzt. Gehört zu
> [`Lamp_Refresh_Analysis.md`](Lamp_Refresh_Analysis.md) — dort steht die Analyse, hier steht,
> wie man den letzten offenen Punkt (§6.5) am echten Automaten schließt.

## 1. Worum es geht

Das Handbuch (*Atari Pinball Troubleshooting Guide*, Abschnitt „Lamp Strobes") beschreibt, dass
Lampen im Aus-Zustand schwach pulsen, und verkauft das als absichtliche „keep-alive routine".
`Lamp_Refresh_Analysis.md` zeigt: die **Beobachtung** stimmt, die **Erklärung** nicht.

| | Stand |
|---|---|
| Software-Ursache | **ausgeschlossen** (LA-Messung 2026-08-09: kein einziger Lampen-RAM-Schreibzugriff in 25,7 s im Spiel; §6.6) |
| Aux-Board-Schaltung | **ausgeschlossen** (1-aus-4-Dekoder ohne Enable, kennt nur Spalten; §3.2) |
| Ursache = Zeilen-Latches werden bei stehender Spalte nachgeladen | **hergeleitet, nicht gemessen** (§3.3) — der offene Punkt |
| AtariFA zeigt das Artefakt | **nein**, blankt sauber (0 Verletzungen in 38 503 Phasen, §6.7) |

Auf der AtariFA gibt es also nichts abzuschalten. Der lohnende Schalter ist der **umgekehrte**:
das Artefakt gezielt wieder herstellen und sehen, ob das Glimmen am echten Spielfeld zurückkommt.
Dann ist §3.3 positiv bewiesen statt nur plausibel.

**Vorher will Ralf das Vorglühen aber noch einmal am Flipper genau beobachten** (geplant
2026-08-10) — Schritt 1. Schritt 2 lohnt nur, wenn Schritt 1 etwas Belastbares zeigt.

## 2. Schritt 1 — Beobachten, ohne irgendetwas zu ändern

Kein Build, kein Eingriff. Ziel ist eine Aussage darüber, **welche** Lampen glimmen — daran hängt
die ganze Beweisführung.

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
4. Mit **AtariFA** im selben Spielfeld gegenprüfen: Erwartung ist „nichts glimmt". Das ist die
   eigentliche Gegenprobe und schon für sich ein Ergebnis.
5. Wenn möglich Handyvideo mit kurzer Belichtung / hoher ISO — auf dem Standbild sieht man
   schwaches Glimmen oft besser als mit dem Auge, und es ist dokumentierbar.
6. Notieren, **welche** Lampennummern (nicht nur „eine Lampe hinten links") — sonst lässt sich
   die Viererblock-Vorhersage hinterher nicht prüfen.

**Bequemer Sonderfall mit FA-Control:** über die Weboberfläche lässt sich eine **einzelne** Lampe
setzen. Damit ist der Test isoliert durchführbar — eine Lampe an, die drei Gruppen-Nachbarn
beobachten. Auf der AtariFA muss dabei (Erwartung) nichts glimmen; wird Schritt 2 gebaut, ist das
derselbe Aufbau mit und ohne Artefakt.

**Ergebnis-Interpretation:**

| Beobachtung am Original | Bedeutung |
|---|---|
| Nur die Viererblock-Nachbarn leuchtender Lampen glimmen | §3.3 bestätigt (Zeilen/Spalten-Versatz) |
| Alle Aus-Lampen glimmen gleichmäßig, unabhängig von den Nachbarn | eher Treiber-/Leckstrom; §3.3 als Hauptursache streichen |
| Gar nichts glimmt (auch mit LEDs) | Handbuch-Aussage betraf einen Zustand, den wir noch nicht haben — dann erst recht kein Grund, an der AtariFA etwas zu bauen |

## 3. Schritt 2 — Gegenexperiment `PREGLOW_CYCLES` (nur bei Bedarf)

**Nicht** einfach `oe_n` weglassen. Das Original schreibt seine Zeilen-Latches parallel
(vier DMA-Schreibzyklen), die AtariFA schiebt 24 Bit seriell durch die 595er — ohne Blank liefen
alle 24 Zwischenzustände sichtbar über die Matrix. Das wäre ein viel gröberes Artefakt als das
Original und würde nichts beweisen.

Originalgetreu ist ein kurzes Fenster **„neue Spalte, alte Zeilen, Ausgänge live"** — genau der
Zustand, den das Original zu Beginn jeder Phase hat.

### Umsetzung in `rtl/common/lamp_matrix.vhd`

```vhdl
generic (
    DWELL_CYCLES   : integer := 12500;
    SHIFT_DIV      : integer := 10;
    PREGLOW_CYCLES : integer := 0    -- 0 = aus (Serienstand); >0 = Original-Artefakt nachbilden
);
```

FSM (heute `… St_Dwell → St_Load`) bekommt einen Zustand dazwischen:

```
St_Dwell (abgelaufen):
    if PREGLOW_CYCLES > 0:
        phase      <= naechste Phase
        strobe_sel <= STROBE_ENC(naechste Phase)   -- Spalte schon umschalten
        oe_n bleibt '0'                            -- Ausgaenge LIVE, 595 halten die ALTE Phase
        -> St_Preglow  (PREGLOW_CYCLES abzaehlen)
    else:
        wie bisher: oe_n <= '1', phase weiter, -> St_Load

St_Preglow (Zaehler abgelaufen):
    oe_n <= '1'   -- ab hier exakt der heutige Ablauf
    -> St_Load
```

Achtung beim Einbau: `phase` wird heute in `St_Dwell` weitergezählt und in `St_Load`/`St_Latch`
benutzt. Im Preglow-Zweig muss `strobe_sel` **vor** dem Nachladen der 595 auf die neue Phase
gehen, `St_Latch` setzt es danach ohnehin auf denselben Wert — es darf also kein zweiter
Strobe-Wechsel entstehen.

**Fensterbreite:** 20 ns je Zyklus. Das Original hat ~4 µs Versatz auf 512 µs Phase (≈0,8 %);
bei 260 µs Phasendauer auf der AtariFA entspricht das **`PREGLOW_CYCLES = 100`** (2 µs ≈ 0,8 %).
`200` (4 µs) macht denselben absoluten Versatz wie das Original — beides ausprobieren.

### Abnahme

- `scripts\check.ps1 -Fit` gegen `scripts/baseline.csv` **mit Default 0**. Erwartung: unverändert
  (der Zustand ist bei statisch 0 unerreichbar und sollte wegoptimiert werden). Falls doch eine
  Differenz: wie bei `St_ShiftLast` (+1 Reg, +6 Comb, 2026-08-09) die Baseline mit Notiz nachziehen.
- Gegenprobe am Logikanalysator mit `DBG_MODE = 5` (§6.7): mit `PREGLOW_CYCLES = 100` müssen dort
  genau **so viele Strobe-Wechsel bei `oe_n = 0`** auftauchen wie Phasen — heute sind es 0. Das ist
  die messtechnische Bestätigung, dass das Fenster wirklich existiert und wie breit es ist.
- Am Spielfeld: Erwartung = die drei Viererblock-Nachbarn jeder leuchtenden Lampe glimmen,
  komplett dunkle Blöcke nicht. Trifft das zu, ist §3.3 bewiesen.
- Danach `PREGLOW_CYCLES` auf 0 zurück; das Generic bleibt als Diagnose-Schalter im Code
  (Verdrahtung in `AtariFA.vhd` analog `DBG_MODE`), der Serienstand ändert sich nicht.

## 4. Querverweise

- [`Lamp_Refresh_Analysis.md`](Lamp_Refresh_Analysis.md) — §3.2/§3.3 (Mechanismus), §6.5 (offene
  Punkte), §6.7 (Blanking-Messung), §6.3 (LA-Prozedur, `DBG_MODE 4/5`)
- [`Lamp_Strobes_Manual.png`](Lamp_Strobes_Manual.png) — die Handbuchstelle
- `rtl/common/lamp_matrix.vhd` (Scan-FSM), `rtl/common/lamp_map_pkg.vhd` (`GRP_OF`, Nummerierung)
- [`FA_Control_Interface.md`](FA_Control_Interface.md) — Einzellampen über die Weboberfläche setzen
