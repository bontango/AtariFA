# Hintergrundmusik über den DFPlayer Mini

> Recherche und Umsetzung 2026-08-20, ausgeliefert mit **SW 0.3.0**.
> **Trigger seit 2026-08-31 / SW 0.3.1 gewechselt: Outhole-Schalter statt Flipperrelais Q12.**
> **Kommandopfad seit SW 0.3.2 auf dem RecelFA-Stand v0.6** (vollständige Rahmen mit
> Prüfsumme, `0x16`, Pausen, `0x0D`-Nachschlag, 5 s Startverzögerung) — §3.1.
> **Damit spielt der Player: am 2026-08-31 am Prüfstand auf `cyclone_10_dev_open` bestätigt.**
> Bis 0.3.1 blieb er stumm. Am Automaten ist die Musik noch nicht erprobt — der Outhole-Trigger
> und seine fünf Schalternummern sind damit weiterhin offen (§2.3, §6.4).
> Portiert aus **GottFA1_PLuS** (`N:\Projekte\FPGA System1\FPGA_source`), wo die Funktion
> seit Längerem im Feld läuft. Der einzige Teil, der sich nicht kopieren ließ, ist der
> Trigger — Atari Gen1 hat kein Game-Over-Relais. Kapitel 2 leitet den Ersatz her; wer nur
> wissen will, warum der erste Ersatz nicht taugte, liest §2.5.

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

SW 0.3.0 nahm dafür das **Flipper Control Relay Q12**. Das war ein Fehlgriff: ein solches
Relais gibt es nur bei **Middle Earth und Space Riders**. Bei den anderen drei Spielen hängt an
demselben Bit etwas ganz anderes — bei The Atarians eine Kickerspule, bei Time 2000 und
Airborne Avenger ein zeitbegrenztes Gate. Der Trigger wäre dort nicht ungenau, sondern falsch:
die Musik ginge im Takt eines Kickers oder eines Gates an und aus (§2.5). **Seit SW 0.3.1 ist
der Trigger der Outhole-Schalter.**

### 2.1 Die Antwort: der Outhole-Schalter, invertiert

> **Die Musik läuft, solange keine Kugel im Outhole liegt.**

Der Outhole-Schalter ist ein Blattkontakt, den die dort liegende Kugel geschlossen hält. Damit
gilt ohne jede Zusatzlogik:

| Zustand der Maschine | Outhole | Musik |
|---|---|---|
| Attract-Modus, Kugel liegt unten | geschlossen | aus |
| Spiel gestartet, Kugel ausgeworfen | offen | an |
| Kugel im Spiel, in einem Kicker, in der Schusslane | offen | an |
| Kugel verloren, Bonuszählung läuft | geschlossen | s. §2.2 |
| Spiel vorbei, Kugel bleibt liegen | geschlossen | aus |

Das Signal liegt im Top-Level ohnehin an (`sw_state` aus `switch_matrix.vhd`) und kostet
weder einen Pin noch einen zusätzlichen Decode.

### 2.2 Warum „Ball 2 verloren" nicht aussieht wie „letzter Ball verloren"

Das war der Einwand, an dem der Outhole-Schalter in der ersten Fassung dieses Dokuments
scheiterte — und er trägt nicht. Die Unterscheidung muss der FPGA gar nicht treffen, **sie
steckt in der Maschine**: beim Ballwechsel wirft der Outhole-Kicker die Kugel wieder heraus,
am Spielende bleibt sie liegen. Es ist keine Zustandsfrage, sondern eine **Dauerfrage**.

Genau dafür ist `GLITCH_CYCLES` da: der Triggerwechsel wird nach der Wartezeit **erneut
geprüft** und nur dann übernommen. Ist die Kugel bis dahin wieder draußen, hat die Musik den
Ballwechsel nicht bemerkt. Seit 0.3.1 steht der Wert auf **2 s** (0.3.0: 500 ms).

