# Die FA-Control-Schnittstelle

Stand 2026-08-14, AtariFA SW 0.2.0, Modul `rtl/fa_control/`.

**Am Prototyp getestet (2026-08-08), funktioniert.** Der Abschnitt „Inbetriebnahme" unten führt
die Schritte auf, in der Reihenfolge, in der sie geprüft wurden.

## 1. Wozu

[FA_Control](https://github.com/bontango/FA_Control) ist eine ESP32-C3-Firmware, die eine
Weboberfläche zum Testen eines Flippers ausliefert (`N:\Projekte\FA_Control`). Bis Version 1.00
hat sie ins Leere gesendet — auf keiner der FPGA-Platinen gab es eine Gegenstelle, und die
Anzahl von Lampen, Spulen, Schaltern und Displays musste der Benutzer von Hand eintragen.

`rtl/fa_control/fa_control.vhd` ist diese Gegenstelle. Sie macht zwei Dinge:

1. **Auskunft geben.** Beim Verbinden fragt FA_Control die Bestückung ab und konfiguriert sich
   selbst. Kein Formular mehr, keine falsch geratenen Zahlen.
2. **Die Anlage steuern.** Nach einer Freigabe darf der Host Lampen, Spulen, Displays und Ton
   direkt setzen und Schalter mitlesen — die Spiel-CPU steht währenddessen.

Das Protokoll ist **LISY API 0.12**, unverändert aus
`N:\Projekte\lisy_5_28\src\lisy\lisy_api.h`. Nichts davon ist erfunden; ein echter LISY-Host
(Raspberry Pi) könnte sich genauso anmelden.

## 2. Verdrahtung

Drei Leitungen, alle schon auf der Platine vorhanden (Schaltplan
`../doc/AtariFA_07_Final_Main_SCH.PDF`, Steckverbinder X7 ↔ X1P):

| ESP32-C3 | Netz | FPGA-Pin (pcb) | VHDL-Port | Richtung |
|---|---|---|---|---|
| GPIO7 | `ESP32_TX` | PIN_33 | `ESP32_ser_tx` | ESP sendet → FPGA empfängt |
| GPIO6 | `ESP32_RX` | PIN_44 | `ESP32_ser_rx` | FPGA sendet → ESP empfängt |
| GPIO10 | `ESP32_IO10` | PIN_11 | `ESP32_ctrl_req` | ESP fordert an → FPGA liest |

115200 Baud, 8N1, kein Flow-Control.

**Die Portnamen sind aus Sicht des ESP32 vergeben.** `ESP32_ser_tx` ist dessen TX und damit ein
FPGA-*Eingang*. Wer das übersieht, verdrahtet die Schnittstelle garantiert falsch herum — genau
das war bis 08.2026 in `FA_Control/main/board_pins.h` passiert (TX und RX vertauscht).

`ESP32_ctrl_req` war früher `ESP32_sig`, ein FPGA-*Ausgang*, fest auf `'0'`. Da GPIO10 auf der
ESP-Seite ein Push-Pull-Ausgang ist, haben mit gestecktem Modul beide Seiten gegeneinander
getrieben. Seit SW 0.1.3 ist es ein Eingang mit Weak-Pull-Up — **kein ESP gesteckt = high = keine
Anforderung**, und die Platine verhält sich exakt wie vorher.

## 3. Die Freigabe

Damit ein angestecktes Testgerät nicht ungefragt mitten im Spiel die Kontrolle übernimmt, müssen
**zwei Bedingungen** zusammenkommen:

| | |
|---|---|
| `ESP32_ctrl_req` = low | Der Host will übernehmen (GPIO10, active low). |
| **Options-DIP 4 = ON** | Der Betreiber erlaubt es. Wird fortlaufend gelesen. |

Erst der Befehl **0x64 (`LISY_INIT`)** schaltet dann tatsächlich um. Seine Antwort sagt dem Host,
woran es lag:

| Antwort | Bedeutung |
|---|---|
| 0 | Kontrolle gewährt |
| 1 | verweigert — Options-DIP 4 steht auf OFF |
| 2 | verweigert — `ESP32_ctrl_req` liegt nicht an |

Die Kontrolle endet **sofort**, wenn eine der beiden Bedingungen wegfällt (der DIP-Schalter wirkt
also auch im laufenden Betrieb), und außerdem, wenn **2 Sekunden lang kein einziges Byte** mehr
ankam. Das ist die Totmannschaltung — sie greift, wenn der Host verstummt: Modul aus der Fassung
gezogen, ESP abgestürzt oder neu gestartet, Kontaktfehler auf der seriellen Leitung. Danach läuft
die Platine von selbst wieder als Flipper an. FA_Control sendet dafür alle 500 ms den
Watchdog-Befehl 0x65 — der Zähler wird aber von **jedem** empfangenen Byte zurückgesetzt, nicht
nur vom Watchdog, damit ein in der Weboberfläche abgeschalteter Watchdog die Verbindung nicht
kappt.

**Nicht durch Stromlosmachen des ESP provozierbar:** das Modul wird von AtariFA mit 5 V versorgt
und braucht kein USB-Kabel. Wer den Automaten ausschaltet, nimmt beiden Seiten gleichzeitig den
Strom — dabei ist nichts zu beobachten.

In allen drei Fällen (Bedingung weg, Timeout, Reset) werden alle Sollwerte gelöscht: Lampen aus,
Spulen aus, Ton aus, Displays leer.

## 4. Was während der Übernahme passiert

**Die Spiel-CPU wird angehalten** (`reset_l_stable` geht auf `'0'`), und das FPGA speist alle
Peripherie aus den Sollwerten des Hosts. Das ist Absicht: liefen Spielcode und Testbefehle
gleichzeitig, würde der Lampen-Refresh des Spiels alle vier Millisekunden jede von Hand gesetzte
Testlampe wieder überschreiben.

Im Top-Level (`top/AtariFA.vhd`) hängt das an einem einzigen Signal:

```
reset_l_stable <= boot_phase(2) and not fa_ctrl_active;   -- CPU
io_live        <= reset_l_stable or fa_ctrl_active;       -- Peripherie
```

`io_live` ist der Grund, warum Schaltermatrix, Lampenmatrix und Tonerzeugung **nicht** an
`reset_l_stable` hängen dürfen: bei angehaltener CPU müssen sie weiterarbeiten, sonst ließe sich
nichts testen. Dasselbe gilt für `solenoids_enable` — bliebe der 74HCT540 gesperrt, käme keine
Spule zum Zug.

Beim Loslassen läuft das Spiel **von vorn** an (Boot-Info, dann Attract Mode). Ein laufendes
Spiel lässt sich nicht anhalten und fortsetzen.

`LED_D4` leuchtet, solange die Kontrolle aktiv ist. Auf `cyclone_10_pcb` gibt es diese LED nicht
(dort ein `VIRTUAL_PIN`), auf `cyclone_10_dev_open` ist sie real.

## 5. Nummerierung

Das ist der Teil, den man beim ersten Hardware-Test in der Hand hat.

**Lampen 0…83** — `Nummer = (Gruppe − 1) × 4 + Strobe`, also Gruppe 1/Strobe A = 0,
Gruppe 1/Strobe D = 3, Gruppe 2/Strobe A = 4 … Gruppe 21/Strobe D = 83. „Gruppe" ist der Ausgang
der 74HC595-Kaskade (= eine ULN2003A-Zeile), „Strobe" die Spalte SA/SB/SC/SD vom Aux-Board.

Die Umrechnung auf das Bit im RAM-Shadow steht als `FA_LAMP_BIT` in
`rtl/common/lamp_map_pkg.vhd` und wird dort **zur Elaborationszeit aus `GRP_OF` berechnet**.
Es gibt bewusst keine zweite, von Hand gepflegte Tabelle: `GRP_OF` bleibt die eine Stelle, an der
die Lampenzuordnung am Prototyp getunt wird, und die Umkehrung fällt automatisch mit.

**Spulen 1…22 — als einzige Gruppe 1-basiert** (seit SW 0.2.0 / FA_Control 1.16)

| Nummer | Ausgang |
|---|---|
| 1…20 | `solenoids(1..20)` = Treiber **Q1…Q20** des Schaltplans |
| 21 | Münzzähler (`COIN_CNTREN`, Aux-Board) |
| 22 | Sperrspule Münztür (`LOCKOUT_EN`, Aux-Board) |

Die Kachelnummer ist damit die Q-Nummer, und zwar durchgängig: sie steht so auf der Kachel,
geht so über die Leitung und wird erst in `fa_control.vhd` auf den 0-basierten Vektor `sol_r`
heruntergerechnet (`par1 - 1`). Das Top-Level bleibt davon unberührt.

**Warum ausgerechnet die Spulen ab 1 zählen und Lampen/Schalter nicht:** so zählt LISY sie auf
der Leitung (`N:\Projekte\lisy_5_28\src\lisy\lisy_w.c`, „sol number starts with 1"), und so heißen
sie im Original. Bis SW 0.1.9 war auch das Protokoll 0-basiert — ein echter LISY-Host hätte damit
mit der 1 die zweite Spule getroffen und die 22. gar nicht erreicht (`par1 < N_SOL` scheiterte
bei 22). Lampen folgen dagegen der Formel `(Gruppe−1)×4 + Strobe` und Schalter dem CPU-Offset,
dort ist 0 die erste — das bleibt so.

Die Positionen **14 und 18** (= Q14 und Q18) sind auf der Platine **nicht bestückt** — je nach
Spiel gibt es diese Ausgänge auch im Original nicht. Der Befehl wird angenommen, es passiert nur
nichts. Anders als der `solenoid_driver`, der sie fest auf AUS hält, lässt FA-Control sie zu;
deshalb sind auch die früher erwarteten Quartus-Warnungen `solenoids[14]/[18] stuck at VCC`
verschwunden.

**Schalter 0…79** — Nummer = CPU-Offset `addr − 0x2000`, **0-basiert**. Damit deckt sich die
Nummer mit dem, was der Selbsttest des Spiels anzeigt.

**Displays 0…4** — LISY-Konvention: **0 = Status/Credit** (4 Stellen), 1…4 = Spieler 1…4
(je 6 Stellen). Ziffern kommen rechtsbündig und höchstwertig zuerst, Blank ist `0x0F`.

**Sounds 0…15** — die 16 Wellenformen des 82s130-ROMs. Der Atari kennt keine „Sound-Nummern";
`0x32` setzt Wellenform *n* mit fester Tonhöhe (`x"8"`) und voller Lautstärke, `0x33` schaltet ab.
Details zur Tonerzeugung: `Sound_Emulation.md`.

## 6. Die Befehle

Alles unverändert LISY API 0.12. **Neu implementiert** ist die Info-Gruppe 0…9 — sie ist der
Connect-Handshake:

| Op | Name | Parameter | Antwort | AtariFA liefert |
|---|---|---|---|---|
| 0 | `G_HW` | – | String+NUL | `AtariFA` |
| 1 | `G_LISY_VER` | – | String+NUL | `0.2.0` (aus `BOARD_ID`/`SW_SUB1`/`SW_SUB2`) |
| 2 | `G_API_VER` | – | String+NUL | `0.12` |
| 3 | `G_NO_LAMPS` | – | 1 Byte | 84 |
| 4 | `G_NO_SOL` | – | 1 Byte | 22 |
| 5 | `G_NO_SOUNDS` | – | 1 Byte | 16 |
| 6 | `G_NO_DISP` | – | 1 Byte | 5 |
| 7 | `G_DISP_DETAIL` | Display-Nr | **2 Bytes**: Typ, Stellen | `(1,4)` für 0, `(1,6)` für 1…4 |
| 8 | `G_GAME_INFO` | – | String+NUL | Spielnummer als Ziffer |
| 9 | `G_NO_SW` | – | 1 Byte | 80 |

Typ 1 = BCD7 (7-Segment ohne Komma). Dass Opcode 7 **zwei** Bytes liefert, ist so, wie der echte
LISY-Host liest (`lisy_api_com.c`, `lisy_api_read_2bytes`).

Die Stellbefehle wirken **nur mit gewährter Kontrolle** und werden sonst folgenlos angenommen.
Die Lesebefehle (10, 20, 40, 41) gehen **immer** — ein Host kann also die Schalter eines laufenden
Spiels mitlesen, ohne es anzuhalten:

| Op | Bedeutung | Parameter | Antwort |
|---|---|---|---|
| 10 / 20 / 40 | Zustand Lampe / Spule / Schalter | Nr | 1 Byte, 0 oder 1 |
| 41 | geänderter Schalter | – | Bit7 = Zustand, Bit0-6 = Nr; **127 = keine Änderung** |
| 11 / 12 | Lampe ein / aus | Nr | – |
| 21 / 22 / 23 | Spule ein / aus / Puls | Nr | – |
| 24 / 25 | Pulszeit / Recycle-Zeit | Nr, ms | – |
| 30…36 | Display setzen | Länge, Ziffern | – |
| 50 / 51 | Sound spielen / stoppen | Track, Nr | – |
| 100 | Init — **Übernahme anfordern** | – | 1 Byte, s. Kapitel 3 |
| 101 | Watchdog | – | 1 Byte 0 |

Unbekannte Opcodes werden ohne Parameter angenommen und mit `0x00` beantwortet.

### Bewusste Vereinfachungen

Das hier ist ein Testwerkzeug, kein Spielbetrieb:

* **Nur ein Spulenpuls gleichzeitig** (Opcode 23). Ein neuer Puls löst den laufenden ab. Ein
  eigener Zähler je Spule wäre ein Vielfaches an Registern, und die Weboberfläche pulst ohnehin
  immer nur eine Spule.
* **Opcode 24 speichert global.** Der Befehl trägt eine Spulennummer, es gibt aber nur eine
  Pulszeit für alle — genau so benutzt FA_Control ihn, das dieselbe Zeit in einer Schleife an
  alle Spulen schickt.
* Die Pulszeit kann **bis zu 1 ms zu kurz** ausfallen, weil der Millisekunden-Takt frei läuft.

## 7. Übernahme in andere FPGA-Projekte

Nichts in `rtl/fa_control/` ist Atari-spezifisch. Für WillFA, GottFA, BallyFA … reicht:

1. Ordner `rtl/fa_control/` kopieren (`fa_control_pkg.vhd`, `uart_rx.vhd`, `uart_tx.vhd`,
   `fa_control.vhd`).
2. Vier Zeilen in die Dateiliste des Projekts (hier: `scripts/files_common.tcl`, vor dem
   Top-Level; das Paket zuerst).
3. Instanz im Top-Level, Generics auf die Anlage setzen, Override-Ausgänge in die vorhandenen
   Treiberpfade muxen.

Die Anzahlen sind **Generics** und werden über die Opcodes 3…9 gemeldet — der Host muss also
nichts mehr wissen. Das ist der ganze Witz an der Sache.

**Die `MAX_*`-Generics knapp setzen.** Sie bestimmen die Vektorbreiten; jeder überzählige Eintrag
kostet ein Register plus seinen Anteil an Adressdekoder und Auslesemux. Bei AtariFA hat
„großzügig statt genau" (128/32/128/8 statt 84/22/80/6) rund **900 Logikelemente** gekostet.

`uart_rx.vhd`/`uart_tx.vhd` sind unverändert die nandland-Module aus
`N:\Projekte\WillFA7\FPGA_source\rtl\serial_api\`. **Achtung bei WillFA7 selbst:** dort liegen
dieselben Entities bereits unter `rtl/serial_api/` — beim Portieren also nicht doppelt in die
Dateiliste eintragen.

Der Code ist **VHDL-93** gehalten (kein `else generate`, keine unconstrained Record-Ports), weil
WillFA/GottFA Cyclone-II-Varianten haben, die noch mit Quartus 13.0sp1 gebaut werden.
`numeric_std` wird nur modulintern benutzt und kollidiert deshalb nicht mit der
`std_logic_unsigned`-Konvention der Top-Levels.

## 8. Ressourcen (AtariFA, Quartus 22.1std.2)

| | vor SW 0.1.3 | mit FA-Control |
|---|---|---|
| Combinational | 2 433 | 4 326 |
| Register | 935 | 1 434 |
| **Memory Bits** | **202 752** | **202 752** |
| LE (Fitter) | 2 545 (41 %) | 4 402 (70 %) |
| Slack | 2,304 ns | 3,142 ns |
| Pins | 85/89 | 85/89 |

Das Modul selbst ist 1 700 ALUTs / 499 Register, der Rest ist die Umschaltlogik im Top-Level.
**Kein zusätzliches BRAM** — das war das eigentliche Abnahmekriterium, denn mit 73 % ist der
Speicher die knappe Ressource, nicht die Logik. Es kommt auch **kein Pin** dazu; `ESP32_sig`
wechselt nur die Richtung.

## 9. Inbetriebnahme

**Am Prototyp durchlaufen und bestanden (2026-08-08, SW 0.1.3).** Die Reihenfolge ist so gewählt,
dass jeder Schritt den nächsten absichert:

1. **Ohne ESP.** Alle fünf Spiele booten und spielen wie mit SW 0.1.2. `ESP32_ctrl_req` liegt
   über den Weak-Pull-Up auf high, es ändert sich also nichts. Das ist der Regressionstest.
2. **ESP gesteckt, DIP 4 = OFF.** „VERBINDEN" in der Weboberfläche muss
   *„Kontrolle verweigert — Option-DIP 4 auf ON stellen"* melden, und das Spiel darf **nicht**
   stehenbleiben.
3. **DIP 4 = ON.** Verbinden. Die Infozeile muss `AtariFA / 0.2.0 / 0.12` zeigen und
   **84 Lampen, 22 Spulen, 80 Schalter, 16 Sounds, 5 Displays (4,6,6,6,6)** — diese Zahlen kommen
   jetzt vom FPGA und stehen in der Oberfläche auf „nicht änderbar". Das Spiel bleibt stehen, die
   Anzeigen bleiben an.
4. **Einzelne Lampe, Spule, Display schalten; Schalter am Spielfeld betätigen** und im Browser
   verfolgen.
5. **DIP 4 im Betrieb auf OFF.** Die Übernahme muss sofort enden, das Spiel neu anlaufen.

### Die Totmannschaltung lässt sich so nicht nebenbei prüfen

Hier stand ursprünglich „USB-Kabel des ESP ziehen". **Das geht nicht:** das Modul wird von
AtariFA mit 5 V versorgt und braucht überhaupt kein USB-Kabel. Ein steckendes Kabel ist der
Ausnahmefall (Flashen, serielles Log), nicht der Normalbetrieb.

Über die Weboberfläche geht es ebenfalls nicht: solange FA-Control die Kontrolle hat, hält
`fa_connect.c` den Watchdog **absichtlich** unabhängig von der Einstellung am Laufen — er ist die
Sicherung selbst und darf sich nicht wegklicken lassen. Und der Zähler im FPGA wird von *jedem*
empfangenen Byte zurückgesetzt, nicht nur vom Watchdog-Opcode.

Wer sie trotzdem gezielt auslösen will: **das ESP-Modul im laufenden Betrieb aus der Fassung
ziehen.** Genau das ist der Fall, gegen den sie schützt — Modul lose, ESP abgestürzt oder im
Neustart, Kontaktfehler auf der seriellen Leitung. Für den Alltag reicht Schritt 5: DIP 4 auf OFF
prüft denselben Rückfallpfad (Kontrolle weg, alle Ausgänge aus, Spiel läuft neu an), nur über
eine Bedingung, die man gefahrlos schalten kann.

### Wenn etwas nicht stimmt

| Beobachtung | Wo drehen |
|---|---|
| Gar keine Antwort | Zuerst TX/RX prüfen — `ESP32_ser_tx` ist ein FPGA-*Eingang* (Kapitel 2) |
| Falsche **Spalte** leuchtet | `STROBE_ENC` in `lamp_matrix.vhd` |
| Falsche **einzelne Lampe** | `GRP_OF` in `lamp_map_pkg.vhd` (die Umkehrung fällt mit) |
| Anzeige seitenverkehrt | Der Spiegelungsblock `fa_disp_map` in `top/AtariFA.vhd` |
| Falsche Spule | Zuordnungsblock in `solenoid_driver.vhd` bzw. Kapitel 5 |

## 10. Verwandte Dateien

| Datei | Inhalt |
|---|---|
| `rtl/fa_control/fa_control.vhd` | der LISY-Slave |
| `rtl/fa_control/fa_control_pkg.vhd` | Nibble-Feld + Display-Breiten |
| `rtl/common/lamp_map_pkg.vhd` | `GRP_OF` und die daraus berechnete Umkehrung |
| `top/AtariFA.vhd` | Instanz `FAC`, `io_live`, die Override-Muxe, `fa_lamp_map`, `fa_disp_map` |
| `N:\Projekte\FA_Control\main\fa_connect.c` | die Gegenseite des Handshakes |
| `N:\Projekte\lisy_5_28\src\lisy\lisy_api.h` | die Protokollreferenz |
| `../doc/AtariFA_07_Final_Main_SCH.PDF` | Schaltplan, Steckverbinder X7/X1P |
