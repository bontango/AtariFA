# Testanweisung Schritt 2 – SW 0.4.3: Credits über das Ausschalten retten

Stand: 11.11.2026 · Variante: **nur `cyclone_10_pcb`** am Prüfstand mit Schaltermatrix.
Voraussetzung: Schritt 1 (`TEST_Highscore_Schritt1.md`, SW 0.4.2) OK.

## Datei

`N:\Projekte\FPGA Atari\FPGA_source\variants\cyclone_10_pcb\output_files\AtariFA.jic`
(Build-Zeit siehe unten). Die Boot-Info zeigt **043**.

## Was die Version tut

- Der FPGA schreibt den **Credit-Zähler** des gewählten Spiels mit. Bei jeder Änderung
  (Münze, Spielstart) wird er sofort im FRAM gespeichert, im selben Slot wie letzte Stände und
  Highscore.
- **Nach dem Einschalten** wartet der FPGA, bis das Spiel sein RAM gelöscht hat (50 ms nach dem
  CPU-Start), hält die CPU kurz an und schreibt den gespeicherten Wert in den Credit-Zähler zurück.
  Mechanik wie die Airborne-Injektion aus SW 0.0.9, jetzt für alle fünf Spiele.
- Das Credit-Display zeigt den Wert **erst nach der nächsten Münze oder dem Spielstart** – so
  verhält sich das Spiel auch im Original (das Display wird nur bei einer Änderung neu geschrieben).
  Eine Münze nach dem Einschalten muss also „gespeicherte Credits + 1“ zeigen.
- **Boot-Info, Status-Display** (rechts): der gespeicherte Credit-Stand, solange DIP 2 ON ist.
- **DIP 2 OFF** schaltet auch das aus und löscht beim Einschalten den Slot (Credits, Stände, Highscore).
- Gilt auch nach einer **FA-Control-Übernahme**: beim Loslassen startet das Spiel neu und bekommt
  die Credits wieder.

**Achtung, Speicherformat geändert:** der Slot ist jetzt 17 statt 16 Byte groß und liegt bei
`Spiel × 32`. Das Kennbyte ist neu (`A6` statt `A5`), deshalb gelten die in 0.4.0–0.4.2
gespeicherten Stände und Highscores als leer – beim ersten Einschalten mit 0.4.3 ist alles weg.

## Credit-Adressen (aus den ROMs)

| Spiel | Adresse | Format | Fundstellen |
|---|---|---|---|
| Atarians | `$CE` | BCD | Münze `7B54`–`7B68` (Limit `$E0`), Start `7B76`–`7B87` |
| Time 2000 | `$D6` | BCD | Münze `7C93`–`7CA7` (Limit `$CA`), Start `7CB4`–`7CC2` |
| Airborne Avenger | `$D5` | binär | `7CA7`–`7CBF` (Limit `$BC`), HW-erprobt mit SW 0.0.9 |
| Middle Earth | `$1D` | BCD | = das Credit-Display-Byte selbst; Münze `7232`, Start `725B`; Boot schreibt `$88` |
| Space Riders | `$B7` | BCD | Münze `7BDA`–`7BEF` (Limit `$A8`), Start `77A0` (addiert `$99` = −1) |

Außer diesen Routinen schreibt in allen fünf ROMs nur der Boot-RAM-Clear auf die Adressen.
Die Werte aus dem alten Probe-Build (Juli 2026: 206/214/240/107/183) stimmen für Atarians
(`$CE`), Time 2000 (`$D6`) und Space Riders (`$B7`) – bei Airborne und Middle Earth lag er daneben.

## Ablauf

Mit Airborne anfangen (dort ist die Injektion schon einmal gelaufen), dann die anderen vier.
DIP 2 ON.

