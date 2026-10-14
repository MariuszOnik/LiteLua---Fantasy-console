#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# LiteLua - test and example graphics for tile maps (P8, D50), drawn by code
# (like make_font.py), so every pixel is on the grid and the tiles fit
# together. Palette: Sweetie 16 (D22); index 0 is transparent.
#
# Writes (16x16 cells):
#   tests/carts/map/gfx/tiles.png   tileset, 8 x 4 tiles (ids 1..32)
#   tests/carts/map/gfx/hero.png    hero, 4 frames: stand, walk 1, walk 2, jump
#
# Tile ids (frame + 1):
#   1 grass   2 dirt     3 brick    4 brick dark  5 platform  6 ladder
#   7 spikes  8 coin     9 crate   10 water top  11 water    12 stone
#  13 bush   14 flower  15 sign    16 flag       17-32 free
#
# Usage: python tools/make_tiles.py

import pathlib
import random
import struct
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "carts" / "map" / "gfx"

PALETTE = [
    0x1a1c2c, 0x5d275d, 0xb13e53, 0xef7d57, 0xffcd75, 0xa7f070, 0x38b764, 0x257179,
    0x29366f, 0x3b5dc9, 0x41a6f6, 0x73eff7, 0xf4f4f4, 0x94b0c2, 0x566c86, 0x333c57,
]
# Names of the palette entries used below
CLEAR, PURPLE, RED, ORANGE, YELLOW, LIME, GREEN, TEAL = range(8)
NAVY, BLUE, SKY, CYAN, WHITE, SILVER, GREY, DARK = range(8, 16)

T = 16


