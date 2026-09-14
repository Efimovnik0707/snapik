[CmdletBinding()]
param(
    [switch]$NoRestore,
    [switch]$SkipTests,
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$dotnet = Join-Path $projectRoot '.dotnet\dotnet.exe'
$solution = Join-Path $projectRoot 'SnapBrief.slnx'
$appProject = Join-Path $projectRoot 'src\SnapBrief.App\SnapBrief.App.csproj'
$canonicalPublishDirectory = Join-Path $projectRoot 'artifacts\publish'
$smokeDirectoryPrefix = 'snapbrief-build-smoke-'
$candidateDirectoryPrefix = 'snapbrief-candidate-'

function Assert-SafeSmokeDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedTempRoot = [IO.Path]::GetFullPath($env:TEMP)
    $resolvedSmokeDirectory = [IO.Path]::GetFullPath($Path)
    $tempRootPrefix = $resolvedTempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $trimmedSmokeDirectory = $resolvedSmokeDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $directoryName = [IO.Path]::GetFileName($trimmedSmokeDirectory)
    if (-not $resolvedSmokeDirectory.StartsWith($tempRootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $directoryName.StartsWith($smokeDirectoryPrefix, [StringComparison]::Ordinal)) {
        throw "Refusing to use unsafe smoke-test directory '$resolvedSmokeDirectory'."
    }

    return $resolvedSmokeDirectory
}

function Assert-SafeCandidateDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedTempRoot = [IO.Path]::GetFullPath($env:TEMP)
    $resolvedCandidateDirectory = [IO.Path]::GetFullPath($Path)
    $tempRootPrefix = $resolvedTempRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $trimmedCandidateDirectory = $resolvedCandidateDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $directoryName = [IO.Path]::GetFileName($trimmedCandidateDirectory)
    if (-not $resolvedCandidateDirectory.StartsWith($tempRootPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not $directoryName.StartsWith($candidateDirectoryPrefix, [StringComparison]::Ordinal)) {
        throw "Refusing to use unsafe release-candidate directory '$resolvedCandidateDirectory'."
    }

    return $resolvedCandidateDirectory
}

$expectedPublish = [IO.Path]::GetFullPath($canonicalPublishDirectory)
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $resolvedPublish = [IO.Path]::GetFullPath($canonicalPublishDirectory)
    if ($resolvedPublish -ne $expectedPublish) {
        throw 'Refusing to clean an unexpected publish directory.'
    }
}
else {
    $resolvedPublish = Assert-SafeCandidateDirectory $OutputDirectory
}

if (-not (Test-Path -LiteralPath $dotnet)) {
    throw 'The project-local SDK is missing. Run scripts\bootstrap-dotnet.ps1 first.'
}

$env:DOTNET_CLI_HOME = Join-Path $projectRoot '.dotnet-home'
$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = '1'
$env:DOTNET_CLI_TELEMETRY_OPTOUT = '1'
$env:NUGET_PACKAGES = Join-Path $projectRoot '.nuget\packages'

if (-not $NoRestore) {
    & $dotnet restore $solution --disable-parallel --disable-build-servers -m:1 -nodeReuse:false -p:NuGetAudit=false
    if ($LASTEXITCODE -ne 0) { throw "Restore failed with exit code $LASTEXITCODE." }
    & $dotnet restore $appProject --runtime win-x64 --disable-parallel --disable-build-servers -m:1 -nodeReuse:false -p:NuGetAudit=false
    if ($LASTEXITCODE -ne 0) { throw "Windows publish restore failed with exit code $LASTEXITCODE." }
}

if (-not $SkipTests) {
    & $dotnet test $solution --configuration Release --no-restore --disable-build-servers -m:1 -nodeReuse:false
    if ($LASTEXITCODE -ne 0) { throw "Tests failed with exit code $LASTEXITCODE." }
}

if (Test-Path -LiteralPath $resolvedPublish) {
    $safePublishDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $verifiedCanonical = [IO.Path]::GetFullPath($canonicalPublishDirectory)
        if ($verifiedCanonical -ne $expectedPublish) { throw 'Refusing to clean an unexpected publish directory.' }
        $verifiedCanonical
    }
    else {
        Assert-SafeCandidateDirectory $resolvedPublish
    }
    Remove-Item -LiteralPath $safePublishDirectory -Recurse -Force
}

