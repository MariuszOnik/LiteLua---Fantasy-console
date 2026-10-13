# SPDX-License-Identifier: Zlib
#
"""Drives melonDS for tests (D17, D43): starts it with the ROM from the
emulator SD card, presses keys, taps the bottom screen with the mouse, saves
screenshots, then closes it (so melonDS writes the SD folder back, log.txt).
melonDS must be on top while keys are sent (default key mapping).

Usage: python tools/melon.py script.txt outdir
Script lines (# starts a comment):
  wait <seconds>
  key <name> [hold_seconds]        a b x y l r start select up down left right
  keys <name+name> [hold_seconds]  several at once, e.g. keys l+r+y
  tap <x> <y>                      bottom screen pixel (0-255, 0-191)
  shot <name>                      both screens as outdir/<name>.png (256x384)
Needs Pillow."""
import ctypes, ctypes.wintypes as W, subprocess, sys, time, os
from PIL import ImageGrab

MELON = r"D:\Programowanie\melonDS-1.1-windows-x86_64\melonDS.exe"
ROM = r"D:\Programowanie\sdcard\litelua.nds"
u = ctypes.windll.user32
u.SetProcessDPIAware()
VK = {"a": 0x41, "b": 0x42, "x": 0x58, "y": 0x59, "l": 0x4C, "r": 0x52,
      "start": 0x0D, "select": 0x20, "up": 0x26, "down": 0x28, "left": 0x25, "right": 0x27}
EXT = {"up", "down", "left", "right"}

def find_window(pid):
    found = []
    @ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)
    def cb(h, _):
        p = W.DWORD()
        u.GetWindowThreadProcessId(h, ctypes.byref(p))
        if p.value == pid and u.IsWindowVisible(h):
            found.append(h)
        return True
    u.EnumWindows(cb, 0)
    return found[0] if found else None

def screens(h):
    r = W.RECT(); u.GetClientRect(h, ctypes.byref(r))
    pt = W.POINT(0, 0); u.ClientToScreen(h, ctypes.byref(pt))
    menu = u.GetSystemMetrics(15)  # SM_CYMENU: Qt's menu bar is in the client area
    w, hh = r.right, r.bottom - menu
    s = min(w / 256, hh / 384)
    ox = pt.x + (w - 256 * s) / 2
    oy = pt.y + menu + (hh - 384 * s) / 2
    return ox, oy, s

def key(names, hold):
    for n in names:
        flags = 1 if n in EXT else 0
        u.keybd_event(VK[n], 0, flags, 0)
    time.sleep(hold)
    for n in names:
        flags = 3 if n in EXT else 2
        u.keybd_event(VK[n], 0, flags, 0)
    time.sleep(0.15)

def tap(h, x, y):
    ox, oy, s = screens(h)
    sx, sy = int(ox + (x + 0.5) * s), int(oy + (192 + y + 0.5) * s)
    u.SetCursorPos(sx, sy)
    time.sleep(0.05)
    u.mouse_event(2, 0, 0, 0, 0)
    time.sleep(0.12)
    u.mouse_event(4, 0, 0, 0, 0)
    time.sleep(0.2)

def shot(h, path):
    ox, oy, s = screens(h)
    img = ImageGrab.grab((int(ox), int(oy), int(ox + 256 * s), int(oy + 384 * s)))
    img.resize((256, 384)).save(path)

def main():
    script, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    p = subprocess.Popen([MELON, ROM])
    h = None
    for _ in range(50):
        time.sleep(0.2)
        h = find_window(p.pid)
        if h: break
    time.sleep(1.5)
    try:
        for line in open(script, encoding="utf-8"):
            line = line.split("#")[0].split()
            if not line: continue
            u.SetForegroundWindow(h)
            c = line[0]
            if c == "wait": time.sleep(float(line[1]))
            elif c in ("key", "keys"):
                key(line[1].split("+"), float(line[2]) if len(line) > 2 else 0.1)
            elif c == "tap": tap(h, int(line[1]), int(line[2]))
            elif c == "shot": shot(h, os.path.join(out, line[1] + ".png"))
    finally:
        u.PostMessageW(h, 0x0010, 0, 0)  # WM_CLOSE: melonDS syncs the SD folder
        try:
            p.wait(15)
        except subprocess.TimeoutExpired:
            p.terminate()

main()
