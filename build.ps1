#Requires -Version 5.1
<#
.SYNOPSIS
    Packages the Factorio mod in fix-enemy-expansion-save\ into dist\.

.DESCRIPTION
    Build only. Writes exactly one file, dist\<name>_<version>.zip, and nothing else.
    Installing the built zip is a manual step, see README.md.

    There is deliberately no output-path parameter and no staging folder, so the script
    contains no recursive delete at all. The only thing it ever removes is a previous
    build of its own zip - a single file, by exact name, inside dist\.

    Entries are added one by one instead of via ZipFile::CreateFromDirectory, because on
    Windows PowerShell 5.1 (.NET Framework) that helper writes entry names with a
    backslash separator. Real mod zips use '/', and Factorio would otherwise read
    "locale\en\x.cfg" as one flat file name and never find the locale.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$modName = 'fix-enemy-expansion-save'
$source = Join-Path $PSScriptRoot $modName
$outputDirectory = Join-Path $PSScriptRoot 'dist'

if (-not (Test-Path -LiteralPath $source)) {
    throw "Mod folder not found: $source"
}

$infoPath = Join-Path $source 'info.json'
$info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json

if ($info.name -ne $modName) {
    throw "info.json declares name '$($info.name)' but the folder is '$modName' - Factorio requires them to match."
}
if ([string]::IsNullOrWhiteSpace($info.version)) {
    throw "info.json has no version."
}

$folderName = "{0}_{1}" -f $modName, $info.version
$zipPath = Join-Path $outputDirectory ($folderName + '.zip')

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

if (Test-Path -LiteralPath $zipPath -PathType Leaf) {
    Remove-Item -LiteralPath $zipPath -Force
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$sourceRoot = (Get-Item -LiteralPath $source).FullName.TrimEnd('\')
$files = Get-ChildItem -LiteralPath $sourceRoot -File -Recurse | Sort-Object FullName

if ($files.Count -eq 0) {
    throw "No files found under $sourceRoot"
}

# The zip gets exactly one top-level folder, which is what Factorio expects. The folder
# name stays unversioned on purpose: Factorio accepts that (several installed mods ship
# that way) and it keeps the folder usable as an unzipped mod without renaming anything.
$archive = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceRoot.Length + 1).Replace('\', '/')
        $entryName = "$modName/$relative"
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,
            $file.FullName,
            $entryName,
            [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        Write-Verbose "added $entryName"
    }
}
finally {
    $archive.Dispose()
}

$size = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1KB, 1)
Write-Host "Built $zipPath ($($files.Count) files, $size KB)"
Write-Host ""
Write-Host "To install it, copy it into the Factorio mods folder yourself:"
Write-Host "  Copy-Item '$zipPath' `"`$env:APPDATA\Factorio\mods\`""

$zipPath
