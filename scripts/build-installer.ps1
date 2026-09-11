[CmdletBinding()]
param(
    [switch]$NoRestore,
    [switch]$SkipTests,
    [switch]$SkipPublish
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$publishDir = Join-Path $projectRoot 'artifacts\publish'
$outputDir = Join-Path $projectRoot 'artifacts\installer'
$issFile = Join-Path $projectRoot 'installer\SnapBrief.iss'

if (-not $SkipPublish) {
    $buildArgs = @{}
    if ($NoRestore) { $buildArgs.NoRestore = $true }
    if ($SkipTests) { $buildArgs.SkipTests = $true }
    & (Join-Path $PSScriptRoot 'build.ps1') @buildArgs
}

if (-not (Test-Path -LiteralPath (Join-Path $publishDir 'SnapBrief.exe'))) {
    throw "No publish found at $publishDir. Run scripts\build.ps1 first."
}

$iscc = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) {
    throw 'Inno Setup 6 not found. Install it: winget install --id JRSoftware.InnoSetup -e'
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
& $iscc "/DPublishDir=$publishDir" "/DOutputDir=$outputDir" /Qp $issFile
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE." }

$setup = Get-ChildItem -LiteralPath $outputDir -Filter 'SnapBrief-Setup-*.exe' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$hash = (Get-FileHash -LiteralPath $setup.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host ("Installer: {0} ({1:N1} MB, sha256 {2})" -f $setup.FullName, ($setup.Length / 1MB), $hash)
