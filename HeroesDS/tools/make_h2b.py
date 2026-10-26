"""Generates the graphics of the H2b test cart (HeroesDS/carts/h2b) from the
original game and copies the cart to the emulator SD card.

  python HeroesDS/tools/make_h2b.py [--sd D:\\Programowanie\\sdcard]

The cart shows a duel, bandit (ne) vs black dragon (sw), in three styles
(h4atlas.STYLES), each unit with its own scale. gfx/ and data/ of the cart are
made from the game files, so they stay out of git (.gitignore); only main.lua
and cart.lua are ours.
"""
import argparse
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import h4atlas  # noqa: E402
import h4r  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
CART = os.path.join(HERE, "..", "carts", "h2b")
DATA = os.path.join(HERE, "..", "Data")

STATES = ("wait", "melee", "flinch")
# unit: (actor, direction, scale per style; other styles: the style's scale hint,
# the dragon 0.8 of it)
UNITS = {"bandit": ("bandit", "ne", {"current": 0.5, "smooth": 0.5, "oldschool": 0.375}, 1.0),
         "dragon": ("black dragon", "sw", {"current": 0.35, "smooth": 0.35, "oldschool": 0.3}, 0.8)}
STYLE_ORDER = ("test1", "oldschool", "smooth", "current")


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("--sd", default=r"D:\Programowanie\sdcard")
    a = p.parse_args(argv[1:])
    lib = h4r.Library(DATA)
    for sub in ("gfx", "data"):
        shutil.rmtree(os.path.join(CART, sub), ignore_errors=True)
    styles = []
    for style in STYLE_ORDER:
        if style not in h4atlas.STYLES:
            print(f"  (no style {style}, skipped)")
            continue
        hint = h4atlas.STYLES[style].scale
        styles.append(dict(name=style, zoom=1))
        for unit, (actor, d, scales, ratio) in UNITS.items():
            scale = scales.get(style, round(hint * ratio, 3))
            for st in STATES:
                atlas, shadow, meta = h4atlas.convert(lib, actor, st, d, scale, style=style)
                name = f"{style}_{unit}_{st}"
                h4atlas.write(CART, name, atlas, shadow, meta)
                bpp = 4 if len(atlas.getpalette()) // 3 <= 16 else 8
                print(f"  {name}: {len(meta['frames'])} frames, {atlas.width}x{atlas.height} {bpp} bpp"
                      + (f", shadow {shadow.width}x{shadow.height}" if shadow else ""))
    with open(os.path.join(CART, "data", "styles.lua"), "w") as f:
        f.write("return {\n" + "".join(f'  {{ name = "{s["name"]}", zoom = {s["zoom"]} }},\n' for s in styles)
                + "}\n")
    if a.sd and os.path.isdir(a.sd):
        dest = os.path.join(a.sd, "litelua", "carts", "h2b")
        shutil.rmtree(dest, ignore_errors=True)
        shutil.copytree(CART, dest)
        print(f"  copied -> {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
