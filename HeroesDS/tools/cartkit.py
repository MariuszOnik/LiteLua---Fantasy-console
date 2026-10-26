"""Shared steps of the HeroesDS cart makers (make_c4bench.py, make_c4.py): the combat engine
into the cart's src/combat, the rules from extracted/rules (make_rules.py) without the help
texts into data/, and a copy of the cart to the emulator SD card. src/combat and data/ are
made, so they stay out of git.
"""
import os
import re
import shutil

HERE = os.path.dirname(os.path.abspath(__file__))
HEROES = os.path.normpath(os.path.join(HERE, ".."))
RULES = os.path.join(HEROES, "extracted", "rules")
SD = r"D:\Programowanie\sdcard"

# `, help = "..."` in the generated rules (a Lua string with \-escapes)
HELP = re.compile(r',\s*help\s*=\s*"(?:[^"\\]|\\.)*"')


def cart_dir(name):
    return os.path.join(HEROES, "carts", name)


def copy_engine(cart):
    dest = os.path.join(cart, "src", "combat")
    shutil.rmtree(dest, ignore_errors=True)
    shutil.copytree(os.path.join(HEROES, "combat"), dest)


def copy_rules(cart, names=("creatures.lua", "spells.lua")):
    os.makedirs(os.path.join(cart, "data"), exist_ok=True)
    for name in names:
        with open(os.path.join(RULES, name), encoding="utf-8") as f:
            text = f.read()
        short = HELP.sub("", text)
        with open(os.path.join(cart, "data", name), "w", encoding="utf-8", newline="\n") as f:
            f.write(short)
        print(f"  {name}: {len(text) // 1024} KB -> {len(short) // 1024} KB")


def deploy(cart, sd=SD):
    if sd and os.path.isdir(sd):
        dest = os.path.join(sd, "litelua", "carts", os.path.basename(cart))
        shutil.rmtree(dest, ignore_errors=True)
        shutil.copytree(cart, dest)
        print(f"  copied -> {dest}")