| # | Aktion | Erwartet |
|---|---|---|
| 1 | Einschalten | Boot-Info Status-Display rechts `00` (beim ersten Mal mit 0.4.3) |
| 2 | 3 Münzen einwerfen | Credit-Display 3 |
| 3 | Ausschalten, einschalten | Boot-Info Status-Display `03` |
| 4 | 1 Münze | Credit-Display **4** (nicht 1) |
| 5 | Spiel starten, bis zum Ende spielen | Credits 3; Highscore wie in Schritt 1 |
| 6 | Ausschalten, einschalten | Boot-Info `03`; letzte Stände + Highscore wieder da |
| 7 | Spiel starten ohne Münze | startet (Credits 3 → 2) |
| 8 | Alle Credits verspielen bis 0, aus/ein, Start drücken | kein Spiel (0 Credits) |
| 9 | DIP 2 OFF, einschalten | Status-Display blank; DIP 2 ON, einschalten: `00` |
| 10 | Schritte 2–4 mit den anderen vier Spielen | wie oben |

**Worauf achten:**
- **Middle Earth:** dort ist der Credit-Zähler das Display-Byte selbst. Nach dem Einschalten
  muss Start ohne Münze ein Spiel beginnen, wenn Credits gespeichert waren.
- Spiel hängt oder startet nach dem Einschalten neu → Injektion stört die CPU (`HALT_SETTLE`).
- Credits nach dem Einschalten 0, obwohl die Boot-Info sie zeigt → Injektion zu früh, vom
  Boot-Clear überschrieben (`CRED_DELAY`, steht auf 50 ms).
- Boot-Info zeigt nach dem Einschalten 0, obwohl Credits da waren → Mitschreiben greift nicht.

## Ressourcen

Gebaut 11.11.2026 17:52. Synthese: Comb 5854 / Reg 2178 / Speicher 202 752 Bit
(0.4.2: 5640 / 2099). LE **96 %** (5993/6272), Slack Setup +2,59 ns / Hold +0,38 ns.
score_keeper inkl. I²C 927 LEs.

**Platz ist damit fast aufgebraucht** (279 LEs frei). Die erste Fassung rechnete die binären
Airborne-Credits für die Boot-Info kombinatorisch in BCD um: 98 % und Setup −5,4 ns. Jetzt
zählt ein getakteter Zähler das Ergebnis aus.

## Ergebnisse

Bemerkungen:

**SW 0.4.3, 11.11.2026:** Credits werden gespeichert und zurückgeschrieben (Spiel ließ sich nach
aus/ein ohne Münze starten). Aber das Credit-Display zeigt nach dem Einschalten `88`.
Ursache: die Injektion schrieb nur den Credit-Zähler. Das Display kommt aus `$1D`, und dort steht
nach dem Boot das `$88` des Segmenttests, bis Münze oder Start das Byte neu schreiben.

## Nachtrag SW 0.4.4 – Credit-Display nach dem Einschalten

Boot-Info zeigt **044**. Die Injektion schreibt jetzt zwei Bytes: den Credit-Zähler und
`$1D` = Credits in BCD, so wie das Spiel es nach einer Münze selbst tut (Airborne: `7CBF`).
Die Display-Logik des FPGA liest dafür den RAM-Port statt des CPU-Busses und sieht damit auch die
Injektion. Bei Middle Earth ist `$1D` zugleich der Zähler, beide Bytes sind gleich.

Unverändert bleibt die linke Hälfte des Status-Displays (`$1C`, Ball/Match): dort steht wie im
Original `88`, bis ein Spiel startet. Bei 0 gespeicherten Credits wird nichts geschrieben, das
Display zeigt dann wie im Original `88`.

**Kurztest:** 3 Credits aufbuchen, aus/ein → gleich nach der Boot-Info zeigt das Credit-Display **3**
(schon während des Segmenttests `888888` auf den Spieler-Displays); 1 Münze → 4. Mit allen fünf Spielen.

Gebaut 11.11.2026 18:18. Comb 5861 / Reg 2180 / Speicher 202 752 Bit, LE 96 % (6013/6272),
Slack Setup +2,64 ns / Hold +0,45 ns.

Ergebnis 0.4.4: **funktioniert** (11.11.2026).
