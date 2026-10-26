"""Generates the creature data for the battle engine from the original game:
table.creatures (stats, Polish names), the abilities heroes4.exe gives each
creature (creature_abilities.py) and the footprint from combat_actor.

  python HeroesDS/tools/make_rules.py [out_dir]

Default output: HeroesDS/extracted/rules/creatures.lua and artifacts.lua (made from the game
files, so it stays out of git). A Lua data file:

  return {
    ["bandit"] = { name = "bandyta", plural = "bandyci", level = 1, alignment = "chaos",
                   hp = 10, dmg = { 1, 3 }, attack = 9, defense = 9, move = 27, speed = 7,
                   shots = 0, spell_points = 0, spell_power = 0, growth = 26,
                   cost = { gold = 20 }, xp = 6, size = 4, magic_resistance = 0,
                   abilities = { stealth = true }, expansion = 0 },
    ...
  }
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import h4actor  # noqa: E402
import h4atlas  # noqa: E402
import h4r  # noqa: E402
import h4table  # noqa: E402
from creature_abilities import CREATURE_ABILITIES  # noqa: E402

DATA = os.path.join(HERE, "..", "Data")
OUT = os.path.join(HERE, "..", "extracted", "rules", "creatures.lua")
MATERIALS = ("Gold", "Wood", "Ore", "Crystal", "Sulfur", "Mercury", "Gems")


def num(s, default=0):
    s = s.strip()
    return int(s) if re.fullmatch(r"-?\d+", s) else default


def fallback_abilities(short_help, shots, name2kw):
    """Abilities from the display names (only for creatures the exe table lacks)."""
    out = [name2kw[n] for n in (x.strip().lower() for x in short_help.split(",")) if n in name2kw]
    if shots > 0 and "ranged" not in out:
        out.append("ranged")
    return out


def creatures(lib):
    _, arows = h4table.parse(lib.read("table.creature_abilities.h4d"))
    name2kw = {r[1].strip().lower(): r[0].strip().lower() for r in arows[1:] if len(r) >= 2 and r[0].strip()}
    _, rows = h4table.parse(lib.read("table.creatures.h4d"))
    expansion = 0
    out, report = {}, []
    for rec in h4table.records(rows):
        kw = rec.get("Keyword", "").strip()
        if not kw:
            continue
        if not rec.get("Level", "").strip().isdigit():
            if "expansion" in kw.lower():   # "Expansion N Creatures below"
                expansion += 1
            continue
        key = kw.lower()
        shots = num(rec["Shots"])
        if key in CREATURE_ABILITIES:
            abilities = list(CREATURE_ABILITIES[key])
        else:
            abilities = fallback_abilities(rec["Short Help Text"], shots, name2kw)
            report.append(f"{kw}: not in the exe table, from display names: {abilities}")
        mr = 0
        if "magic_resistance" in abilities:
            m = re.search(r"(\d+)\s*%", rec["Short Help Text"])
            mr = int(m.group(1)) if m else 50
        if "magic_immunity" in abilities:
            mr = 100
        size = None
        res = f"combat_actor.{kw}.h4d"
        if res in lib:
            size = max(1, h4actor.parse(lib.read(res), res)["footprint"])
        else:
            report.append(f"{kw}: no {res}")
        out[key] = dict(
            name=rec["Name"].strip(), plural=rec["Plural Name"].strip(), level=num(rec["Level"]),
            alignment=rec["Alignment"].strip().lower(), hp=num(rec["Hit Points"]),
            dmg=[num(rec["Low"]), num(rec["High"])], attack=num(rec["Attack"]), defense=num(rec["Defense"]),
            move=num(rec["Move"]), speed=num(rec["Speed"]), shots=shots, spell_points=num(rec["Spell Points"]),
            spell_power=num(rec.get("Spell Power", "")), growth=num(rec["Weekly Growth"]),
            cost={m.lower(): num(rec[m]) for m in MATERIALS if num(rec.get(m, ""))},
            xp=num(rec["Experience"]), size=size or 1, magic_resistance=mr,
            abilities={a: True for a in abilities}, expansion=expansion)
    return out, report


# Artifact effect types (exe_tables.ARTIFACT_EFFECTS "type"): names worked out from homm4-mac
# and checked against the artifacts' Polish help texts; None = meaning not known yet.
# Units: hero attack/defense in tenths of a point (500 = +50); move in hundredths of a
# cell (300 = +1); army attack/defense, resistance, spell power in percent.
EFFECT_TYPES = {
    0: "adventure_move_pct", 1: None, 4: "scroll_spell", 5: "combat_move", 6: None, 7: "dwelling_growth_pct",
    8: "damage_pct", 9: "extra_damage", 10: "defense", 11: None, 13: None, 15: None, 16: "hit_points_pct",
    17: "spell_immunity", 18: "income", 20: None, 22: "luck", 23: "magic_resistance_pct", 25: "spell_points",
    26: "spell_point_regen", 27: "morale", 36: None, 38: None, 39: None, 40: None, 42: "speed",
    43: "spell_effect", 44: "spellbook", 45: "spell_power_pct", 46: "charged_spell", 47: "spell_cost",
    49: "spell_on_hit", 50: "skill_bonus", 54: "ignore_terrain", 55: "attack", 56: "ability", 57: None,
    58: "set_spell", 59: "set_bonus",
}
TARGETS = {0: "self", 1: "enemy_creatures", 2: "enemy_heroes", 3: "own_creatures", 4: "own_heroes", 5: "all"}


def readable_effect(e):
    """An effect with its type and target named, spell and skill ids as keywords."""
    from exe_tables import SKILL_IDS, SPELL_KEYWORDS
    out = {"type": EFFECT_TYPES.get(e["type"]) or f"type_{e['type']}", "target": TARGETS[e["target"]]}
    for k, v in e.items():
        if k in ("type", "target"):
            continue
        if k == "spell":
            v = SPELL_KEYWORDS[v] if 0 <= v < len(SPELL_KEYWORDS) else v
        elif k == "spells":
            v = "all" if len(v) >= 150 else [SPELL_KEYWORDS[i] for i in v]
        elif k == "skill":
            v = SKILL_IDS[v]
        elif k == "required":
            from exe_tables import ARTIFACT_IDS
            v = [ARTIFACT_IDS[i] for i in v]
        elif k == "subs":
            v = [readable_effect(x) for x in v]
        elif k == "perLevel":
            k = "per_level"
        elif k == "damageKind":
            k = "damage_kind"
        out[k] = v
    return out


def artifacts(lib):
    from exe_tables import ARTIFACT_EFFECTS, ARTIFACT_IDS
    _, rows = h4table.parse(lib.read("table.Artifacts.h4d"))
    texts = {r["Keyword"].strip().lower(): r for r in h4table.records(rows) if r.get("Keyword", "").strip()}
    out, report = {}, []
    for i, kw in enumerate(ARTIFACT_IDS):
        r = texts.get(kw.lower())
        if not r:
            report.append(f"artifact {i} {kw}: not in table.Artifacts")
            continue
        out[kw] = dict(id=i, name=r["Name"].strip(), slot=r["Slot"].strip().lower(), level=r["Level"].strip().lower(),
                       cost=num(r["Cost"]), help=r["Help text"].strip(),
                       effects=[readable_effect(e) for e in ARTIFACT_EFFECTS.get(i, [])])
    return out, report


def write_lua(path, title, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"-- {title}: generated by HeroesDS/tools/make_rules.py from the original game\n")
        f.write("return {\n")
        for key, c in data.items():
            f.write(f'  ["{key}"] = {lua_value(c)},\n')
        f.write("}\n")


def lua_value(v):
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{k} = {lua_value(x)}" if re.fullmatch(r"[a-z_][a-z0-9_]*", k)
                                else f'["{k}"] = {lua_value(x)}' for k, x in v.items()) + " }"
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_value(x) for x in v) + " }"
    if isinstance(v, str):
        esc = v.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
        return '"' + esc + '"'
    return h4atlas.lua(v)


def main(argv):
    out_dir = argv[1] if len(argv) > 1 else os.path.dirname(OUT)
    lib = h4r.Library(DATA)
    for name, title, make in (("creatures", "Creatures of Heroes IV", creatures),
                              ("artifacts", "Artifacts of Heroes IV", artifacts)):
        data, report = make(lib)
        path = os.path.join(out_dir, name + ".lua")
        write_lua(path, title, data)
        for line in report:
            print("  " + line)
        print(f"{len(data)} {name} -> {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
