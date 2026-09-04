#Requires -Version 5.1
<#
.SYNOPSIS
    Proves that the repair survives saving and removing the mod.

.DESCRIPTION
    test-headless.ps1 only shows that the mod rewrites the live values. It cannot show
    that they stay in the save, because --benchmark never writes the save back.

    This test closes that gap in two phases, inside a throwaway instance:

      Phase 1  damaged map + repair mod. The mod fixes the values on on_init, then a
               tiny test-only harness mod calls game.auto_save(), so Factorio writes
               the repaired state to _autosave-feas-persist.zip.
      Phase 2  the repair mod zip is deleted and dropped from mod-list.json. The
               autosave is loaded with only the harness left, and the harness logs
               map_settings.enemy_expansion as it comes out of the save file.

    If phase 2 still reports the repaired numbers while the repair mod is provably not
    loaded, the fix lives in the save and not in the mod. That is the whole claim.

    Headless phase 1 runs Factorio as a server, not as a benchmark: --benchmark accepts
    game.auto_save() without complaining but never performs it, so no file would ever
    appear. The server runs with auto_pause off (nobody connects) and is stopped once
    the log confirms the save was written. Phase 2 writes nothing and stays a benchmark.

    The harness is a second, test-only mod package in this repo (feas-test-harness\).
    It is copied into the throwaway instance and never published or installed into a
    real game. Nothing test-related is added to the shipped mod.

    Isolation is the same as in test-headless.ps1: own config.ini with its own
    write-data, own --mod-directory. %APPDATA%\Factorio is neither read nor written.

.PARAMETER Visual
    Run both phases in the normal game window instead of headless, so you can watch the
    mod work and read the messages in the chat. This is a demo mode, not an extra test:
    same two phases, same assertions, nothing extra is proven. It cannot be automated,
    because Factorio will not exit by itself - quit the game yourself (Esc -> Quit) when
    the harness tells you to, and the script continues with the next phase.

.PARAMETER FactorioExe
    Path to Factorio.exe. Found automatically if omitted: FACTORIO_EXE, then the Steam
    library folders, then the usual standalone install locations.

.PARAMETER TestRoot
    Throwaway directory. Defaults to %TEMP%\feas-persist-test. Never deleted by this
    script - clean-up stays a manual decision.
#>
[CmdletBinding()]
param(
    [switch] $Visual,
    [string] $FactorioExe,
    [string] $TestRoot = (Join-Path $env:TEMP 'feas-persist-test')
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Find-Factorio.ps1')

$modName = 'fix-enemy-expansion-save'
$harnessName = 'feas-test-harness'
$autoSaveName = 'feas-persist'

# The damaged fixture: every value differs from the mod defaults, so a no-op fails.
$boosted = @{
    enabled                = $true
    max_expansion_distance = 20
    settler_group_min_size = 20
    settler_group_max_size = 60
    min_expansion_cooldown = 1800
    max_expansion_cooldown = 3600
}

# What must still be in the save in phase 2, with the repair mod gone.
$expected = [ordered]@{
    min_expansion_cooldown = 14400
    max_expansion_cooldown = 216000
    settler_group_min_size = 5
    settler_group_max_size = 20
    min_expansion_distance = 3
    max_expansion_distance = 5
}

function Write-Step([string] $text) {
    Write-Host ""
    Write-Host "== $text" -ForegroundColor Cyan
}

#-------------------------------------------------------------------------------
# preconditions
#-------------------------------------------------------------------------------

$FactorioExe = Find-FactorioExe -Explicit $FactorioExe
Write-Host "Factorio: $FactorioExe" -ForegroundColor DarkGray

$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot "$modName\info.json") -Raw | ConvertFrom-Json).version
$zipPath = Join-Path $PSScriptRoot ('dist\{0}_{1}.zip' -f $modName, $version)

if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
    throw "Mod zip not found: $zipPath - run build.ps1 first."
}

$installRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $FactorioExe))
$dataPath = Join-Path $installRoot 'data'
$examplePath = Join-Path $dataPath 'map-settings.example.json'

if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) {
    throw "Not found in the Factorio install: $examplePath"
}

$harnessSource = Join-Path $PSScriptRoot $harnessName
$harnessInfo = Join-Path $harnessSource 'info.json'

if (-not (Test-Path -LiteralPath $harnessInfo -PathType Leaf)) {
    throw "Test harness mod not found: $harnessInfo"
}

$harnessDeclaredName = (Get-Content -LiteralPath $harnessInfo -Raw | ConvertFrom-Json).name
if ($harnessDeclaredName -ne $harnessName) {
    throw "The harness declares name '$harnessDeclaredName' but its folder is '$harnessName' - Factorio requires them to match."
}

#-------------------------------------------------------------------------------
# isolated instance
#-------------------------------------------------------------------------------

Write-Step "Preparing isolated instance in $TestRoot"

$writeData = Join-Path $TestRoot 'write'
$modDir = Join-Path $writeData 'mods'
$savesDir = Join-Path $writeData 'saves'
$configPath = Join-Path $TestRoot 'config.ini'
$logPath = Join-Path $writeData 'factorio-current.log'
$savePath = Join-Path $savesDir 'damaged.zip'
$autoSavePath = Join-Path $savesDir ("_autosave-{0}.zip" -f $autoSaveName)
$mapSettingsPath = Join-Path $TestRoot 'boosted-map-settings.json'
$serverSettingsPath = Join-Path $TestRoot 'server-settings.json'
$modListPath = Join-Path $modDir 'mod-list.json'
$harnessDir = Join-Path $modDir $harnessName
$installedZip = Join-Path $modDir (Split-Path -Leaf $zipPath)

