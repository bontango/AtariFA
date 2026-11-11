# Testanweisung Schritt 1 – SW 0.4.0: letzte Spielstände und Highscore im FRAM

Stand: 10.11.2026 · Variante: **nur `cyclone_10_pcb` (FPGA_board_v4.x)** am Schreibtisch-Prüfstand
mit Schaltermatrix. Voraussetzung: Schritt 0 (`TEST_Highscore_Schritt0.md`), alle fünf Spiele OK.

## Datei

`N:\Projekte\FPGA Atari\FPGA_source\variants\cyclone_10_pcb\output_files\AtariFA.jic`
(gebaut 10.11.2026 18:19). Die Boot-Info zeigt **040**.

## Was die Version tut

- **Spielende** (Erkennung wie im Messbuild 2, ~2 s nach dem Ende): Die Stände aller vier
  Spieler werden im FRAM gespeichert, getrennt für jedes der fünf Spiele. Ein Spiel ohne einen
  einzigen Punkt wird nicht gespeichert.
- **Highscore** je Spiel = höchster Einzelstand aller bisher gespeicherten Spiele.
- **Nach dem Einschalten** zeigen die vier Spieler-Displays bis zum ersten Spielstart die
  gespeicherten letzten Stände, auch während des Segmenttests `888888`. Player-up-Lampen
  und das Credit-/Ball-Display bleiben die des Spiels.
- **Im Attract** (kein Spiel läuft) im Wechsel: **8 s** normale Anzeige, **4 s** der Highscore
  auf allen vier Spieler-Displays.
- **DIP 2 ON beim Einschalten** löscht den Speicher des **gewählten** Spiels (letzte Stände
  und Highscore). Die anderen vier Spiele bleiben erhalten. Danach DIP 2 wieder auf OFF,
  sonst wird bei jedem Einschalten gelöscht. **Ab SW 0.4.2 umgedreht** (ON = an, OFF = aus +
  löschen), s. Nachtrag unten.
- **Nicht in dieser Version: Credits.** Dazu muss der FPGA den Wert ins Spiel-RAM zurückschreiben,
  und die Adresse des Credit-Zählers ist bisher nur für Airborne bekannt (`$D5`). Für die
  anderen vier Spiele muss ich sie erst aus den ROMs heraussuchen. Das ist Schritt 2.
- LED D1 zeigt wieder den Watchdog (wie v034).

## Ablauf

Mit **einem** Spiel beginnen (Vorschlag Airborne, dort lief das FRAM schon 2026-07).

| # | Aktion | Erwartet |
|---|---|---|
| 1 | DIP 2 **ON**, einschalten, Boot abwarten, ausschalten, DIP 2 **OFF** | Speicher des Spiels gelöscht |
| 2 | Einschalten | Spieler-Displays verhalten sich wie bisher (nichts gespeichert), **kein** Highscore-Wechsel |
| 3 | Spiel mit 1 Spieler, ein paar Punkte, bis zum Ende spielen | normales Spiel |
| 4 | ~2 s nach Spielende im Attract warten | im Wechsel 8 s Spielanzeige / 4 s Highscore = Stand von Spieler 1 auf **allen vier** Displays |
| 5 | Ausschalten, einschalten | nach der Boot-Info stehen die Stände aus Schritt 3 in den Displays (auch statt `888888`); alle 12 s der Highscore |
| 6 | Spiel mit 2 Spielern, Spieler 2 schlägt den Highscore | nach Spielende: Highscore = Stand von Spieler 2 |
| 7 | Spiel mit schlechterem Ergebnis | Highscore bleibt; letzte Stände = das schlechtere Spiel |
| 8 | Ausschalten, einschalten | Stände aus Schritt 7, Highscore aus Schritt 6 |
| 9 | Spielauswahl auf ein anderes Spiel, einschalten | dessen eigener Speicher (beim ersten Mal leer) |
| 10 | zurück zum ersten Spiel, einschalten | Stände und Highscore aus Schritt 7/6 wieder da |
| 11 | DIP 2 ON, einschalten | Stände und Highscore dieses Spiels gelöscht |

**Worauf achten:**
- Ziffern **verdreht oder gespiegelt** (z. B. `021000` statt `120000`) → Kodierung im Speicher.
- Der Highscore zeigt den Stand eines **Spielers, der nicht gespielt hat**, oder Reste eines
  früheren Spiels → die Displays der nicht beteiligten Spieler werden beim Spielstart nicht
  geleert; dann muss ich sie beim Schnappschuss ausblenden.
- Nach Spielende wird **ein Bonus nicht mehr mitgezählt** (Stand im Speicher kleiner als
  in der Anzeige) → Schnappschuss zu früh.
- Bei Tilt: Spiel läuft bis zum Ende weiter, gespeichert wird der Stand danach.
- **Space Riders** (Fehler aus Schritt 0): Nach Spielende muss der Highscore-Wechsel nach
  ~2 s einsetzen. Bleibt er aus, ist das Spielende wieder nicht erkannt worden.

## Optional: Logic-Analyzer

Nur wenn etwas nicht stimmt. Dafür `DBG_MODE := 6` in `top/AtariFA.vhd` setzen und neu bauen
(dann zeigt LED D1 wieder „Spiel läuft“):

