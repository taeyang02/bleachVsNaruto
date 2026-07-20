#Requires -Version 5.1
<#
.SYNOPSIS
  CLI build for SHELL_Pc (Windows AIR captive / .air)

.DESCRIPTION
  Build order: CORE_Shared -> LIB_KyoLib -> CORE_KernelLogic -> CORE_Utils -> SHELL_Pc
  Then package with ADT.

  Required env:
    FLEX_HOME  - path to flex4.16.1-air51.0.1.1 SDK

  Optional env:
    KEYSTORE_PASS - p12 password (default 123456, see keysign/README.md)
    PACKAGE_TARGET - bundle | air  (default bundle)
#>
param(
    [ValidateSet('bundle', 'air', 'swf')]
    [string]$PackageTarget = $(if ($env:PACKAGE_TARGET) { $env:PACKAGE_TARGET } else { 'bundle' }),
    [string]$KeystorePass = $(if ($env:KEYSTORE_PASS) { $env:KEYSTORE_PASS } else { '123456' })
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $Root

function Require-Cmd($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Missing command: $name"
    }
}

function Require-Path($path, $hint) {
    if (-not (Test-Path $path)) {
        throw "Missing path: $path`n$hint"
    }
}

if (-not $env:FLEX_HOME) {
    throw 'FLEX_HOME is not set. Point it to flex4.16.1-air51.0.1.1'
}
$FlexHome = (Resolve-Path $env:FLEX_HOME).Path
$env:PATH = "$FlexHome\bin;$env:PATH"

Require-Cmd 'asconfigc'
Require-Cmd 'java'
Require-Path "$FlexHome\bin\adt.bat" 'Invalid Flex/AIR SDK (adt.bat not found)'
Require-Path 'LIB_KyoLib\asconfig.json' 'Init submodule: git submodule update --init LIB_KyoLib'
Require-Path 'shared\assets\assets\config' 'Overlay TagAssets (shared/assets) before build'
Require-Path 'keysign\5dplay.p12' 'Missing signing certificate'

# external-library-path may be empty; ensure directory exists for asconfigc
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'shared\lib\swc') | Out-Null

Write-Host '== Prepare Flash UI/sound libs =='
& (Join-Path $PSScriptRoot 'prepare-flash-libs.ps1')
if ($LASTEXITCODE -ne 0) {
    throw "prepare-flash-libs failed ($LASTEXITCODE)"
}

# GithubUtils.as Embeds .git/refs/heads/{master,develop}. CI often builds
# another branch with shallow clone, so those files are missing.
Write-Host '== Ensure git refs for GithubUtils Embed =='
$gitRefs = Join-Path $Root '.git\refs\heads'
New-Item -ItemType Directory -Force -Path $gitRefs | Out-Null
$headSha = $null
try {
    $headSha = (git -C $Root rev-parse HEAD 2>$null | Out-String).Trim()
}
catch {
}
if (-not $headSha -or $headSha.Length -lt 7) {
    $headSha = if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { '0000000000000000000000000000000000000000' }
}
foreach ($branch in @('master', 'develop')) {
    $refPath = Join-Path $gitRefs $branch
    if (-not (Test-Path $refPath)) {
        # Embed expects a plain SHA file (with trailing newline like real git refs)
        [System.IO.File]::WriteAllText($refPath, ($headSha + "`n"))
        Write-Host "Created stub ref: refs/heads/$branch -> $headSha"
    }
    else {
        Write-Host "Keep existing ref: refs/heads/$branch"
    }
}

Write-Host '== Sync assets -> shared/_tmp/pc =='
$srcAssets = Join-Path $Root 'shared\assets\assets'
$dstPc = Join-Path $Root 'shared\_tmp\pc\assets'
if (Test-Path (Join-Path $Root 'shared\_tmp\pc')) {
    Remove-Item (Join-Path $Root 'shared\_tmp\pc') -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $dstPc | Out-Null
Copy-Item -Path (Join-Path $srcAssets '*') -Destination $dstPc -Recurse -Force

# Ensure online.json exists for CI builds
$onlineSrc = Join-Path $Root 'ONLINE_RelayServer\online.json.example'
$onlineDst = Join-Path $dstPc 'config\online.json'
if ((Test-Path $onlineSrc) -and -not (Test-Path $onlineDst)) {
    New-Item -ItemType Directory -Force -Path (Split-Path $onlineDst) | Out-Null
    Copy-Item $onlineSrc $onlineDst -Force
}

$outDirs = @(
    'out\production\LIB_Other',
    'out\production\CORE_Shared',
    'out\production\LIB_KyoLib',
    'out\production\CORE_KernelLogic',
    'out\production\CORE_Utils',
    'out\production\SHELL_Pc',
    'dist'
)
foreach ($d in $outDirs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $Root $d) | Out-Null
}

