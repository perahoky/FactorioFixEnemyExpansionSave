#Requires -Version 5.1
<#
.SYNOPSIS
    Locates Factorio.exe. Dot-sourced by the test scripts.

.DESCRIPTION
    Kept out of the test scripts so neither of them has to carry a hard-coded path to
    somebody's machine. Checked in this order:

      1. -FactorioExe passed to the test script
      2. the FACTORIO_EXE environment variable
      3. every Steam library folder (registry SteamPath plus libraryfolders.vdf)
      4. the usual standalone install locations
#>

function Find-FactorioExe {
    [CmdletBinding()]
    param(
        [string] $Explicit
    )

    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit -PathType Leaf)) {
            throw "Factorio.exe not found at the path you passed: $Explicit"
        }
        return (Get-Item -LiteralPath $Explicit).FullName
    }

    $candidates = New-Object System.Collections.Generic.List[string]

    if ($env:FACTORIO_EXE) { $candidates.Add($env:FACTORIO_EXE) }

    $steamRoots = New-Object System.Collections.Generic.List[string]
    $steamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
    if ($steamPath) { $steamRoots.Add($steamPath.Replace('/', '\')) }
    $steamRoots.Add("$env:ProgramFiles\Steam")
    $steamRoots.Add("${env:ProgramFiles(x86)}\Steam")

    foreach ($root in $steamRoots) {
        if (-not $root) { continue }

        $candidates.Add((Join-Path $root 'steamapps\common\Factorio\bin\x64\Factorio.exe'))

        # Games often live on a different drive than Steam itself.
        $libraryFile = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraryFile -PathType Leaf) {
            $vdf = Get-Content -LiteralPath $libraryFile -Raw -ErrorAction SilentlyContinue
            foreach ($match in [regex]::Matches($vdf, '"path"\s*"([^"]+)"')) {
                $library = $match.Groups[1].Value -replace '\\\\', '\'
                $candidates.Add((Join-Path $library 'steamapps\common\Factorio\bin\x64\Factorio.exe'))
            }
        }
    }

    foreach ($standalone in @("$env:ProgramFiles\Factorio", "${env:ProgramFiles(x86)}\Factorio", "$env:LOCALAPPDATA\Programs\Factorio")) {
        if ($standalone) { $candidates.Add((Join-Path $standalone 'bin\x64\factorio.exe')) }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }

    throw "Factorio.exe not found. Pass -FactorioExe <path> or set the FACTORIO_EXE environment variable."
}
