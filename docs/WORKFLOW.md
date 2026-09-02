# AtariFA — Arbeitsablauf

Wie man in diesem Baum etwas ändert, ohne die anderen Varianten zu vergessen — und wie die
Quartus-IDE neben den Skripten koexistiert.

---

## Die eine Regel

**`variants/<name>/AtariFA.qsf` ist erzeugt. Niemals von Hand ändern.**

Sie wird aus sechs Bausteinen zusammengesetzt (`scripts/gen_qsf.ps1`):

| Baustein | Inhalt | gepflegt von |
|---|---|---|
| `scripts/common_header.tcl` | globale Assignments, in jeder Variante gleich | Hand |
| `variants/<n>/device.tcl` | FAMILY, DEVICE, Quartus-Version | Hand |
| `variants/<n>/pins.tcl` | die `set_location_assignment`-Zeilen | Hand |
| `variants/<n>/variant.psd1` | Board-ID, Familie, VirtualPins, Release-Ziel | Hand |
| `scripts/files_common.tcl` | die gemeinsamen Quellen inkl. Top-Level | Hand |
| `scripts/files_<family>.tcl` | die Megafunctions der Familie (`cyclone_10`, `cyclone_IV`) | Hand |

Quartus schreibt aus der IDE heraus selbst in die `.qsf` zurück. Deshalb rufen `check.ps1`
und `build.ps1` als Erstes `gen_qsf.ps1 -Quiet` auf und melden es gelb, wenn dabei etwas
zurückgesetzt werden musste. `gen_qsf.ps1 -Check` zeigt den Unterschied, ohne zu schreiben.

## Was du ändern willst → wo es hingehört

| Vorhaben | Ort |
|---|---|
| Logik ändern, Modul erweitern | `rtl/common/*.vhd` bzw. `top/AtariFA.vhd` |
| **neue** `.vhd` ins Projekt | Datei nach `rtl/common/`, Zeile in `scripts/files_common.tcl` |
| Pin verschieben, Pin ergänzen | `variants/<n>/pins.tcl` |
| Port, den ein Board nicht hat | Port bleibt im Top-Level, Name in `VirtualPins` in `variant.psd1` |
| anderer FPGA / andere Quartus-Version | `variants/<n>/device.tcl` |
| Versionsnummer hochziehen | **nur** `rtl/common/version_pkg.vhd` (`SW_SUB1`/`SW_SUB2`) |
| Board-Kennziffer | `variants/<n>/variant_pkg.vhd` (`BOARD_ID`) |
| Timing-Constraint | `variants/<n>/AtariFA.sdc` |
| `.sof` → `.jic` | `variants/<n>/AtariFA.cof`, Pfade **relativ** halten |
| neue Variante | Ordner unter `variants/` mit den sieben Dateien anlegen, `gen_qsf.ps1` |
| neue **Chipfamilie** | `rtl/<family>/` + `scripts/files_<family>.tcl`, dann `RtlFamily` in `variant.psd1` |

## Ablauf einer Änderung

1. Ändern in `rtl/common/` bzw. `top/AtariFA.vhd`.
2. `scripts\check.ps1` — schnelle Synthese aller Varianten. Fängt Syntax- und
   Elaborationsfehler und vergleicht schon hier Comb/Reg/Memory gegen die Baseline.
3. `scripts\check.ps1 -Fit` — Fitter und Timing dazu. **Comb/Register/Memory müssen exakt
   stimmen**, sonst ist etwas anderes passiert als beabsichtigt; die LE-Zahl des Fitters
   ist nur Information — sie schwankt schon dann, wenn sich die Packung ändert (ein
   einzelner zusätzlicher `VIRTUAL_PIN` genügt).
4. `scripts\build.ps1 cyclone_10_pcb` → `.jic` flashen → auf der Platine testen.
5. Version in `rtl/common/version_pkg.vhd` hochziehen.
6. `scripts\release.ps1 -Note "..."` → alle Varianten bauen, nach `bin/` kopieren,
   Changelog schreiben.
7. Ein Commit, ein Tag — alle Varianten konsistent.

Absichtliche Ressourcenänderung? Dann `scripts/baseline.csv` mit der neuen Zahl **und einer
Begründung in der Note-Spalte** nachziehen. Die Notiz ist der Teil, der später zählt.

## Quartus-IDE

Die IDE ist nicht verboten, sie ist nur nicht die Quelle der Wahrheit. Öffne
`variants/<n>/AtariFA.qpf` und arbeite normal — nur:

- Dateien **nicht** über die IDE zum Projekt hinzufügen. Das landet in der generierten
  `.qsf` und ist beim nächsten `gen_qsf.ps1` weg. Stattdessen `files_common.tcl`.
- Pin-Planner-Änderungen sofort nach `pins.tcl` übertragen (oder gleich dort machen).
- Nach IDE-Sitzungen einmal `gen_qsf.ps1 -Check` laufen lassen — es zeigt genau, was
  Quartus hineingeschrieben hat.

## Stolperfallen, die hier schon zugeschlagen haben

- **Pfade sind projektverzeichnisrelativ**, und das Projektverzeichnis ist
  `variants/<n>/`. Das gilt für die Quellenliste, für `init_file` in den ROM-Wrappern
  (`../../rom/...`) und für die Pfade in der `.cof`. Die `.qip` sind die Ausnahme: sie
  benutzen `$::quartus(qip_path)` und sind ortsunabhängig.
- **Ein deklarierter Ausgangsport ohne Location ist für Quartus ein benutzter Pin.**
  `RESERVE_ALL_UNUSED_PINS` schützt nicht davor. Dafür ist `VirtualPins` da.
- **Quartus löst Entity-Referenzen auch im nicht genommenen `generate`-Zweig auf**
  (`Error 10481`). Optionale Module müssen in *jede* Dateiliste, auch wo sie nichts kosten.
- **`else generate` gibt es in VHDL-93 nicht** — immer zwei komplementäre `if ... generate`.
- **Generate-Labels ändern Hierarchienamen.** Was in `AtariFA.sdc` referenziert wird, darf
  nicht in ein Generate wandern, sonst brechen die Constraints stumm.
- **`numeric_std` nicht neben `std_logic_unsigned`** (`Error 10327`) — dieser Baum benutzt
  durchgehend `std_logic_unsigned`.
- **Ein Pfadfehler tarnt sich als Portlistenfehler** (`Error 10349, formal ... does not
  exist`). Erst die Dateiliste prüfen, dann die Entity.
