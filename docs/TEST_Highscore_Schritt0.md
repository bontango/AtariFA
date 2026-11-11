# Testanweisung Schritt 0 – Messbuild „Läuft ein Spiel?“ (Highscore / letzte Spielstände)

Stand: 10.11.2026 · Variante: **nur `cyclone_10_pcb` (FPGA_board_v4.x)** am Schreibtisch-Prüfstand
mit Schaltermatrix.

## Zweck

Bevor FRAM-Speicherung und Highscore gebaut werden, muss feststehen, ob der FPGA
spielunabhängig erkennt, **ob gerade ein Spiel läuft**. Nur dann dürfen später Spielstände
gespeichert werden (nicht der Segmenttest `888888`, nicht der Selbsttest).

Kriterium im Messbuild: **genau eine Player-up-Lampe an** (4. Byte je Spieler im Display-RAM,
Nibble 8). Der Zustand wird **2 s nachgehalten**, falls die Lampe blinkt.
- alle vier an = Segmenttest
- keine an = Attract

Der Messbuild speichert **noch nichts**. FRAM ist aus, DIP 2 hat noch keine Funktion.

## Datei

`N:\Projekte\FPGA Atari\FPGA_source\variants\cyclone_10_pcb\output_files\AtariFA.jic`
(gebaut 10.11.2026 12:01, 2.097.377 Byte)

## Erkennungsmerkmal

- Die Info-Anzeige beim Boot zeigt weiterhin **034**. Die Version wurde für den Messbuild
  bewusst nicht erhöht.
- **LED D1** zeigt jetzt **„Spiel läuft“** (an = in_game) statt der Watchdog-Meldung.

## Ablauf je Spiel-ROM

Möglichst mit 2–3 Spielen testen. **Middle Earth und Space Riders bevorzugt**, weil dort die
up-Lampe indiziert geschrieben wird und statisch nicht sicher zu beurteilen war. Atarians oder
Time 2000 sind gut als Gegenprobe.

| # | Situation | LED D1 erwartet |
|---|---|---|
| 1 | Einschalten, Boot-Info, Segmenttest `888888` | aus |
| 2 | Attract (nach dem Segmenttest) | aus |
| 3 | Selbsttest (Testschalter) durchklicken, wieder verlassen | aus |
| 4 | Münze, Start: Spiel mit 1 Spieler, Kugel im Spiel | **an**, durchgehend |
| 5 | Outhole → Kugel 2, 3 … (Kugelwechsel, ggf. Bonuszählung) | **an**, durchgehend |
| 6 | Neues Spiel, Spieler 2 hinzufügen, Spielerwechsel | **an**, durchgehend |
| 7 | Tilt während des Spiels | an, bis das Spiel wirklich vorbei ist |
| 8 | Spielende (letzte Kugel im Outhole) | geht **~2 s** nach dem Ende aus |
| 9 | Attract nach dem Spiel (Displays zeigen die letzten Stände) | aus |

**Wichtigste Fehlerbilder:**
- D1 **flackert oder geht aus**, während das Spiel läuft (z. B. beim Spielerwechsel oder
  in der Bonuszählung)
- D1 **geht an** im Attract, im Segmenttest oder im Selbsttest

## Optional: Logic-Analyzer am Debug-Header

| Kanal | Signal |
|---|---|
| 0 | up-Lampe Spieler 1 (RAM $03) |
| 1 | up-Lampe Spieler 2 (RAM $07) |
| 2 | up-Lampe Spieler 3 (RAM $0B) |
| 3 | up-Lampe Spieler 4 (RAM $0F) |
| 4 | „genau eine an“, roh (ohne Nachhalten) |
| 5 | in_game, 2 s nachgehalten (= LED D1) |
| 6 | „alle vier an“ (Segmenttest) |
| 7 | Puls bei jedem Schreibzugriff auf ein up-Byte |

Kanal 7 zeigt, wie oft das Spiel die up-Bytes schreibt. Ein Blinken der Lampe ist damit
direkt sichtbar. Wenn Kanal 4 im Spiel Lücken hat, ist interessant, wie lang sie werden:
Das Nachhalten beträgt 2 s.

## Ergebnisse (bitte ausfüllen)

| Situation | Atarians | Time 2000 | Airborne | Middle Earth | Space Riders |
|---|---|---|---|---|---|
| 1 Boot / Segmenttest | | | | | |
| 2 Attract | | | | | |
| 3 Selbsttest | | | | | |
| 4 Spiel 1 Spieler | | | | | |
| 5 Kugelwechsel / Bonus | | | | | |
| 6 2 Spieler / Wechsel | | | | | |
| 7 Tilt | | | | | |
| 8 Spielende (~2 s) | | | | | |
| 9 Attract danach | | | | | |

