#Requires -Version 5.1
<#
.SYNOPSIS
    Headless smoke test for the fix-enemy-expansion-save mod.

.DESCRIPTION
    Proves, without touching the real Factorio installation, that the mod loads, that
    control.lua parses, and that it actually rewrites map_settings.enemy_expansion.

    Everything happens inside one throwaway directory (default %TEMP%\feas-test):

      1. Write an isolated config.ini whose write-data points into that directory, so
         Factorio uses its own mods, saves, mod-settings.dat and factorio-current.log.
         AppData\Roaming\Factorio is never read or written, and the running game keeps
         its own lock file.
      2. Create a deliberately damaged map with --map-settings, using a copy of Wube's
         map-settings.example.json whose enemy_expansion block is boosted. No console
         command is involved, so nothing here depends on /c.
      3. Drop the built mod zip into the isolated mod directory and enable it.
      4. Run --benchmark for a few ticks. Loading a save with a newly added mod fires
         on_init, which is where the mod applies its values.
      5. Assert on the isolated factorio-current.log.

    The graphical Factorio.exe is used because that is what is installed; --benchmark
    exits on its own once the ticks are done.

.PARAMETER FactorioExe
    Path to Factorio.exe. Found automatically if omitted: FACTORIO_EXE, then the Steam
    library folders, then the usual standalone install locations.

.PARAMETER TestRoot
    Throwaway directory for config, mods, saves and log. Defaults to %TEMP%\feas-test.

.PARAMETER Keep
    Keep the test directory afterwards instead of reporting where it is. The script
    never deletes it either way - clean-up is a manual decision.
#>
[CmdletBinding()]
param(
    [string] $FactorioExe,
    [string] $TestRoot = (Join-Path $env:TEMP 'feas-test'),
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Find-Factorio.ps1')

$modName = 'fix-enemy-expansion-save'

# The damaged fixture: what a save looks like after the retired Dynamic Biter Expansion
# feature boosted it. Every value differs from the mod defaults, so a no-op would fail.
$boosted = @{
    enabled                          = $true
    max_expansion_distance           = 20
    settler_group_min_size            = 20
    settler_group_max_size            = 60
    min_expansion_cooldown            = 1800
    max_expansion_cooldown            = 3600
}

# What the mod is expected to write (settings.lua defaults).
$expected = @{
    min_expansion_cooldown = 14400
    max_expansion_cooldown = 216000
    settler_group_min_size = 5
    settler_group_max_size = 20
    max_expansion_distance = 5
    min_expansion_distance = 3
}

function Write-Step([string] $text) {
    Write-Host ""
    Write-Host "== $text" -ForegroundColor Cyan
}

function Invoke-Factorio {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $What
    )

    Write-Host "   Factorio.exe $($Arguments -join ' ')" -ForegroundColor DarkGray
    $stdout = Join-Path $TestRoot ("out-{0}.txt" -f $What)
    $stderr = Join-Path $TestRoot ("err-{0}.txt" -f $What)

    $process = Start-Process -FilePath $FactorioExe -ArgumentList $Arguments -Wait -PassThru `
        -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    if ($process.ExitCode -ne 0) {
        Write-Host (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)
        Write-Host (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
        throw "$What failed with exit code $($process.ExitCode)"
    }
}

#-------------------------------------------------------------------------------
# 0. preconditions
#-------------------------------------------------------------------------------

$FactorioExe = Find-FactorioExe -Explicit $FactorioExe
Write-Host "Factorio: $FactorioExe" -ForegroundColor DarkGray

$zipPath = Join-Path $PSScriptRoot ('dist\{0}_{1}.zip' -f $modName,
    ((Get-Content -LiteralPath (Join-Path $PSScriptRoot "$modName\info.json") -Raw | ConvertFrom-Json).version))

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Mod zip not found: $zipPath - run build.ps1 first."
}

$installRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $FactorioExe))
$dataPath = Join-Path $installRoot 'data'
$examplePath = Join-Path $dataPath 'map-settings.example.json'

foreach ($required in @($dataPath, $examplePath)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Not found in the Factorio install: $required"
    }
}

#-------------------------------------------------------------------------------
# 1. isolated instance
#-------------------------------------------------------------------------------

Write-Step "Preparing isolated instance in $TestRoot"

$writeData = Join-Path $TestRoot 'write'
$modDir = Join-Path $writeData 'mods'
$savesDir = Join-Path $writeData 'saves'
$configPath = Join-Path $TestRoot 'config.ini'
$logPath = Join-Path $writeData 'factorio-current.log'
$savePath = Join-Path $savesDir 'damaged.zip'
$mapSettingsPath = Join-Path $TestRoot 'boosted-map-settings.json'

foreach ($dir in @($TestRoot, $writeData, $modDir, $savesDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# Start from a clean log so the assertions cannot pass on output of an earlier run.
if (Test-Path -LiteralPath $logPath -PathType Leaf) { Remove-Item -LiteralPath $logPath -Force }
if (Test-Path -LiteralPath $savePath -PathType Leaf) { Remove-Item -LiteralPath $savePath -Force }

@"
; generated by test-headless.ps1 - throwaway instance, not the real config
[path]
read-data=$dataPath
write-data=$writeData

[general]
locale=en
"@ | Set-Content -LiteralPath $configPath -Encoding ASCII

# Vanilla only: the DLC mods are not needed to exercise map_settings and only slow the
# load down. They live in the read-data path, so disabling them here changes nothing
# about the real install.
$modList = @{
    mods = @(
        @{ name = 'base'; enabled = $true }
        @{ name = 'elevated-rails'; enabled = $false }
        @{ name = 'quality'; enabled = $false }
        @{ name = 'space-age'; enabled = $false }
    )
}
$modListPath = Join-Path $modDir 'mod-list.json'
$modList | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $modListPath -Encoding ASCII

Write-Host "   config:  $configPath"
Write-Host "   mods:    $modDir"
Write-Host "   log:     $logPath"

#-------------------------------------------------------------------------------
# 2. damaged map fixture
#-------------------------------------------------------------------------------

Write-Step "Creating a deliberately damaged map"

$mapSettings = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
foreach ($key in $boosted.Keys) {
    $mapSettings.enemy_expansion.$key = $boosted[$key]
}
$mapSettings | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $mapSettingsPath -Encoding ASCII

Write-Host "   boosted: $(($boosted.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', ')"

Invoke-Factorio -What 'create' -Arguments @(
    '--config', "`"$configPath`""
    '--mod-directory', "`"$modDir`""
    '--create', "`"$savePath`""
    '--map-settings', "`"$mapSettingsPath`""
    '--disable-audio'
    '--no-log-rotation'
)

if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) {
    throw "Map creation reported success but $savePath does not exist."
}
Write-Host "   created: $savePath" -ForegroundColor Green

#-------------------------------------------------------------------------------
# 3. add the mod
#-------------------------------------------------------------------------------

Write-Step "Adding the mod to the isolated instance"

Copy-Item -LiteralPath $zipPath -Destination $modDir -Force
$modList.mods += @{ name = $modName; enabled = $true }
$modList | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $modListPath -Encoding ASCII
Write-Host "   copied:  $(Split-Path -Leaf $zipPath)"

#-------------------------------------------------------------------------------
# 4. load the damaged map with the mod
#-------------------------------------------------------------------------------

Write-Step "Loading the damaged map with the mod (benchmark, 60 ticks)"

Invoke-Factorio -What 'benchmark' -Arguments @(
    '--config', "`"$configPath`""
    '--mod-directory', "`"$modDir`""
    '--benchmark', "`"$savePath`""
    '--benchmark-ticks', '60'
    '--disable-audio'
    '--no-log-rotation'
)

