[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sdkDirectory = Join-Path $projectRoot '.dotnet'
$sdkVersion = '10.0.400'
$dotnet = Join-Path $sdkDirectory 'dotnet.exe'

if (Test-Path -LiteralPath $dotnet) {
    $installedVersion = (& $dotnet --version).Trim()
    if ($installedVersion -eq $sdkVersion) {
        Write-Host ".NET SDK $sdkVersion is already installed in $sdkDirectory"
        exit 0
    }
}

$installer = Join-Path $env:TEMP "snapik-dotnet-install-$([Guid]::NewGuid().ToString('N')).ps1"
try {
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $installer
    & $installer -Version $sdkVersion -InstallDir $sdkDirectory -NoPath
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet-install exited with code $LASTEXITCODE."
    }
}
finally {
    if (Test-Path -LiteralPath $installer) {
        Remove-Item -LiteralPath $installer -Force
    }
}

