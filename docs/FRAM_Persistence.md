# FRAM-Persistenz — Credits, Highscore, letzte Spielstände

> **STATUS 2026-11-11 — AKTIV seit SW 0.4.0, alle 5 Spiele, HW-getestet auf `cyclone_10_pcb`
> mit SW 0.4.4.** Der aktuelle Stand steht im ersten Abschnitt *„SW 0.4.x"*. Alles danach ist
> die Vorgeschichte (SW 0.0.8–0.1.0, nur Airborne, ab 2026-07-10 zurückgestellt) und bleibt als
> Beleg für die Mechanik und die Fehlversuche stehen. Testprotokolle:
> `docs/TEST_Highscore_Schritt0.md`, `…Schritt1.md` (Highscore), `…Schritt2.md` (Credits).

## SW 0.4.x — aktueller Stand

**Bedienung:** Options-DIP 2 (`options(2)`, Boot-Matrix). **ON = an**, **OFF = aus und beim
Boot den Slot des gewählten Spiels löschen**. (0.4.0/0.4.1 hatten es umgekehrt; im Test wurde
DIP 2 als „an/aus“ verstanden und stand auf ON, was bei jedem Boot löschte. Gedreht in 0.4.2.)

**Modul `rtl/common/score_keeper.vhd`** (instanziiert in `top/AtariFA.vhd`, Instanz `SCORES`)
enthält `fram_i2c.vhd` und ist spielunabhängig, bis auf die Credit-Adresse, die das Top-Level
liefert.

- **Letzte Stände + Highscore** (0.4.0): arbeitet nur auf den Display-Shadow-Buffern. Die
  Player-up-Erkennung im Top-Level (`in_game`, `up_refresh`) liefert Spielende und
  Schnappschuss-Strobe. Am Spielende (fallende Flanke `in_game`) werden die vier Stände
  gespeichert, Highscore = max(alt, bester Spieler); ein Spiel ohne Punkt wird nicht gespeichert.
  Nach dem Boot zeigen die Spieler-Displays bis zum ersten Spiel die gespeicherten Stände (auch
  über dem Segmenttest `888888`), im Attract wechseln 8 s Spielanzeige / 4 s Highscore. Nichts
  davon wird ins Spiel-RAM geschrieben, es wird nur in die Anzeige eingeblendet.
- **Credits** (0.4.3/0.4.4): Credit-Zähler je Spiel per ROM-Disassembly (`tools/dis6800.py`):

  | Spiel | Adresse | Format | Münze / Start |
  |---|---|---|---|
  | Atarians | `$CE` | BCD | `7B54`–`7B68` (Limit `$E0`) / `7B76`–`7B87` |
  | Time 2000 | `$D6` | BCD | `7C93`–`7CA7` (Limit `$CA`) / `7CB4`–`7CC2` |
  | Airborne | `$D5` | binär | `7CA7`–`7CBF` (Limit `$BC`), Anzeige über BCD-Wandlung `7CD5` |
  | Middle Earth | `$1D` | BCD | = Credit-Display-Byte selbst; `7232` / `725B`; Boot schreibt `$88` (`7FE9`), `71C1` behandelt `$88` als 0 |
  | Space Riders | `$B7` | BCD | `7BDA`–`7BEF` (Limit `$A8`) / `77A0` (addiert `$99` = −1) |

  Außer Münz-/Startroutine schreibt in allen fünf ROMs nur der Boot-RAM-Clear auf diese Adressen.
  Der alte CRED_PROBE (unten) lag bei Atarians/Time/Space Riders also richtig (206/214/183),
  bei Airborne und Middle Earth falsch.
- **Mitschreiben:** `credit_sniffer` im Top-Level meldet jede CPU-Schreibung auf
  `CRED_ADDR(game_sel)` (Adressbits 8..0, also auch über den RAM-Mirror). Ändert sich der Wert,
  schreibt `score_keeper` sofort den ganzen Slot. Scharf erst nach der Injektion — sonst landeten
  der Boot-Clear (0) bzw. das `$88` von Middle Earth im FRAM.