# LIB_KyoLib includes LIB_Other.swc — compile Other first.
$projects = @(
    'LIB_Other\asconfig.json',
    'CORE_Shared\asconfig.json',
    'LIB_KyoLib\asconfig.json',
    'CORE_KernelLogic\asconfig.json',
    'CORE_Utils\asconfig.json',
    'SHELL_Pc\asconfig.json'
)

foreach ($proj in $projects) {
    Write-Host "== Compile $proj =="
    Require-Path $proj "Missing $proj"
    & asconfigc --sdk $FlexHome --project $proj
    if ($LASTEXITCODE -ne 0) {
        throw "asconfigc failed: $proj (exit $LASTEXITCODE)"
    }
}

$swf = Join-Path $Root 'out\production\SHELL_Pc\launch.swf'
Require-Path $swf 'launch.swf was not produced'

if ($PackageTarget -eq 'swf') {
    Write-Host "SWF only: $swf"
    exit 0
}

Write-Host '== Prepare application descriptor =='
$descSrc = Join-Path $Root 'SHELL_Pc\src\launch-app.xml'
$descOut = Join-Path $Root 'out\production\SHELL_Pc\launch-app.xml'
$xml = Get-Content -Raw -Encoding UTF8 $descSrc
$xml = $xml -replace '<content>\[[^\]]*\]</content>', '<content>launch.swf</content>'
$xml = $xml -replace '<content>\[此值将由 Flash Builder 在输出 app\.xml 中覆盖\]</content>', '<content>launch.swf</content>'
Set-Content -Path $descOut -Value $xml -Encoding UTF8

$keystore = Join-Path $Root 'keysign\5dplay.p12'
$adt = Join-Path $FlexHome 'bin\adt.bat'
$dist = Join-Path $Root 'dist'
$work = Join-Path $Root 'out\production\SHELL_Pc'

Push-Location $work
try {
    if ($PackageTarget -eq 'air') {
        $outAir = Join-Path $dist 'BleachVsNaruto.air'
        if (Test-Path $outAir) { Remove-Item $outAir -Force }
        Write-Host '== ADT package .air =='
        # -tsa none: GitHub Actions often cannot reach Adobe TSA (Connection reset)
        & $adt -package `
            -storetype pkcs12 -keystore $keystore -storepass $KeystorePass `
            -tsa none `
            -target air $outAir `
            launch-app.xml launch.swf `
            -C (Join-Path $Root 'shared\assets') assets `
            -C (Join-Path $Root 'SHELL_Pc\lib') icon
        if ($LASTEXITCODE -ne 0) { throw "adt air package failed ($LASTEXITCODE)" }
        Write-Host "OK: $outAir"
    }
    else {
        $bundleDir = Join-Path $dist 'BleachVsNaruto'
        if (Test-Path $bundleDir) { Remove-Item $bundleDir -Recurse -Force }
        Write-Host '== ADT package Windows captive bundle =='
        # -tsa none: GitHub Actions often cannot reach Adobe TSA (Connection reset)
        & $adt -package `
            -storetype pkcs12 -keystore $keystore -storepass $KeystorePass `
            -tsa none `
            -target bundle $bundleDir `
            launch-app.xml launch.swf `
            -C (Join-Path $Root 'shared\assets') assets `
            -C (Join-Path $Root 'SHELL_Pc\lib') icon
        if ($LASTEXITCODE -ne 0) { throw "adt bundle package failed ($LASTEXITCODE)" }

        # Keep online config next to the EXE for playable builds
        $onlineSrc = Join-Path $Root 'ONLINE_RelayServer\online.json.example'
        $cfgDir = Join-Path $bundleDir 'config'
        if (Test-Path $onlineSrc) {
            New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
            Copy-Item $onlineSrc (Join-Path $cfgDir 'online.json') -Force
        }

        $zip = Join-Path $dist 'BleachVsNaruto-windows.zip'
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Compress-Archive -Path (Join-Path $bundleDir '*') -DestinationPath $zip -Force
        Write-Host "OK: $bundleDir"
        Write-Host "OK: $zip"
        Write-Host 'Play: unzip BleachVsNaruto-windows.zip then run launch.exe'
    }
}
finally {
    Pop-Location
}
