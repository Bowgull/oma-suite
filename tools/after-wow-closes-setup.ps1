# Waits until WoW Forever closes, then turns OmaDoomed's rings off (Platynator draws the plates now). WoW rewrites saved
# settings when it closes, so this can only be edited while the game is shut. Safe to run twice.
# 2026-11-16: the RestedXP part was dropped. Joshua switched to Guidelime + TUGs (free), so RestedXP stays off.
# A backup of the file goes to Documents\addon-backups\wow-sv-<time>\ first.
$ErrorActionPreference = 'Stop'
$wtf = 'C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account'
Write-Host "Will turn OmaDoomed's rings off once WoW closes."

while (Get-Process Wow -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 3 }
Start-Sleep -Seconds 3   # let WoW finish writing its files

$oma = Get-ChildItem $wtf -Recurse -Filter 'OmaDoomed.lua' | Where-Object { $_.Directory.Name -eq 'SavedVariables' -and $_.Directory.Parent.Parent.Name -eq 'Account' } | Select-Object -First 1 -ExpandProperty FullName
if (-not $oma) { Write-Host "OmaDoomed settings not found."; exit 1 }
$bak = Join-Path $env:USERPROFILE ("Documents\addon-backups\wow-sv-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $bak | Out-Null; Copy-Item $oma $bak
$t = [IO.File]::ReadAllText($oma)
$n = [regex]::Replace($t, '(\["rings"\] = \{\s*\["enabled"\] = )true', '${1}false', 1)
if ($n -ne $t) { [IO.File]::WriteAllText($oma, $n, [Text.UTF8Encoding]::new($false)); Write-Host "OmaDoomed rings off (backup in $bak)" } else { Write-Host "OmaDoomed rings were already off" }
