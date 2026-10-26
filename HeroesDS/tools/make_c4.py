r"""Makes the C4 battle cart (HeroesDS/carts/c4) and copies it to the emulator SD card.

  python HeroesDS/tools/make_c4.py [--sd D:\Programowanie\sdcard]

The cart gets the combat engine and the rules (cartkit); main.lua and src/ are ours.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cartkit  # noqa: E402

CART = cartkit.cart_dir("c4")


def main(argv):
    p = argparse.ArgumentParser()
    p.add_argument("--sd", default=cartkit.SD)
    a = p.parse_args(argv[1:])
    cartkit.copy_engine(CART)
    cartkit.copy_rules(CART)
    cartkit.deploy(CART, a.sd)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
