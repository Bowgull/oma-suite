# Installs OmaDemon from this repo's folder into the Shadow's WoW Forever (no zip). Safe to run twice.
# 1. Refuses while WoW is running (new files need a fresh start; it never closes WoW).
# 2. Copies (never moves) the installed folder to C:\Omashu-backup\OmaDemon-<date-time>, checks the copy by hashes.
# 3. Puts every file the toc lists, plus OmaDemon.toc, Libs, and the game's art and sound (.tga .blp .ogg .mp3 .ttf
#    under art and shards) into a fresh folder; leaves out tests, the .py art makers, .png sources and .html sheets.
#    The old folder goes to the Recycle Bin only after the backup is checked.
# 4. Checks every installed file's SHA-256 against the repo.
# Run with -WhatIf to see the file list without changing anything.
# Undo: delete the AddOns\OmaDemon folder and copy the backup folder back in its place.
param(
  [string]$Game = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns',
  [string]$BackupRoot = 'C:\Omashu-backup',
  [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$src = (Resolve-Path (Join-Path $PSScriptRoot '..\addons\OmaDemon')).Path   # resolved: a '..' left in it threw off the relative paths
$dst = Join-Path $Game 'OmaDemon'

if (Get-Process -Name 'Wow*' -ErrorAction SilentlyContinue) { throw 'WoW is running. Quit it fully first.' }
if (-not (Test-Path $Game)) { throw "WoW Forever AddOns folder not found: $Game" }

# the file list: the toc's own lines, then the extras
$toc = Join-Path $src 'OmaDemon.toc'
$files = Get-Content $toc | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
$files += 'OmaDemon.toc'
Get-ChildItem (Join-Path $src 'Libs') -Recurse -File | Where-Object { $_.Extension -ne '.md' } |
  ForEach-Object { $files += $_.FullName.Substring($src.Length + 1) }
foreach ($dir in 'art', 'shards') {
  Get-ChildItem (Join-Path $src $dir) -Recurse -File | Where-Object { @('.tga', '.blp', '.ogg', '.mp3', '.ttf') -contains $_.Extension.ToLower() } |
    ForEach-Object { $files += $_.FullName.Substring($src.Length + 1) }
}
$files = $files | Sort-Object -Unique
foreach ($f in $files) { if (-not (Test-Path (Join-Path $src $f))) { throw "Listed but missing in the repo: $f" } }

Write-Host "From: $src"
Write-Host "To:   $dst"
Write-Host "Files: $($files.Count)"
if ($WhatIf) { $files; return }

# back up what's there (copy), check it
if (Test-Path $dst) {
  $bk = Join-Path $BackupRoot ('OmaDemon-' + (Get-Date -Format 'yyyyMMdd-HHmm'))
  if (Test-Path $bk) { $bk = $bk + (Get-Date -Format 'ss') }
  Write-Host "Backup: $dst -> $bk"
  New-Item -ItemType Directory -Force $bk | Out-Null
  Copy-Item (Join-Path $dst '*') $bk -Recurse -Force
  $a = Get-ChildItem $dst -Recurse -File; $b = Get-ChildItem $bk -Recurse -File
  if ($a.Count -ne $b.Count) { throw "Backup file count differs ($($a.Count) vs $($b.Count))" }
  foreach ($x in $a) {
    $rel = $x.FullName.Substring($dst.Length + 1)
    if ((Get-FileHash $x.FullName).Hash -ne (Get-FileHash (Join-Path $bk $rel)).Hash) { throw "Backup hash differs: $rel" }
  }
  Write-Host "Backup checked: $($a.Count) files, hashes match."
  Add-Type -AssemblyName Microsoft.VisualBasic
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($dst, 'OnlyErrorDialogs', 'SendToRecycleBin')
}

# install
foreach ($f in $files) {
  $to = Join-Path $dst $f
  New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
  Copy-Item (Join-Path $src $f) $to -Force
}
# check
$bad = 0
foreach ($f in $files) {
  if ((Get-FileHash (Join-Path $src $f)).Hash -ne (Get-FileHash (Join-Path $dst $f)).Hash) { Write-Host "MISMATCH $f"; $bad++ }
}
$extra = (Get-ChildItem $dst -Recurse -File).Count - $files.Count
if ($bad -or $extra) { throw "Install check failed: $bad mismatches, $extra extra files" }
Write-Host "Installed $($files.Count) files, every SHA-256 matches the repo."
