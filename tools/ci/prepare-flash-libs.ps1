#Requires -Version 5.1
<#
.SYNOPSIS
  Prepare Flash UI/sound libs for CLI/CI builds (public TagAssets naming differs from source).

.DESCRIPTION
  - Downloads Lib_fl.swc + sound.swc from upstream code tag
  - Generates silent stub Sound classes for combat SFX missing from sound.swc
  - Ensures Embed SWFs exist under shared/lib/swf (rename from older TagAssets names)
  - Rewrites KernelLogic `$prefix$Class` type annotations to MovieClip so old SWF
    instances can be assigned without type coercion errors
#>
param(
    [string]$UiAssetsTag = $(if ($env:UI_TAG_ASSETS) { $env:UI_TAG_ASSETS } else { '3.7.0.0.11112024_alpha' }),
    [string]$KernelSwcTag = $(if ($env:KERNEL_SWC_TAG) { $env:KERNEL_SWC_TAG } else { '3.7.0.0.11112024_alpha' })
)

$ErrorActionPreference = 'Stop'
$Root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Set-Location $Root

function Download-File([string]$Url, [string]$OutFile) {
    Write-Host "GET $Url"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
    if (-not (Test-Path $OutFile) -or ((Get-Item $OutFile).Length -lt 64)) {
        throw "Download failed or too small: $OutFile"
    }
}

function Assert-Path([string]$Path) {
    if (-not (Test-Path $Path)) {
        throw "Missing: $Path"
    }
}

$kernelSwcDir = Join-Path $Root 'CORE_KernelLogic\lib\swc'
New-Item -ItemType Directory -Force -Path $kernelSwcDir | Out-Null

Write-Host '== Kernel SWCs (Lib_fl + sound) =='
$baseRaw = "https://raw.githubusercontent.com/5DPLAY-Game-Studio/BleachVsNaruto/$KernelSwcTag/CORE_KernelLogic/lib/swc"
Download-File "$baseRaw/Lib_fl.swc" (Join-Path $kernelSwcDir 'Lib_fl.swc')
Download-File "$baseRaw/sound.swc" (Join-Path $kernelSwcDir 'sound.swc')