Bemerkungen:

**10.11.2026, Einschalten bis Attract (Schritte 1–2):**

| Spiel | Player-up-Lampen nach dem Einschalten | D1 |
|---|---|---|
| Atarians | alle aus | aus ✓ |
| Time 2000 | schnelles Lauflicht, einer nach dem anderen | **an ✗** |
| Airborne Avenger | alle an, dann 1–4 einzeln aus, dann Lauflicht | **an ✗** |
| Middle Earth | alle an | aus ✓ |
| Space Riders | wie Airborne | **an ✗** |

Befund: Das Lauflicht im Attract erfüllt „genau eine an“ in jedem Moment, und das 2-s-Nachhalten
überbrückt die Wechsel. Das Kriterium in dieser Form reicht nicht.

**10.11.2026, Atarians und Middle Earth, alle Schritte 1–9:** D1 in allen Testfällen wie
erwartet. Atarians reagiert nicht auf den Testschalter; das Spiel hat keinen Selbsttest
(bekannt seit B13, kein Defekt).

## Messbuild 2 (10.11.2026): dieselbe Lampe muss stehen

Neues Kriterium in `in_game_hold` (`top/AtariFA.vhd`):

- `in_game` geht erst an, wenn **dieselbe** up-Lampe allein insgesamt **2 s** geleuchtet hat.
  Dunkelphasen beim Blinken halten den Zähler an, setzen ihn aber nicht zurück. Im Lauflicht
  wechselt die Lampe schneller, deshalb wird die Schwelle dort nie erreicht.
- Läuft das Spiel schon, triggert die leuchtende Lampe das Nachhalten sofort nach.
- Spielerwechsel: Ein Wechsel auf einen anderen Spieler hält `in_game` nur, wenn die alte Lampe
  zuvor stabil war.
- Zurückgesetzt wird die Stabilität, wenn länger als 2 s keine Lampe leuchtet oder wenn
  2–4 Lampen gleichzeitig an sind (Segmenttest, Abschaltfolge bei Airborne/Space Riders).
- Folge: D1 geht im Spiel erst **~2 s nach dem Start** an. Das ist für das Speichern am
  Spielende ohne Bedeutung.

Datei: `variants\cyclone_10_pcb\output_files\AtariFA.jic` (gebaut 10.11.2026 17:53,
2.097.377 Byte). Boot-Info weiterhin **034**, D1 = „Spiel läuft“, LA-Belegung unverändert.

Test wie oben, Schwerpunkt **Time 2000, Airborne, Space Riders** (Attract muss jetzt aus
bleiben). Atarians und Middle Earth als Gegenprobe, ob sich am Spielverhalten nichts geändert hat.
Besonders auf das Spielende achten: D1 muss ausgehen, auch wenn danach das Lauflicht startet.

**Ergebnis 10.11.2026: alle fünf Spiele getestet, D1 in allen Testfällen OK.** Die Erkennung
„Spiel läuft“ über die Player-up-Lampen (Messbuild 2) ist damit für Schritt 1 (FRAM) freigegeben.

**Nachtrag 10.11.2026, Space Riders:** Nach dem Spielende wechseln die Player-up-Lampen schnell
(Lauflicht), die Displays zeigen die letzten Stände statt `888888`, und **D1 ging nicht aus**.
Ursache: Die Regel „läuft das Spiel schon, triggert dieselbe Lampe sofort nach“ frischte
das Nachhalten mit jeder Lampe des Lauflichts wieder auf. Behoben in SW 0.4.0 mit dem Flag
`up_trust`: Nur ein akzeptierter Spielerwechsel (alte Lampe stabil) oder eine selbst stabile
Lampe darf nachtriggern; jeder andere Wechsel entzieht das Vertrauen. Test in Schritt 1.

## Wie es danach weitergeht

- **Alles wie erwartet:** Ich baue den FRAM-Teil (letzte Stände und Highscore, DIP 2,
  SW 0.4.0), wieder nur für `cyclone_10_pcb`.
- **D1 flackert im Spiel:** Ich verlängere das Nachhalten oder ändere das Kriterium; dafür
  helfen die LA-Aufnahmen von Kanal 4/7.
- **D1 an im Attract/Selbsttest:** Ich weiche auf den Outhole-Schalter als Spielende-Erkennung
  aus, wie beim Musik-Feature.

Hinweis: Nach dem Test wieder eine reguläre Version flashen (z. B. `bin\FPGA_board_v4.x`
v034). Im Messbuild fehlt an LED D1 die Watchdog-Anzeige.
