# lfg-test.ps1: one unattended run of the OmaChat group finder tests on this PC (Shadow).
# What it does, in order (re-runnable; it refuses to start if WoW is already running, so it never interrupts play):
#   1. copies the throwaway test add-on scripts/wow/OmaProbe into WoW: Forever's AddOns folder
#   2. starts WoW with couch-mode/wow-start.ps1, presses Enter on the character screen (enters the world)
#   3. sends Ctrl+Shift+F-keys from outside the game, the way Couch Mode would for the phone:
#        F10 state, F7 search, then each listing shape (F1 one dungeon, F2 + playstyle, F3 two dungeons, F4 both)
#        with an unlist (F9) after each
#   3b. pointer tests with a pretend Xbox pad (scripts/wow/pad.py): game pointer on (Ctrl+Shift+F11), right stick,
#       D-pad up (move the real mouse), D-pad left (simulated click), the right-click menu (Ctrl+Shift+F12)
#   4. quits WoW normally (so the log is saved), prints the log, deletes the add-on and its saved file
# Nothing here whispers or invites anyone. The character is listed in the Group Finder for a few seconds per shape.
# Log of the run: C:\Omashu\logs\lfg-test.txt
param([int]$LoadSeconds = 75, [switch]$SkipLfg, [switch]$SkipPointer)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$wow = "${env:ProgramFiles(x86)}\World of Warcraft\_forever_"
$addon = "$wow\Interface\AddOns\OmaProbe"
$log = 'C:\Omashu\logs\lfg-test.txt'; New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function L($m) { $s = "{0:HH:mm:ss} {1}" -f (Get-Date), $m; Add-Content $log $s; Write-Output $s }
Set-Content $log ''
if (Get-Process Wow -ErrorAction SilentlyContinue) { L 'WoW is already running: not starting a test (it would interrupt play).'; exit 1 }

Add-Type @"
using System; using System.Runtime.InteropServices;
public class LT {
 [StructLayout(LayoutKind.Sequential)] public struct KI { public ushort vk, scan; public uint flags, time; public IntPtr extra; }
 [StructLayout(LayoutKind.Explicit, Size=40)] public struct IN { [FieldOffset(0)] public uint type; [FieldOffset(8)] public KI ki; }
 [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint n, IN[] i, int size);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern void keybd_event(byte k, byte s, uint f, UIntPtr e);
 static IN Make(ushort vk, ushort sc, uint fl) { IN x = new IN(); x.type = 1; x.ki.vk = vk; x.ki.scan = sc; x.ki.flags = fl; return x; }
 public static bool Chord(ushort vk, ushort sc) { IN[] a = { Make(0x11,0x1D,0), Make(0x10,0x2A,0), Make(vk,sc,0), Make(vk,sc,2), Make(0x10,0x2A,2), Make(0x11,0x1D,2) }; return SendInput(6, a, Marshal.SizeOf(typeof(IN))) == 6; }
 public static bool Key(ushort vk, ushort sc) { IN[] a = { Make(vk,sc,0), Make(vk,sc,2) }; return SendInput(2, a, Marshal.SizeOf(typeof(IN))) == 2; }
}
"@
function Front($p) { [LT]::keybd_event(0x12,0,0,[UIntPtr]::Zero); [LT]::SetForegroundWindow($p.MainWindowHandle) | Out-Null; [LT]::keybd_event(0x12,0,2,[UIntPtr]::Zero); Start-Sleep -Milliseconds 400; return ([LT]::GetForegroundWindow() -eq $p.MainWindowHandle) }
$F = @{ F1 = @(0x70,0x3B); F2 = @(0x71,0x3C); F3 = @(0x72,0x3D); F4 = @(0x73,0x3E); F7 = @(0x76,0x41); F9 = @(0x78,0x43); F10 = @(0x79,0x44) }

L "1. installing the test add-on into $addon"
New-Item -ItemType Directory -Force $addon | Out-Null
Copy-Item "$root\scripts\wow\OmaProbe\OmaProbe.toc", "$root\scripts\wow\OmaProbe\OmaProbe.lua" $addon -Force
L '2. starting WoW'
& "$root\couch-mode\wow-start.ps1" -Timeout 150 | Out-Null
$p = Get-Process Wow -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { L 'WoW did not start.'; exit 2 }
Start-Sleep 100
if (Front $p) { [LT]::Key(0x0D, 0x1C) | Out-Null; L '   pressed Enter on the character screen' } else { L '   could not bring WoW to the front' }
Start-Sleep $LoadSeconds

if (-not $SkipLfg) {
L '3. sending the test keys'
$plan = @('F10',4, 'F7',5, 'F1',6, 'F9',4, 'F2',6, 'F9',4, 'F3',6, 'F9',4, 'F4',6, 'F9',4, 'F10',3)
for ($i = 0; $i -lt $plan.Count; $i += 2) {
  $k = $plan[$i]; $ok = (Front $p) -and [LT]::Chord([uint16]$F[$k][0], [uint16]$F[$k][1])
  L "   Ctrl+Shift+$k sent=$ok"; Start-Sleep $plan[$i + 1]
}
}
if (-not $SkipPointer) {
  L '3b. pointer tests with the pretend pad'
  $py = & python -I "$root\scripts\wow\pad.py" wait:3 front key:F10 key:F11 wait:0.5 btn:DPAD_UP wait:0.5 key:F8 btn:DPAD_LEFT wait:1 btn:DPAD_RIGHT wait:0.4 btn:DPAD_DOWN wait:1 btn:DPAD_UP wait:0.5 rt wait:1 key:F8 2>&1
  $py | ForEach-Object { L "   pad: $_" }
}

L '4. quitting WoW normally'
$p.CloseMainWindow() | Out-Null; $p.WaitForExit(45000) | Out-Null
$sv = Get-ChildItem "$wow\WTF\Account" -Recurse -Filter 'OmaProbe.lua' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($sv) { Get-Content $sv.FullName | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^"' } | ForEach-Object { L ("   log " + $_.Trim('",')) } } else { L '   no saved log found' }
if (-not (Get-Process Wow -ErrorAction SilentlyContinue)) {
  Remove-Item -Recurse -Force $addon -Confirm:$false
  if ($sv) { Remove-Item -Force $sv.FullName -Confirm:$false; Remove-Item -Force ($sv.FullName + '.bak') -ErrorAction SilentlyContinue -Confirm:$false }
  L '   test add-on and its saved file removed'
} else { L '   WoW still running: add-on left in place, remove it after quitting' }
