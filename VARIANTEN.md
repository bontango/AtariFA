# AtariFA — Varianten

Stand: 06.08.2026 · Version `.1.2` (`rtl/common/version_pkg.vhd`)

Was jede Variante ist, was sie kostet, und — der eigentliche Punkt dieses Dokuments —
**was davon in Hardware getestet ist und was nicht.**

---

## Übersicht

| Variante | Board | FPGA | Board-ID | Angezeigte Version | HW-getestet |
|---|---|---|---|---|---|
| `cyclone_10_pcb` | AtariFA PCB v1.0 + lisy.dev Cyclone-10-Piggy-back | 10CL006YE144C8G | 0 | `0.1.2` | ✅ bis SW 0.1.2 |
| `cyclone_10_dev_open` | AtariFA PCB v1.0 + `dev_open`-Cyclone-10-Board | 10CL006YE144C8G | 1 | `1.1.2` | ❌ nie |

Beide nutzen **denselben FPGA**. Der Unterschied ist ausschließlich das Piggy-back-Board
darum herum — deshalb gibt es nur ein `rtl/cyclone_10/` und keine zweite Chipfamilie.

## Ressourcen (Stand 06.08.2026, Quartus 22.1std.2)

| Variante | Comb. Funktionen | Register | Memory Bits | LE nach Fitter | Pins | Virtual Pins | Setup-Slack |
|---|---|---|---|---|---|---|---|
| `cyclone_10_pcb` | 2433 | 935 | 202.752 (73 %) | 2545 / 6272 (41 %) | 85 / 89 (96 %) | 1 | 2,30 ns |
| `cyclone_10_dev_open` | 2432 | 935 | 202.752 (73 %) | 2560 / 6272 (41 %) | 81 / 89 (91 %) | 5 | 2,43 ns |

**Comb/Register/Memory sind das Abnahmekriterium, nicht die LE-Zahl des Fitters.**
Gemessen beim Umbau: ein einziger zusätzlicher `VIRTUAL_PIN` ließ die Synthese Byte für
Byte gleich (2433/935/202752) und schob den Fitter trotzdem von 2554 auf 2545, weil er die
LEs anders packt. Ein exakter Test auf diese Zahl meldet eine Änderung, die es nicht gibt.
`scripts/baseline.csv` prüft deshalb Comb/Reg/Mem exakt und führt die Fitter-LE nur mit.

Der **enge Pfad ist `cpu_clk`** (1-MHz-PLL-Ausgang), nicht `clk_50` — `clk_50` liegt bei
knapp 6 ns. Slack schwankt bei identischen Quellen um mehrere hundert Pikosekunden;
`check.ps1` toleriert 1,5 ns und meldet zusätzlich jeden Wert unter 1,0 ns.

Der knappste Posten ist **nicht** Logik oder Speicher, sondern **Pins**: `cyclone_10_pcb`
liegt bei 85 von 89, also 4 Reserve. Ein neues Feature mit eigenem Anschluss braucht dort
zuerst einen freien Pin.

---

## 1 — `cyclone_10_pcb`

Die Leitvariante. Hier wird entwickelt und auf echter Hardware getestet.

Board: AtariFA-PCB v1.0 mit dem selbst entworfenen lisy.dev-Cyclone-10-Piggy-back
(<https://lisy.dev/cyclone10-dev-board.html>).

Eigenheiten:
- **3 Status-LEDs**, parallel zu den drei LEDs des Piggy-back-Boards. `LED_D4` existiert
  hier nicht → `VIRTUAL_PIN` (siehe `variant.psd1`).
- **Reset-Taster** parallel zum Taster des Piggy-back-Boards.
- **Alle 8 Debug-Leitungen** liegen auf dem 10-poligen LA-Header.

**Hardware-Teststand:** SW 0.1.2, alle fünf Spiele. Boot, Credits, Spielstart, Freispiel-
ROMs, Selbsttest und Schalterwerte, Lampen-Selbsttest, Solenoide, Onboard-Audio und die
Boot-Sprachausgabe sind bestätigt. Nicht bestätigt: der **Aux-Board-Audiopfad** nach dem
Dauerton-Fix von SW 0.1.1 (siehe `CLAUDE.md`, Abschnitt Sound).

**Nach dem Umbau in diesen Baum ist die Netzliste dieser Variante unverändert** — Comb,
Register und Memory Bits sind exakt die des zuletzt geflashten Stands. Ein erneuter
Hardwaretest ist trotzdem fällig, bevor der Umbau als abgenommen gilt; die Prüfliste steht
unten.

## 2 — `cyclone_10_dev_open`

Dieselbe AtariFA-PCB, aber mit dem `dev_open`-Cyclone-10-Board darauf. Am 06.08.2026 als
Dateikopie der Leitvariante entstanden und nur im Pinout angepasst; es gab dafür **kein
eigenes Git** — die Historie dieser Variante beginnt mit dem Umbau in diesen Baum.

Eigenheiten:
- **4 Status-LEDs auf dem Piggy-back-Board selbst**, `LED_D4` ist Reserve und wird bewusst
  auf `'1'` (aus, active-low) getrieben.
- **Reset-Taster auf dem Piggy-back-Board selbst.**
- **Nur 3 Debug-Leitungen** am LA-Header; `debug_signal[3..7]` sind `VIRTUAL_PIN`.

Zwei Dinge sind mit dem gemeinsamen Top-Level mitgekommen, beide Aufräumen:
- `LED_D4` war deklariert, aber **von niemandem getrieben**. Für Quartus ist so ein Port
  trotzdem ein benutzter Pin. Jetzt getrieben — das erklärt die 8 kombinatorischen
  Funktionen weniger gegenüber dem alten Ordner (2440 → 2432).
- Die Blöcke `gen_dbg1`/`gen_dbg2` wiesen dem auf 3 Bit verkleinerten Port
  `cpu_addr(7 downto 0)` zu. Solange `DBG_MODE = 0` gilt, wird der Zweig nicht elaboriert;
  beim Umschalten auf 1 oder 2 wäre die Synthese gebrochen. Mit der gemeinsamen 8-Bit-
  Portliste ist das strukturell weg.

**Hardware-Teststand: nie getestet.** Was zuerst zu prüfen ist:
1. Bootet das Board überhaupt, zeigt die Info-Anzeige `1.1.2`?
2. Reset-Taster (anderer Pin, anderes Board) — löst er aus?
3. Die vier LEDs: D1 Watchdog-Sticky, D2 CPU-Fetch-Blinker ~0,6 Hz, D3 NMI-Blinker
   ~0,48 Hz, D4 dunkel.
4. Erst danach Displays, Schalter, Lampen, Solenoide — die hängen alle am Pinout, das für
   dieses Board noch nie gegen die Platine geprüft wurde.

---

## Prüfliste nach einem Umbau am gemeinsamen Baum

Auf `cyclone_10_pcb` (die Variante mit bekanntem Sollverhalten):

1. Boot-Info-Anzeige: Version `0.1.2`, Game-Select, Options, Freispiel-Flag.
2. Ein Spiel starten, Credits buchen, Freispiel-ROM ohne Credit.
3. Selbsttest über den Testschalter, Schalterwerte, keine Phantomschalter
   (Atarians hat keinen dokumentierten Selbsttest — kein Defekt).
4. Lampen-Selbsttest: richtige Lampe, richtiger Strobe.
5. Solenoide, Münztür.
6. Onboard-Audio und die Boot-Sprachausgabe „Lisü" (~2 s nach dem Start).

Erst wenn das gegen SW 0.1.2 unverändert läuft, ist ein Umbau abgenommen.
