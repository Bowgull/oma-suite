# Installs OmaDemon on this PC from the zip sitting next to this script (in Downloads).
# Safe to run twice. The old OmaDemon folder is renamed to OmaDemon-old-<time>, never deleted.
# Run from an admin PowerShell:  & "$env:USERPROFILE\Downloads\<this file>.ps1"
param([string]$Zip = '')
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Zip) {
  $Zip = Get-ChildItem $here -Filter 'OmaDemon-*.zip' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Zip -or -not (Test-Path $Zip)) { Write-Host "No OmaDemon zip found next to this script." -ForegroundColor Red; exit 1 }

$addons = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
if (-not (Test-Path $addons)) { Write-Host "WoW Forever AddOns folder not found: $addons" -ForegroundColor Red; exit 1 }

if (Get-Process -Name 'Wow*' -ErrorAction SilentlyContinue) {
  Write-Host "WoW is open. That's fine: type /reload in game after this finishes." -ForegroundColor Yellow
}

Write-Host "Will install: $Zip"
Write-Host "Into:         $addons\OmaDemon"

$tmp = Join-Path $env:TEMP ("OmaDemon-unpack-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
Expand-Archive -Path $Zip -DestinationPath $tmp -Force
$src = Join-Path $tmp 'OmaDemon'
if (-not (Test-Path (Join-Path $src 'OmaDemon.toc'))) { Write-Host "Zip has no OmaDemon\OmaDemon.toc. Nothing changed." -ForegroundColor Red; exit 1 }

$dst = Join-Path $addons 'OmaDemon'
if (Test-Path $dst) {
  $old = 'OmaDemon-old-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  Rename-Item -Path $dst -NewName $old
  # WoW would load the renamed copy as a second add-on, so it moves out of AddOns into a backup folder
  $bk = 'C:\Omashu-backup'; New-Item -ItemType Directory -Force $bk | Out-Null
  Move-Item -Path (Join-Path $addons $old) -Destination (Join-Path $bk $old)
  Write-Host "Old copy kept at $bk\$old"
}
Copy-Item -Path $src -Destination $dst -Recurse

$a = (Get-ChildItem $src -Recurse -File | Measure-Object Length -Sum)
$b = (Get-ChildItem $dst -Recurse -File | Measure-Object Length -Sum)
Remove-Item $tmp -Recurse -Force
if ($a.Count -eq $b.Count -and $a.Sum -eq $b.Sum) {
  Write-Host ("Installed: {0} files, {1} bytes. In game: /reload" -f $b.Count, $b.Sum) -ForegroundColor Green
} else {
  Write-Host "Copy check failed ($($a.Count) vs $($b.Count) files). Tell Claude." -ForegroundColor Red; exit 1
}
