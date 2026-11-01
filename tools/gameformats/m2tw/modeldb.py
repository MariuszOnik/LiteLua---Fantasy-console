"""Print what battle_models.modeldb says about a model: meshes, textures per faction, skeletons.
python modeldb.py MODEL [faction]"""
import re, sys

DB = "E:/AI/M2TW/teutonic/mods/teutonic/data/unit_models/battle_models.modeldb"
name = sys.argv[1].lower()
faction = sys.argv[2].lower() if len(sys.argv) > 2 else None
t = open(DB, encoding="latin1").read()
i = t.lower().find(f" {name} ")
nxt = re.search(r" \d+ -?\d[\d.]* -?\d[\d.]* -?\d[\d.]* -?\d[\d.]* -?\d[\d.]* -?\d[\d.]* \d+ [a-z]", t[i + 50:])
chunk = t[i:i + 50 + (nxt.start() if nxt else 3000)]
toks = chunk.split()
for k, tok in enumerate(toks):
    low = tok.lower()
    if low.endswith(".mesh") or low.startswith("mtw2_") or low.startswith("fs_") or low == "horse":
        print(tok)
    elif low.endswith(".texture") and (faction is None or f"_{faction}" in low or toks[k - 2].lower() == faction):
        print(tok, " <- faction", toks[k - 2])
