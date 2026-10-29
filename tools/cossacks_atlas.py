#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
"""Soldier atlas for billboards() (D60) from the PNGs of the Cossacks sprite
extractor (DSCossac/cossacks-ce/tools/extract_sprites.py, mode "unit").

Takes the stored directions (d00..d08: south, turning west, to north; with
--dirs 5 every second one, for 8 directions around) of a few
animations, crops them to one cell around the common anchor, scales them down
and packs them in one 16-color PNG (index 0 transparent; the shadow becomes a
checkerboard of a dark color). Frame of animation a, direction d, step f is
first[a] + d * frames[a] + f, as billboards:anim expects.

Writes <out>/gfx/<name>.png and <out>/src/<name>.lua (frame size, anchor,
animations). The art belongs to the game: keep the output out of the repo.

  python tools/cossacks_atlas.py <extractor out>/MBA tests/carts/army3d \
      --name soldier --scale 0.4 --anims STAND:1 WALK:10 PATTACK:11
"""

import argparse
import json
import math
import os

from PIL import Image

BODY = 180     # alpha from which a pixel is the figure
SHADOW = 50    # alpha from which a pixel is shadow


def pick_steps(n, want):
    """'want' steps spread evenly over an animation of n frames."""
    if want >= n:
        return list(range(n))
    return [round(i * n / want) for i in range(want)]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("unit", help="extractor output folder of one unit (meta.json)")
    ap.add_argument("cart", help="cart folder")
    ap.add_argument("--name", default="soldier")
    ap.add_argument("--scale", type=float, default=0.4)
    ap.add_argument("--dirs", type=int, default=9, choices=(2, 3, 5, 9),
                    help="stored directions to keep: 9 (16 around), 5 (8), 3 (4), 2")
    ap.add_argument("--anims", nargs="+", default=["STAND:1", "WALK:10", "PATTACK:11"],
                    help="NAME:steps")
    ap.add_argument("--colors", type=int, default=15)
    args = ap.parse_args()

    meta = json.load(open(os.path.join(args.unit, "meta.json")))["animations"]
    anims = []
    for spec in args.anims:
        name, _, steps = spec.partition(":")
        a = meta[name]
        anims.append((name, a, pick_steps(a["frames"], int(steps or a["frames"]))))

    # Stored directions run south to north in 9 steps; keep every n-th
    keep = [d * 8 // (args.dirs - 1) for d in range(args.dirs)]

    # One cell for all: the union of the visible boxes around the anchor
    left = top = right = bottom = 0
    for name, a, steps in anims:
        axp, ayp = a["anchor"]
        for d in keep:
            for f in steps:
                x0, y0, x1, y1 = a["boxes"][d][f]
                left, right = min(left, x0 - axp), max(right, x1 - axp)
                top, bottom = min(top, y0 - ayp), max(bottom, y1 - ayp)
    s = args.scale
    cl, ct = math.floor(left * s), math.floor(top * s)
    cw, ch = math.ceil(right * s) - cl + 1, math.ceil(bottom * s) - ct + 1
    cw += cw & 1
    ch += ch & 1

    frames = []          # RGBA cells in atlas order
    layout = []
    for name, a, steps in anims:
        axp, ayp = a["anchor"]
        layout.append((name, len(frames), len(steps)))
        for d in keep:
            for f in steps:
                im = Image.open(os.path.join(args.unit, name, "d%02d_f%03d.png" % (d, f)))
                im = im.convert("RGBA")
                w, h = round(im.width * s), round(im.height * s)
                small = im.resize((w, h), Image.LANCZOS)
                cell = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
                # the anchor lands on (-cl, -ct) of the cell
                cell.paste(small, (round(-cl - axp * s), round(-ct - ayp * s)))
                frames.append(cell)

    # Smallest power-of-two texture: try widths, keep the least area
    best = None
    for tw in (64, 128, 256, 512, 1024):
        c = tw // cw
        if c == 0:
            continue
        rows = math.ceil(len(frames) / c)
        th = 8
        while th < rows * ch:
            th *= 2
        if th > 1024:
            continue
        if best is None or tw * th < best[0] * best[1]:
            best = (tw, th, c)
    if best is None:
        raise SystemExit("atlas does not fit in 1024x1024: lower --scale or steps")
    tw, th, cols = best
    atlas = Image.new("RGBA", (cols * cw, math.ceil(len(frames) / cols) * ch), (0, 0, 0, 0))
    for i, cell in enumerate(frames):
        atlas.paste(cell, ((i % cols) * cw, (i // cols) * ch))

    # 16 colors: the figure quantized, the shadow one dark color on a checkerboard
    px = atlas.load()
    rgb = Image.new("RGB", atlas.size, (0, 0, 0))
    rp = rgb.load()
    body = []
    for y in range(atlas.height):
        for x in range(atlas.width):
            r, g, b, al = px[x, y]
            if al >= BODY:
                rp[x, y] = (r, g, b)
                body.append((x, y))
    shade_colors = args.colors - 1
    sample = Image.new("RGB", (len(body), 1))
    sample.putdata([rp[x, y] for x, y in body])
    q = sample.quantize(shade_colors, method=Image.MEDIANCUT)
    pal = q.getpalette()[:shade_colors * 3]
    idx = list(q.get_flattened_data() if hasattr(q, "get_flattened_data") else q.getdata())
    out = Image.new("P", atlas.size, 0)
    op = out.load()
    for (x, y), i in zip(body, idx):
        op[x, y] = i + 2
    for y in range(atlas.height):
        for x in range(atlas.width):
            al = px[x, y][3]
            if SHADOW <= al < BODY and (x + y) & 1 == 0:
                op[x, y] = 1
    palette = [255, 0, 255, 24, 28, 16] + pal
    palette += [0] * (48 - len(palette))
    out.putpalette(palette)
    os.makedirs(os.path.join(args.cart, "gfx"), exist_ok=True)
    os.makedirs(os.path.join(args.cart, "src"), exist_ok=True)
    out.save(os.path.join(args.cart, "gfx", args.name + ".png"), transparency=0)

    with open(os.path.join(args.cart, "src", args.name + ".lua"), "w", newline="\n") as fh:
        fh.write("-- Generated by tools/cossacks_atlas.py: frames of gfx/%s.png\n" % args.name)
        fh.write("return {\n")
        fh.write("  w = %d, h = %d, dirs = %d,\n" % (cw, ch, args.dirs))
        fh.write("  ax = %.4f, ay = %.4f,\n" % (-cl / cw, -ct / ch))
        fh.write("  anims = {\n")
        for name, first, n in layout:
            fh.write("    %s = { first = %d, frames = %d },\n" % (name, first, n))
        fh.write("  },\n}\n")
    vram = tw * th // 2
    print("%s: %d frames of %dx%d, atlas %dx%d (texture %dx%d, %d KB at 4 bpp)"
          % (args.name, len(frames), cw, ch, atlas.width, atlas.height, tw, th, vram // 1024))


if __name__ == "__main__":
    main()
