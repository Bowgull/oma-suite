# Waits until WoW Forever closes, then sets up Bujuju for the WC run (2026-11-16, Joshua: "get rested xp back on and
# adjusted for my WC quests ... you can do all those steps too for me"). WoW rewrites these files when it closes, so they
# can only be edited while the game is shut. Safe to run twice: every change is skipped if it's already in place.
#   1. AddOns.txt: RestedXP (RXPGuides) back on
#   2. RestedXP: current guide = "RestedXP Forever Dungeon Guide (H)" / "18-21 The Barrens" (then 21-22 WC, 22-24 Hillsbrad)
#   3. RestedXP: Wailing Caverns added to the enabled dungeons
#   4. OmaDoomed: rings off (Platynator draws the plates now)
# Backups of every file it touches go to Documents\addon-backups\wow-sv-<time>\ first.
param([string]$Char = 'Bujuju-Banton')
$ErrorActionPreference = 'Stop'
$wtf = 'C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account'
Write-Host "Will set up $Char once WoW closes: RestedXP on (Dungeon Guide 18-21 Barrens, WC enabled), OmaDoomed rings off."

while (Get-Process Wow -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 3 }
Start-Sleep -Seconds 3   # let WoW finish writing its files

$charDir = Get-ChildItem $wtf -Recurse -Directory -Filter $Char | Select-Object -First 1
if (-not $charDir) { Write-Host "No folder for $Char found."; exit 1 }
$addons = Join-Path $charDir.FullName 'AddOns.txt'
$rxp    = Join-Path $charDir.FullName 'SavedVariables\RXPGuides.lua'
$oma    = Get-ChildItem $wtf -Recurse -Filter 'OmaDoomed.lua' | Where-Object { $_.Directory.Parent.Name -notmatch $Char } | Select-Object -First 1 -ExpandProperty FullName

$bak = Join-Path $env:USERPROFILE ("Documents\addon-backups\wow-sv-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $bak | Out-Null
foreach ($f in @($addons, $rxp, $oma)) { if ($f -and (Test-Path $f)) { Copy-Item $f $bak } }
Write-Host "Backed up to $bak"

function Edit-File($path, [scriptblock]$change) {
  if (-not $path -or -not (Test-Path $path)) { Write-Host "missing: $path"; return }
  $t = [IO.File]::ReadAllText($path); $n = & $change $t
  if ($n -ne $t) { [IO.File]::WriteAllText($path, $n, [Text.UTF8Encoding]::new($false)); Write-Host "changed: $path" } else { Write-Host "already set: $path" }
}

Edit-File $addons { param($t) $t -replace 'RXPGuides: disabled', 'RXPGuides: enabled' }

Edit-File $rxp { param($t)
  $t = [regex]::Replace($t, '\["currentGuideGroup"\] = "[^"]*"', '["currentGuideGroup"] = "RestedXP Forever Dungeon Guide (H)"', 1)
  $t = [regex]::Replace($t, '\["currentGuideName"\] = "[^"]*"', '["currentGuideName"] = "18-21 The Barrens"', 1)
  if ($t -notmatch '\["WC"\] = "Wailing Caverns"') {
    $t = [regex]::Replace($t, '(\["enabledDungeons"\] = \{\s*\["Horde"\] = \{)', ('$1' + "`n" + '["WC"] = "Wailing Caverns",'), 1)
  }
  $t }

Edit-File $oma { param($t) [regex]::Replace($t, '(\["rings"\] = \{\s*\["enabled"\] = )true', '${1}false', 1) }

Write-Host "Done. Start WoW: RestedXP opens on 18-21 The Barrens (Dungeon Guide); OmaDoomed rings are off."