| Kanal | Signal |
|---|---|
| 0–3 | up-Lampe Spieler 1–4 |
| 4 | genau eine an, roh |
| 5 | in_game (= Speicherzeitpunkt bei fallender Flanke) |
| 6 | FRAM-Slot gültig |
| 7 | Puls je Speichervorgang |

## Ressourcen

LE 92 % (5794/6272). Synthese: Comb 5624 / Reg 2090 (Messbuild 2: 4694 / 1603).
score_keeper inkl. I²C 753 LUTs. Speicher unverändert
202 752 Bit. Für Schritt 2 (Credits) ist noch Platz, aber nicht mehr viel.

## Ergebnisse

Bemerkungen:

**SW 0.4.0, 11.11.2026 (Airborne):** Nach Aus-/Einschalten ist der Highscore weg. Im laufenden
Betrieb funktioniert der Wechsel zur Highscore-Anzeige. Der Wert stand also nur in den
FPGA-Registern; entweder ist er nie im FRAM angekommen, oder beim Booten wurde der Slot gelöscht.

## Nachtrag SW 0.4.1 – Diagnose „Highscore nach dem Ausschalten weg“

Gebaut 11.11.2026 17:06, gleiche Datei (`variants\cyclone_10_pcb\output_files\AtariFA.jic`),
Boot-Info zeigt **041**. Zwei Änderungen:

1. **DIP-Lesen mit Wartezeit** (`read_the_dips.vhd` v1.1): Jede Zeile der Boot-Matrix wird erst
   50 µs nach dem Strobe-Wechsel gelesen, statt nach 1 µs. Verdacht: DIP 2 (`options(2)`) hängt an
   derselben Rückleitung wie Freispiel aus der Zeile davor. Steht Freispiel auf ON, war die Leitung
   nach 1 µs womöglich noch low, DIP 2 wurde dann als ON gelesen und hat bei **jedem** Boot gelöscht.
2. **FRAM-Zustand in der Boot-Info, Display 4** (Freispiel bleibt ganz rechts):

   | Stelle | Bedeutung |
   |---|---|
   | ganz links | `1` = FRAM antwortet (ACK), `0` = keine Antwort |
   | zweite von links | `2` = Slot gelöscht (DIP 2 als ON gelesen), `1` = gültiger Slot gelesen, `0` = leer/ungültig |
   | ganz rechts | Freispiel wie bisher |

**Ablauf:** Schritte 1–5 von oben wiederholen und dabei bei jedem Einschalten Display 3 und 4 notieren.

| Boot-Info Display 4 (links) | Heißt |
|---|---|
| `1 1` nach dem gespeicherten Spiel | Speichern + Lesen in Ordnung, Fehler behoben |
| `1 2` obwohl DIP 2 OFF | DIP 2 wird immer noch falsch gelesen → Display 3, zweite Ziffer, prüfen |
| `1 0` nach dem gespeicherten Spiel | FRAM antwortet, aber der Slot ist leer → Schreiben am Spielende kommt nicht an |
| `0 x` | FRAM antwortet gar nicht → Hardware (Bestückung, Pull-ups, Versorgung) |

Ressourcen 0.4.1: Comb 5625 / Reg 2098 / Speicher 202 752 Bit (0.4.0: 5624 / 2090), LE 92 %
(5799/6272), Slack Setup +2,78 ns / Hold +0,44 ns.

Ergebnis 0.4.1: **funktioniert** (11.11.2026). Ursache war keine Hardware: DIP 2 stand im Test
auf ON, weil „OFF = Highscore aus“ angenommen war – und ON hat bei jedem Einschalten gelöscht.

## Nachtrag SW 0.4.2 – DIP 2 umgedreht

Boot-Info zeigt **042**. DIP 2 bedeutet jetzt:

| DIP 2 | Wirkung |
|---|---|
| **ON** | Highscore/letzte Stände **an**: beim Einschalten lesen, am Spielende speichern, im Attract einblenden |
| **OFF** | **aus**: beim Einschalten den Speicher des gewählten Spiels löschen, danach nichts speichern und nichts einblenden |

Speicher eines Spiels zurücksetzen = einmal mit DIP 2 OFF einschalten, dann wieder ON.
Boot-Info Display 4, zweite Stelle von links: `2` = aus/gelöscht (DIP 2 OFF), `1` = gültig gelesen,
`0` = an, aber noch nichts gespeichert.

**Kurztest:**

| # | Aktion | Erwartet |
|---|---|---|
| 1 | DIP 2 ON, Spiel mit Punkten bis zum Ende, aus/ein | Display 4 links `1 1`, Stände + Highscore wieder da |
| 2 | DIP 2 OFF, einschalten | Display 4 links `1 2`; keine gespeicherten Stände, kein Highscore-Wechsel |
| 3 | Spiel mit Punkten bis zum Ende (DIP 2 noch OFF) | **kein** Highscore-Wechsel im Attract |
| 4 | DIP 2 ON, einschalten | Display 4 links `1 0`, nichts gespeichert (gelöscht in 2, nicht gespeichert in 3) |

Gebaut 11.11.2026 17:33. Ressourcen: Comb 5640 / Reg 2099 / Speicher 202 752 Bit, LE 93 %
(5809/6272), Slack Setup +3,16 ns / Hold +0,42 ns.

Ergebnis 0.4.2: **funktioniert** (11.11.2026).
