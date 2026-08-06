<#
.SYNOPSIS
  Builds the AtariFA variants and compares result, resources and timing in one table.

.DESCRIPTION
  Scans variants\ for subfolders containing a *.qpf, picks the Quartus installation
  that matches the FAMILY line of the *.qsf and runs Analysis & Synthesis, optionally
  the Fitter and the Timing Analyzer as well. Afterwards fit.rpt / map.rpt / sta.rpt
  are parsed and, unless -NoBaseline is given, checked against scripts\baseline.csv.

  Without a switch only quartus_map runs - fast, catches syntax and elaboration
  errors. Resource and timing figures need -Fit.

  Variants marked Dormant in their variant.psd1 are skipped by default. None is today.

.PARAMETER Root
  Folder holding the variant folders. Default: the variants\ folder next to this script.

.PARAMETER Variants
  Folder names to check. Default: all active ones.

.PARAMETER Fit
  Run the Fitter and the Timing Analyzer on top of the mapper (gives LE/Memory/Slack).

.PARAMETER Full
  Run the complete flow (map+fit+asm+sta), producing the .sof.

.PARAMETER All
  Also check the variants marked Dormant in their variant.psd1. None is today.

.PARAMETER NoBaseline
  Do not compare against scripts\baseline.csv.

.PARAMETER NoGen
  Do not regenerate the .qsf first. Only for deliberately checking a hand edited
  one - the next run without the switch throws that edit away again.

.EXAMPLE
  .\check.ps1 -Fit

.EXAMPLE
  .\check.ps1 -Variants cyclone_10_pcb -Fit
