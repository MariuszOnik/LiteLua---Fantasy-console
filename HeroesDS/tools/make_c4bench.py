"""Makes the C4a speed test cart (HeroesDS/carts/c4bench) and copies it to the emulator
SD card.

  python HeroesDS/tools/make_c4bench.py [--sd D:\\Programowanie\\sdcard] [--battles 12]

The cart gets the combat engine (HeroesDS/combat -> src/combat) and the rules from
extracted/rules (make_rules.py) without the help texts, which the DS does not need. The
same benchmark (src/bench.lua) runs here on a PC through lupa; its results go to
data/pc.lua, so the cart shows how much slower the DS is and whether its battles end in the
same state. src/combat and data/ are made here, so they stay out of git.
"""
import argparse
import os
import re
import shutil
import sys

import lupa.lua54 as lua54

HERE = os.path.dirname(os.path.abspath(__file__))
HEROES = os.path.normpath(os.path.join(HERE, ".."))
CART = os.path.join(HEROES, "carts", "c4bench")
RULES = os.path.join(HEROES, "extracted", "rules")

# `, help = "..."` in the generated rules (a Lua string with \-escapes)
HELP = re.compile(r',\s*help\s*=\s*"(?:[^"\\]|\\.)*"')


def copy_engine():
    dest = os.path.join(CART, "src", "combat")
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(os.path.join(HEROES, "combat"), dest)


def copy_rules():
    os.makedirs(os.path.join(CART, "data"), exist_ok=True)
    for name in ("creatures.lua", "spells.lua"):
        with open(os.path.join(RULES, name), encoding="utf-8") as f:
            text = f.read()
        short = HELP.sub("", text)
        with open(os.path.join(CART, "data", name), "w", encoding="utf-8", newline="\n") as f:
            f.write(short)
        print(f"  {name}: {len(text) // 1024} KB -> {len(short) // 1024} KB")


def run_pc(battles):
    rt = lua54.LuaRuntime()
    root = CART.replace("\\", "/")
    rt.execute(f'package.path = "{root}/src/?.lua;" .. package.path')
    run = rt.eval("""function(root, battles)
      local bench = require("bench")
      local env = { clock = function() return math.floor(os.clock() * 1e6) end,
                    creatures = dofile(root .. "/data/creatures.lua"),
                    spells = dofile(root .. "/data/spells.lua") }
      local out = { reach = bench.reachable(env, 5), battles = {} }
      for seed = 1, battles do out.battles[seed] = bench.battle(env, seed) end
      return out
    end""")
    res = run(root, battles)
    reach = res["reach"]
    lines = ["-- The PC run of src/bench.lua: made by HeroesDS/tools/make_c4bench.py",
             "return {",
             f"  reach = {{ avg = {reach['avg']}, worst = {reach['worst']} }},",
             "  battles = {"]
    print(f"  PC reachable: avg {reach['avg']} us, worst {reach['worst']} us")
    for seed in range(1, battles + 1):
        b = res["battles"][seed]
        print(f"  PC #{seed}: {b['rounds']} rounds, {b['turns']} turns, avg {b['avg'] / 1000:.1f} ms, "
              f"worst {b['worst'] / 1000:.1f} ms, spell {b['spell'] / 1000:.0f} / path {b['path'] / 1000:.0f}"
              f" of {b['total'] / 1000:.0f} ms")
        lines.append(f"    {{ avg = {b['avg']}, worst = {b['worst']}, checksum = {lua_str(b['checksum'])} }},")
    lines += ["  },", "}", ""]
    with open(os.path.join(CART, "data", "pc.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("--sd", default=r"D:\Programowanie\sdcard")
    p.add_argument("--battles", type=int, default=12)
    a = p.parse_args(argv[1:])
    copy_engine()
    copy_rules()
    run_pc(a.battles)
    if a.sd and os.path.isdir(a.sd):
        dest = os.path.join(a.sd, "litelua", "carts", "c4bench")
        shutil.rmtree(dest, ignore_errors=True)
        shutil.copytree(CART, dest)
        print(f"  copied -> {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
