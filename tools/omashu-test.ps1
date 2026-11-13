# omashu-test.ps1: one unattended run on the Omashu laptop (2026-11-13). Checks that OmaPointer loads in a real
# session and runs the OmaChat Party-tab tests from key presses sent the way Couch Mode sends the phone's.
# Runs on the laptop's desktop (started by a one-off scheduled task, since SSH has no desktop).
#   1. refuses if WoW is already running (never interrupts play)
#   2. copies the throwaway test add-on OmaProbe (from C:\Omashu\stage\OmaProbe) into WoW: Forever's AddOns
#   3. starts WoW with Couch Mode's own C:\Omashu\couch\wow-start.ps1, presses Enter on the character screen
#   4. Ctrl+Shift+F10 (state), then Ctrl+Shift+1..7: invite / add friend (a made-up name), follow, inspect,
#      ready check, leave + remove + make leader (a made-up name), a raid mark on yourself (then cleared)
#   5. quits WoW normally so both add-ons' logs are saved, prints them, removes OmaProbe and its saved file
# Nobody real is invited, added or whispered. Log: C:\Omashu\logs\omashu-test.txt
param([int]$LoadSeconds = 80)
$ErrorActionPreference = 'Stop'
$wow = "${env:ProgramFiles(x86)}\World of Warcraft\_forever_"
$addon = "$wow\Interface\AddOns\OmaProbe"
$log = 'C:\Omashu\logs\omashu-test.txt'; Set-Content $log ''
function L($m) { $s = "{0:HH:mm:ss} {1}" -f (Get-Date), $m; Add-Content $log $s }
if (Get-Process Wow -ErrorAction SilentlyContinue) { L 'WoW is already running: not starting a test.'; exit 1 }

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
$K = @{ F10 = @(0x79,0x44); '1' = @(0x31,0x02); '2' = @(0x32,0x03); '3' = @(0x33,0x04); '4' = @(0x34,0x05); '5' = @(0x35,0x06); '6' = @(0x36,0x07); '7' = @(0x37,0x08) }

L "1. installing OmaProbe into $addon"
New-Item -ItemType Directory -Force $addon | Out-Null
Copy-Item 'C:\Omashu\stage\OmaProbe\OmaProbe.toc', 'C:\Omashu\stage\OmaProbe\OmaProbe.lua' $addon -Force
L '2. starting WoW'
& 'C:\Omashu\couch\wow-start.ps1' -Timeout 150 | Out-Null
$p = $null; for ($i = 0; $i -lt 60 -and -not $p; $i++) { $p = Get-Process Wow -ErrorAction SilentlyContinue | Select-Object -First 1; if (-not $p) { Start-Sleep 2 } }
if (-not $p) { L 'WoW did not start.'; Remove-Item -Recurse -Force $addon -Confirm:$false; exit 2 }
L "   Wow.exe $($p.Id) up"
Start-Sleep 100
$p.Refresh()
if (Front $p) { [LT]::Key(0x0D, 0x1C) | Out-Null; L '   pressed Enter on the character screen' } else { L '   could not bring WoW to the front' }
Start-Sleep $LoadSeconds

L '3. party tests'
$plan = @('F10',4, '1',5, '2',5, '3',4, '4',5, '5',4, '6',5, '7',4, 'F10',3)
for ($i = 0; $i -lt $plan.Count; $i += 2) {
  $k = $plan[$i]; $ok = (Front $p) -and [LT]::Chord([uint16]$K[$k][0], [uint16]$K[$k][1])
  L "   Ctrl+Shift+$k sent=$ok"; Start-Sleep $plan[$i + 1]
}

L '4. quitting WoW normally'
$p.CloseMainWindow() | Out-Null; $p.WaitForExit(60000) | Out-Null
foreach ($name in 'OmaProbe', 'OmaPointer') {
  $sv = Get-ChildItem "$wow\WTF\Account" -Recurse -Filter "$name.lua" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'SavedVariables' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($sv) { L "   --- $name log ($($sv.LastWriteTime))"; Get-Content $sv.FullName | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^"' } | Select-Object -Last 60 | ForEach-Object { L ("   " + $_.Trim('",')) } } else { L "   no saved file for $name" }
}
if (-not (Get-Process Wow -ErrorAction SilentlyContinue)) {
  Remove-Item -Recurse -Force $addon -Confirm:$false
  Get-ChildItem "$wow\WTF\Account" -Recurse -Filter 'OmaProbe.lua*' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match 'SavedVariables' } | Remove-Item -Force -Confirm:$false
  L '   OmaProbe and its saved file removed'
} else { L '   WoW still running: OmaProbe left in place' }
L 'done'