foreach ($dir in @($TestRoot, $writeData, $modDir, $savesDir, $harnessDir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

# Stale artefacts of an earlier run would make the assertions meaningless. Each of these
# is removed by exact name as a single file; nothing here deletes a directory tree.
foreach ($stale in @($logPath, $savePath, $autoSavePath, $installedZip)) {
    if (Test-Path -LiteralPath $stale -PathType Leaf) { Remove-Item -LiteralPath $stale -Force }
}

@"
; generated by test-persistence.ps1 - throwaway instance, not the real config
[path]
read-data=$dataPath
write-data=$writeData

[general]
locale=en
"@ | Set-Content -LiteralPath $configPath -Encoding ASCII

# A server is only needed for headless phase 1 (see the header comment). auto_pause off
# is essential: with nobody connected a Factorio server pauses, and a paused game would
# never reach the tick where the harness triggers the save. The huge autosave interval
# keeps the server's own periodic autosave out of the way.
@{
    name = 'feas-persistence-test'
    description = 'throwaway instance of test-persistence.ps1'
    visibility = @{ public = $false; lan = $false }
    require_user_verification = $false
    auto_pause = $false
    autosave_interval = 1000000
    autosave_slots = 1
    allow_commands = 'admins-only'
} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $serverSettingsPath -Encoding ASCII

function Set-ModList([bool] $WithRepairMod) {
    $mods = @(
        @{ name = 'base'; enabled = $true }
        @{ name = 'elevated-rails'; enabled = $false }
        @{ name = 'quality'; enabled = $false }
        @{ name = 'space-age'; enabled = $false }
        @{ name = $harnessName; enabled = $true }
    )
    if ($WithRepairMod) { $mods += @{ name = $modName; enabled = $true } }
    @{ mods = $mods } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $modListPath -Encoding ASCII
}

#-------------------------------------------------------------------------------
# the test-only harness mod
#-------------------------------------------------------------------------------
# Copied in as an unzipped mod folder. It reads map_settings.enemy_expansion and
# reports it; whether it also triggers the autosave is decided inside the harness via
# script.active_mods, so the same code drives both phases and its log tag cannot lie.

Copy-Item -Path (Join-Path $harnessSource '*') -Destination $harnessDir -Recurse -Force

foreach ($required in @('info.json', 'control.lua')) {
    $path = Join-Path $harnessDir $required
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Harness was not copied correctly, missing: $path"
    }
}

Write-Host "   config:  $configPath"
Write-Host "   mods:    $modDir"
Write-Host "   harness: $harnessSource -> $harnessDir"

#-------------------------------------------------------------------------------
# running Factorio
#-------------------------------------------------------------------------------

function Wait-ForFactorioExit {
    param(
        [int[]] $IgnorePids = @(),
        [int] $StartTimeoutSeconds = 300
    )

    # Factorio writes "Goodbye" as the very last line of a clean shutdown, so that is the
    # signal we wait for. Start-Process cannot tell us: a Steam build re-launches itself,
    # the handle we get back exits within a second and waiting on it makes the script race
    # ahead of the game. The PID snapshot only exists to notice a crash without mistaking
    # a Factorio the user already had open for ours.
    $startDeadline = (Get-Date).AddSeconds($StartTimeoutSeconds)
    $started = $false
    $goneFor = 0

    while ($true) {
        $tail = @(Get-Content -LiteralPath $logPath -Tail 3 -ErrorAction SilentlyContinue)
        if ($tail -match 'Goodbye') { return }

        $ours = @(Get-Process -Name 'factorio*' -ErrorAction SilentlyContinue |
            Where-Object { $IgnorePids -notcontains $_.Id })

        if (-not $started) {
            # "started" means the game really came up, not just that a process appeared -
            # the re-launch would otherwise look like an immediate exit.
            if (@(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue) -match 'Factorio initialised') {
                $started = $true
            }
            elseif ((Get-Date) -gt $startDeadline) {
                throw "Factorio did not start within $StartTimeoutSeconds seconds. Log: $logPath"
            }
        }
        elseif ($ours.Count -eq 0) {
            $goneFor++
            if ($goneFor -ge 6) {
                throw "Factorio disappeared without writing 'Goodbye' - it probably crashed. Log: $logPath"
            }
        }
        else {
            $goneFor = 0
        }

        Start-Sleep -Milliseconds 500
    }
}

function Invoke-Factorio {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [string] $What,
        [switch] $ForceHeadless
    )

    # A clean log per phase, so an assertion can never pass on output of an earlier one.
    if (Test-Path -LiteralPath $logPath -PathType Leaf) { Remove-Item -LiteralPath $logPath -Force }

    Write-Host "   Factorio.exe $($Arguments -join ' ')" -ForegroundColor DarkGray

    # Map creation always runs headless: it exits on its own and there is nothing to watch.
    if ($Visual -and -not $ForceHeadless) {
        $ignorePids = @(Get-Process -Name 'factorio*' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Id)
        Start-Process -FilePath $FactorioExe -ArgumentList $Arguments | Out-Null
        Write-Host "   waiting for you to quit the game window (Esc -> Quit)..." -ForegroundColor Yellow
        Wait-ForFactorioExit -IgnorePids $ignorePids
    }
    else {
        $stdout = Join-Path $TestRoot ("out-{0}.txt" -f $What)
        $stderr = Join-Path $TestRoot ("err-{0}.txt" -f $What)
        $process = Start-Process -FilePath $FactorioExe -ArgumentList $Arguments -Wait -PassThru `
            -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr

        if ($process.ExitCode -ne 0) {
            throw "$What failed with exit code $($process.ExitCode). Log: $logPath"
        }
    }

    $copy = Join-Path $TestRoot ("log-{0}.txt" -f $What)
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        Copy-Item -LiteralPath $logPath -Destination $copy -Force
    }
    return $copy
}

function Get-RunArguments([string] $Save) {
    $arguments = @(
        '--config', "`"$configPath`""
        '--mod-directory', "`"$modDir`""
    )
    if ($Visual) {
        $arguments += @('--load-game', "`"$Save`"")
    }
    else {
        $arguments += @('--benchmark', "`"$Save`"", '--benchmark-ticks', '300', '--disable-audio')
    }
    $arguments += '--no-log-rotation'
    return $arguments
}

function Invoke-FactorioServer {
    param(
        [Parameter(Mandatory)] [string] $Save,
        [Parameter(Mandatory)] [string] $What,
        [Parameter(Mandatory)] [string] $ReadyPattern,
        [int] $TimeoutSeconds = 300
    )

    if (Test-Path -LiteralPath $logPath -PathType Leaf) { Remove-Item -LiteralPath $logPath -Force }

    $arguments = @(
        '--config', "`"$configPath`""
        '--mod-directory', "`"$modDir`""
        '--start-server', "`"$Save`""
        '--server-settings', "`"$serverSettingsPath`""
        '--disable-audio'
        '--no-log-rotation'
    )
    Write-Host "   Factorio.exe $($arguments -join ' ')" -ForegroundColor DarkGray

    $stdout = Join-Path $TestRoot ("out-{0}.txt" -f $What)
    $stderr = Join-Path $TestRoot ("err-{0}.txt" -f $What)
    $process = Start-Process -FilePath $FactorioExe -ArgumentList $arguments -PassThru `
        -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    try {
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $ready = $false

        while ((Get-Date) -lt $deadline) {
            if (@(Get-Content -LiteralPath $logPath -ErrorAction SilentlyContinue) -match $ReadyPattern) {
                $ready = $true
                break
            }
            if ($process.HasExited) { break }
            Start-Sleep -Milliseconds 500
        }

        if (-not $ready) {
            throw "The server never logged '$ReadyPattern' within $TimeoutSeconds seconds. Log: $logPath"
        }
    }
    finally {
        if (-not $process.HasExited) {
            # A server has no tick limit and no command-line way to exit, so it has to be
            # stopped from here. That is safe at this point: Factorio logs the ready
            # pattern only after the save has been written and closed.
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit(30000) | Out-Null
        }
    }

    $copy = Join-Path $TestRoot ("log-{0}.txt" -f $What)
    if (Test-Path -LiteralPath $logPath -PathType Leaf) {
        Copy-Item -LiteralPath $logPath -Destination $copy -Force
    }
    return $copy
}

if ($Visual) {
    Write-Host ""
    Write-Host "   Visual mode: a real game window opens twice." -ForegroundColor Yellow
    Write-Host "   Watch the chat, then quit the game (Esc -> Quit) to let the test continue." -ForegroundColor Yellow
}

#-------------------------------------------------------------------------------
# phase 0: the damaged map
#-------------------------------------------------------------------------------

Write-Step "Creating a deliberately damaged map"

$mapSettings = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
foreach ($key in $boosted.Keys) {
    $mapSettings.enemy_expansion.$key = $boosted[$key]
}
$mapSettings | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $mapSettingsPath -Encoding ASCII

Set-ModList $false
Invoke-Factorio -What 'create' -ForceHeadless -Arguments @(
    '--config', "`"$configPath`""
    '--mod-directory', "`"$modDir`""
    '--create', "`"$savePath`""
    '--map-settings', "`"$mapSettingsPath`""
    '--disable-audio'
    '--no-log-rotation'
) | Out-Null

if (-not (Test-Path -LiteralPath $savePath -PathType Leaf)) {
    throw "Map creation reported success but $savePath does not exist."
}
Write-Host "   created: $savePath" -ForegroundColor Green

#-------------------------------------------------------------------------------
# phase 1: repair and save
#-------------------------------------------------------------------------------

Write-Step "Phase 1 - loading the damaged map with the repair mod, then autosaving"

Copy-Item -LiteralPath $zipPath -Destination $modDir -Force
Set-ModList $true

if ($Visual) {
    $logPhase1 = Invoke-Factorio -What 'phase1' -Arguments (Get-RunArguments $savePath)
}
else {
    $logPhase1 = Invoke-FactorioServer -What 'phase1' -Save $savePath -ReadyPattern 'Saving finished'
}

if (-not (Test-Path -LiteralPath $autoSavePath -PathType Leaf)) {
    $candidates = Get-ChildItem -LiteralPath $savesDir -Filter '*.zip' |
        Where-Object { $_.FullName -ne $savePath } | Sort-Object LastWriteTime -Descending
    if (-not $candidates) {
        throw "No autosave was written. game.auto_save() did not produce a file in $savesDir. Log: $logPhase1"
    }
    $autoSavePath = $candidates[0].FullName
}
Write-Host "   autosaved: $autoSavePath" -ForegroundColor Green

#-------------------------------------------------------------------------------
# phase 2: remove the mod and read the save back
#-------------------------------------------------------------------------------

Write-Step "Phase 2 - removing the repair mod and loading the autosave"

if (Test-Path -LiteralPath $installedZip -PathType Leaf) {
    Remove-Item -LiteralPath $installedZip -Force
}
Set-ModList $false

if (Test-Path -LiteralPath $installedZip) {
    throw "The repair mod is still in $modDir - phase 2 would prove nothing."
}
Write-Host "   removed:  $(Split-Path -Leaf $installedZip)"

$logPhase2 = Invoke-Factorio -What 'phase2' -Arguments (Get-RunArguments $autoSavePath)

#-------------------------------------------------------------------------------
# assertions
#-------------------------------------------------------------------------------

Write-Step "Checking the logs"

$lines1 = @(Get-Content -LiteralPath $logPhase1)
$lines2 = @(Get-Content -LiteralPath $logPhase2)

$harness2 = $lines2 | Where-Object { $_ -match '\[feas-harness\]' }
if (-not $harness2) {
    throw "The harness produced no output in phase 2. Log: $logPhase2"
}

Write-Host ""
$harness2 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
Write-Host ""

$failures = New-Object System.Collections.Generic.List[string]

function Assert-In {
    param([string[]] $Lines, [string] $Pattern, [string] $Description)
    if ($Lines -match [regex]::Escape($Pattern)) {
        Write-Host "   [ok]   $Description" -ForegroundColor Green
    }
    else {
        Write-Host "   [FAIL] $Description" -ForegroundColor Red
        $script:failures.Add($Description)
    }
}

function Assert-NotIn {
    param([string[]] $Lines, [string] $Pattern, [string] $Description)
    $hits = $Lines | Where-Object { $_ -match $Pattern }
    if (-not $hits) {
        Write-Host "   [ok]   $Description" -ForegroundColor Green
    }
    else {
        Write-Host "   [FAIL] $Description" -ForegroundColor Red
        $hits | Select-Object -First 3 | ForEach-Object { Write-Host "          $_" -ForegroundColor Red }
        $script:failures.Add($Description)
    }
}

Assert-In $lines1 'applied (mod added to this save):' 'phase 1: the repair mod applied the values'
Assert-In $lines1 'triggering auto_save' 'phase 1: the autosave was requested'

# The point of the whole test: the repair mod must be gone in phase 2.
Assert-NotIn $lines2 '\[fix-enemy-expansion-save\]' 'phase 2: the repair mod produced no output'
Assert-In $lines2 'repair mod loaded: false' 'phase 2: script.active_mods confirms the mod is gone'

foreach ($key in $expected.Keys) {
    Assert-In $lines2 ("without-mod {0}={1}" -f $key, $expected[$key]) "phase 2: $key survived in the save"
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "FAILED: $($failures.Count) check(s) did not pass." -ForegroundColor Red
    Write-Host "  phase 1 log: $logPhase1"
    Write-Host "  phase 2 log: $logPhase2"
    exit 1
}

Write-Host "PASSED: the repaired values are stored in the save and outlive the mod." -ForegroundColor Green
Write-Host "Test instance left at $TestRoot - delete it manually when you no longer need it."