- **Zurückschreiben:** `credit_inject` im Top-Level, Mechanik wie Stufe 2 von SW 0.0.9: nach
  **jedem** CPU-Start (auch nach einer FA-Control-Übernahme) `CRED_DELAY` = 50 ms warten, CPU per
  `halt` anhalten (`HALT_SETTLE` ≈ 82 µs), RAM-Port muxen, **zwei Bytes** schreiben: den
  Credit-Zähler und `$1D` = Credits in BCD (so schreibt es das Spiel nach einer Münze selbst).
  Ohne das zweite Byte zeigte das Credit-Display bis zur ersten Münze das `88` des Segmenttests
  (HW-Test 0.4.3). Der Display-Sniffer liest dafür `ram_p_*` statt des CPU-Busses. Credit 0
  wird nicht injiziert (= Originalverhalten).
- **Boot-Info:** Display 4 links = FRAM-Status (Ziffer 1: FRAM hat quittiert; Ziffer 2:
  `2` = aus/gelöscht, `1` = gültig gelesen, `0` = leer), Status-Display rechts = gespeicherte
  Credits. Die binären Airborne-Credits wandelt `cred_bcd` getaktet in BCD (kombinatorisch
  kostete das ~100 LEs und −5,4 ns Setup).

**FRAM-Slot je Spiel** (17 Byte ab `game_sel × 32`):

| Byte | Inhalt |
|---|---|
| 0 | Magic `0xA6` (0.4.0–0.4.2: `0xA5`, 16 Byte ab `game_sel × 16` — gelten jetzt als leer) |
| 1–12 | letzte Stände, je Display 3 Byte, linkes Ziffernpaar zuerst, Ziffern roh (Blank = `F`) |
| 13–15 | Highscore, gleiche Kodierung |
| 16 | Credits, roh wie im Spiel-RAM |

Ein Slot, der nur wegen der Credits geschrieben wurde, hat bei den Ständen Blank-Ziffern; beim
Boot werden Stände nur eingeblendet, wenn eine Ziffer 1..9 dabei ist (`has_digit`).

**Nebenbefund DIP-Lesen (0.4.1):** `read_the_dips.vhd` tastete jede Matrixzeile 1 µs nach dem
Strobe-Wechsel ab. Seit v1.1 sind es 50 µs (`SETTLE_CYCLES`). Ausgelöst durch den Verdacht, DIP 2
werde über die Rückleitung der Freispiel-Zeile verfälscht — die eigentliche Ursache war dann die
DIP-2-Bedeutung (s. o.), die Wartezeit ist trotzdem geblieben.

**Ressourcen (SW 0.4.4, pcb):** Comb 5861 / Reg 2180 / Speicher unverändert 202 752 Bit,
LE 96 % (6013/6272). `score_keeper` inkl. I²C ≈ 930 LEs. Der Chip ist damit praktisch voll.

---

# Vorgeschichte: SW 0.0.8–0.1.0 (nur Airborne)

> **STATUS 2026-07-10 — damals ZURÜCKGESTELLT / I²C deaktiviert.** Die Ausweitung auf alle 5 Spiele
> scheiterte (empirischer CRED_PROBE unzuverlässig, s. Abschnitt am Ende). Der HW-verifizierte
> Airborne-Stand (SW 0.0.9, `959ff6b`) liegt in der git-History. Abgelöst durch SW 0.4.x (oben).

Atari Gen1 hat **kein natives NVRAM**: RAM `0x0000–0x01FF` ist single-port und wird beim Boot
gelöscht (Clear-Loop `0x00–0xD8`). Angezeigt wird immer nur der Score des **letzten Spiels**;
einen „High Game To Date" gibt es nicht (Nutzer-bestätigt). Ziel dieses Features: **Credits und die
Punktestände des letzten Spiels** in einem externen I²C-FRAM (FM24CL64B) sichern und beim Boot
wiederherstellen. Umgesetzt in zwei Stufen; **Stufe 1 (Save/Restore ins FRAM) + Credit-Restore ins
Spiel-RAM sind HW-verifiziert**, die **Score-Anzeige** ist bewusst zurückgestellt (s. unten).

Alle Adressen/Trigger sind **spielspezifisch**; implementiert ist bisher nur **Airborne Avenger**
(`game_idx = 2`).