Dauert die Bonuszählung länger als 2 s, pausiert die Musik eben doch und setzt mit dem
nächsten Ball wieder ein — auch das ist ein brauchbares Verhalten, keine Fehlfunktion. Die
2 s sind die Stellschraube am Automaten und kosten **keine Logik**: die Zählerbreite liegt
über `WAIT_MAX = max(START_DELAY, GLITCH_CYCLES)` ohnehin bei 100 000 000. Der Preis ist,
dass die Musik 2 s verzögert einsetzt und 2 s verzögert pausiert.

### 2.3 Die Schalternummer ist spielabhängig

Das ist der einzige Punkt, an dem der Outhole dem Relais unterlegen ist — es braucht einen
Mux über `game_sel`:

| Spiel | `game_idx` | CPU-Adresse | `sw_state`-Offset |
|---|---|---|---|
| The Atarians | 0 | `0x2032` | **50** (s. Kasten) |
| Time 2000 | 1 | `0x2035` | 53 |
| Airborne Avenger | 2 | `0x2043` | **67** (HW-verifiziert) |
| Middle Earth | 3 | `0x2038` | 56 |
| Space Riders | 4 | `0x2038` | 56 |

Quelle aller fünf Zeilen ist `Manuals\Atari Schalterzuordnungen und Kontakttestcodes.csv`
(Zeilen 13/20/30/36, Spalte des jeweiligen Spiels). Airborne ist zusätzlich HW-verifiziert:
auf genau diesem Offset lief am 2026-07-09 der FRAM-Save-Trigger an einer echten Maschine
([`FRAM_Persistence.md`](FRAM_Persistence.md), Stufe 1). Die übrigen vier sind an der Maschine
noch zu bestätigen — am schnellsten über die SWITCHES-Ansicht von FA-Control: Kugel in den
Outhole legen und nachsehen, welche Kachel schließt.

> **Korrektur: The Atarians ist 50, nicht 19.** In `FRAM_Persistence.md` und in der ersten
> Fassung dieses Dokuments stand für Atarians der Offset **19**. Das ist `0x2013` und damit der
> **Slam-Tilt** — bei allen fünf Spielen dieselbe Adresse, s. auch
> [`FA_Control_Names_Files.md`](FA_Control_Names_Files.md). Der Outhole steht in der CSV
> (Zeile 36) auf `0x2032` = 50. Gegenprobe im Atarians-ROM: `0x2032` wird zweimal gepollt
> (`76B4` und `76F0`, beide `LDX #$2032 / JSR $78D2` = Entprellroutine, dann Sprung in die
> Ball-Ende-Behandlung), `0x2013` dagegen nur einmal (`76BF`) im Slam-Tilt-Zweig. Vermutliche
> Ursache des alten Werts: in CSV-Zeile 26 steht **19** als *Manual-Schalternummer*, nicht als
> Offset.

Im Mux steht `game_sel` (geklemmt 0…4) und nicht `game_idx`, weil die unbenutzten DIP-Codes
5…7 mit dem Middle-Earth-ROM laufen. Gemuxt werden bewusst die **vier Kandidatenbits** und
nicht `sw_state(variabler Index)` — letzteres synthetisiert einen 80:1-Mux, so sind es drei
LUTs.

### 2.4 Was das Verfahren nicht kann

* **Kein sofortiger Tilt-Stopp.** Bei Q12 fiel das Relais mit dem Tilt ab und die Musik hörte
  auf der Stelle auf. Jetzt läuft sie weiter, bis die Kugel unten liegt. Originalgetreu ist
  ohnehin keine der beiden Varianten — Atari hat gar keine Musik.
