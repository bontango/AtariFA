<#
.SYNOPSIS
  Full compile of one AtariFA variant, plus the .jic for the serial configuration device.

.DESCRIPTION
  Runs quartus_sh --flow compile in variants\<name>\ and then quartus_cpf against the
  variant's AtariFA.cof. The .sof comes out of the flow, the .jic does NOT - it has to
  be converted, which is what the .cof describes.

  quartus_cpf runs with the variant folder as its working directory, so the paths
  inside the .cof must be relative to it (output_files/AtariFA.sof). They used to be
  absolute and pointed into the old flat project folder; do not let Quartus write
  them back as absolute paths.

.PARAMETER Variant
  Folder name below variants\, e.g. cyclone_10_pcb.

.PARAMETER NoGen
  Do not regenerate the .qsf first.

.PARAMETER NoJic
  Stop after the compile, do not run quartus_cpf.

.EXAMPLE
  .\build.ps1 cyclone_10_pcb
#>
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string] $Variant,
    [switch] $NoGen,
    [switch] $NoJic
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir
$VarDir    = Join-Path (Join-Path $RepoRoot 'variants') $Variant
if (-not (Test-Path $VarDir)) { throw "unknown variant: $Variant (looked in $RepoRoot\variants)" }

$QuartusBin = 'C:\intelFPGA_lite\22.1std\quartus\bin64'
$project    = 'AtariFA'

if (-not $NoGen) { & (Join-Path $ScriptDir 'gen_qsf.ps1') -Variants $Variant -Quiet }

$meta = Import-PowerShellDataFile (Join-Path $VarDir 'variant.psd1')
Write-Host "Building $($meta.Name) - $($meta.Title)" -ForegroundColor Cyan

Push-Location $VarDir
try {
    $sh = Join-Path $QuartusBin 'quartus_sh.exe'
    if (-not (Test-Path $sh)) { throw "quartus_sh not found: $sh" }
    & $sh --flow compile $project
    if ($LASTEXITCODE -ne 0) { throw "compile failed for $Variant (exit $LASTEXITCODE)" }

    $sof = Join-Path $VarDir 'output_files\AtariFA.sof'
    if (-not (Test-Path $sof)) { throw "compile reported success but $sof is missing" }
    Write-Host "  .sof ok" -ForegroundColor Green

    if (-not $NoJic -and $meta.ReleaseArtifact -eq 'jic') {
        $cpf = Join-Path $QuartusBin 'quartus_cpf.exe'
        if (-not (Test-Path $cpf)) { throw "quartus_cpf not found: $cpf" }
        & $cpf -c 'AtariFA.cof'
        if ($LASTEXITCODE -ne 0) { throw "quartus_cpf failed for $Variant (exit $LASTEXITCODE)" }
        Write-Host "  .jic ok" -ForegroundColor Green
    }
}
finally { Pop-Location }

Write-Host "Done: variants\$Variant\output_files\" -ForegroundColor Green