## Hardware / I²C
- **FRAM FM24CL64B-GTR**, 8K×8, I²C. Adress-Pins auf der AtariFA-PCB: **A0=3V, A1=A2=GND**
  → 7-Bit-Slave `1010 001` = **0x51** (Write-Byte 0xA2, Read-Byte 0xA3), 2-Byte-Speicheradresse.
- **HW-Check (2026-07-08):** /WP=GND, Vdd=3,3 V, SDA/SCL je 4k7-Pull-up an 3,3 V. Der FRAM quittiert
  (ACK) an 0x51 → Verdrahtung/Adresse ok. (LED_D3 = `fram_ack_ok` im Diagnose-Build.)
- **`fram_i2c.vhd`** = Bit-Banging-I²C-Master @clk_50 (`CLK_DIV=125` ≈ 100 kHz), Block-Read/Write,
  SDA open-drain `inout` / SCL push-pull.
  - **Read-Bug (gefixt 2026-07-08):** `P_RX` schob `shreg` ursprünglich in **jedem** Takt der
    SCL-high-Phase (`CLK_DIV`×) → gelesenes Byte war nur das **LSB, 8-fach** (0x42 → 0x00,
    Magic 0xA5 → 0xFF). Fix: Bit **genau 1× pro Bit** am letzten Takt der Phase sampeln
    (`if phase_last then shreg <= shreg(6 downto 0) & sda;`). Danach Loopback HW-bestätigt
    (Testmuster byte-exakt zurückgelesen).

## FRAM-Record (@ Adresse 0)
| Index | Inhalt | Airborne-RAM |
|---|---|---|
| 0 | Magic `0xA5` (Gültig-Signatur) | — |
| 1 | `game_idx` (= `not game_select`) | — |
| 2 | Credits | `$D5` |
| 3..12 | Player-Scores (10 Bytes, BCD) | `$81..$8A` |

Gültig, wenn `Magic==0xA5` **und** `game_idx` == aktuelles Spiel (`restore_valid`).