& $dotnet publish $appProject `
    --configuration Release `
    --runtime win-x64 `
    --self-contained true `
    --no-restore `
    --disable-build-servers `
    -m:1 `
    -nodeReuse:false `
    -p:UseSharedCompilation=false `
    --output $resolvedPublish
if ($LASTEXITCODE -ne 0) { throw "Publish failed with exit code $LASTEXITCODE." }

$publishedExe = Join-Path $resolvedPublish 'SnapBrief.exe'
$publishedDll = Join-Path $resolvedPublish 'SnapBrief.dll'
if (-not (Test-Path -LiteralPath $publishedExe) -or -not (Test-Path -LiteralPath $publishedDll)) {
    throw 'Publish completed without the expected SnapBrief.exe and SnapBrief.dll artifacts.'
}

$smokeDirectory = Assert-SafeSmokeDirectory (Join-Path $env:TEMP "$smokeDirectoryPrefix$([Guid]::NewGuid().ToString('N'))")
New-Item -ItemType Directory -Path $smokeDirectory | Out-Null
$smokeSucceeded = $false
try {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $publishedExe
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = '--smoke-test'
    $startInfo.EnvironmentVariables['SNAPBRIEF_DATA_DIR'] = $smokeDirectory

    $smokeProcess = [Diagnostics.Process]::Start($startInfo)
    if ($null -eq $smokeProcess) {
        throw "Smoke test process could not be started. Artifacts retained at $smokeDirectory"
    }
    if (-not $smokeProcess.WaitForExit(60000)) {
        $smokeProcess.Kill()
        $smokeProcess.WaitForExit()
        throw "Smoke test timed out after 60 seconds. Artifacts retained at $smokeDirectory"
    }
    if ($smokeProcess.ExitCode -ne 0) {
        throw "Smoke test failed with exit code $($smokeProcess.ExitCode). Artifacts retained at $smokeDirectory"
    }

    $smokeResultPath = Join-Path $smokeDirectory 'smoke-test-result.json'
    if (-not (Test-Path -LiteralPath $smokeResultPath)) {
        throw "Smoke test did not produce smoke-test-result.json. Artifacts retained at $smokeDirectory"
    }
    try {
        $smokeResult = Get-Content -LiteralPath $smokeResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Smoke test produced invalid result JSON. Artifacts retained at $smokeDirectory. $($_.Exception.Message)"
    }
    if ($smokeResult.success -ne $true) {
        throw "Smoke test result reported failure. Artifacts retained at $smokeDirectory"
    }
    $smokeSucceeded = $true
}
finally {
    if ($smokeSucceeded -and (Test-Path -LiteralPath $smokeDirectory)) {
        $safeSmokeDirectory = Assert-SafeSmokeDirectory $smokeDirectory
        Remove-Item -LiteralPath $safeSmokeDirectory -Recurse -Force
    }
}

# The framework the application is actually built for, read from the project so that build-info
# cannot drift away from it the next time the moniker moves.
$appTargetFramework = ([xml](Get-Content -LiteralPath $appProject -Raw)).Project.PropertyGroup.TargetFramework |
    Where-Object { $_ } | Select-Object -First 1
if (-not $appTargetFramework) { throw "Could not read TargetFramework from $appProject." }
$sdkVersion = (& $dotnet --version).Trim()
$exeInfo = Get-Item -LiteralPath $publishedExe
$dllInfo = Get-Item -LiteralPath $publishedDll
$buildInfo = [ordered]@{
    schemaVersion = 1
    builtAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    configuration = 'Release'
    targetFramework = $appTargetFramework
    runtimeIdentifier = 'win-x64'
    selfContained = $true
    dotnetSdkVersion = $sdkVersion
    validation = [ordered]@{
        automatedTests = if ($SkipTests) { 'skipped' } else { 'passed' }
        smokeTest = 'passed'
    }
    artifacts = [ordered]@{
        'SnapBrief.exe' = [ordered]@{
            bytes = $exeInfo.Length
            sha256 = (Get-FileHash -LiteralPath $publishedExe -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        'SnapBrief.dll' = [ordered]@{
            bytes = $dllInfo.Length
            sha256 = (Get-FileHash -LiteralPath $publishedDll -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}
$buildInfoPath = Join-Path $resolvedPublish 'build-info.json'
$buildInfoJson = $buildInfo | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($buildInfoPath, $buildInfoJson, [Text.UTF8Encoding]::new($false))

Write-Host "SnapBrief published and smoke-tested at $resolvedPublish"
