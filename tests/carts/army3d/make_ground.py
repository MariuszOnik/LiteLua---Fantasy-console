#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
"""Ground tiles of the army3d test cart: gfx/ground.png, 4 frames of 32x32 in
16 colors (grass, grass, field, road), and gfx/grass.png, 64x64 of grass that
repeats over the ground (draw3d with tpt), drawn from noise - our own art."""

import os
import random

from PIL import Image

TILE = 32
KINDS = [
    [(78, 120, 52), (88, 132, 58), (70, 108, 46), (98, 140, 64)],     # grass
    [(84, 126, 54), (74, 114, 50), (96, 136, 60), (66, 100, 44)],     # grass, darker
    [(150, 132, 74), (138, 120, 66), (160, 142, 84), (126, 110, 60)], # field
    [(146, 120, 88), (132, 108, 78), (158, 132, 98), (120, 98, 70)],  # road
]


def main():
    rnd = random.Random(7)
    palette = [(255, 0, 255)] + [c for kind in KINDS for c in kind[:3]]
    palette = palette[:16]
    img = Image.new("P", (TILE * 2, TILE * 2))
    pal = []
    for c in palette:
        pal += list(c)
    img.putpalette(pal + [0] * (768 - len(pal)))
    for k in range(4):
        ox, oy = (k % 2) * TILE, (k // 2) * TILE
        for y in range(TILE):
            for x in range(TILE):
                v = rnd.random()
                if k == 2 and y % 8 < 2:      # furrows
                    v = min(1, v + 0.5)
                i = 0 if v < 0.55 else 1 if v < 0.85 else 2
                img.putpixel((ox + x, oy + y), 1 + k * 3 + i)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gfx", "ground.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)

    grass = Image.new("P", (64, 64))
    grass.putpalette(pal + [0] * (768 - len(pal)))
    for y in range(64):
        for x in range(64):
            v = rnd.random()
            k = 0 if ((x // 16 + y // 16) * 7 + x * y) % 5 else 1   # patches
            i = 0 if v < 0.55 else 1 if v < 0.85 else 2
            grass.putpixel((x, y), 1 + k * 3 + i)
    grass.save(os.path.join(os.path.dirname(out), "grass.png"))


if __name__ == "__main__":
    main()