## Airborne — RAM-Adressen (RE, `tools/listing_aav.txt` + PinMAME `doc/atari.c`)
- **Credits:** `$D5` (Limit `$BC`).
- **Player-Scores:** `$81–$8A` (BCD). Werden vom ROM (7CF5) in die Display-Region `$05/$06/$09/$0A/$0D/$0E`
  kopiert — **aber nur in bestimmten Zuständen**, nicht im Cold-Boot-Attract (s. „Atari-Verhalten").
- **Outhole-Latch:** CPU-Adresse `0x2043` → `sw_state`-Offset **67** (= Spielende-Marke; Ball landet
  am Ballende immer im Outhole). Outhole-Offsets der anderen Spiele: Atarians **50** (`0x2032`),
  Time 2000 53, Middle Earth 56, Space Riders 56.
  > **Korrigiert 2026-08-31:** hier stand für Atarians **19**. Das ist `0x2013` = **Slam Tilt** —
  > bei allen fünf Spielen dieselbe Adresse. Richtig ist `0x2032` = 50
  > (`Manuals\Atari Schalterzuordnungen und Kontakttestcodes.csv`, Zeile 36, Spalte Atarians
  > „Outhole Kicker"; Gegenprobe im ROM: `0x2032` wird bei `76B4` und `76F0` in die
  > Ball-Ende-Behandlung gepollt, `0x2013` nur bei `76BF` im Slam-Tilt-Zweig). Die Zahl war nie
  > in Hardware ausgeübt — Stufe 1 lief nur mit Airborne. Verwendet wird sie jetzt vom
  > Musik-Trigger, s. `Background_Music.md` §2.3.
- **Boot:** `@7000` löscht RAM `0x00–0xD8`, Re-Init `0x40–0x7B` (Werte 1..60, **keine** Scores/Credits).
  Scores/Credits bleiben nach dem Clear auf 0, bis das Spiel/wir sie schreiben.
- **NMI (7DBE)** = reiner Watchdog (RAM-Signatur `$D9=AA/$DA=55` + PC-High in `[0x70,0x80)`), **keine**
  Spiellogik. Die Signatur-Bytes `$D9/$DA` liegen **außerhalb** unserer Injektionsbereiche.

## Stufe 1 — Save/Restore ins FRAM (HW-OK)
- **Save-Trigger (`save_trig`, `AtariFA.vhd`):** steigende **Outhole**-Flanke armiert; wenn die
  Player-Scores dann `STABLE_CYCLES` (~3 s) **unverändert** sind (Bonuszählung fertig) **und**
  `game_played` (ein Score ≠ 0) **und** `game_idx=2` **und** `options(1)='0'` (ON), feuert
  `save_request` → FRAM-Write von `persist_buf` (Sniffer auf Page-0-Writes `$D5`/`$81–$8A`).
- **Boot-Verwaltung (`fram_ctrl`-FSM):** an `boot_phase(1)` (DIP-Read fertig, PLL gelockt):
  `options(1)='0'` (ON) → **Block-Read** FRAM→`fram_shadow` + `restore_valid`; `options(1)='1'` (OFF)
  → **Erase** (Nullen schreiben → Magic ungültig). Liegt im ~5-s-Boot-Info-Fenster.
- **Verifikation im Boot-Info:** Status-Display = `restore_valid`-Flag + restaurierte Credits;
  Player-4-Display = restauriertes `$81`-Score-Byte.
  - **Ziffern-Dreher „24 statt 42" (gelöst):** Das **Status-/Credit-Ball-Display** läuft in der
    Digit-Reihenfolge **entgegengesetzt** zu Display 1–4 (Index 0 = links statt rechts). Fix nur in
    `bi_status`: hi-Nibble → Index 2, lo-Nibble → Index 3. Rein kosmetisch (FRAM war byte-exakt).
  - **CD4511-Vorbehalt:** der Status-Decoder zeigt nur 0–9, A–F = **BLANK** → BCD-Werte lesbar, Hex nicht.
- **HW-Test (2026-07-09, Airborne, options(1)=ON):** Save am Outhole (LED_D1), Credits nach Power-Cycle
  im Boot-Info wieder da, OFF-Boot löscht das FRAM. ✅

## Stufe 2 — Bus-Injection-Restore ins Spiel-RAM (Credit-Restore HW-OK)
Damit die restaurierten Werte nicht nur im Boot-Info, sondern **im Spiel** wirken, injiziert der FPGA
`fram_shadow` direkt ins Spiel-RAM (Nutzer-Entscheid: Restore-Mechanismus = **Bus-Injection/DMA**).
- **Mechanik (`injection`-FSM + RAM-Mux, `AtariFA.vhd`):** cpu68-`halt` (active-high, nur im Fetch
  honoriert) hält die CPU an (Idle-Bus, alle Register gelatcht → transparenter Resume). Der RAM-Port
  (`address/data/wren`) wird von der CPU auf einen Injektor gemuxt.
- **Ablauf:** `INJ_ARM` (warten `reset_h=0` = CPU released + `restore_valid` + `game_idx=2`) →
  `INJ_WAIT_CLEAR` (`DELAY_CLEAR` ≈ 20 ms, Boot-RAM-Clear abwarten) → `INJ_HALT` (`cpu_halt=1`,
  `HALT_SETTLE` ≈ 82 µs) → `INJ_WRITE` (RAM-Port gemuxt, Bytes aus `fram_shadow` schreiben) →
  `INJ_DONE` (Resume, One-Shot `injected`). Läuft einmalig pro Boot.
- **HW-Test (2026-07-09):** CPU läuft sauber weiter (D2-Fetch-Heartbeat, Attract zyklisch), **2 Credits
  aus dem Vorspiel korrekt restauriert** (Coin-Simulation → Credit direkt auf 3). ✅ Der Credit-Restore
  ist damit verifiziert.

## ⚠ Schlüssel-Erkenntnis: Atari-Attract-Anzeigeverhalten
Beim HW-Test der Score-Anzeige zeigte sich das **normale Atari-Verhalten** (kein Fehler!):
- Nach dem Boot zeigt Atari **fix `888888`** auf **allen** Displays für **~20–30 s** (Anzeige-/Segmenttest).
- Danach werden die **Player-Displays geblankt**; das Status-Display bleibt auf `8888`.
- **Scores werden erst nach dem ersten Spiel angezeigt.** Das Status-Display wechselt von `8888` erst
  bei **Coin-Einwurf oder Spielstart** (dann zeigt es die Credits).

**Konsequenz für die Score-Wiederherstellung:** Die Score-Bytes `$81–$8A` werden zwar korrekt ins RAM
injiziert (gleiche Mechanik wie der verifizierte Credit-Restore), **aber Atari zeigt im Cold-Boot-Attract
gar keine Scores an** — es blankt die Player-Displays, bis ein Spiel gespielt wurde. Die restaurierten
Scores sind unsichtbar, obwohl sie im RAM stehen.

Der **Credit-Restore ist davon nicht betroffen** und funktioniert, weil das Status-Display die Credits
beim Coin/Start ohnehin aus `$D5` anzeigt.

## Status & offene Punkte
- **Fertig + HW-verifiziert:** I²C-Treiber, Stufe-1-Save/Restore ins FRAM, **Credit-Restore ins Spiel-RAM**.
- **Zurückgestellt — Score-Anzeige:** Die Score-Injektion ist in `AtariFA.vhd` per Konstante
  **`INJ_SCORES := false`** deaktiviert (Mechanik bleibt erhalten; `true` reaktiviert sie). Sichtbar
  werden die Scores erst, wenn Atari in seinen **„Spiel-gespielt / Scores anzeigen"-Zustand** versetzt
  wird — dazu muss das entsprechende **RAM-Flag** (vom Game-Over-Code gesetzt, vom Attract-Loop
  ausgewertet) per ROM-Disassembly gefunden und **mit-injiziert** werden. Alternativ die Display-Region
  `$05/$06/$09/$0A/$0D/$0E` direkt injizieren (fragil, da der Game-Code sie blankt).
- **Andere 4 Spiele:** Score-/Credit-/Outhole-Adressen je `game_idx` via Disassembly ergänzen.

## HW-Tuning-Hebel (Konstanten in `AtariFA.vhd`)
- **`DELAY_CLEAR`** (~20 ms): Wartezeit nach CPU-Release, bevor injiziert wird. Zu klein → Injektion
  fällt in den laufenden Boot-Clear/Init. Robustere Alternative: erste `ram_wren`-Write auf `$D8` nach
  Release abwarten (= Clear-Loop fertig).
- **`HALT_SETTLE`** (~82 µs): Wartezeit nach `cpu_halt=1`, bis die CPU sicher im `halt_state` ist.
- **`INJ_SCORES`** (false): Score-Injektion `$81–$8A` an/aus. **`INJ_DEBUG_LED`** (false): LED_D1 =
  `injected` (Injection-Bestätigung) statt `save_seen`.

---

## Ausweitung auf alle 5 Spiele — ZURÜCKGESTELLT (2026-07-10)

Der Versuch, das Credit-Save/Restore von Airborne auf **alle 5 Spiele** auszuweiten, wurde am
2026-07-10 **zurückgestellt** (Nutzer-Entscheid: Aufwand ↔ Nutzen stimmt nicht). Damit ist das
**gesamte NVRAM/FRAM-Feature vorerst pausiert**: Das **I²C-Modul ist aus dem Build deaktiviert**
(in `AtariFA.qsf` ist die Zeile `VHDL_FILE fram_i2c.vhd` entfernt; das Top-Level treibt die FRAM-Pins
auf sicheren Leerlauf `fram_i2c_sda <= 'Z'` / `fram_i2c_scl <= '1'`). Die **Source `fram_i2c.vhd`
bleibt im Repo** erhalten und ist jederzeit reaktivierbar. Build: **SW 0.1.0**. Der committete
Airborne-Stand (SW 0.0.9, `959ff6b`) bleibt in der git-History als Referenz-Implementierung.

### Warum der empirische CRED_PROBE-Ansatz scheiterte

Um die Credit-RAM-Adresse je Spiel **ohne** ROM-Disassembly zu finden, wurde ein Diagnose-Build
(`CRED_PROBE`) gebaut: Er puffert den letzten Page-0-Spielvariablen-Write und **votet** ihn (Boyer-Moore)
bei jeder Änderung des Credit-Displays `$1D` (Annahme: der Credit-Zähler wird unmittelbar **vor** `$1D`
mit demselben Wert geschrieben). Ergebnis am Board (Display 1 = gefundene Adresse dezimal):

| Spiel | Probe (Display 1) | erwartet | Bewertung |
|---|---|---|---|
| Atarians | 206 (`$CE`) | ? | unbestätigt |
| Time 2000 | 214 (`$D6`) | ? | unbestätigt |
| **Airborne** | **240 (`$F0`)** | **213 (`$D5`)** | **FALSCH → Sanity-Anker verfehlt** |
| Middle Earth | 107 (`$6B`) | ? | Konfidenz bleibt `01` = wertlos |
| Space Race | 183 (`$B7`) | ? | Credit-Zählung hinkt/verzählt = wertlos |

**Der bekannte Anker Airborne (`$D5` = 213, per HW-Restore bewiesen) wird verfehlt → die Methode ist
unzuverlässig; 206/214/240/107/183 sind NICHT vertrauenswürdig.**

**Root-Cause** (verifiziert in `tools/listing_aav.txt`): Die Heuristik „letzter Spielvariablen-Write vor
einer `$1D`-Änderung = Credit-Zähler" ist **nicht eindeutig**, weil `$1D` aus **vielen** Codepfaden
beschrieben wird:
- Airborne schreibt `$1D` an ≥5 Stellen: `7CBF` (echte Credit-Routine, davor `STAB $D5` ✓), aber auch
  `7D1C / 7D52 / 7D5E / 7DB0` (Attract-/Münz-/Start-Scan). Beim Test („nach Boot ein paar Coins") läuft
  der **Attract-Münz-Scan** `7D4C–7DBB`, der `$1D` **direkt** hochzählt — **ohne** `$D5` davor. Der
  „letzte Write" ist dann eine BCD-/Scratch-Variable (`$F0` = 240) statt des Credit-Masters `$D5`.
- Middle Earth schreibt `$1D` aus ~10 Stellen → kein Kandidat gewinnt → Konfidenz konvergiert nie (`01`).
- PinMAME (`doc/atari.c`) bestätigt: Gen1 hat **kein echtes NVRAM**; der Credit-Zähler ist reine
  Spiel-RAM-Variable und wird von PinMAME nicht exponiert → nur per ROM-Disassembly sicher zu finden.

### Verankerte Fakten für eine spätere Implementierung
- **Airborne Credit-Master `$D5`** (HW-Restore bewiesen), Credit-**Limit** `$BC`, Credit-**Display** `$1D`.
- **Outhole-Offsets** (Spielende-Marke, `sw_state`-Offset): Atarians **50** (nicht 19, s.o.),
  Time 53, ME 56, Space 56, Airborne 67. Der Outhole-Trigger (`outhole_ofs`-Mux) war bereits
  generisch; er lebt seit SW 0.3.1 als Musik-Trigger in `AtariFA.vhd` weiter. **Alle fünf sind
  inzwischen gegen die ROMs gegengeprüft** (Fundstellen: `docs/Background_Music.md` §2.3);
  an einer Maschine erprobt bleibt nur Airborne.
- **FRAM-Slot-Idee je Spiel:** `mem_addr = game_idx * 16` (16-Byte-Record pro Spiel).

### Empfohlener Zukunftsweg = RE statt Probe
1. Je Spiel ein `dis6800.py`-Listing erzeugen (ME/AAV existieren schon in `tools/`).
2. Die Master-Credit-Variable über das Airborne-Muster tracen:
   `LDAB $cc; CMPB $limit; INCB/DECB; STAB $cc; JSR <BCD-Konvert>; STAA $1D` — die Adresse `$cc` ist der
   gesuchte Credit-Master. Gegen Airborne = `$D5` verankern.
3. Generischer Umbau (dann): `credit_addr(game_idx)`-Tabelle, die `game_idx=2`-Gates auf `0..4` öffnen,
   per-Game-FRAM-Slot (`mem_addr = game_idx*16`), `CRED_PROBE`/Diagnose entfernen. Scores bleiben deferred.
4. `fram_i2c.vhd` wieder in `AtariFA.qsf` aufnehmen und das Top-Level-Feature reaktivieren.