#>
param(
    [string]  $Root,
    [string[]]$Variants,
    [switch]  $Fit,
    [switch]  $Full,
    [switch]  $All,
    [switch]  $NoBaseline,
    [switch]  $NoGen
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$OwnRoot   = -not $Root                      # working on the repo's own variants\
if (-not $Root) { $Root = Join-Path $RepoRoot 'variants' }

# Quartus rewrites the .qsf by itself when the project has been open in the IDE. The
# .qsf is a generated file, so regenerate it before anything reads it. Otherwise the
# numbers below describe a project nobody can reproduce from device.tcl / pins.tcl /
# variant.psd1. Silent unless something actually had to be put back.
if ($OwnRoot -and -not $NoGen) { & (Join-Path $ScriptDir 'gen_qsf.ps1') -Quiet }

# How much setup slack drift counts as a finding, and below which value the slack
# itself is worth flagging regardless of the baseline.
#
# Slack is placement dependent: byte-identical sources have been measured more than
# 1 ns apart between runs on this family. A tolerance below that only produces false
# alarms, and a column that cries wolf every run is a column nobody reads. What
# actually matters is the absolute value, which SlackFloor covers - and on AtariFA
# the tight domain is cpu_clk, not clk_50.
$SlackTolerance = 1.5
$SlackFloor     = 1.0

# ---------------------------------------------------------------------------
# Quartus installations. Key = substring of the FAMILY value in the .qsf,
# DEFAULT applies when nothing matches. quartus_sh is not on the PATH here.
#
# Both AtariFA boards are Cyclone 10 LP and use 22.1std; the table exists so a
# future variant on another family does not need a new mechanism. The other
# installations on this machine (C:\intelFPGA\23.1std, C:\altera) are programmer
# only or the wrong version - do not point this at them.
# ---------------------------------------------------------------------------
$QuartusBin = [ordered]@{
    'DEFAULT' = 'C:\intelFPGA_lite\22.1std\quartus\bin64'
}

function Get-QuartusBin([string]$Family) {
    foreach ($key in $QuartusBin.Keys) {
        if ($key -eq 'DEFAULT') { continue }
        if ($Family -like "*$key*") { return $QuartusBin[$key] }
    }
    return $QuartusBin['DEFAULT']
}

# First number out of lines like "; Total logic elements ; 2,554 / 6,272 ( 41 % ) ;"
function Get-ReportValue([string]$Path, [string]$Label) {
    if (-not (Test-Path $Path)) { return $null }
    $line = Select-String -Path $Path -Pattern ("^;\s+" + [regex]::Escape($Label) + "\s+;") -List
    if ($null -eq $line) { return $null }
    $parts = $line.Line -split ';'
    if ($parts.Count -lt 3) { return $null }
    return $parts[2].Trim()
}

# "2,554 / 6,272 ( 41 % )" -> 2554
function Get-FirstNumber([string]$Text) {
    if (-not $Text) { return $null }
    if ($Text -match '([\d,]+)') { return [int](($Matches[1]) -replace ',','') }
    return $null
}

# The netlist, straight out of Analysis & Synthesis: combinational functions,
# registers, memory bits. THESE are the property of the design and must match a
# baseline exactly.
#
# The fitter's "Total logic elements" must NOT be used for that. Measured 06.08.2026
# during the move into this tree: adding a single VIRTUAL_PIN left the synthesis
# result byte for byte identical (2433 comb / 935 reg / 202752 bit) while the fitter
# went 2554 -> 2545, because it packs LEs differently once one more node exists. An
# exact test on that number reports a change that did not happen.
function Get-SynthNumbers([string]$MapPath) {
    $r = @{ Comb = $null; Reg = $null; Mem = $null }
    if (-not (Test-Path $MapPath)) { return $r }
    $m = Select-String -Path $MapPath -Pattern '^;\s+Total combinational functions\s+;\s+([\d,]+)' -List
    if ($m) { $r.Comb = [int](($m.Matches[0].Groups[1].Value) -replace ',','') }
    $m = Select-String -Path $MapPath -Pattern '^;\s+Total registers\s+;\s+([\d,]+)' -List
    if ($m) { $r.Reg = [int](($m.Matches[0].Groups[1].Value) -replace ',','') }
    $m = Select-String -Path $MapPath -Pattern '^;\s+Total memory bits\s+;\s+([\d,]+)' -List
    if ($m) { $r.Mem = [int](($m.Matches[0].Groups[1].Value) -replace ',','') }
    return $r
}

# Worst setup slack over all clocks, from the Setup Summary.
# Careful: "... Model Setup Summary" also appears in the table of contents of the
# .rpt, and right behind the table other tables with completely different numbers
# follow. The table is therefore strictly delimited: it consists only of lines
# starting with ';' or '+', the first line without that pattern ends it.
function Get-WorstSlack([string]$StaPath) {
    if (-not (Test-Path $StaPath)) { return $null }
    $inTable = $false
    $worst   = $null
    foreach ($line in Get-Content $StaPath) {
        if (-not $inTable) {
            # Only real section headings, not the TOC line ("  12. Slow ...")
            if ($line -match 'Model Setup Summary' -and $line -notmatch '^\s*\d+\.\s') {
                $inTable = $true
            }
            continue
        }
        if ($line -notmatch '^\s*[;+]') { $inTable = $false; continue }
        # Data line "; <clock> ; <slack> ; <tns> ;" - the header line has text in
        # column 2 and therefore fails the number pattern.
        if ($line -match '^;\s+\S.*?;\s+(-?\d+(?:\.\d+)?)\s+;') {
            $val = [double]$Matches[1]
            if ($null -eq $worst -or $val -lt $worst) { $worst = $val }
        }
    }
    if ($null -eq $worst) { return $null }
    return $worst.ToString('0.000', [System.Globalization.CultureInfo]::InvariantCulture)
}

# Warnings worth watching: 10036 = port declared but never used, 10492/10540 =
# signal used but never assigned. Something in this class appearing where it did not
# before usually means a signal got lost in a refactor.
#
# Deliberately NOT watched, because they are expected on every AtariFA build:
#   113009  Intel-HEX 32 byte records into an 8 bit memory - format inherent
#   14320   sound_rom q[7:4] optimised away - the ROM is 4 bit wide by design
#   stuck at VCC on solenoids[14]/[18] - those MOSFETs are not fitted
function Get-WatchedWarnings([string]$RptPath) {
    if (-not (Test-Path $RptPath)) { return @() }
    $hits = Select-String -Path $RptPath -Pattern 'Warning \((10036|10492|10540)\)'
    if (-not $hits) { return @() }
    return @($hits | ForEach-Object { $_.Line.Trim() })
}

# "22.1std" out of the installation path
function Get-QuartusLabel([string]$BinPath) {
    if ($BinPath -match '\\([^\\]+)\\quartus\\bin') { return $Matches[1] }
    return $BinPath
}

# ---------------------------------------------------------------------------

if (-not (Test-Path $Root)) { throw "Root not found: $Root" }

$found = Get-ChildItem -Path $Root -Directory | Where-Object {
    Get-ChildItem -Path $_.FullName -Filter '*.qpf' -File -ErrorAction SilentlyContinue
}
if ($Variants) {
    $found = $found | Where-Object { $Variants -contains $_.Name }
}
elseif (-not $All) {
    # Skip the dormant ones unless explicitly asked for.
    $found = $found | Where-Object {
        $meta = Join-Path $_.FullName 'variant.psd1'
        if (-not (Test-Path $meta)) { return $true }
        $data = Import-PowerShellDataFile $meta
        -not $data.Dormant
    }
}
if (-not $found) { throw "No variant folders with *.qpf below $Root" }

$baseline = @{}
$baselineFile = Join-Path $ScriptDir 'baseline.csv'
if (-not $NoBaseline -and (Test-Path $baselineFile)) {
    foreach ($row in (Import-Csv $baselineFile -Delimiter ';')) { $baseline[$row.Variant] = $row }
}

$mode = 'map'
if ($Fit)  { $mode = 'fit'  }
if ($Full) { $mode = 'full' }
Write-Host "Mode: $mode - $($found.Count) variant(s) below $Root" -ForegroundColor Cyan

$results = @()

foreach ($dir in $found) {
    $qpf     = (Get-ChildItem -Path $dir.FullName -Filter '*.qpf' -File | Select-Object -First 1)
    $project = [System.IO.Path]::GetFileNameWithoutExtension($qpf.Name)
    $qsf     = Join-Path $dir.FullName "$project.qsf"

    $family = ''
    $device = ''
    if (Test-Path $qsf) {
        $fLine = Select-String -Path $qsf -Pattern '-name FAMILY\s+"?([^"\r\n]+)"?' -List
        if ($fLine) { $family = $fLine.Matches[0].Groups[1].Value.Trim().Trim('"') }
        $dLine = Select-String -Path $qsf -Pattern '-name DEVICE\s+(\S+)' -List
        if ($dLine) { $device = $dLine.Matches[0].Groups[1].Value.Trim() }
    }

    $bin = Get-QuartusBin $family
    Write-Host ("  {0,-22} {1,-16} {2}" -f $dir.Name, $family, (Get-QuartusLabel $bin))

    $status = 'ok'
    $firstError = ''

    Push-Location $dir.FullName
    try {
        $steps = @()
        switch ($mode) {
            'map'  { $steps = @(@{exe='quartus_map.exe'; args=@($project)}) }
            'fit'  { $steps = @(@{exe='quartus_map.exe'; args=@($project)},
                                @{exe='quartus_fit.exe'; args=@($project)},
                                @{exe='quartus_sta.exe'; args=@($project)}) }
            'full' { $steps = @(@{exe='quartus_sh.exe';  args=@('--flow','compile',$project)}) }
        }

        foreach ($step in $steps) {
            $exe = Join-Path $bin $step.exe
            if (-not (Test-Path $exe)) {
                $status = 'quartus missing'; $firstError = $exe; break
            }
            $out = & $exe $step.args
            if ($LASTEXITCODE -ne 0) {
                $status = "FAILED ($($step.exe))"
                $err = $out | Select-String -Pattern '^Error \(' | Select-Object -First 1
                if ($err) { $firstError = $err.Line.Trim() }
                break
            }
        }
    }
    finally { Pop-Location }

    # Only evaluate the reports when the run was clean. Otherwise the numbers come
    # from an earlier build and claim something about code that could not even be
    # compiled just now.
    $le = $null; $mem = $null; $slk = $null; $warn = @()
    $syn = @{ Comb = $null; Reg = $null; Mem = $null }
    if ($status -eq 'ok') {
        $of = Join-Path $dir.FullName 'output_files'
        $warn = Get-WatchedWarnings (Join-Path $of "$project.map.rpt")
        # The netlist figures come from the mapper and are available in every mode.
        $syn = Get-SynthNumbers (Join-Path $of "$project.map.rpt")
        $mem = $syn.Mem
        if ($mode -ne 'map') {
            $le  = Get-ReportValue (Join-Path $of "$project.fit.rpt") 'Total logic elements'
            $slk = Get-WorstSlack  (Join-Path $of "$project.sta.rpt")
        }
    }

    # Baseline comparison. Comb/Reg/Mem are the design and are checked in every mode;
    # slack needs the timing analyzer, so only with -Fit / -Full. The fitter's LE
    # number is reported but deliberately NOT compared - see Get-SynthNumbers.
    $delta = ''
    if ($status -eq 'ok' -and $baseline.ContainsKey($dir.Name)) {
        $b = $baseline[$dir.Name]
        $bits = @()
        if ($null -ne $syn.Comb -and $syn.Comb -ne [int]$b.Comb) { $bits += ("Comb {0:+#;-#;0}" -f ($syn.Comb - [int]$b.Comb)) }
        if ($null -ne $syn.Reg  -and $syn.Reg  -ne [int]$b.Reg)  { $bits += ("Reg {0:+#;-#;0}"  -f ($syn.Reg  - [int]$b.Reg))  }
        if ($null -ne $syn.Mem  -and $syn.Mem  -ne [int]$b.Mem)  { $bits += ("Mem {0:+#;-#;0}"  -f ($syn.Mem  - [int]$b.Mem))  }
        # Slack is placement dependent and jitters between runs of identical sources.
        # Only a big move or an actually tight result is worth reporting - anything
        # else is noise that trains you to ignore the whole column.
        if ($slk) {
            $d = [double]$slk - [double]$b.Slack
            if ([math]::Abs($d) -gt $SlackTolerance) { $bits += ("Slack {0:+0.000;-0.000}" -f $d) }
            elseif ([double]$slk -lt $SlackFloor)    { $bits += ("Slack only $slk ns") }
        }
        if ($bits) { $delta = $bits -join ', ' } else { $delta = '=' }
    }

    if ($status -ne 'ok')      { Write-Host "       -> $status" -ForegroundColor Red }
    elseif ($delta -and $delta -ne '=') { Write-Host "       -> ok, but baseline delta: $delta" -ForegroundColor Yellow }
    else                       { Write-Host '       -> ok' -ForegroundColor Green }
    foreach ($w in $warn)      { Write-Host "          $w" -ForegroundColor DarkYellow }

    $results += [pscustomobject]@{
        Variant  = $dir.Name
        Device   = $device
        Status   = $status
        Comb     = $syn.Comb
        Reg      = $syn.Reg
        Memory   = $mem
        LEfit    = $le
        Slack    = $slk
        Delta    = $delta
        Warnings = $warn.Count
        Error    = $firstError
    }
}

Write-Host ''
$results | Format-Table Variant, Device, Status, Comb, Reg, Memory, LEfit, Slack, Delta, Warnings -AutoSize

$bad = $results | Where-Object { $_.Status -ne 'ok' }
if ($bad) {
    Write-Host 'Errors:' -ForegroundColor Red
    $bad | ForEach-Object { Write-Host "  $($_.Variant): $($_.Error)" }
    exit 1
}
$drift = $results | Where-Object { $_.Delta -and $_.Delta -ne '=' }
if ($drift) {
    Write-Host 'Baseline drift:' -ForegroundColor Yellow
    $drift | ForEach-Object { Write-Host "  $($_.Variant): $($_.Delta)" }
    exit 2
}
Write-Host 'All variants clean.' -ForegroundColor Green