class Sheet:
    def __init__(self, cols, rows):
        self.w, self.h = cols * T, rows * T
        self.px = [[CLEAR] * self.w for _ in range(self.h)]

    def cell(self, n):
        """Drawing helper for cell n (0-based)."""
        return Cell(self, (n % (self.w // T)) * T, (n // (self.w // T)) * T)

    def png(self):
        def chunk(kind, data):
            body = kind + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
        raw = b"".join(b"\0" + bytes((r[x] << 4) | r[x + 1] for x in range(0, self.w, 2))
                       for r in self.px)
        plte = b"".join(struct.pack(">I", c)[1:] for c in PALETTE)
        return (b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 4, 3, 0, 0, 0))
                + chunk(b"PLTE", plte)
                + chunk(b"tRNS", b"\0")  # Index 0 transparent
                + chunk(b"IDAT", zlib.compress(raw, 9))
                + chunk(b"IEND", b""))


class Cell:
    def __init__(self, sheet, ox, oy):
        self.s, self.ox, self.oy = sheet, ox, oy

    def p(self, x, y, c):
        if 0 <= x < T and 0 <= y < T:
            self.s.px[self.oy + y][self.ox + x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.p(xx, yy, c)

    def art(self, rows, colors):
        """rows: strings of characters, colors: character -> palette entry."""
        for y, row in enumerate(rows):
            for x, ch in enumerate(row):
                if ch in colors:
                    self.p(x, y, colors[ch])

    def speckle(self, y1, y2, colors, n, seed):
        rnd = random.Random(seed)
        for _ in range(n):
            self.p(rnd.randrange(T), rnd.randrange(y1, y2), rnd.choice(colors))


def dirt(c, top, seed):
    c.rect(0, top, T, T - top, ORANGE)
    c.speckle(top, T, [PURPLE, RED], 14, seed)


def tiles():
    s = Sheet(8, 4)

    # 1 grass: dirt with a grass top whose blades repeat every 16 pixels
    c = s.cell(0)
    dirt(c, 4, 1)
    c.rect(0, 0, T, 4, GREEN)
    for x in range(T):
        c.p(x, 4 + (1 if x % 5 in (1, 2) else 0), GREEN)
        if x % 4 == 0:
            c.p(x, 0, LIME)
    # 2 dirt
    dirt(s.cell(1), 0, 2)
    # 3, 4 bricks (rows of 8x4 with offset joints)
    for n, face, joint in ((2, RED, PURPLE), (3, GREY, DARK)):
        c = s.cell(n)
        c.rect(0, 0, T, T, face)
        for y in range(0, T, 4):
            c.rect(0, y + 3, T, 1, joint)
            off = 0 if (y // 4) % 2 == 0 else 4
            for x in range(off, T, 8):
                c.rect(x, y, 1, 3, joint)
        c.speckle(0, T, [joint], 4, n)
    # 5 platform: a wooden plank (one-way)
    c = s.cell(4)
    c.rect(0, 0, T, 5, ORANGE)
    c.rect(0, 0, T, 1, YELLOW)
    c.rect(0, 4, T, 1, PURPLE)
    for x in (3, 11):
        c.rect(x, 1, 1, 3, RED)
    # 6 ladder
    c = s.cell(5)
    c.rect(2, 0, 2, T, ORANGE)
    c.rect(12, 0, 2, T, ORANGE)
    for y in (2, 7, 12):
        c.rect(4, y, 8, 2, YELLOW)
    # 7 spikes
    spike = [".ww.", ".ws.", ".ss.", ".sg.", "ssgg", "ssgg", "sggg", "dddd"]
    s.cell(6).art(["................"] * 8 + [row * 4 for row in spike],
                  {"w": WHITE, "s": SILVER, "g": GREY, "d": DARK})
    # 8 coin
    s.cell(7).art([
        "................",
        "................",
        "......4444......",
        ".....433334.....",
        "....43344334....",
        "....43343334....",
        "....43343334....",
        "....43343334....",
        "....43343334....",
        "....43343334....",
        "....43344334....",
        ".....433334.....",
        "......4444......",
        "................",
    ], {"4": YELLOW, "3": ORANGE})
    # 9 crate
    c = s.cell(8)
    c.rect(0, 0, T, T, ORANGE)
    c.rect(0, 0, T, 2, YELLOW)
    c.rect(0, 14, T, 2, PURPLE)
    c.rect(0, 0, 2, T, YELLOW)
    c.rect(14, 0, 2, T, PURPLE)
    for i in range(2, 14):
        c.p(i, i, RED)
        c.p(15 - i, i, RED)
    # 10 water top, 11 water
    c = s.cell(9)
    c.rect(0, 3, T, T - 3, BLUE)
    for x in range(T):
        c.p(x, 2 + (x // 4) % 2, SKY)
    c.speckle(5, T, [SKY], 5, 10)
    c = s.cell(10)
    c.rect(0, 0, T, T, BLUE)
    c.speckle(0, T, [SKY, NAVY], 8, 11)
    # 12 stone block
    c = s.cell(11)
    c.rect(0, 0, T, T, SILVER)
    c.rect(0, 0, T, 1, WHITE)
    c.rect(0, 15, T, 1, GREY)
    c.rect(15, 0, 1, T, GREY)
    c.speckle(1, 15, [GREY], 10, 12)
    # 13 bush, 14 flower, 15 sign, 16 flag (decorations, no flags)
    s.cell(12).art([
        "................", "................", "................", "................",
        "................", "................", "......6666......", "....66556666....",
        "...6655566666...", "..665566666776..", "..666666667776..", ".66666667777776.",
        ".66666677777776.", "6666667777777766", "7777777777777777", "................",
    ], {"5": LIME, "6": GREEN, "7": TEAL})
    s.cell(13).art([
        "................", "................", "................", "................",
        "................", "................", "................", ".......22.......",
        "......2442......", ".......22.......", ".......6........", "......66........",
        ".......6..6.....", ".......666......", ".......6........", ".......6........",
    ], {"2": RED, "4": YELLOW, "6": GREEN})
    s.cell(14).art([
        "................", "................", "................", "..333333333333..",
        "..344444444443..", "..34cccc4ccc43..", "..344444444443..", "..34ccc4cccc43..",
        "..344444444443..", "..333333333333..", ".......33.......", ".......33.......",
        ".......33.......", ".......33.......", ".......33.......", ".......33.......",
    ], {"3": PURPLE, "4": ORANGE, "c": RED})
    s.cell(15).art([
        "....d...........", "....d222222.....", "....d2222222....", "....d22222222...",
        "....d2222222....", "....d222222.....", "....d...........", "....d...........",
        "....d...........", "....d...........", "....d...........", "....d...........",
        "....d...........", "....d...........", "...ddd..........", "..ddddd.........",
    ], {"d": SILVER, "2": RED})
    return s


def hero():
    s = Sheet(4, 1)
    body = [
        "................",
        ".....999999.....",
        "....99999999....",
        "....9cc44cc9....",
        "....94c44c49....",
        "....94444449....",
        ".....444444.....",
        "......2222......",
        "....22222222....",
        "...4.222222.4...",
        "...4.222222.4...",
        ".....888888.....",
        ".....88..88.....",
    ]
    legs = {
        0: [".....88..88.....", ".....33..33.....", "....333..333...."],
        1: [".....88...88....", "....33.....33...", "...333.....333.."],
        2: ["......88.88.....", "......33.33.....", ".....333.333...."],
        3: ["....88....88....", "...33......33...", "..333......333.."],
    }
    colors = {"9": ORANGE, "c": WHITE, "4": YELLOW, "2": BLUE, "8": NAVY, "3": PURPLE}
    for f in range(4):
        rows = list(body) + legs[f]
        if f == 3:  # Jump: arms up
            rows[9] = "..4..222222..4.."
            rows[8] = "..4.22222222.4.."
        s.cell(f).art(rows, colors)
    return s


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, sheet in (("tiles", tiles()), ("hero", hero())):
        path = OUT / (name + ".png")
        path.write_bytes(sheet.png())
        print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
