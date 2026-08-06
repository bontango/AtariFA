<#
.SYNOPSIS
  Builds every active AtariFA variant and copies the artefacts to bin\<BinFolder>\.

.DESCRIPTION
  A release is one version across all boards: the version digits live in
  rtl\common\version_pkg.vhd (SW_SUB1/SW_SUB2) plus BOARD_ID per variant, so every
  board built here reports <BoardId>.<SW_SUB1>.<SW_SUB2> on its boot info display.

  The artefact name carries the version, the folder carries the board. Nothing is
  overwritten silently: an existing file of the same name aborts the run unless
  -Force is given.

  The changelog is append only and is the place to write down what is NOT tested -
  cyclone_10_dev_open has never run on hardware.

.PARAMETER Note
  One line describing this release. Goes into bin\changelog.txt. Required.

.PARAMETER Variants
  Limit to these variants. Default: all that are not Dormant.

.PARAMETER Force
  Overwrite artefacts that already exist in bin\.

.EXAMPLE
  .\release.ps1 -Note "shared source tree, no functional change"
#>
param(
    [Parameter(Mandatory=$true)]
    [string]  $Note,
    [string[]]$Variants,
    [switch]  $Force
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$VarRoot   = Join-Path $RepoRoot 'variants'
$BinRoot   = Join-Path $RepoRoot 'bin'

# Read the shared version digits out of version_pkg.vhd - no second place to keep
# in sync, and a typo there shows up as a wrong file name before it ships.
$vpkg = Get-Content (Join-Path $RepoRoot 'rtl\common\version_pkg.vhd') -Raw
if ($vpkg -notmatch 'SW_SUB1\s*:\s*std_logic_vector\(3 downto 0\)\s*:=\s*x"([0-9A-Fa-f])"') { throw 'SW_SUB1 not found in rtl\common\version_pkg.vhd' }
$sub1 = $Matches[1]
if ($vpkg -notmatch 'SW_SUB2\s*:\s*std_logic_vector\(3 downto 0\)\s*:=\s*x"([0-9A-Fa-f])"') { throw 'SW_SUB2 not found in rtl\common\version_pkg.vhd' }
$sub2 = $Matches[1]

$folders = Get-ChildItem $VarRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'variant.psd1') }
if ($Variants) { $folders = $folders | Where-Object { $Variants -contains $_.Name } }
else           { $folders = $folders | Where-Object { -not (Import-PowerShellDataFile (Join-Path $_.FullName 'variant.psd1')).Dormant } }
if (-not $folders) { throw "nothing to release below $VarRoot" }

New-Item -ItemType Directory -Force $BinRoot | Out-Null
$made = @()

foreach ($dir in $folders) {
    $meta = Import-PowerShellDataFile (Join-Path $dir.FullName 'variant.psd1')
    $ver  = "$($meta.BoardId)$sub1$sub2"      # e.g. 012 for board 0, version .1.2

    & (Join-Path $ScriptDir 'build.ps1') $meta.Name
    if ($LASTEXITCODE -ne 0) { throw "build failed for $($meta.Name)" }

    $ext = $meta.ReleaseArtifact                       # 'jic' or 'sof'
    $src = Join-Path $dir.FullName "output_files\AtariFA.$ext"
    if (-not (Test-Path $src)) { throw "missing artefact: $src" }

    $outDir = Join-Path $BinRoot $meta.BinFolder
    New-Item -ItemType Directory -Force $outDir | Out-Null
    $dst = Join-Path $outDir "AtariFA_v$ver.$ext"
    if ((Test-Path $dst) -and -not $Force) { throw "$dst already exists - bump the version in rtl\common\version_pkg.vhd or use -Force" }
    Copy-Item $src $dst -Force

    $hash = (Get-FileHash $dst -Algorithm SHA256).Hash.Substring(0,16)
    $made += [pscustomobject]@{ Variant = $meta.Name; Version = "$($meta.BoardId).$sub1.$sub2"; File = $dst; SHA256 = $hash }
}

$log = Join-Path $BinRoot 'changelog.txt'
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
$lines = @("", "$stamp  version .$sub1.$sub2", "  $Note")
foreach ($m in $made) { $lines += ("  {0,-22} {1,-8} {2}  sha256:{3}" -f $m.Variant, $m.Version, (Split-Path $m.File -Leaf), $m.SHA256) }
Add-Content -Path $log -Value $lines -Encoding UTF8

$made | Format-Table Variant, Version, File, SHA256 -AutoSize
Write-Host "changelog: $log" -ForegroundColor Green
Write-Host "Remember to note in VARIANTEN.md which of these has actually been on hardware." -ForegroundColor Yellow