#-------------------------------------------------------------------------------
# 5. assertions
#-------------------------------------------------------------------------------

Write-Step "Checking $logPath"

if (-not (Test-Path -LiteralPath $logPath -PathType Leaf)) {
    throw "No log file was written: $logPath"
}

$log = Get-Content -LiteralPath $logPath
$modLines = $log | Where-Object { $_ -match '\[fix-enemy-expansion-save\]' }

if (-not $modLines) {
    throw "The mod produced no output at all - it probably did not load. See $logPath"
}

Write-Host ""
$modLines | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
Write-Host ""

$failures = New-Object System.Collections.Generic.List[string]

function Assert-Log([string] $pattern, [string] $description) {
    if ($modLines -match [regex]::Escape($pattern)) {
        Write-Host "   [ok]   $description" -ForegroundColor Green
    }
    else {
        Write-Host "   [FAIL] $description" -ForegroundColor Red
        $script:failures.Add($description)
    }
}

Assert-Log 'applied (mod added to this save):' 'on_init applied the values'

foreach ($key in ($expected.Keys | Sort-Object)) {
    if ($boosted.ContainsKey($key)) {
        Assert-Log ("{0}: {1} -> {2}" -f $key, $boosted[$key], $expected[$key]) "$key was rewritten"
    }
    else {
        # min_expansion_distance is not part of the fixture; it only has to end up right,
        # and "already matches" would show up as no diff line for it.
        Write-Host "   [--]   $key not in the fixture, covered by the verify line" -ForegroundColor DarkGray
    }
}

Assert-Log 'verified: every value was accepted by the engine.' 'read-back verification passed'

# Any Lua error surfaces as an "Error ... .lua" line; the mod must not produce one.
$luaErrors = $log | Where-Object { $_ -match 'fix-enemy-expansion-save' -and $_ -match '(?i)\berror\b' }
if ($luaErrors) {
    Write-Host "   [FAIL] the log contains errors mentioning the mod" -ForegroundColor Red
    $luaErrors | ForEach-Object { Write-Host "          $_" -ForegroundColor Red }
    $failures.Add('no Lua errors')
}
else {
    Write-Host "   [ok]   no Lua errors mentioning the mod" -ForegroundColor Green
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures.Count) check(s) did not pass. Full log: $logPath" -ForegroundColor Red
    exit 1
}

Write-Host "PASSED: the mod loads and repairs enemy_expansion." -ForegroundColor Green
if ($Keep) {
    Write-Host "Test instance kept at $TestRoot"
}
else {
    Write-Host "Test instance left at $TestRoot - delete it manually when you no longer need it."
}