Write-Host '== Generate missing sound stubs =='
$stubSrc = Join-Path $Root 'tools\ci\_generated\sound_stubs'
if (Test-Path $stubSrc) { Remove-Item $stubSrc -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stubSrc | Out-Null

# Sounds referenced by KernelLogic but absent from public sound.swc
$missingSounds = @(
    'snd_baoqi', 'snd_baoqi1', 'snd_bs', 'snd_cbs', 'snd_change1', 'snd_cls',
    'snd_dash', 'snd_dash_air', 'snd_def', 'snd_defx', 'snd_fykan', 'snd_fykanx',
    'snd_fz', 'snd_ghost_step', 'snd_hit11', 'snd_hit2', 'snd_hit_cache',
    'snd_hit_dian', 'snd_hit_fire', 'snd_hit_heavy', 'snd_hit_ice', 'snd_hitfloor',
    'snd_hitfloor_heavy', 'snd_hitfloor_low', 'snd_jump', 'snd_kan1', 'snd_kan2',
    'snd_level_up', 'snd_luodi', 'snd_mfdjx'
)

foreach ($name in $missingSounds) {
    $as = @"
package {
import flash.media.Sound;

/**
 * CI stub — real SFX not published in public sound.swc.
 */
public class $name extends Sound {
    public function $name() {
        super();
    }
}
}
"@
    # AS3 / project uses CRLF
    [System.IO.File]::WriteAllText((Join-Path $stubSrc "$name.as"), ($as -replace "`n", "`r`n"))
}

$stubAsconfig = Join-Path $stubSrc 'asconfig.json'
$stubOutRel = '../../../CORE_KernelLogic/lib/swc/sound_stubs.swc'
$stubOut = Join-Path $kernelSwcDir 'sound_stubs.swc'
$stubAsconfigJson = @"
{
    "type": "lib",
    "compilerOptions": {
        "source-path": ["."],
        "include-sources": ["."],
        "output": "$stubOutRel"
    }
}
"@
[System.IO.File]::WriteAllText($stubAsconfig, ($stubAsconfigJson -replace "`n", "`r`n"))

if (-not $env:FLEX_HOME) {
    throw 'FLEX_HOME required to compile sound stubs'
}
Write-Host '== Compile sound_stubs.swc =='
Push-Location $stubSrc
try {
    & asconfigc --sdk $env:FLEX_HOME --project .\asconfig.json
    if ($LASTEXITCODE -ne 0) { throw "sound stubs compile failed ($LASTEXITCODE)" }
}
finally {
    Pop-Location
}
Assert-Path $stubOut

Write-Host '== UI Embed SWFs (legacy TagAssets names -> SwfLib names) =='
$swfDir = Join-Path $Root 'shared\lib\swf'
New-Item -ItemType Directory -Force -Path $swfDir | Out-Null

$swfMap = @{
    'big_map.swf'   = 'bigmap.swf'
    'common.swf'    = 'common_ui.swf'
    'dialog.swf'    = 'dialog_ui.swf'
    'fight.swf'     = 'fight.swf'
    'game_over.swf' = 'gameover.swf'
    'how2play.swf'  = 'howtoplay.swf'
    'language.swf'  = 'language.swf'
    'loading.swf'   = 'loading.swf'
    'musou.swf'     = 'mosou.swf'
    'select.swf'    = 'select.swf'
    'setting.swf'   = 'setting.swf'
    'title.swf'     = 'title.swf'
    'win_ui.swf'    = 'win_ui.swf'
}

$uiSwfBase = "https://raw.githubusercontent.com/5DPLAY-Game-Studio/BleachVsNaruto_TagAssets/$UiAssetsTag/shared/lib/swf"
foreach ($destName in $swfMap.Keys) {
    $dest = Join-Path $swfDir $destName
    if ((Test-Path $dest) -and ((Get-Item $dest).Length -gt 1024)) {
        Write-Host "Keep existing $destName"
        continue
    }
    $srcName = $swfMap[$destName]
    $tmp = Join-Path $env:TEMP "bvn-ui-$srcName"
    Download-File "$uiSwfBase/$srcName" $tmp
    Copy-Item $tmp $dest -Force
    Write-Host "Prepared $destName (<= $srcName)"
}

Write-Host '== Patch KernelLogic $UI$Type annotations -> MovieClip (CI only) =='
$asFiles = Get-ChildItem -Path (Join-Path $Root 'CORE_KernelLogic\src') -Filter '*.as' -Recurse
$patched = 0
foreach ($f in $asFiles) {
    $text = [System.IO.File]::ReadAllText($f.FullName)
    $orig = $text
    # Type annotations / casts only — string literals like '$common$MC_menuBtn' stay intact
    $text = [regex]::Replace($text, '(?<=:\s*)\$[a-z0-9_]+\$[A-Za-z0-9_]+', 'MovieClip')
    $text = [regex]::Replace($text, '(?<=\bas\s+)\$[a-z0-9_]+\$[A-Za-z0-9_]+', 'MovieClip')
    if ($text -ne $orig) {
        # Ensure MovieClip import if file now references it and lacks import
        if ($text -match '\bMovieClip\b' -and $text -notmatch 'import flash\.display\.MovieClip') {
            if ($text -match '(import flash\.display\.[^\r\n]+;\r?\n)') {
                $text = $text -replace '(import flash\.display\.[^\r\n]+;\r?\n)', "`$1import flash.display.MovieClip;`r`n"
            }
            elseif ($text -match '(package [^\r\n]+ \{\r?\n)') {
                $text = $text -replace '(package [^\r\n]+ \{\r?\n)', "`$1import flash.display.MovieClip;`r`n"
            }
        }
        [System.IO.File]::WriteAllText($f.FullName, $text)
        $patched++
    }
}
Write-Host "Patched $patched ActionScript files"

Write-Host '== prepare-flash-libs done =='