* **Attract-Modus mit Kugel außerhalb des Outholes.** Wird der Automat eingeschaltet, während
  die Kugel in der Schusslane oder auf dem Spielfeld liegt, spielt die Musik im Attract-Modus.
  Eine Sperre („erst freigeben, wenn der Outhole einmal geschlossen war") wurde **bewusst
  nicht** eingebaut: sie würde bei einer falschen Schalternummer dauerhafte Stille erzeugen,
  und Stille ist der Fehler, den man am schwersten findet. So herum fällt eine falsche Nummer
  sofort auf — und am Prüfstand ohne Maschine (dort lesen alle Schalter „offen") beweist die
  laufende Musik, dass UART, Speicherkarte und Player in Ordnung sind.

### 2.5 Warum nicht das Flipperrelais Q12 (der Trigger von SW 0.3.0)

Q12 = Latch `0x1088` Bit 6. Als *Signal* ist es sauber belegt:

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

#### Der Fehlschluss

Die anderen vier Spiele tun es nicht inline, sondern über eine generische Routine „Bit
setzen/löschen an `$1000 + A`", gespeist aus einer Spulentabelle mit 2-Byte-Einträgen
`(Latch-Offset, Bitmaske)`. Der Eintrag **`88 40`** kommt in jedem der vier ROMs vor — **genau
einmal**:

| Spiel | Tabelle ab | `88 40` bei | Tabellenindex |
|---|---|---|---|
| The Atarians | `7F90` | `7F98` | 4 |
| Time 2000 | `7EB1` | `7EB1` | 0 |
| Airborne Avenger | `7EA4` | `7EA4` | 0 |
| Space Riders | `7DFE` | `7E14` | 11 |
| Middle Earth | — (inline) | `7F36` / `77BC` | — |

*(Die erste Fassung nannte hier `75FA`/`7614` für Space Riders — um `0x800` daneben, weil ROM1
bei `0x7800` liegt und nicht bei `0x7000`. Die Tabellenanfänge stammen jetzt aus den
`LDX #imm` der jeweiligen Aufrufer, die `88 40`-Adressen aus einem Bytescan über alle fünf
ROM-Images.)*

Daraus wurde geschlossen, der Trigger sei board- statt spielabhängig. **Das ist falsch.** Der
Tabelleneintrag beweist nur, dass der Treiber Q12 auf der MPU existiert — das tut er
board-weit. Er sagt nichts darüber, *was* an dem Treiber hängt und *wie lange* das Spiel ihn
hält. Genau dort gehen die fünf Spiele auseinander:

| Spiel | Was an Q12 hängt | Wie das ROM es ansteuert |
|---|---|---|
| **Middle Earth** | Flipper Control Relay | Pegel über die ganze Spieldauer (`7F36` an, `77BC` aus) ✔ |
| **Space Riders** | Flipper Control Relay (so im Handbuch benannt) | Timer `$0064` wird auf `0xFF` gesetzt (`719D  COMA / STAA $64`); der Treiber überspringt bei negativem Wert das Dekrementieren (`7A94  BMI`) = **dauerhaft an**, bis `740C`/`76EF` löschen ✔ |
| **Airborne Avenger** | **Gate** (Herstellertabelle „Table 5: Solenoid Identification": `1 Gate -> Q12`) | Timer `$0090`, zeitbegrenzt nachgeladen (`7670  LDAA #$03`), gelöscht bei `7663`/`76C2`/`7289` ✘ |
| **Time 2000** | dieselbe Gate-Mechanik | Timer `$0090` auf 15 bzw. 3 (`75D6`, `75F5`), danach aus (`75E4`, `7650`) ✘ |
| **The Atarians** | **Kickerspule „Hole Kicker Left"** | Feuerroutine `$7E0D` (Index = Spulennummer − 2), aufgerufen mit Spule 6 = Index 4 = `7F98`; Auslöser ist der Schalter `$2030` (`709D  LDX #$2030 … LDAA #$06 / TAB / JSR $7E0D`, Puls 6 Ticks) und `7543` (Puls 10 Ticks) ✘ |

Am Automaten hieße das: bei **Atarians** spränge die Musik bei jedem Schuss in den linken
Hole-Kicker für ein paar Ticks an, bei **Time 2000** und **Airborne** für die Öffnungsdauer
des Gates. Ein „Spiel läuft"-Pegel ist Q12 nur bei zwei von fünf Spielen.

Der Signalweg selbst bleibt trotzdem nützlich: bei einer **FA-Control-Übernahme** ist der
Trigger weiterhin `fa_sol_ovr(11)`, also die COILS-Kachel 12. Am Prüfstand hängt keine
Schaltermatrix, dort wäre der Outhole-Zweig sinnlos.

### 2.6 Ebenfalls geprüft und verworfen: die Player-up-LED

`display1..4(6) = x"8"` (RAM `0x03/0x07/0x0B/0x0F`, unteres Nibble) sieht auf den ersten Blick
brauchbar aus: spielunabhängig, im Display-Sniffer schon vorhanden, mit bloßem Auge prüfbar.
Sie taugt trotzdem nicht — sie kann im Selbsttest mitlaufen (dort stehen Testwerte in den
Score-Bytes), und vor allem **blinkt Index 6 im Attract-Modus**. Das steht als Kommentar im
FRAM-Stand (Commit `959ff6b`, `AtariFA.vhd`: „OHNE die Player-up-LED (Index 6, blinkt im
Attract)"), wo sie aus genau diesem Grund aus der Score-Stabilitätsprüfung herausgenommen
wurde. Bis SW 0.3.0 stand sie hier als Reserve; das ist sie nicht.

---

## 3. Umsetzung

### 3.1 `rtl/common/dfplayer_cmd.vhd`

**Herkunft und Stand — bitte merken, wenn hier je wieder etwas nachgezogen wird.** Die Datei
folgt seit **SW 0.3.2** dem Stand von **RecelFA**
(`N:\Projekte\FPGA Recel\FPGA_source\rtl\common\DFPlayer_Mini_CMD.vhd`, **v0.6, 08.2026**).
*Das* ist die gepflegte Linie. Die erste Portierung (SW 0.3.0) kam aus **GottFA1_PLuS**
(`N:\Projekte\FPGA System1\FPGA_source\rtl\common\DFPlayer_Mini_CMD.vhd`, **v0.5, 09.2025**) —
ein älterer Zweig, dem vier im Feld gelernte Härten fehlten. Genau die decken die Fälle ab, in
denen ein Modul stumm bleibt:

| RecelFA | Was dort steht | AtariFA bis 0.3.1 |
|---|---|---|
| v0.5 | „send complete 10 byte frames **including checksum**, some clone chips **insist on it**" | 8 Byte ohne Prüfsumme |
| v0.5 | „some chips only set the mode …, so **kick playback with `0x0D`** as well" | kein Nachschlag nach `0x17` |
| v0.5 | 0,5 s Pause zwischen einem Kommando und seinem Folgekommando | Rahmen lückenlos hintereinander |
| v0.6 | **5 s** Startverzögerung, „also supports very slow modules" | 2 s |
| v0.6 | Reset `0x0C` verworfen (schickt den Player durch einen zweiten Boot mit SD-Scan, „which is exactly when a command gets lost"), stattdessen `0x42` **und `0x16`** | nur `0x42` |
| v0.5 | `0x42` als allererster Rahmen — manche Klone verwerfen den ersten nach dem Einschalten | war schon drin |

Übernommen ist der **Ablauf**, nicht der Aufbau: RecelFA schiebt ein 100-Bit-Register an einem
eigenen 9600-Hz-Takt, hier sendet das im Baum vorhandene **`work.UART_TX`**
(`rtl/fa_control/uart_tx.vhd`, sonst für den ESP32 mit 115200 Baud im Einsatz) mit
`g_CLKS_PER_BIT = 5208` in der `clk_50`-Domäne. Kein zweiter Takt, nichts für die SDC.

**Rahmenformat** — die vollen 10 Byte laut Datenblatt:

```
7E FF 06 <cmd> 00 <par1> <par2> <csumH> <csumL> EF
csum = 0 − ( FF + 06 + cmd + 00 + par1 + par2 )      -- 16 Bit
```

Bis 0.3.1 gingen nur die 8 Byte ohne Prüfsumme hinaus (so macht es GottFA1_PLuS bis heute, dort
im Feld erprobt). Ein Player, der ohne Prüfsumme arbeitet, kommt mit ihr ebenfalls zurecht —
der vollständige Rahmen ist also strikt die sicherere Wahl, nicht bloß die andere.

**Kommandos**

| Kommando | Wann | Parameter |
|---|---|---|
| `0x42` Status abfragen | erster Rahmen nach dem Boot, weckt den Player | — |
| `0x16` Stop | zweiter Rahmen — definierter Zustand **ohne** Player-Reboot | — |
| `0x06` Lautstärke | dritter Rahmen, wenn `SET_VOLUME` | `par2 = VOLUME` (0…30) |
| `0x17` repeat folder | Musik zum ersten Mal starten | `par2 = FOLDER` |
| `0x0D` play/resume | als Nachschlag nach `0x17`, und wenn der Trigger wieder `'1'` wird | — |
| `0x0E` pause | Trigger `'0'` | — |

**Ablauf**

```
st_Boot → st_Init → st_Idle → st_Delay → st_Decide → st_Send → st_Wait
             ^                                          ^         |
             +---------------- st_Gap <-----------------+---------+
```

Nach **jedem** Rahmen liegt `st_Gap` — ein Weg statt Sonderfällen. Steht dabei ein
Folgekommando an (`pending`), geht es direkt in den nächsten Rahmen statt zurück nach
`after_send`. Der Init-Ablauf nutzt das mit `after_send = st_Init`, sodass zwischen den drei
Init-Rahmen automatisch je eine Pause liegt.

| Generic | Vorgabe | Bedeutung |
|---|---|---|
| `CLKS_PER_BIT` | 5208 | 50 MHz / 9600 Baud |
| `START_DELAY` | 250 000 000 | **5 s**, bis der Player hochgelaufen ist (0.3.0/0.3.1: 2 s) |
| `GAP_CYCLES` | 25 000 000 | 500 ms Pause nach jedem Rahmen |
| `GLITCH_CYCLES` | 100 000 000 | 2 s Entprellung des Triggers (0.3.0: 500 ms) |
| `FOLDER` | 2 | SD-Ordner `02`, wie bei GottFA1_PLuS |
| `SET_VOLUME` / `VOLUME` | true / 20 | Lautstärke einmalig setzen (sonst gilt die im Player gespeicherte) |

`GLITCH_CYCLES` ist die wichtigste Stellschraube: der Triggerwechsel wird nach der Wartezeit
**erneut geprüft** und nur dann übernommen. Bei Gottlieb fängt das die Relais-Aussetzer
zwischen den Bällen ab, hier den **Ballwechsel** (§2.2) — und in beiden Fällen sorgt es dafür,
dass ein einzelner Spulenpuls aus der COILS-Ansicht von FA-Control die Musik nicht startet.
Die Zählerbreite folgt `WAIT_MAX = max(START_DELAY, GLITCH_CYCLES, GAP_CYCLES)`, seit 0.3.2
also 28 statt 27 Bit.

**Rückfallweg, falls ein Modul mit Ordnern nicht zurechtkommt:** statt `0x17` mit `par2 = FOLDER`
das Kommando `0x11` mit `par2 = 1` („alles wiederholen") senden — so macht es RecelFA. Hier
steht `0x17`, weil AtariFA und GottFA1_PLuS sich die Karte mit dem Ordner `02` teilen. Das ist
bewusst ein Einzeiler im Code und **keine** zweite Betriebsart.

### 3.2 Anbindung im Top-Level

```vhdl
outhole <= sw_state(50) when game_sel = 0 else   -- Atarians  0x2032
           sw_state(53) when game_sel = 1 else   -- Time 2000 0x2035
           sw_state(67) when game_sel = 2 else   -- Airborne  0x2043
           sw_state(56);                         -- ME / Space Riders 0x2038

music_trig   <= fa_sol_ovr(11) when fa_ctrl_active = '1' else not outhole;
music_enable <= not options(1);          -- DIP ON wird als '0' gelesen

MUSIC: entity work.dfplayer_cmd
generic map(
    CLKS_PER_BIT  => 5208,
    GLITCH_CYCLES => 100000000           -- 2 s, s. 2.2
    )
port map(
    clk_50    => clk_50,
    reset     => not io_live,
    trigger   => music_trig and music_enable,
    start_new => '0',
    txd       => SB_Audio
    );
```

Vier Entscheidungen, die dahinterstehen:

* **`outhole` muxt die vier Kandidatenbits, nicht `sw_state(Index)`.** Ein variabler Index
  über einen 80-Bit-Vektor wird zu einem 80:1-Mux; so sind es drei LUTs. Der Mux läuft über
  `game_sel` (0…4 geklemmt), nicht über `game_idx`.
* **Bei FA-Control-Übernahme bleibt der Trigger die COILS-Kachel 12** (`fa_sol_ovr(11)`).
  Am Prüfstand hängt keine Schaltermatrix — dort lesen alle Schalter „offen", der
  Outhole-Zweig wäre sinnlos, und die Bench-Prozedur aus §6 bliebe ohne Maschine unbrauchbar.
* **`reset => not io_live`, nicht `not reset_l_stable`.** Bei einer Übernahme steht die CPU,
  das Musikmodul muss aber noch das Pause-Kommando absetzen können. Das ist die Konvention
  des Baums für Peripherie. Nebeneffekt: `switch_matrix` hängt am selben Signal, beide werden
  gemeinsam freigegeben. Beim Loslassen des Resets stehen alle `sw_state` auf `'0'` (= offen),
  die echten Werte stehen nach ~2 ms — lange bevor `START_DELAY` (2 s) abgelaufen ist.
* **`start_new => '0'`.** Die Musik läuft weiter, wo sie aufgehört hat (bei GottFA ist das
  Gottlieb-DIP 16 = OFF). `options(2)` bleibt frei, falls das später ein DIP werden soll.

### 3.3 Freigabe per DIP

**Options-DIP 1** = Hintergrundmusik EIN/AUS. Er kommt aus der Boot-Strobe-Matrix
(`read_the_dips.vhd`) und wird **nur beim Einschalten gelesen** — Umlegen im laufenden
Betrieb hat keine Wirkung, dazu ist ein Neustart nötig. Die Matrix ist damit voll belegt;
frei ist nur noch `options(2)`.

### 3.4 Kosten

Das Modul selbst kostete gegenüber SW 0.2.1: **Comb +158, Reg +92**, Memory unverändert bei
202 752 Bit, **kein zusätzlicher Pin** (85/89 wie bisher). Der größte Einzelposten ist der
27-Bit-Wartezähler für `START_DELAY`/`GLITCH_CYCLES`, dazu die 8 Rahmenbytes und `UART_TX`.

Der Triggerwechsel in **0.3.1** war demgegenüber Kleingeld: `cyclone_10_pcb` **Comb −10**,
`cyclone_10_dev_open` **Comb +3**, **Reg unverändert 1532**, Memory unverändert, Pins
unverändert. Das größere `GLITCH_CYCLES` kostet nichts (s. §3.1).

Der RecelFA-Stand in **0.3.2** kostet **Comb +63** (pcb) bzw. **+51** (dev_open) und
**Reg +12**, Memory und Pins unverändert. Enthalten sind zwei zusätzliche Rahmenbytes,
`pending`/`pending_cmd`, ein Zustand mehr und ein Zählerbit (28 statt 27). Die Prüfsummen
selbst kosten fast nichts: alle `build`-Aufrufe außer dem über `pending_cmd` haben konstante
Argumente, die Addierer falten sich weg.

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

### 6.1 Was wann auf der Leitung liegt

Nach dem Einschalten läuft erst das ~5 s lange Boot-Info-Fenster (`io_live` ist low, das Modul
im Reset), dann `START_DELAY`, dann die Init-Rahmen mit ihren Pausen, dann `GLITCH_CYCLES`:

| ab Einschalten | Ereignis |
|---|---|
| 0…5 s | Boot-Info, **nichts** auf `SB_Audio` |
| +5 s | `0x42`, 0,5 s Pause, `0x16`, 0,5 s Pause, `0x06` (Lautstärke) |
| +2 s | `0x17`, 0,5 s Pause, `0x0D` → **Musik** |

Bis zum ersten Ton vergehen also **rund 13…15 s**. Wer früher aufhört zu warten, sucht den
Fehler, wo keiner ist.

### 6.2 Die erwarteten Telegramme

Am Logikanalysator auf `SB_Audio` (pcb **PIN_7**, dev_open **PIN_111**), 9600 8N1. Byte für
Byte, Prüfsumme schon ausgerechnet:

| Kommando | Telegramm |
|---|---|
| `0x42` Status | `7E FF 06 42 00 00 00 FE B9 EF` |
| `0x16` Stop | `7E FF 06 16 00 00 00 FE E5 EF` |
| `0x06` Volume 20 | `7E FF 06 06 00 00 14 FE E1 EF` |
| `0x17` Ordner 2 | `7E FF 06 17 00 00 02 FE E2 EF` |
| `0x0D` Play | `7E FF 06 0D 00 00 00 FE EE EF` |
| `0x0E` Pause | `7E FF 06 0E 00 00 00 FE ED EF` |

Damit teilt sich die Fehlersuche sauber:

* **gar nichts auf der Leitung** → die FSM sendet nicht. Dann liegt es *vor* dem Player:
  Options-DIP 1 nicht ON, kein Neustart nach dem Umlegen, oder `io_live` gibt nicht frei.
* **Telegramme da, Player stumm** → der Player verwirft sie oder liest die Karte nicht. Dann
  bleibt der Rückfallweg `0x11` statt `0x17` (§3.1) und die Prüfung der Karte.

### 6.3 Am Prüfstand, ohne Maschine

Dort ist keine Schaltermatrix angeschlossen, alle Schalter lesen „offen" — der Outhole-Trigger
steht also dauerhaft an:

| Schritt | Erwartung |
|---|---|
| Boot-Info-Anzeige | `032` (bzw. `132` auf `cyclone_10_dev_open`) |
| Options-DIP 1 = ON, einfach warten | die Folge aus §6.1 läuft von selbst durch, nach ~13…15 s spielt Musik — das beweist UART, Karte und Player in einem Schritt |
| FA-Control aktiv (DIP 4 = ON, Opcode 100) → COILS → Kachel 12 einmal antippen | **keine** Reaktion (Glitch-Filter) |
| FA-Control → Spule 12 dauerhaft ein/aus | Musik startet/pausiert nach ~2 s |
| Options-DIP 1 = OFF, Neustart | kein Telegramm mehr, keine Musik |

### 6.4 Am Automaten

Das ist der eigentliche Test, denn hier hängt alles an der Schalternummer:

| Schritt | Erwartung |
|---|---|
| Einschalten, Kugel liegt im Outhole | still |
| Spiel starten (Kugel wird ausgeworfen) | Musik nach ~2 s |
| Kugel in der Mitte verlieren, nächster Ball folgt | Musik läuft durch, solange die Kugel < 2 s im Outhole liegt; sonst kurze Pause (§2.2) |
| Letzten Ball verlieren | Musik pausiert ~2 s später |
| Nächstes Spiel | läuft an der alten Stelle weiter (`start_new = '0'`) |
| Tilt | Musik läuft bis zum Drain, **dann** Pause (§2.4) |
| Kugel von Hand in den Outhole legen | Musik pausiert |
| Attract-Modus mit Kugel im Outhole | still |

**Je Spiel zu wiederholen**, weil die Schalternummer spielabhängig ist (50/53/67/56/56, §2.3)
und außer Airborne keine davon an der Maschine bestätigt ist. Schnellprüfung ohne Spiel: in
FA-Control die SWITCHES-Ansicht öffnen, Kugel in den Outhole legen und nachsehen, welche
Kachel schließt — steht dort die Nummer aus §2.3, stimmt der Mux.
