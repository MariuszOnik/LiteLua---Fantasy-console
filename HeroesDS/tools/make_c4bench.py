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
import sys

import lupa.lua54 as lua54

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cartkit  # noqa: E402

CART = cartkit.cart_dir("c4bench")


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
    p.add_argument("--sd", default=cartkit.SD)
    p.add_argument("--battles", type=int, default=12)
    a = p.parse_args(argv[1:])
    cartkit.copy_engine(CART)
    cartkit.copy_rules(CART)
    run_pc(a.battles)
    cartkit.deploy(CART, a.sd)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
