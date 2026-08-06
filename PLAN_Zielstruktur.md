# AtariFA – Weg zur gemeinsamen Quell- und Repo-Struktur

Stand: 06.08.2026 · Status: **umgesetzt, Hardwaretest offen**
Was dabei herausgekommen ist, steht in `VARIANTEN.md` und `WORKFLOW.md`.
Dieses Dokument ist die Begründung – warum die Struktur so aussieht, wie sie aussieht.

---

## 1. Die Ausgangslage in einem Satz

Am 06.08.2026 kam eine zweite Ausprägung dazu (`AtariFA_dev_open`, dieselbe Platine mit
einem anderen Piggy-back-Board), als vollständige Dateikopie neben dem bisherigen flachen
Projektordner – und von 54 verglichenen Quelldateien unterschieden sich **drei**:
`AtariFA.qsf` (nur Pinlagen), `AtariFA.cof` (nur ein absoluter Pfad) und `AtariFA.vhd`
(elf Zeilen). Alle 20 übrigen Module, alle ROMs, `.sdc` und `.qpf` waren byte-identisch.

Damit war absehbar, dass jede künftige Änderung an `lamp_matrix`, `sound`, `switch_matrix`
zweimal von Hand nachgezogen werden müsste – und zwar auch in zwei getrennte `.qsf`, was
genau die Fehlerart erzeugt, bei der eine neue `.vhd` in einer der beiden Varianten fehlt
und dort stillschweigend nicht übersetzt wird.

Vorbild und gearbeitetes Beispiel: `N:\Projekte\WillFA7\FPGA_source` (sieben Varianten,
drei Chipfamilien, Juli 2026).

## 2. Die vier tragenden Mechanismen

### 2.1 Ein Top-Level statt zwei
Alle optionalen Ports (`LED_D4`, `debug_signal(7 downto 0)`) bleiben dauerhaft in der
Portliste deklariert. Ob ein Board den Pin hat, entscheidet `VirtualPins` in
`variants/<n>/variant.psd1`:

```powershell
VirtualPins = @('debug_signal[3]', 'debug_signal[4]', ...)
```

Das ist **nicht** Kosmetik: für Quartus ist ein deklarierter Ausgangsport ohne Location ein
*benutzter* Pin, `RESERVE_ALL_UNUSED_PINS` greift nicht, und er würde auf einem echten,
womöglich beschalteten Pin platziert und getrieben. `VIRTUAL_PIN` funktioniert auf
Cyclone 10 unter Quartus 22.1 einwandfrei (bei WillFA7 scheiterte es nur auf Cyclone II
unter Quartus 13.0sp1 – dieser Fall tritt hier nicht auf).

Anders als bei WillFA7 brauchte es **kein einziges `if ... generate`** und keine
Boolean-Konstante: der ganze funktionale Unterschied zwischen den Boards ist das Pinout.

### 2.2 Versionsnummer nur noch an einer Stelle
`SW_MAIN` ist zu `BOARD_ID` in `variants/<n>/variant_pkg.vhd` geworden, `SW_SUB1`/`SW_SUB2`
stehen in `rtl/common/version_pkg.vhd`. Ein Release = eine Zahl ändern; beide Boards zeigen
automatisch `<BoardId>.NN`. Vorher lag `SW_MAIN` in der jeweils eigenen Kopie des
Top-Levels – die einzige Stelle, an der die beiden Varianten überhaupt „inhaltlich"
auseinanderliefen (0.1.2 gegen 1.1.2), ohne dass es einen Ort gab, an dem man beide
gemeinsam hochzieht.

### 2.3 `.qsf` generieren statt pflegen
Handgepflegt bleibt pro Variante nur `device.tcl` (drei Zeilen) und `pins.tcl` (85 bzw. 81
`set_location_assignment`). Die Dateiliste kommt aus `scripts/files_common.tcl` plus der
Familienauswahl über `RtlFamily`. `gen_qsf.ps1` setzt daraus die `.qsf` zusammen. Damit
kann eine neue `.vhd` nicht mehr in einer von zwei `.qsf` fehlen.

Nebeneffekt, der sofort greift: `check.ps1` und `build.ps1` regenerieren vorher, also fällt
auf, wenn Quartus aus der IDE heraus in die Datei zurückgeschrieben hat.

### 2.4 Compile-Check als Sicherheitsnetz
`check.ps1` baut beide Varianten und vergleicht gegen `scripts/baseline.csv`. Ohne diesen
Vergleich wäre nicht belegbar gewesen, dass der Umbau die HW-erprobte Variante nicht
verändert hat.

## 3. Ablauf

Anders als bei WillFA7 gab es **keine Etappe „erst inhaltlich angleichen"** – die Varianten
waren am selben Tag auseinander hervorgegangen und schon auf einem Stand. Der Umzug lief in
einem Zug, abgesichert durch die Baseline aus dem alten Baum:

