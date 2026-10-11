#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# Generates the test images of the sprites cart (gfx/*.png) with the standard
# library only, covering the PNG kinds of D10:
#   hero.png   16x16, palette of 6 colors, no tRNS (index 0 transparent)  -> 4 bpp
#   chars.png  64x16, 4 frames of 16x16, palette of 8 colors              -> 4 bpp
#   pal256.png 64x64, palette of 200 colors, tRNS makes index 5 clear     -> 8 bpp
#   rgba.png   40x24 RGBA (not a power of two), alpha gradient            -> 16 bpp
#   gray2.png  16x16 gray, 2 bits per pixel                               -> 16 bpp
#   big.png    512x256 RGB: fills all texture VRAM (256 KB)               -> 16 bpp
#
# Usage: python make_images.py   (writes into gfx/ next to this file)

import math
import pathlib
import struct
import zlib

OUT = pathlib.Path(__file__).resolve().parent / "gfx"


def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))


def write_png(name, w, h, ctype, depth, rows, plte=None, trns=None):
    """rows: list of bytes objects (already packed for the bit depth)."""
    raw = b"".join(b"\x00" + r for r in rows)  # filter 0 (none) on every row
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, depth, ctype, 0, 0, 0))
    if plte:
        png += chunk(b"PLTE", b"".join(bytes(c) for c in plte))
    if trns is not None:
        png += chunk(b"tRNS", bytes(trns))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    (OUT / name).write_bytes(png)
    print(f"{name}: {w}x{h}, {len(png)} bytes")


def pack4(values):
    return bytes((values[i] << 4) | values[i + 1] for i in range(0, len(values), 2))


def hero():
    # 0 transparent, 1 dark outline, 2 skin, 3 eyes, 4 mouth, 5 hair
    plte = [(255, 0, 255), (26, 28, 44), (255, 205, 117), (41, 54, 111), (177, 62, 83),
            (93, 39, 93)]
    rows = []
    for y in range(16):
        row = []
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            d = math.hypot(dx, dy)
            if d > 7.5:
                v = 0
            elif d > 6.4:
                v = 1
            elif y < 5:
                v = 5
            elif y in (6, 7) and x in (5, 10):
                v = 3
            elif y == 11 and 5 <= x <= 10:
                v = 4
            else:
                v = 2
            row.append(v)
        rows.append(pack4(row))
    write_png("hero.png", 16, 16, 3, 4, rows, plte)


def chars():
    # Four 16x16 frames: a square in a different color with a growing bar
    plte = [(0, 0, 0), (244, 244, 244), (177, 62, 83), (56, 183, 100), (59, 93, 201),
            (255, 205, 117), (26, 28, 44), (115, 239, 247)]
    rows = []
    for y in range(16):
        row = []
        for x in range(64):
            f, fx = divmod(x, 16)
            if fx in (0, 15) or y in (0, 15):
                v = 6
            elif 3 <= fx <= 12 and 3 <= y <= 12 - f * 2:
                v = 2 + f
            elif 3 <= fx <= 12 and y == 13:
                v = 1
            else:
                v = 0
            row.append(v)
        rows.append(pack4(row))
    write_png("chars.png", 64, 16, 3, 4, rows, plte)


def pal256():
    # 200 colors in a hue wheel; index 5 is made transparent by tRNS
    plte = []
    for i in range(200):
        a = i / 200 * 2 * math.pi
        plte.append((int(127 + 127 * math.cos(a)), int(127 + 127 * math.cos(a - 2.1)),
                     int(127 + 127 * math.cos(a + 2.1))))
    trns = [255] * 5 + [0]
    rows = []
    for y in range(64):
        row = []
        for x in range(64):
            d = math.hypot(x - 31.5, y - 31.5)
            if d < 8:
                v = 5  # transparent hole in the middle
            else:
                v = int((math.atan2(y - 31.5, x - 31.5) + math.pi) / (2 * math.pi) * 199)
                if v == 5:
                    v = 6
            row.append(v)
        rows.append(bytes(row))
    write_png("pal256.png", 64, 64, 3, 8, rows, plte, trns)


def rgba():
    rows = []
    for y in range(24):
        row = b""
        for x in range(40):
            a = int(x / 39 * 255)  # left half (< 128) becomes transparent
            row += bytes((255, int(y / 23 * 255), int(x / 39 * 255), a))
        rows.append(row)
    write_png("rgba.png", 40, 24, 6, 8, rows)


def gray2():
    rows = []
    for y in range(16):
        vals = [((x // 4) + (y // 4)) % 4 for x in range(16)]
        rows.append(bytes((vals[i] << 6) | (vals[i + 1] << 4) | (vals[i + 2] << 2) | vals[i + 3]
                          for i in range(0, 16, 4)))
    write_png("gray2.png", 16, 16, 0, 2, rows)


def big():
    rows = [b"".join(bytes((x // 64 * 32, y // 32 * 32, 128)) for x in range(512))
            for y in range(256)]
    write_png("big.png", 512, 256, 2, 8, rows)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    hero()
    chars()
    pal256()
    rgba()
    gray2()
    big()
