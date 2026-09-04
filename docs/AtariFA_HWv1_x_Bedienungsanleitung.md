# AtariFA

**Atari Generation 1 MPU auf FPGA-Basis**

**Hardware-Version v1.x**

**Software-Version 0.3.3**

**Bedienungsanleitung**

ralf@lisy.dev

v1.1 04.09.2026

> Deutsche Fassung von `AtariFA_HWv1_x_user_manual.md`. Die Kapitelnummern sind in beiden
> Fassungen gleich.

## Inhaltsverzeichnis

- [Wichtiger Hinweis](#wichtiger-hinweis)
- [1. Einführung](#1-einführung)
- [2. Schnellstart](#2-schnellstart)
- [3. Einbau](#3-einbau)
  - [3.1. Was AtariFA ersetzt und was nicht](#31-was-atarifa-ersetzt-und-was-nicht)
  - [3.2. Die Box-Connectors](#32-die-box-connectors)
  - [3.3. Sicherungen](#33-sicherungen)
- [4. DIP-Schalter-Einstellungen](#4-dip-schalter-einstellungen)
  - [4.1. Die 4er-Bank: Spielauswahl und Freispiel](#41-die-4er-bank-spielauswahl-und-freispiel)
  - [4.2. Die 6er-Bank: Optionen](#42-die-6er-bank-optionen)
    - [4.2.1. Option 3 -> wo der Ton herauskommt](#421-option-3---wo-der-ton-herauskommt)
    - [4.2.2. Option 4 -> FA-Control darf übernehmen](#422-option-4---fa-control-darf-übernehmen)
    - [4.2.3. Option 1 -> Hintergrundmusik, Option 2 reserviert](#423-option-1---hintergrundmusik-option-2-reserviert)
    - [4.2.4. Optionen 5 und 6 -> Totzeit der Lampenspalten](#424-optionen-5-und-6---totzeit-der-lampenspalten)
    - [4.2.5. Wenn das Glimmen bleibt](#425-wenn-das-glimmen-bleibt)
  - [4.3. Sechs der zehn DIPs werden nur beim Einschalten gelesen](#43-sechs-der-zehn-dips-werden-nur-beim-einschalten-gelesen)
- [5. Der Startvorgang](#5-der-startvorgang)
  - [5.1. Phase 1: die DIP-Schalter werden gelesen](#51-phase-1-die-dip-schalter-werden-gelesen)
  - [5.2. Phase 2: die Info-Anzeige](#52-phase-2-die-info-anzeige)
  - [5.3. Phase 3: das Spiel läuft](#53-phase-3-das-spiel-läuft)
- [6. Spieleinstellungen und Selbsttest](#6-spieleinstellungen-und-selbsttest)
  - [6.1. Die Programmier-DIP-Bänke und der Replay-Schalter](#61-die-programmier-dip-bänke-und-der-replay-schalter)
  - [6.2. Der Selbsttest](#62-der-selbsttest)
  - [6.3. Credits und Highscores bleiben nicht erhalten](#63-credits-und-highscores-bleiben-nicht-erhalten)
- [7. Freispiel](#7-freispiel)
- [8. Ton](#8-ton)
  - [8.1. Was nachgebildet wird](#81-was-nachgebildet-wird)
  - [8.2. Die zwei Tonwege](#82-die-zwei-tonwege)
  - [8.3. Die Ansage beim Einschalten](#83-die-ansage-beim-einschalten)
  - [8.4. Hintergrundmusik vom MP3-Spieler](#84-hintergrundmusik-vom-mp3-spieler)
- [9. Die FA-Control-Schnittstelle (ESP32)](#9-die-fa-control-schnittstelle-esp32)
  - [9.1. Die Freigabe: Option 4](#91-die-freigabe-option-4)
  - [9.2. Was während der Übernahme passiert](#92-was-während-der-übernahme-passiert)
  - [9.3. Wie die Kontrolle wieder zurückgeht](#93-wie-die-kontrolle-wieder-zurückgeht)
  - [9.4. Was die Weboberfläche von der Platine erfährt](#94-was-die-weboberfläche-von-der-platine-erfährt)
  - [9.5. Anschluss](#95-anschluss)
- [10. Die Status-LEDs](#10-die-status-leds)
- [11. Das FPGA programmieren](#11-das-fpga-programmieren)
- [12. Platinen-Varianten](#12-platinen-varianten)
- [13. Noch nicht implementiert](#13-noch-nicht-implementiert)
- [Anhang A 'game select'](#anhang-a-game-select)
- [Anhang B Kurzübersicht](#anhang-b-kurzübersicht)

## Wichtiger Hinweis

Durch den Einsatz von AtariFA kann Ihr Flipperautomat beschädigt werden. Da es sich um ein privates Projekt OHNE kommerzielles Interesse handelt, übernimmt der Autor keinerlei Haftung für Schäden, die durch die Verwendung von AtariFA entstehen!

## 1. Einführung

AtariFA ersetzt die MPU eines Atari-Generation-1-Flippers durch eine FPGA-Platine. Nachgebildet werden der Prozessor MC6800, das RAM, die Spiel-ROMs und die TTL-Logik drumherum: die Adress-Latches, der Display-Multiplexer, die Dekoder der Schaltermatrix, die Lampentreiber und die Spulentreiber.

Das FPGA ist ein Cyclone 10 LP (10CL006) auf einer Huckepack-Platine, die auf der AtariFA-Platine sitzt. Die Platine trägt die originalen Atari-Steckverbinder — sie kommt also genau dorthin, wo die Atari-MPU ausgebaut wurde.

**Fünf Spiele werden unterstützt, und alle fünf liegen gleichzeitig im FPGA:**

The Atarians, Time 2000, Airborne Avenger, Middle Earth und Space Riders. Welches läuft, stellen drei DIP-Schalter ein — es gibt keine SD-Karte und nichts, was pro Spiel geladen werden müsste. Freispiel ist ein vierter DIP-Schalter und kein anderer ROM-Satz.

**Was wird benötigt?**

- Ein PC mit USB-Anschluss und ein USB-Blaster, um das FPGA programmieren zu können

Mehr nicht. Keine SD-Karte, kein Kartenleser, keine Batterie.

**Zwei Dinge sollten Sie vorher wissen:**

- **Sechs der zehn DIP-Schalter werden nur einmal beim Einschalten gelesen.** Eine Änderung im laufenden Spiel bleibt wirkungslos. Siehe Kapitel 4.3.

- **Credits und Highscores gehen beim Ausschalten verloren.** Das ist keine Einschränkung von AtariFA — die originale Atari-Generation-1-MPU hat ebenfalls keine Batteriepufferung. Siehe Kapitel 6.3.

## 2. Schnellstart

1.  Das aktuelle FPGA-Programm für **AtariFA** von lisy.dev herunterladen

2.  Das FPGA programmieren (Kapitel 11)

3.  Die Spielauswahl passend zu Ihrem Flipper einstellen (Anhang A)

4.  Entscheiden, wo der Ton herauskommen soll — Option 3, siehe Kapitel 4.2.1. Bei einem unveränderten Automaten mit vorhandenem Auxiliary Board bleibt sie auf **OFF**

5.  Die originale Atari-MPU durch AtariFA ersetzen

6.  Den Automaten einschalten

7.  Die Info-Anzeige rund fünf Sekunden lang beobachten und prüfen, ob Spielauswahl und Version stimmen (Kapitel 5.2)

8.  Viel Spaß

Es gibt keine Erstinbetriebnahme und nichts zu initialisieren — die Platine hat keinen nichtflüchtigen Speicher, der das nötig machen würde.

## 3. Einbau

AtariFA hat dieselben Steckverbinder wie die originale Atari-Generation-1-MPU und kommt an deren Platz. Automaten ausschalten, originale MPU ziehen, AtariFA einsetzen, fertig.

### 3.1. Was AtariFA ersetzt und was nicht

**Ersetzt wird:** die MPU-Platine einschließlich der Display-Ansteuerung, der Dekoder für die Schaltermatrix, der Lampentreiber und der Spulentreiber. Das sitzt jetzt alles auf der AtariFA-Platine — zwölf ULN2003A für die Lampenmatrix, zwanzig IRL540-MOSFETs für die Spulen.

**Weiterhin nötig: das Atari Auxiliary Board.** Zwei Dinge kommen von dort und werden auf AtariFA nicht nachgebildet:

- **die vier Lampen-Strobes.** Die Lampenmatrix ist 21 × 4; AtariFA treibt die 21 Zeilen, das Auxiliary Board erzeugt daraus die vier Spalten-Strobes mit +20 V — gesteuert über zwei Auswahlleitungen, die AtariFA hinschickt.
- **der Tonausgang**, sofern Sie den Ton nicht auf den bordeigenen Verstärker umschalten — siehe Kapitel 8.2.

Auch der Münzzähler und die Sperrspule der Münztür werden über das Auxiliary Board angesteuert.

Also: **das Auxiliary Board bleibt im Automaten.**

### 3.2. Die Box-Connectors

Neben den originalen Atari-Steckverbindern trägt die Platine zwei 25-polige „Box-Connectors". Sie führen dieselben Signale auf einen Steckverbinder, an dem sich leichter messen lässt — für Tests auf dem Werktisch ohne angeschlossenes Spielfeld.

Die Box-Connectors führen auch die vier Lampen-Strobes, die auf der Platine von vier P-Kanal-MOSFETs erzeugt werden. **Diese sind ausschließlich für Test-LEDs gedacht** — sie sind nicht dafür ausgelegt, die 20-V-Lampenmatrix eines echten Spielfelds zu treiben. Im Automaten kommen die Strobes vom Auxiliary Board.

### 3.3. Sicherungen

Die Platine hat eigene Sicherungshalter für die Spulenversorgung. Verwenden Sie **2 A träge**.

Zwei der zwanzig Spulentreiber, Q14 und Q18, sind nicht bestückt — je nach Spiel gibt es diese Ausgänge auch im Original nicht. Es fehlt dort schlicht der MOSFET; das Spiel kann sie ohnehin nicht ansteuern.

## 4. DIP-Schalter-Einstellungen

AtariFA hat **zehn DIP-Schalter** in zwei Bänken: eine mit vier und eine mit sechs Schaltern.

In dieser Anleitung und auf der Info-Anzeige gilt durchgehend: ein Schalter auf **„ON" zählt**, und Schalter 1 einer Bank ist immer derjenige, der 1 zählt.

### 4.1. Die 4er-Bank: Spielauswahl und Freispiel

| DIP  | Funktion                       | Wertigkeit |
|------|--------------------------------|------------|
| Dip1 | Spielauswahl, Bit 0            | 1          |
| Dip2 | Spielauswahl, Bit 1            | 2          |
| Dip3 | Spielauswahl, Bit 2            | 4          |
| Dip4 | **Freispiel** — ON = aktiv     | –          |

Die drei Schalter der Spielauswahl ergeben eine Zahl von 0 bis 7. Die Zahlen 0 bis 4 sind die fünf Spiele, siehe Anhang A. **Die Zahlen 5, 6 und 7 sind nicht belegt und fallen auf Middle Earth zurück** — ein falsch gestellter Schalter lässt die Platine also nie ohne Spiel.

Freispiel ist in Kapitel 7 beschrieben.

### 4.2. Die 6er-Bank: Optionen

Grundeinstellung ist **alle „OFF"** — das ist bei einem Standardautomaten richtig.

| DIP  | Funktion                                                    | Wird gelesen      |
|------|-------------------------------------------------------------|-------------------|
| Dip1 | **Hintergrundmusik** — ON = aktiv                            | beim Einschalten  |
| Dip2 | reserviert                                                  | beim Einschalten  |
| Dip3 | **Ton: OFF = Auxiliary Board, ON = Verstärker auf der Platine** | fortlaufend    |
| Dip4 | **FA-Control darf übernehmen** — ON = erlaubt                | fortlaufend       |
| Dip5 | **Lampen-Totzeit, höherwertiges Bit** — allein = Zeitverhalten der Original-MPU | fortlaufend |
| Dip6 | **Lampen-Totzeit, niederwertiges Bit** — vier Stufen zusammen mit Dip5, nur nötig, wenn LEDs glimmen | fortlaufend |

#### 4.2.1. Option 3 -> wo der Ton herauskommt

- **„OFF"** — **der Originalweg.** AtariFA speist das Atari Auxiliary Board genau so, wie es die originale MPU tut: über die vier Audioleitungen und die vier Leitungen des Lautstärke-Latches. Der Ton entsteht dann auf dem Auxiliary Board und geht an den Verstärker Ihres Automaten. **Das ist die Einstellung für einen unveränderten Flipper.**

- **„ON"** — **der Weg über die Platine.** Der Ton wird im FPGA erzeugt, gefiltert und an den kleinen Verstärker (TDA7267) auf der AtariFA-Platine geschickt. Sinnvoll auf dem Werktisch oder in einem Automaten, dessen Auxiliary Board im Tonteil defekt ist. Die Ausgänge zum Auxiliary Board bleiben währenddessen im Ruhezustand.

Dieser Schalter **darf im laufenden Spiel umgestellt werden** — er wird fortlaufend gelesen. Der Ton wandert sofort mit.

#### 4.2.2. Option 4 -> FA-Control darf übernehmen

- **„OFF"** — **niemand redet dazwischen.** Ein angestecktes FA-Control-Modul kann die Anzeigen und Schalter mitlesen, aber nichts schalten. Das ist die Einstellung für den normalen Spielbetrieb, und es ist die Grundeinstellung.

- **„ON"** — **FA-Control darf die Anlage steuern.** Erst dann gibt AtariFA auf Anfrage die Kontrolle ab; das Spiel wird dabei angehalten. Alles Weitere in Kapitel 9.

Auch dieser Schalter wird fortlaufend gelesen: wer ihn im laufenden Betrieb auf „OFF" stellt, nimmt FA-Control die Kontrolle **sofort** wieder weg, und das Spiel startet neu. Das ist der Not-Aus für den Fall, dass ein Testgerät sich aufhängt.

#### 4.2.3. Option 1 -> Hintergrundmusik, Option 2 reserviert

- **Option 1, „ON"** — **solange eine Kugel im Spiel ist, läuft Hintergrundmusik.** Der MP3-Spieler auf der Platine spielt den Ordner 02 seiner Speicherkarte in Schleife und pausiert wieder, sobald die Kugel unten liegt und das Spiel vorbei ist. Alles Weitere in Kapitel 8.4.

- **Option 1, „OFF"** — keine Hintergrundmusik. Das ist die Vorgabe und die Einstellung für einen Automaten, der sich wie das Original verhalten soll.

Option 1 gehörte früher zu einer versuchsweisen Speicherung von Credits und Highscores, die derzeit zurückgestellt ist, siehe Kapitel 13. Ab Software 0.3.0 ist sie der Schalter für die Hintergrundmusik.

**Option 2** ist nicht belegt, bitte auf „OFF" lassen. Sie ist verdrahtet, sie wird auf der Info-Anzeige dargestellt, und sie ist für spätere Software-Versionen vorgesehen.

Beide Schalter werden **nur beim Einschalten gelesen** — siehe Kapitel 4.3.

#### 4.2.4. Optionen 5 und 6 -> Totzeit der Lampenspalten

Die Lampen laufen bei Atari im Zeitmultiplex: vier Spalten werden der Reihe nach je eine halbe Millisekunde eingeschaltet. An der Original-MPU wird die Spalte im selben Augenblick umgeschaltet, in dem die neuen Lampenwerte gültig werden. Weil die Spaltentreiber auf dem Auxiliary Board beim Abschalten ein paar Mikrosekunden nachhängen, bekommt dabei jedes Mal die *falsche* Lampe einen ganz kurzen Stromstoß — die Nachbarlampe in derselben Treibergruppe, aus der vorherigen Spalte.

Bei einer Glühlampe merkt man davon nichts. **LED-Ersatzlampen glimmen dadurch aber sichtbar**, obwohl sie ausgeschaltet sind. Das ist der bekannte Effekt, dass LEDs in einem Atari „nie ganz ausgehen"; das Atari-Handbuch beschreibt ihn als angebliche „keep-alive"-Schaltung, gemeint ist aber dieselbe Sache.

AtariFA schaltet die Spalte deshalb um, **während alle Lampen ausgetastet sind**, und lässt der alten Spalte anschließend eine kurze **Totzeit** zum Abklingen, bevor die neuen Lampenwerte scharf werden. Wie lange ein Spaltentreiber zum Abschalten braucht, ist aber von Automat zu Automat verschieden — es hängt an den Bauteilen und daran, wie viel Strom die Lampen dieser Spalte ziehen. Je weniger Strom, desto länger. Eine Spalte mit LED-Ersatzlampen ist deshalb der ungünstigste Fall. Darum ist die Totzeit einstellbar, über die **Optionen 5 und 6 gemeinsam**:

| Option 5 | Option 6 | Totzeit | Helligkeit |
|---|---|---|---|
| **OFF** | **OFF** | **etwa 65 µs — Grundeinstellung** | 21,8 % |
| OFF | ON | etwa 250 µs | 12,8 % |
| ON | OFF | *keine* — Zeitverhalten der Original-MPU | 24,5 % |
| ON | ON | etwa 400 µs | 5,5 % |

**Was einzustellen ist:**

- **Glühlampen im Automaten:** nichts. Die Grundeinstellung passt, der Schalter ist für Sie ohne Bedeutung.

- **LED-Ersatzlampen, alles in Ordnung:** ebenfalls nichts. Die Grundeinstellung genügt in den meisten Automaten.

- **Einzelne LEDs glimmen, obwohl sie aus sein sollten:** eine Stufe höher gehen — erst Option 6 = „ON" (250 µs), und nur wenn das nicht reicht, beide auf „ON" (400 µs). **Nehmen Sie die kleinste Stufe, die das Glimmen beseitigt**, denn jede Stufe kostet Helligkeit. Bei 250 µs fällt das im Automaten kaum auf; **400 µs sind deutlich dunkler**, das ist so gewollt und kein Fehler.

- **Option 5 = „ON" allein** schaltet das **Zeitverhalten der Original-MPU** ein, einschließlich des Glimmens. Interessant, wenn Sie AtariFA mit der Originalplatine vergleichen wollen oder wenn Ihnen das Original-Verhalten lieber ist. Auf Glühlampen hat das keinerlei Einfluss.

Beide Schalter werden fortlaufend gelesen, dürfen also im laufenden Spiel umgestellt werden — damit lässt sich der Unterschied unmittelbar vergleichen, ohne den Automaten aus- und wieder einzuschalten. Die Länge einer Spalte bleibt in allen vier Stellungen dieselbe halbe Millisekunde; es ändert sich nur, wie viel davon zum Abklingen reserviert ist.

> **Gegenüber Software 0.1.7 und 0.1.8 hat sich die Bedeutung der Kombination geändert.** Option 5 allein und Option 6 allein bedeuten weiterhin dasselbe; **beide zusammen** ergaben früher das Original-Timing und sind jetzt die längste Totzeit. Welche Fassung läuft, zeigt die Info-Anzeige beim Einschalten (Kapitel 5.2).

#### 4.2.5. Wenn das Glimmen bleibt

**Wenn auch die längste Stufe (Option 5 und 6 beide „ON") nichts ändert:** dann liegt es nicht an der Abschaltzeit der Spalte, und weiter hochdrehen hilft nicht — mehr als 400 Mikrosekunden gibt eine halbe Millisekunde Spaltendauer auch gar nicht her. Es gibt einen zweiten Grund, gegen den keine Software etwas ausrichtet: die Lampentreiber (ULN2003A) lassen im ausgeschalteten Zustand einen Reststrom von einigen Mikroampere durch, und weil immer eine Spalte unter Spannung steht, genügt das einer modernen LED zum Glimmen. Eine Glühlampe zeigt das nie. Die Original-MPU hat denselben Reststrom.

Gegenmittel an der betroffenen Fassung: **ein Widerstand von etwa 2,2 kΩ (½ W) parallel zur Lampe** — er leitet den Reststrom ab, ohne die Lampe im Betrieb zu beeinflussen. Ebenso wirksam: an dieser Stelle eine Glühlampe verwenden oder eine LED-Ersatzlampe mit eingebautem Ableitwiderstand („ghost free").

### 4.3. Sechs der zehn DIPs werden nur beim Einschalten gelesen

**Das ist der Punkt, über den die meisten stolpern.**

Die ersten sechs Schalter — die drei der Spielauswahl, Freispiel sowie Option 1 und 2 — haben keine eigenen sechs Leitungen. Sie werden über eine kleine 3 × 2-Matrix eingelesen, und diese Matrix leiht sich dafür drei Leitungen, die eigentlich den Lampentreibern gehören. Ein fortlaufendes Einlesen würde die Lampen flackern lassen; deshalb wird genau einmal gelesen, während des Startvorgangs, bevor das Spiel anläuft. Danach gehen die drei Leitungen zurück an die Lampen.

**Also: nach dem Ändern von Spielauswahl, Freispiel oder Option 1 / 2 den Automaten aus- und wieder einschalten.** Eine Änderung im laufenden Betrieb bleibt wirkungslos.

Die übrigen vier Schalter — Option 3 bis 6 — haben eigene Leitungen und werden fortlaufend gelesen. Sie können jederzeit verstellt werden.

## 5. Der Startvorgang

### 5.1. Phase 1: die DIP-Schalter werden gelesen

Unmittelbar nach dem Einschalten, sobald der interne Takt eingerastet ist, liest die Platine die ersten sechs DIP-Schalter über die Strobe-Matrix ein. Das dauert Mikrosekunden und ist nicht zu sehen. Die Anzeigen bleiben bis hierher dunkel.

### 5.2. Phase 2: die Info-Anzeige

Ist der DIP-Einlesevorgang fertig, gehen die Anzeigen an und zeigen für **etwa fünf Sekunden** die Konfiguration. Der Prozessor wird in dieser Zeit noch im Reset gehalten — das Spiel hat also noch nicht begonnen.

| Anzeige         | Zeigt                                                             |
|-----------------|-------------------------------------------------------------------|
| **Spieler 1**   | Version des FPGA-Programms, drei Ziffern: `<Platine> <Sub1> <Sub2>` |
| **Spieler 2**   | Wert der Spielauswahl, zweistellig, 00 bis 07                     |
| **Spieler 3**   | die sechs Optionsschalter, Option 1 links, Option 6 rechts — `1` = ON |
| **Spieler 4**   | Freispiel: `1` = aktiv, `0` = nicht aktiv                         |
| **Credit/Ball** | dunkel                                                            |

Alles steht rechtsbündig, die nicht benutzten Stellen bleiben dunkel.

Beispiel: Spieler 1 zeigt `033`, Spieler 2 zeigt `02`, Spieler 3 zeigt `000000`, Spieler 4 zeigt `0` — das ist Software 0.3.3 auf der Standardplatine, Airborne Avenger, keine Optionen gesetzt, kein Freispiel.

**Die erste Ziffer der Version sagt Ihnen, welche Platinen-Variante Sie haben**, siehe Kapitel 12. `0` ist die Standard-AtariFA-Platine.

Etwa zwei Sekunden nach Beginn dieses Fensters meldet sich die Platine über den bordeigenen Verstärker mit ihrem Namen — siehe Kapitel 8.3.

**Nutzen Sie diese Anzeige.** Sie ist der schnellste Weg zu sehen, ob die DIP-Schalter wirklich so stehen, wie Sie denken — und da sechs von ihnen ohnehin nur hier gelesen werden, ist sie die einzige Stelle, an der sich das überhaupt kontrollieren lässt.

### 5.3. Phase 3: das Spiel läuft

Nach dem Info-Fenster wird der Prozessor freigegeben und das Spiel startet. Ab hier gehören die Anzeigen dem Spiel und verhalten sich genau wie mit einer originalen Atari-MPU.

Die Spiel-ROMs liegen im FPGA; es wird nichts geladen, und es gibt keine Wartezeit.

## 6. Spieleinstellungen und Selbsttest

Die Einstellungen werden genau so vorgenommen wie bei der originalen Atari-MPU. AtariFA bildet die originale Einstell-Hardware 1:1 nach und ersetzt sie nicht durch ein Menü.

### 6.1. Die Programmier-DIP-Bänke und der Replay-Schalter

Die Platine trägt die beiden Bänke mit je acht Programmier-DIP-Schaltern und den Drehschalter „Replay", die auch die originale Atari-MPU hat — an derselben Stelle im Adressraum. Stellen Sie sie nach dem Handbuch Ihres Flipperautomaten ein; AtariFA reicht sie dem Spielprogramm genau so weiter wie das Original.

**Nicht mit den zehn Konfigurations-DIPs aus Kapitel 4 verwechseln.** Die zehn Schalter konfigurieren *AtariFA*, die beiden Achterbänke und der Replay-Schalter konfigurieren *das Spiel*.

Zusätzlich gibt es drei Taster auf der Platine, parallel zum Automaten verdrahtet: **„Atari Test", „Coin 2" und „Start"**. Damit lässt sich die Platine auf dem Werktisch ohne Münztür betreiben und prüfen.

### 6.2. Der Selbsttest

Betätigen Sie den Testschalter — entweder den in der Münztür oder den auf der Platine. Das Spiel geht in seinen Selbsttest, und Sie können nach dem Handbuch Ihres Flipperautomaten Schaltertest, Lampentest, Spulentest und Anzeigen durchgehen.

**Ausnahme: The Atarians.** Ataris erstes Spiel hat keinen dokumentierten Selbsttest und reagiert nicht auf den Testschalter. Das ist kein Fehler von AtariFA.

### 6.3. Credits und Highscores bleiben nicht erhalten

Beim Ausschalten des Automaten sind Credits und Spielstände weg. **Die originale Atari-Generation-1-MPU verhält sich genauso** — anders als spätere Geräte hat sie überhaupt keinen batteriegepufferten Speicher.

Auf der Platine sitzt zwar ein FRAM-Baustein, um das zu ändern, aber diese Funktion ist noch nicht fertig und in dieser Software-Version abgeschaltet. Siehe Kapitel 13.

Wenn der Automat ohne Münzeinwurf starten soll, verwenden Sie Freispiel — Kapitel 7.

## 7. Freispiel

Schalter 4 der 4er-Bank, **ON = Freispiel aktiv**. Denken Sie daran, dass dieser Schalter nur beim Einschalten gelesen wird — nach dem Umstellen also aus- und wieder einschalten.

Freispiel funktioniert bei **allen fünf Spielen**. Atari hat die Freispiel-Ausführung als anderen ROM-Satz verkauft; AtariFA hat diese Unterschiede eingebaut und legt sie über das Spiel-ROM, sobald der Schalter auf ON steht. Über alle fünf Spiele hinweg unterscheiden sich nur 42 Bytes — deshalb passt das, ohne einen zweiten ROM-Satz im FPGA vorhalten zu müssen.

Das Ergebnis ist Byte für Byte derselbe Code, den die originalen Freispiel-ROMs enthalten.

## 8. Ton

### 8.1. Was nachgebildet wird

Die Tonerzeugung der Atari Generation 1, so wie sie auf der MPU-Platine und dem Auxiliary Board sitzt:

- **ein Wellenform-ROM** mit 16 Wellenformen zu je 32 Abtastwerten, vom Spiel ausgewählt
- **ein Tonhöhen-Teiler**, der die Note bestimmt
- **ein Lautstärke-Latch**, das den Abschwächer auf dem Auxiliary Board ansteuert

Das Spiel beschreibt drei Latches für Wellenform, Tonhöhe und Lautstärke — genau wie im Original —, und AtariFA erzeugt den daraus entstehenden Ton digital.

Das ist der vollständige Ton eines Atari-Generation-1-Automaten: Diese Spiele haben keine eigene Soundplatine und keine Sprachausgabe.

### 8.2. Die zwei Tonwege

Eingestellt wird mit Option 3, siehe Kapitel 4.2.1: entweder der Originalweg über das Auxiliary Board (Schalter OFF) oder der Verstärker auf der Platine (Schalter ON). Beide erzeugen dieselben Töne; sie unterscheiden sich nur darin, wo das analoge Signal entsteht.

**Ein Hinweis dazu, wie die Spiele den Ton abschalten.** Das Spielprogramm setzt die Lautstärke nicht auf null, wenn ein Ton enden soll — es zieht die Leitung „Audio Reset" und lässt das Lautstärke-Latch stehen, wo es war. AtariFA bildet das nach: Audio Reset friert die Tonerzeugung ein, dadurch wird das Ausgangssignal ein konstanter Pegel, und den blockiert das Auxiliary Board. Wenn Sie einen Dauerton hören, der nie aufhört, liegt das an der Verdrahtung der Audioleitungen zum Auxiliary Board und nicht an der Lautstärke.

### 8.3. Die Ansage beim Einschalten

Etwa zwei Sekunden nach dem Einschalten, während des Info-Fensters, sagt die Platine über den bordeigenen Verstärker **„Lisü"**. Die Ansage ist fest hinterlegt, sie kommt einmal, und sie zeigt Ihnen, dass das FPGA läuft und die Tonkette auf der Platine funktioniert.

Sie kommt **immer aus dem Verstärker auf der Platine**, unabhängig von Option 3 — sie gehört nicht zum Spielton und erreicht das Auxiliary Board nie.

Hören Sie hier nichts, prüfen Sie zuerst den Verstärker auf der Platine und dessen Lautsprecheranschluss, bevor Sie woanders suchen.

### 8.4. Hintergrundmusik vom MP3-Spieler

Seit Software 0.3.0 kann der kleine MP3-Spieler auf der Platine (ein „MP3-Mini-Player" mit eigener Speicherkarte) **während eines laufenden Spiels** Hintergrundmusik abspielen. Eingeschaltet wird das mit **Option 1**, Kapitel 4.2.3; ab Werk ist es aus.

**Was auf die Speicherkarte gehört.** Legen Sie einen Ordner **`02`** an und stellen Sie Ihre Titel durchnummeriert hinein:

```
/02/001.mp3
/02/002.mp3
...
```

Der Spieler spielt diesen Ordner in Schleife, in seiner eigenen Reihenfolge. Es gibt keine Auswahl je Spiel und keinen Zufallsmodus. Wer auch eine GottFA1_PLuS-Platine betreibt, kann dieselbe Karte verwenden.

**Was im Betrieb passiert.** Die Platine richtet sich nach dem **Outhole-Schalter**: die Musik läuft, solange keine Kugel im Outhole liegt. Sie setzt also ein, wenn die Kugel zum Spielbeginn ausgeworfen wird, und pausiert, wenn die letzte Kugel unten liegen bleibt. Beim nächsten Spiel läuft sie dort weiter, wo sie aufgehört hat, statt von vorn zu beginnen.

Damit sie beim Ballwechsel nicht ständig aussetzt, reagiert die Platine erst nach **zwei Sekunden**. Wird die Kugel schneller wieder ausgeworfen, läuft die Musik durch; dauert die Bonuszählung länger, macht sie eine kurze Pause und kommt mit dem nächsten Ball zurück. Aus demselben Grund beginnt die Musik zwei Sekunden nach dem Spielstart und endet zwei Sekunden nach dem letzten Ball.

**Ein Tilt pausiert die Musik nicht sofort** — sie läuft, bis die Kugel unten liegt. (Bis Software 0.3.0 richtete sich die Platine nach dem Flipperrelais und stoppte beim Tilt sofort. Dieses Relais gibt es aber nur bei Middle Earth und Space Riders, deshalb der Wechsel.)

**Liegt beim Einschalten keine Kugel im Outhole** — etwa weil sie in der Schusslane oder auf dem Spielfeld liegt —, spielt die Musik auch im Attract-Modus. Kugel in den Outhole legen oder ein Spiel starten und beenden, dann ist wieder Ruhe.

**Der Spielton bleibt unberührt.** Musik und Spielton sind zwei getrennte Analogwege, die erst am Verstärker zusammenlaufen. Die Töne aus Kapitel 8.1 spielen über der Musik; es wird nichts ausgeblendet und nichts stummgeschaltet. Das Verhältnis stellen Sie über die Lautstärke des Spielers und die Lautstärke Ihres Automaten ein.

**Wenn Sie nichts hören:** der Schalter wird nur beim Einschalten gelesen — nach dem Umstellen von Option 1 also aus- und wieder einschalten. Prüfen Sie außerdem, ob der Ordner wirklich `02` heißt, ob die Karte im Spieler steckt, und ob die Info-Anzeige die Version **033** zeigt — auf den beiden „dev_open"-Platinen entsprechend **133** oder **233**, Kapitel 5.2.

**Geben Sie ihr Zeit.** Die Platine lässt dem Spieler nach dem Einschalten fünf Sekunden zum Hochlaufen, meldet sich dann bei ihm an und wartet noch die Entprellung ab. Bis zum ersten Ton vergehen dadurch **rund 15 Sekunden**. Wer vorher aufgibt, hält ein funktionierendes Modul für defekt.

Bleibt es danach still, obwohl eine Kugel im Spiel ist, prüfen Sie die Spielauswahl (Anhang A) noch einmal — die Platine liest je nach eingestelltem Spiel einen anderen Outhole-Schalter.

## 9. Die FA-Control-Schnittstelle (ESP32)

Auf der Platine ist ein Steckplatz für ein **ESP32-C3 Super Mini** vorbereitet. Darauf läuft **FA-Control** — eine kleine Firmware, die ein WLAN aufmacht und im Browser eine Testoberfläche anbietet: jede Lampe einzeln schalten, jede Spule pulsen, alle Schalter live mitlesen, Ziffern auf die Displays schreiben, Töne abspielen.

Das ist ein **Werkzeug für die Werkbank und die Fehlersuche**, kein Zubehör für den Spielbetrieb. Wer nichts einsteckt, merkt von dieser Schnittstelle nichts — die Platine verhält sich exakt so wie ohne.

> Diese Funktion ist neu in Software-Version 0.1.3 und am Automaten erprobt.

### 9.1. Die Freigabe: Option 4

Ein Testgerät soll nicht ungefragt in ein laufendes Spiel eingreifen können. Deshalb müssen **zwei Dinge** zusammenkommen:

1. Das ESP32-Modul fragt aktiv an („ich möchte übernehmen").
2. **Option-DIP 4 steht auf ON.**

Steht Option 4 auf OFF, meldet die Weboberfläche im Klartext *„Kontrolle verweigert — Option-DIP 4 auf ON stellen"*, und das Spiel läuft ungestört weiter. Lesen darf das Modul trotzdem: Schalterzustände lassen sich also auch bei laufendem Spiel mitverfolgen, ohne etwas freizugeben.

### 9.2. Was während der Übernahme passiert

**Das Spiel wird angehalten.** Der Prozessor geht in den Reset, und alles — Lampen, Spulen, Displays, Ton — kommt ab sofort aus der Weboberfläche. Das muss so sein: liefe das Spiel weiter, würde es jede von Hand gesetzte Testlampe nach wenigen Millisekunden wieder überschreiben.

**Das Spiel beginnt danach von vorn.** Es lässt sich nicht anhalten und fortsetzen. Ein laufendes Spiel geht also verloren — übernehmen Sie die Kontrolle nur im Attract Mode oder auf der Werkbank.

### 9.3. Wie die Kontrolle wieder zurückgeht

Auf drei Wegen, und alle drei führen sofort dazu, dass alle Ausgänge abfallen und das Spiel neu startet:

- **In der Weboberfläche** auf „Kontrolle zurückgeben".
- **Option-DIP 4 auf OFF stellen.** Der Schalter wird fortlaufend gelesen — das ist der Not-Aus.
- **Nichts tun.** Meldet sich das Modul zwei Sekunden lang nicht mehr, gibt AtariFA von selbst zurück. Das ist die Sicherung für den Fall, dass das Modul sich aufhängt, neu startet oder den Kontakt verliert — der Automat bleibt dann nicht in der Übernahme hängen, sondern läuft wieder als Flipper an.

### 9.4. Was die Weboberfläche von der Platine erfährt

Beim Verbinden fragt FA-Control die Ausstattung ab und stellt sich selbst darauf ein — es muss nichts von Hand eingetragen werden. Bei AtariFA kommt zurück:

| | |
|---|---|
| Kennung | `AtariFA` |
| Software-Version | dieselbe wie auf der Info-Anzeige, z. B. `0.3.3` |
| Lampen | 84 |
| Spulen | 22 (20 Spielfeld + Münzzähler + Sperrspule) |
| Schalter | 80 |
| Töne | 16 |
| Displays | 5 (Status mit 4 Stellen, vier Spieler mit je 6) |

Die Nummerierung folgt dabei der Platine: Schalter tragen dieselbe Nummer wie im Selbsttest des Spiels, und **Spule 1 bis 20 sind die Treiber Q1 bis Q20 des Schaltplans**, 21 der Münzzähler und 22 die Sperrspule. Die Spulen sind die einzige Gruppe, die bei 1 anfängt — so zählt sie das Original, und so zählt sie das LISY-Protokoll. Lampen (0 bis 83) und Schalter (0 bis 79) beginnen bei 0. *(Bis Version 0.1.9 begannen auch die Spulen bei 0; wer eine ältere FA-Control-Firmware als 1.16 benutzt, löst damit die falsche Spule aus.)*

### 9.5. Anschluss

Das ESP32-Modul wird nur aufgesteckt; es sind keine Kabel zu löten. Versorgt wird es von der Platine — **im Betrieb wird kein USB-Kabel gebraucht.** Eines anzustecken ist nur zum Aufspielen der FA-Control-Firmware oder zum Mitlesen des Boot-Logs nötig. Für die Ersteinrichtung des WLAN macht FA-Control beim ersten Start einen eigenen Zugangspunkt auf — Näheres in der Anleitung von FA-Control selbst.

## 10. Die Status-LEDs

Die Platine hat drei Status-LEDs, parallel zu den LEDs der Huckepack-Platine geschaltet. Sie sind die schnellste Diagnose ohne Logikanalysator.

| LED    | Bedeutung                                                                 |
|--------|---------------------------------------------------------------------------|
| **D1** | Watchdog: leuchtet und bleibt an, sobald der interne Watchdog mindestens einmal angesprochen hat. **Dunkel ist der Normalzustand.** |
| **D2** | Der Prozessor holt Befehle aus dem ROM — blinkt langsam, je nach Spiel einige Sekunden je Phase. **Steht die LED, hell oder dunkel, dann steht der Prozessor.** |
| **D3** | Der NMI-Zeitgeber läuft — blinkt mit 0,48 Hz, also gut eine Sekunde hell und gut eine Sekunde dunkel. Das ist freilaufende Hardware und hängt nicht vom Prozessor ab. |

Lesen Sie die drei zusammen:

- **D2 und D3 blinken** — Platine und Spiel leben. So soll es aussehen.
- **D3 blinkt, D2 steht** — die Hardware läuft, aber der Prozessor arbeitet nicht. Spielauswahl und Reset-Taster prüfen.
- **Nichts blinkt** — das FPGA ist nicht programmiert oder hat keinen Takt. Neu programmieren (Kapitel 11).

## 11. Das FPGA programmieren

Alles, was Sie brauchen, um die Software auf die Platine zu bekommen, ist auf meiner Website beschrieben und wird dort aktuell gehalten:

> **<https://lisy.dev/documentation-01.html>**

Dort finden Sie das aktuelle FPGA-Programm zum Herunterladen, welche Programmiersoftware Sie benötigen, wie der Treiber für den USB-Blaster installiert wird und wie das FPGA programmiert wird.

**Achten Sie darauf, die AtariFA-Fassung zu nehmen** — und, falls es mehrere gibt, die für Ihre Platinen-Variante, siehe Kapitel 12. Welche Variante gemeint ist, steht als erste Ziffer der Version auf der Info-Anzeige.

Für AtariFA gibt es kein SD-Karten-Abbild. Die Spiel-ROMs sind Teil des FPGA-Programms.

## 12. Platinen-Varianten

Dasselbe Design läuft auf drei Huckepack-Platinen. Das FPGA-Programm ist zwischen ihnen **nicht** austauschbar — die Pinbelegung unterscheidet sich, und bei der dritten sitzt ein FPGA aus einer anderen Familie.

| Variante | Platine | FPGA | Version beginnt mit |
|---|---|---|---|
| `cyclone_10_pcb` | AtariFA-Platine v1.x mit der lisy.dev-Cyclone-10-Huckepackplatine | Cyclone 10 LP | **0** |
| `cyclone_10_dev_open` | AtariFA-Platine v1.x mit der „dev_open"-Cyclone-10-Platine | Cyclone 10 LP | **1** |
| `cyclone_IV_dev_open` | dieselbe „dev_open"-Platine, aber mit Cyclone IV bestückt | Cyclone IV E | **2** |

**Die Info-Anzeige sagt Ihnen, welches Programm läuft:** Die erste der drei Versionsziffern auf der Anzeige von Spieler 1 ist die Platinennummer. Haben Sie das falsche Programm geladen, bleiben die Anzeigen höchstwahrscheinlich dunkel oder zeigen Unsinn — prüfen Sie dann zuerst diese Ziffer.

Abgesehen von der Pinbelegung sind alle drei gleich, mit zwei kleinen Unterschieden auf der Huckepackplatine selbst: Bei den beiden „dev_open"-Platinen sitzen der Reset-Taster und alle vier Status-LEDs auf der Huckepackplatine (die vierte ist Reserve und bleibt dunkel), und sie führen 3 statt 8 Debug-Leitungen auf den Stecker für den Logikanalysator. Die beiden „dev_open"-Fassungen unterscheiden sich nur im bestückten FPGA und in zwei Pins, die auf dem Cyclone IV anders liegen.

**Erprobungsstand.** Am Automaten gespielt ist bisher nur `cyclone_10_pcb`. `cyclone_10_dev_open` läuft seit Software 0.3.0 auf dem Prüfstand — Start, Info-Anzeige und der MP3-Spieler sind dort bestätigt, alles übrige hängt an der Verdrahtung zum Automaten und ist ungeprüft. `cyclone_IV_dev_open` ist gebaut, aber noch nie auf Hardware gelaufen.

## 13. Noch nicht implementiert

Das Folgende ist auf der Platine vorhanden und verdrahtet, wird von dieser Software-Version aber nicht genutzt. Es tut nichts, und es schadet nichts — das FPGA hält es in einem sicheren Ruhezustand.

- **FRAM (Credits und Highscores über das Ausschalten hinweg).** Der Baustein ist bestückt und die Ansteuerung funktioniert, aber es zuverlässig für alle fünf Spiele hinzubekommen erfordert mehr Analyse der Spiel-ROMs als erwartet. Die Funktion ist abgeschaltet. Optionsschalter 1, der sie früher gesteuert hat, ist seit Software 0.3.0 der Schalter für die Hintergrundmusik, Kapitel 4.2.3. Siehe Kapitel 6.3.

## Anhang A 'game select'

Schalter der **4er-Bank**. Dip4 dieser Bank ist Freispiel und gehört nicht zur Spielnummer.

| **Nr** | **Dip1** | **Dip2** | **Dip3** | **Spiel**           | **Jahr** |
|-------:|----------|----------|----------|---------------------|----------|
|      0 | off      | off      | off      | The Atarians        | 1976     |
|      1 | on       | off      | off      | Time 2000           | 1977     |
|      2 | off      | on       | off      | Airborne Avenger    | 1977     |
|      3 | on       | on       | off      | Middle Earth        | 1978     |
|      4 | off      | off      | on       | Space Riders        | 1978     |
|    5–7 | –        | –        | –        | nicht belegt, fällt auf Middle Earth zurück | |

Alle fünf laufen auch mit Freispiel (Kapitel 7).

**The Atarians** hat keinen Selbsttest — siehe Kapitel 6.2.

## Anhang B Kurzübersicht

**Die zehn Konfigurationsschalter**

```
4er-Bank                            6er-Bank
 1  Spielauswahl Bit 0  (+1)         1  Hintergrundmusik    beim Einschalten
 2  Spielauswahl Bit 1  (+2)         2  reserviert          beim Einschalten
 3  Spielauswahl Bit 2  (+4)         3  Tonweg              fortlaufend
 4  Freispiel, ON = aktiv            4  FA-Control erlaubt  fortlaufend
                                     5  Lampen-Totzeit  \  fortlaufend
 alle vier nur beim Einschalten      6  Lampen-Totzeit  /  fortlaufend
```

**Hintergrundmusik, Option 1:** OFF = aus (Standard) · ON = der MP3-Spieler spielt den Ordner `02`, solange eine Kugel im Spiel ist (Kapitel 8.4)

**Tonweg, Option 3:** OFF = Auxiliary Board (Standard) · ON = Verstärker auf der Platine

**FA-Control, Option 4:** OFF = niemand redet dazwischen (Standard) · ON = das ESP32-Testwerkzeug darf die Anlage steuern (Kapitel 9)

**Lampen-Totzeit, Optionen 5 und 6 gemeinsam** (Kapitel 4.2.4) — gegen glimmende LED-Ersatzlampen die kleinste Stufe nehmen, die wirkt:

| Option 5 | Option 6 | Totzeit | Helligkeit |
|---|---|---|---|
| OFF | OFF | etwa 65 µs (Standard) | 21,8 % |
| OFF | ON | etwa 250 µs | 12,8 % |
| ON | OFF | keine — Zeitverhalten der Original-MPU, LEDs glimmen wie am Original | 24,5 % |
| ON | ON | etwa 400 µs, sichtbar dunkler | 5,5 % |

Glimmt es auch bei 400 µs weiter, liegt es nicht an der Software — Kapitel 4.2.5.

**Nach dem Ändern eines Schalters, der beim Einschalten gelesen wird: aus- und wieder einschalten.**

**Die Info-Anzeige, die ersten 5 Sekunden nach dem Einschalten**

```
Spieler 1   0 3 3      Version, erste Ziffer = Platinen-Variante
Spieler 2      0 2     Spielauswahl  (Anhang A)
Spieler 3   000000     Optionen 1..6, von links nach rechts, 1 = ON
Spieler 4        0     Freispiel, 1 = aktiv
Credit      (dunkel)
```

**LEDs:** D1 Watchdog (dunkel = gut) · D2 Prozessor läuft (blinkt langsam) · D3 NMI-Zeitgeber (blinkt ~0,48 Hz)

**Credits und Spielstände überleben das Ausschalten nicht** — wie bei der originalen Atari-MPU.