| # | Inhalt | Ergebnis |
|---|---|---|
| 0 | Baseline im alten Baum, `AtariFA_dev_open` als ZIP gesichert (hatte kein Git) | Referenz |
| 1 | `.git` nach `FPGA_source`, Baum per `git mv` sortiert, `init_file`-Pfade auf `../../rom/` | – |
| 2 | `version_pkg` + `variant_pkg` mit `BOARD_ID` | – |
| 3 | `instruction_buffer_type` nach `rtl/common/display_pkg.vhd` | – |
| 4 | gemeinsame Portliste (`LED_D4`, `debug_signal(7:0)`) + `VIRTUAL_PIN` | – |
| 5 | ein `top/AtariFA.vhd` | – |
| 6 | `gen_qsf.ps1`, `.qsf` generiert | Assignments Zeile für Zeile identisch |
| 7 | `.cof` auf relative Pfade | – |
| 8 | `check.ps1` / `build.ps1` / `release.ps1` / `baseline.csv` | beide Varianten „clean" |

## 4. Was anders kam als geplant

- **Die LE-Zahl des Fitters taugt nicht als Abnahmekriterium.** Sie war als exakter
  Vergleich vorgesehen (so macht es WillFA7). Gemessen: die Synthese von `cyclone_10_pcb`
  blieb Byte für Byte gleich (2433 kombinatorische Funktionen, 935 Register, 202.752
  Memory Bits), und der Fitter ging trotzdem von 2554 auf 2545 LE – der eine zusätzliche
  `VIRTUAL_PIN` reicht, damit er anders packt. Das Kriterium wurde auf die
  **Synthesezahlen** umgestellt; `baseline.csv` führt die Fitter-LE nur noch als Information
  mit. Damit ist auch belegt, was wirklich zählt: **die Netzliste der hardwareerprobten
  Variante ist unverändert.**
- **Der Umbau hat in `dev_open` einen echten Fehler mitgenommen.** `LED_D4` war dort
  deklariert, aber von niemandem getrieben – `Warning (10541): used implicit default value
  for signal "LED_D4" because signal was never assigned`. Diese Warnung ist jetzt weg, und
  die 8 kombinatorischen Funktionen weniger (2440 → 2432) sind genau das.
- **Zweiter latenter Fehler, ebenfalls in `dev_open`:** `gen_dbg1`/`gen_dbg2` wiesen dem auf
  3 Bit verkleinerten `debug_signal` ein 8-Bit-Signal zu. Solange `DBG_MODE = 0` gilt, wird
  der Zweig nicht elaboriert; beim Umschalten auf 1 oder 2 wäre die Synthese gebrochen. Mit
  der gemeinsamen 8-Bit-Portliste ist das strukturell erledigt.
- **`AtariFA_dev_open` hatte kein Git.** Die dort gemachten Pin-Änderungen existierten in
  keiner Historie. Vor dem ersten Eingriff gesichert als
  `N:\Projekte\FPGA Atari\AtariFA_dev_open_BACKUP_2026-08-06.zip`.
- **Kein `.gitattributes eol=crlf`.** Bei WillFA7 war das nötig, weil sich die Varianten in
  den Zeilenenden unterschieden. Hier ist der Baum aus einer Quelle entstanden; ein
  `text=auto`-Eintrag hätte nur eine Renormalisierung des halben Repos ausgelöst. Stattdessen
  `* -text` – Zeilenenden bleiben, wie sie committet sind.

## 5. Ziel-Workflow

Steht in `WORKFLOW.md`. Kurz: ändern in `rtl/common/` bzw. `top/`, `check.ps1 -Fit`,
auf `cyclone_10_pcb` in Hardware testen, Version in `version_pkg.vhd`, `release.ps1`,
ein Commit für beide Varianten.

## 6. Was offen bleibt

- **Hardwaretest des umgebauten Stands** – auf keinem Board erfolgt. Die Netzliste von
  `cyclone_10_pcb` ist zwar nachweislich unverändert, aber „nachweislich unverändert" ist
  kein Hardwaretest. Prüfliste in `VARIANTEN.md`.
- **`cyclone_10_dev_open` war noch nie auf Hardware** – unabhängig vom Umbau. Das Pinout
  dieses Boards ist gegen die Platine nie geprüft worden.
- **Der Aux-Board-Audiopfad** nach dem Dauerton-Fix von SW 0.1.1 ist ebenfalls noch
  ungetestet (siehe `CLAUDE.md`, Abschnitt Sound).
- **Die alten Ordner** `N:\Projekte\FPGA Atari\AtariFA\` und `...\AtariFA_dev_open\` stehen
  unverändert als vorläufiges Backup. Rückbau erst nach ausdrücklicher Freigabe und nach dem
  Hardwaretest. Aus `AtariFA\` darf nicht mehr gepusht werden – es zeigt auf dasselbe Remote.
- **`AtariFA - on SYS3 Test PCB`** (Cyclone IV, Stand 06.06.2026) bleibt bewusst außen vor.
  Nachrücken hieße `variants/cyclone_iv_sys3/` + `rtl/cyclone_iv/` + `files_cyclone_iv.tcl`
  – die Struktur ist darauf vorbereitet, der Codestand dort ist es nicht.
