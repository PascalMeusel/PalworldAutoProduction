[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ModsDirectory,
    [switch]$DisableLegacyPriority
)
$ErrorActionPreference = 'Stop'
$modsPath = (Resolve-Path -LiteralPath $ModsDirectory).Path
if ((Split-Path -Leaf $modsPath) -ne 'Mods') { throw 'Choose the active UE4SS Mods directory.' }
$targetPath = Join-Path $modsPath 'PalworldAutoProduction'
$backupRoot = Join-Path (Split-Path -Parent $modsPath) 'PalworldAutoProduction-backups'
$backupPath = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
if (Test-Path -LiteralPath $targetPath) {
    Copy-Item -LiteralPath $targetPath -Destination (Join-Path $backupPath 'PalworldAutoProduction') -Recurse
}
$modListPath = Join-Path $modsPath 'mods.txt'
if (Test-Path -LiteralPath $modListPath) {
    Copy-Item -LiteralPath $modListPath -Destination (Join-Path $backupPath 'mods.txt')
    $modList = Get-Content -LiteralPath $modListPath -Raw
} else { $modList = '' }

New-Item -ItemType Directory -Path (Join-Path $targetPath 'Scripts') -Force | Out-Null
# The installer and distributable ZIP use exactly the same release manifest.
$releaseFiles = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release-files.txt')
foreach ($file in $releaseFiles) {
    if ($file -cnotmatch '^(enabled\.txt|README\.md|LICENSE|Scripts/[a-z_]+\.lua)$') { throw "Unexpected release file: $file" }
    $destination = Join-Path $targetPath $file
    if ($file -eq 'Scripts/config.lua' -and (Test-Path -LiteralPath $destination)) { continue }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $destination
}

if ($modList -match '(?m)^[ \t]*PalworldAutoProduction[ \t]*:') {
    $modList = [regex]::Replace($modList, '(?m)^[ \t]*PalworldAutoProduction[ \t]*:[ \t]*[01]', 'PalworldAutoProduction : 1')
} elseif ($modList -match '(?m)^Keybinds[ \t]*:') {
    $modList = [regex]::Replace($modList, '(?m)^Keybinds[ \t]*:', "PalworldAutoProduction : 1`r`nKeybinds :")
} else { $modList += "`r`nPalworldAutoProduction : 1`r`n" }

if ($DisableLegacyPriority) {
    $legacyPath = Join-Path $modsPath 'PalWorkPriority'
    if (Test-Path -LiteralPath $legacyPath) {
        Copy-Item -LiteralPath $legacyPath -Destination (Join-Path $backupPath 'PalWorkPriority') -Recurse
        $legacyEnabled = Join-Path $legacyPath 'enabled.txt'
        if (Test-Path -LiteralPath $legacyEnabled) {
            Rename-Item -LiteralPath $legacyEnabled -NewName ('enabled.disabled-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        }
    }
    if ($modList -match '(?m)^[ \t]*PalWorkPriority[ \t]*:') {
        $modList = [regex]::Replace($modList, '(?m)^[ \t]*PalWorkPriority[ \t]*:[ \t]*[01]', 'PalWorkPriority : 0')
    }
}
Set-Content -LiteralPath $modListPath -Value ($modList.TrimEnd([char]13,[char]10) + "`r`n") -Encoding utf8 -NoNewline
Write-Output "Installed: $targetPath"
Write-Output "Backup: $backupPath"
Write-Output 'Restart Palworld to load the update. This installer never stops the game.'
