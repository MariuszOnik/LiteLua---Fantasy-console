# Starts Azahar with a .3dsx, waits, saves a screenshot of its window, closes it.
# -cx/-cy: a mouse click in the window first (a tap) -- only when nobody works at the
# PC: when Azahar is not in front, the click lands in another window.
# Usage: .\azshot.ps1 -rom builds\heroes3d-<tag>.3dsx -png shot.png [-wait 12]
param([string]$rom, [string]$png, [int]$wait = 12, [int]$cx = -1, [int]$cy = -1)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class W {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e);
  public struct RECT { public int L, T, R, B; }
}
"@
$az = "D:\Programowanie\azahar-windows-mxe-2127.0-alpha3\azahar-windows-mxe-2127.0-alpha3\azahar.exe"
$p = Start-Process $az -ArgumentList "`"$rom`"" -PassThru
Start-Sleep $wait
$p.Refresh()
$h = $p.MainWindowHandle
[W]::SetForegroundWindow($h) | Out-Null
Start-Sleep 1
$r = New-Object W+RECT
[W]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.R - $r.L; $hh = $r.B - $r.T
if ($cx -ge 0) {   # a tap: click at (cx, cy) in the window
    [W]::SetCursorPos($r.L + $cx, $r.T + $cy) | Out-Null
    [W]::mouse_event(2, 0, 0, 0, 0); Start-Sleep -Milliseconds 120; [W]::mouse_event(4, 0, 0, 0, 0)
    Start-Sleep 2
}
$bmp = New-Object System.Drawing.Bitmap $w, $hh
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
$bmp.Save($png)
Stop-Process $p.Id
"saved $png ($w x $hh)"
