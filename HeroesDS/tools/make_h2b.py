"""Generates the graphics of the H2b test cart (HeroesDS/carts/h2b) from the
original game and copies the cart to the emulator SD card.

  python HeroesDS/tools/make_h2b.py [--sd D:\\Programowanie\\sdcard]

gfx/ and data/ of the cart are made from the game files, so they stay out of
git (.gitignore); only main.lua and cart.lua are ours.
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

# The duel: bandit bottom left facing ne, bandit top right facing sw (a black
# dragon does not fit next to anything at scale 0.5 - DS_GRAPHICS.md)
DUEL = [("bandit", s, d) for d in ("ne", "sw") for s in ("wait", "melee", "flinch")]
# Extra atlases only for the load-time measurement: (actor, state, dir, colors, name)
BENCH = [("black dragon", "melee", "sw", 255, None),
         ("black dragon", "melee", "sw", 15, "black_dragon_melee_sw_16c"),
         ("bandit", "melee", "sw", 15, "bandit_melee_sw_16c"),
         ("black dragon", "walk", "sw", 255, "black_dragon_walk_sw")]


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("--sd", default=r"D:\Programowanie\sdcard")
    a = p.parse_args(argv[1:])
    lib = h4r.Library(DATA)
    for sub in ("gfx", "data"):
        shutil.rmtree(os.path.join(CART, sub), ignore_errors=True)
    names = []
    jobs = [(actor, st, d, 255, None) for actor, st, d in DUEL] + BENCH
    for actor, st, d, colors, name in jobs:
        atlas, shadow, meta = h4atlas.convert(lib, actor, st, d, 0.5, colors)
        name = name or f"{actor}_{st}_{d}".replace(" ", "_")
        h4atlas.write(CART, name, atlas, shadow, meta)
        names.append(name)
        print(f"  {name}: {len(meta['frames'])} frames, {atlas.width}x{atlas.height}"
              + (f", shadow {shadow.width}x{shadow.height}" if shadow else ""))
    with open(os.path.join(CART, "data", "list.lua"), "w") as f:
        f.write("return " + h4atlas.lua(names) + "\n")
    if a.sd and os.path.isdir(a.sd):
        dest = os.path.join(a.sd, "litelua", "carts", "h2b")
        shutil.rmtree(dest, ignore_errors=True)
        shutil.copytree(CART, dest)
        print(f"  copied -> {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
