# FRAM-Persistenz — Credits & Highscore über Power-Cycle (Airborne)

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
  am Ballende immer im Outhole). Outhole-Offsets der anderen Spiele: Atarians 19, Time2000 53,
  Middle Earth 56, Space Riders 56.
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
