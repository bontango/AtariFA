# Hintergrundmusik über den DFPlayer Mini

> Recherche und Umsetzung 2026-08-20, ausgeliefert mit **SW 0.3.0**.
> Portiert aus **GottFA1_PLuS** (`N:\Projekte\FPGA System1\FPGA_source`), wo die Funktion
> seit Längerem im Feld läuft. Der einzige Teil, der sich nicht kopieren ließ, ist der
> Trigger — Atari Gen1 hat kein Game-Over-Relais. Kapitel 2 leitet den Ersatz her.

---

## 1. Was auf der Platine schon da war

| Baustein | Bezeichner | Anschluss |
|---|---|---|
| DFPlayer Mini (MP3-Modul mit eigener microSD, DAC und kleiner Endstufe) | `Audio1` | eigener Analogausgang in den Onboard-**TDA7267** |
| einzige Steuerleitung vom FPGA | **`SB_Audio`** | `cyclone_10_pcb` **PIN_7**, `cyclone_10_dev_open` **PIN_111** |

Bis SW 0.2.1 lag die Leitung tot auf `'0'` („SB_Audio: separater MP3/Background-Pfad — nicht
Teil der Emulation"), und beide Handbücher führten den Pfad unter „noch nicht implementiert".
Es gibt **keine Rückleitung** — kein `BUSY`, kein RX vom Player. Der Wiedergabezustand wird
deshalb im FPGA mitgeführt.

Musik aus dem FPGA-Speicher wäre ohnehin keine Option gewesen: der Baum liegt bei
**26 von 30 M9K** (87 % der Implementierungsbits), allein das 0,46 s lange Bootwort „Lisü"
belegt 4 M9K. Ein externes Modul ist hier nicht bequem, sondern alternativlos — und es ist
bestückt.

---

## 2. Woran man bei Atari „Spiel aktiv" erkennt

Gottlieb System 1 hat ein **Game-Over-Relais**, das GottFA1_PLuS direkt als Trigger abgreift.
Atari Gen1 hat so ein Relais nicht. Gesucht war also ein Signal, das

* über alle fünf unterstützten Spiele gleich funktioniert,
* im FPGA schon vorliegt (kein zusätzlicher Decode, kein zusätzlicher Pin),
* und „Spiel läuft" wirklich meint — nicht bloß korreliert.

### 2.1 Die Antwort: Flipper Control Relay = Q12 = Latch `0x1088` Bit 6

Vier unabhängige Belege:

| Quelle | Aussage |
|---|---|
| Space-Riders-Handbuch, Tabelle 5-6 | `FLIPPER CONTROL RELAY (A)1088 D6` |
| Space-Riders-Selbsttest und Fehlersuchtabelle | Spulentest **Nr. 12** = „Flipper Relay"; bei toten Flippern „troubleshoot Processor PCB driver **Q12**" |
| [`solenoid_mapping.txt`](solenoid_mapping.txt) (aus dem AtariFA-Schaltplan) | `solenoids(12) = 0x1088 bit6 = F_Q12` |
| Middle-Earth-ROM ([`../tools/listing.txt`](../tools/listing.txt)) | siehe unten |

Middle Earth macht es inline und damit besonders gut lesbar. **Spielstart:**

```
7F36  96 88     LDAA $88      ; Schattenkopie von Latch 3 (0x1088 spiegelt RAM 0x88)
7F38  8A 40     ORAA #$40     ; Bit 6 setzen = Flipperrelais AN
7F3A  B7 10 88  STAA $1088
7F3D  86 FF     LDAA #$FF     ; danach Display/Ball initialisieren
```

**Game Over:**

```
77B5  96 1C     LDAA $1C      ; Ballnummer
77B7  4C        INCA
77B8  91 22     CMPA $22      ; == Bälle pro Spiel?
77BA  26 0A     BNE  $77C6    ; nein -> nächster Ball
77BC  7F 10 88  CLR  $1088    ; ja  -> Flipperrelais AUS
77BF  86 11     LDAA #$11
77C3  7E 7C 33  JMP  $7C33    ; Match/Attract
```

Und der Tilt-Zweig, der dasselbe Bit bedient:

```
7341  96 2A     LDAA $2A
7343  2B 09     BMI  $734E
7345  96 88     LDAA $88
7347  8A 40     ORAA #$40     ; Relais AN
7349  B7 10 88  STAA $1088
734E  96 88     LDAA $88
7350  84 BF     ANDA #$BF     ; Relais AUS
7352  20 F5     BRA  $7349
```

### 2.2 Auch die anderen vier Spiele treiben dieses Bit

Sie tun es nicht inline, sondern über eine generische Routine „Bit setzen/löschen an
`$1000 + A`". Bei Airborne Avenger:

```
7B5C  A6 00     LDAA $00,X    ; Latch-Offset aus der Tabelle
7B5E  E6 01     LDAB $01,X    ; Bitmaske aus der Tabelle
7B60  CE 10 00  LDX  #$1000
7B63  BD 7C E7  JSR  $7CE7    ; X := X + A
7B66  EA 00     ORAB $00,X
7B68  E7 00     STAB $00,X

7CE7  DF 19     STX  $19      ; die Additionsroutine
7CE9  9B 1A     ADDA $1A
7CEB  97 1A     STAA $1A
7CED  24 03     BCC  $7CF2
7CEF  7C 00 19  INC  $0019
7CF2  DE 19     LDX  $19
7CF4  39        RTS
```

Die zugehörigen Spulentabellen bestehen aus 2-Byte-Einträgen `(Latch-Offset, Bitmaske)`.
Jede von ihnen enthält den Eintrag **`88 40`**:

| Spiel | Tabelle ab | Eintrag `88 40` bei |
|---|---|---|
| The Atarians | `7F90` | `7F98` |
| Time 2000 | `7EAD` | `7EB1` |
| Airborne Avenger | `7EA0` | `7EA4` |
| Space Riders | `75FA` | `7614` |
| Middle Earth | — (inline) | `7F36` / `77BC` |

Damit ist der Trigger board- statt spielabhängig, und im Top-Level liegt er als
`sol_ah(12)` ohnehin schon an.

### 2.3 Bewusste Nebenwirkung: Tilt

Das Relais fällt beim Tilt ab (Zweig `7341` oben). Die Musik hört dann auf und setzt beim
nächsten Ball wieder ein. Das ist originalgetreu und gewollt.

### 2.4 Warum nicht der Outhole-Schalter

Naheliegend, aber untauglich: der Outhole-Schalter ist im **Attract-Modus geschlossen** (die
Kugel liegt darin) und schließt während des Spiels bei **jedem** Drain — „Ball 2 verloren"
sieht genauso aus wie „letzter Ball verloren". Man bräuchte eine eigene Zustandsmaschine mit
Start-Taster und Ballzähler, und die Schalternummer ist zusätzlich spielabhängig (Atarians 19,
Time 2000 53, Airborne 67, Middle Earth 56, Space Riders 56).

### 2.5 Ebenfalls geprüft: die Player-up-LED

`display1..4(6) = x"8"` (RAM `0x03/0x07/0x0B/0x0F`, unteres Nibble) ist die zweite brauchbare
Quelle — spielunabhängig, im Display-Sniffer schon vorhanden und an der Maschine mit bloßem
Auge prüfbar: leuchtet keine Player-up-LED, läuft kein Spiel. Sie wurde nicht genommen, weil
sie im Selbsttest mitlaufen kann (dort stehen Testwerte in den Score-Bytes). Als Reserve ist
sie notiert — der Wechsel wäre eine Zeile in `top/AtariFA.vhd`.

---

## 3. Umsetzung

### 3.1 `rtl/common/dfplayer_cmd.vhd`

Kommando-FSM, portiert aus GottFA1_PLuS `rtl/common/DFPlayer_Mini_CMD.vhd` (v0.5). Ein
Unterschied: dort schiebt ein handgebautes 80-Bit-Register an einem eigenen 9600-Hz-Takt,
hier sendet das im Baum vorhandene **`work.UART_TX`** (`rtl/fa_control/uart_tx.vhd`, sonst
für den ESP32 mit 115200 Baud im Einsatz) mit `g_CLKS_PER_BIT = 5208` in der
`clk_50`-Domäne. Kein zweiter Takt, nichts für die SDC.

**Rahmenformat** — laut Datenblatt 10 Byte, davon zwei Prüfsummenbytes:

```
7E FF 06 <cmd> 00 <par1> <par2> [csumH csumL] EF
```

Gesendet werden wie bei GottFA nur die **8 Byte ohne Prüfsumme**. Der Player akzeptiert das;
so läuft es dort im Feld.

**Kommandos**

| Kommando | Wann | Parameter |
|---|---|---|
| `0x42` Status abfragen | einmal nach dem Boot, weckt den Player | — |
| `0x06` Lautstärke | einmal nach dem Boot, wenn `SET_VOLUME` | `par2 = VOLUME` (0…30) |
| `0x17` repeat folder | Musik zum ersten Mal starten | `par2 = FOLDER` |
| `0x0D` play/resume | Trigger wieder `'1'`, es lief schon einmal | — |
| `0x0E` pause | Trigger `'0'` | — |

**Ablauf:** `st_Boot → st_InitCmd → st_Idle → st_Delay → st_Decide → st_Send/st_Wait → st_Idle`

| Generic | Vorgabe | Bedeutung |
|---|---|---|
| `CLKS_PER_BIT` | 5208 | 50 MHz / 9600 Baud |
| `START_DELAY` | 100 000 000 | 2 s, bis der Player hochgelaufen ist (dasselbe Mittel wie in `speech.vhd`) |
| `GLITCH_CYCLES` | 25 000 000 | 500 ms Entprellung des Triggers |
| `FOLDER` | 2 | SD-Ordner `02`, wie bei GottFA1_PLuS |
| `SET_VOLUME` / `VOLUME` | true / 20 | Lautstärke einmalig setzen (sonst gilt die im Player gespeicherte) |

`GLITCH_CYCLES` ist die wichtigste Stellschraube: der Triggerwechsel wird nach der Wartezeit
**erneut geprüft** und nur dann übernommen. Bei Gottlieb fängt das die Relais-Aussetzer
zwischen den Bällen ab; hier sorgt es zusätzlich dafür, dass ein einzelner Spulenpuls aus der
COILS-Ansicht von FA-Control die Musik nicht startet.

### 3.2 Anbindung im Top-Level

```vhdl
flipper_relay <= fa_sol_ovr(11) when fa_ctrl_active = '1' else sol_ah(12);
music_enable  <= not options(1);          -- DIP ON wird als '0' gelesen

MUSIC: entity work.dfplayer_cmd
generic map( CLKS_PER_BIT => 5208 )
port map(
    clk_50    => clk_50,
    reset     => not io_live,
    trigger   => flipper_relay and music_enable,
    start_new => '0',
    txd       => SB_Audio
    );
```

Drei Entscheidungen, die dahinterstehen:

* **`flipper_relay` kommt aus demselben Mux wie der physische Ausgang.** Im Spiel aus dem
  `solenoid_driver`, bei einer FA-Control-Übernahme aus `fa_sol_ovr`. Damit ist Q12 am
  Prüfstand über die COILS-Ansicht schaltbar — man braucht keine Maschine, um den Trigger zu
  testen.
* **`reset => not io_live`, nicht `not reset_l_stable`.** Bei einer Übernahme steht die CPU,
  das Musikmodul muss aber noch das Pause-Kommando absetzen können. Das ist die Konvention
  des Baums für Peripherie.
* **`start_new => '0'`.** Die Musik läuft weiter, wo sie aufgehört hat (bei GottFA ist das
  Gottlieb-DIP 16 = OFF). `options(2)` bleibt frei, falls das später ein DIP werden soll.

### 3.3 Freigabe per DIP

**Options-DIP 1** = Hintergrundmusik EIN/AUS. Er kommt aus der Boot-Strobe-Matrix
(`read_the_dips.vhd`) und wird **nur beim Einschalten gelesen** — Umlegen im laufenden
Betrieb hat keine Wirkung, dazu ist ein Neustart nötig. Die Matrix ist damit voll belegt;
frei ist nur noch `options(2)`.

### 3.4 Kosten

Gegenüber SW 0.2.1: **Comb +158, Reg +92**, Memory unverändert bei 202 752 Bit, **kein
zusätzlicher Pin** (85/89 wie bisher). Der größte Einzelposten ist der 27-Bit-Wartezähler für
`START_DELAY`/`GLITCH_CYCLES`, dazu die 8 Rahmenbytes und `UART_TX`.

---

## 4. SD-Karte

Der Player spielt **Ordner `02`** in Endlosschleife (`0x17`), die Reihenfolge macht seine
eigene Firmware. Es wird keine Titelnummer gesetzt, nichts ist zufällig und nichts
spielabhängig. Kartenlayout also:

```
/02/001.mp3
/02/002.mp3
...
```

Dieselbe Karte funktioniert in GottFA1_PLuS und umgekehrt.

---

## 5. Was das Feature nicht tut

* **Kein Mixer, kein Ducking.** Spielsound (Aux-Board bzw. `SB_Sound`) und Musik sind
  getrennte Analogpfade, die erst auf der Platine zusammenlaufen. Die Musik spielt durch,
  während das Spiel tönt — wie bei GottFA1_PLuS.
* **Keine Titelauswahl je Spiel.**
* **Keine Rückmeldung vom Player.** Ob wirklich etwas abgespielt wird, weiß das FPGA nicht;
  `BUSY` ist nicht angeschlossen.

---

## 6. Prüfen

| Schritt | Erwartung |
|---|---|
| Boot-Info-Anzeige | `030` (bzw. `130` auf `cyclone_10_dev_open`) |
| Options-DIP 1 = ON, `SB_Audio` (PIN_7) am Logikanalysator | 9600 Baud, 8 Byte, erstes Telegramm `7E FF 06 42 00 00 00 EF` |
| FA-Control → COILS → Kachel 12 einmal antippen | **keine** Musik (Glitch-Filter) |
| FA-Control → Spule 12 dauerhaft ein | Musik startet nach ~0,5 s |
| Spiel starten | Musik setzt nach ~0,5 s ein |
| Letzten Ball verlieren | Musik pausiert |
| Tilt | Musik pausiert (erwartet, s. 2.3) |
| Attract-Modus | still |
| Options-DIP 1 = OFF, Neustart | nach dem Init kein Telegramm mehr, keine Musik |
