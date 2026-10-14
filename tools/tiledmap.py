# SPDX-License-Identifier: Zlib
#
# LiteLua - Tiled maps (JSON: .tmj / .json) -> LiteLua map files (P8, D50).
#
# Tiled (https://www.mapeditor.org) is a free map editor for the PC. The map
# must be orthogonal and finite, with square tiles of 8, 16 or 32 pixels and
# at most 4 tile layers. Each layer uses one tileset; its image name (without
# folder and .png) becomes the LiteLua tileset, so the PNG goes to gfx/ of the
# cart. Tile flags come from the tile properties of the tileset of the layer
# "main" (or the first layer): a boolean property that is true (e.g.
# solid = true), or the tile class/type, is a flag of that tile.

import base64
import gzip
import json
import pathlib
import xml.etree.ElementTree as ET
import zlib

FLIP_BITS = 0xE0000000
MAX_LAYERS = 4
MAX_FLAGS = 8


class TiledError(Exception):
    pass


def _layer_gids(layer):
    data = layer.get("data")
    if isinstance(data, list):
        return [int(g) for g in data]
    if layer.get("encoding") != "base64" or not isinstance(data, str):
        raise TiledError(f"layer '{layer.get('name')}': unknown data encoding")
    raw = base64.b64decode(data)
    comp = layer.get("compression", "")
    if comp == "zlib":
        raw = zlib.decompress(raw)
    elif comp == "gzip":
        raw = gzip.decompress(raw)
    elif comp:
        raise TiledError(f"layer '{layer.get('name')}': compression '{comp}' "
                         "is not supported (use CSV, zlib or gzip)")
    return [int.from_bytes(raw[i:i + 4], "little") for i in range(0, len(raw), 4)]


def _load_tileset(ts, base):
    """Embedded tileset, or the external .tsx/.tsj it points to."""
    first = ts["firstgid"]
    src = ts.get("source")
    if not src:
        return first, ts
    path = (base / src).resolve()
    if path.suffix.lower() in (".tsj", ".json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        return first, data
    root = ET.parse(path).getroot()
    data = {"name": root.get("name"), "tilecount": int(root.get("tilecount", 0)),
            "tiles": []}
    img = root.find("image")
    if img is not None:
        data["image"] = img.get("source")
    for tile in root.findall("tile"):
        props = [{"name": p.get("name"), "type": p.get("type", "string"),
                  "value": p.get("value")} for p in tile.iter("property")]
        cls = tile.get("class") or tile.get("type")
        data["tiles"].append({"id": int(tile.get("id")), "properties": props,
                              "class": cls})
    return first, data


def _tile_flags(tileset):
    """flag name -> sorted tile ids (1-based) from tile properties/classes."""
    flags = {}
    for tile in tileset.get("tiles", []):
        tid = int(tile["id"]) + 1
        names = []
        for p in tile.get("properties", []) or []:
            v = p.get("value")
            if p.get("type") == "bool" and (v is True or str(v).lower() == "true"):
                names.append(p["name"])
        cls = tile.get("class") or tile.get("type")
        if cls:
            names.append(cls)
        for n in names:
            flags.setdefault(n, set()).add(tid)
    return {n: sorted(ids) for n, ids in flags.items()}


def _ranges(ids):
    """[1,2,3,5] -> ["1-3", 5]"""
    out, i = [], 0
    while i < len(ids):
        j = i
        while j + 1 < len(ids) and ids[j + 1] == ids[j] + 1:
            j += 1
        out.append(ids[i] if i == j else f"{ids[i]}-{ids[j]}")
        i = j + 1
    return out


def convert(tiled, base=pathlib.Path(".")):
    """Tiled map (dict) -> (LiteLua map dict, warnings)."""
    warn = []
    if tiled.get("orientation", "orthogonal") != "orthogonal":
        raise TiledError(f"orientation '{tiled.get('orientation')}': only orthogonal "
                         "maps (preset platform) are supported")
    if tiled.get("infinite"):
        raise TiledError("infinite maps are not supported (Map > Map Properties > "
                         "Infinite off)")
    tw, th = tiled.get("tilewidth"), tiled.get("tileheight")
    if tw != th or tw not in (8, 16, 32):
        raise TiledError(f"tiles must be square 8, 16 or 32 pixels (got {tw}x{th})")
    w, h = tiled["width"], tiled["height"]

    tilesets = sorted((_load_tileset(ts, base) for ts in tiled.get("tilesets", [])),
                      key=lambda t: t[0])

    def tileset_of(gid):
        found = None
        for first, ts in tilesets:
            if gid >= first:
                found = (first, ts)
        if found is None:
            raise TiledError(f"tile {gid} has no tileset")
        return found

    layers = []
    for layer in tiled.get("layers", []):
        if layer.get("type") != "tilelayer":
            warn.append(f"layer '{layer.get('name')}' ({layer.get('type')}) skipped: "
                        "only tile layers are converted")
            continue
        gids = _layer_gids(layer)
        if len(gids) != w * h:
            raise TiledError(f"layer '{layer.get('name')}': {len(gids)} tiles, "
                             f"expected {w * h}")
        if any(g & FLIP_BITS for g in gids):
            warn.append(f"layer '{layer.get('name')}': flipped tiles are drawn unflipped")
            gids = [g & ~FLIP_BITS for g in gids]
        used = {tileset_of(g)[0] for g in gids if g}
        if len(used) > 1:
            raise TiledError(f"layer '{layer.get('name')}' uses {len(used)} tilesets; "
                             "LiteLua needs one tileset per layer")
        first, ts = (tileset_of(min(g for g in gids if g)) if used
                     else tilesets[0] if tilesets else (1, {"image": "tiles"}))
        image = ts.get("image")
        if not image:
            raise TiledError(f"tileset '{ts.get('name')}': image collections are not "
                             "supported (use one tileset image)")
        rows = [[(g - first + 1) if g else 0 for g in gids[y * w:(y + 1) * w]]
                for y in range(h)]
        if not layer.get("visible", True):
            warn.append(f"layer '{layer.get('name')}' is hidden in Tiled but converted")
        layers.append({"name": layer.get("name") or f"{len(layers) + 1}",
                       "tileset": pathlib.Path(image).stem, "data": rows,
                       "_ts": ts})
    if not layers:
        raise TiledError("the map has no tile layers")
    if len(layers) > MAX_LAYERS:
        raise TiledError(f"{len(layers)} tile layers; LiteLua maps have at most {MAX_LAYERS}")

    main = next((l for l in layers if l["name"] == "main"), layers[0])
    flags = _tile_flags(main["_ts"])
    if len(flags) > MAX_FLAGS:
        raise TiledError(f"{len(flags)} flags in the tileset; at most {MAX_FLAGS}")
    for l in layers:
        if l["_ts"] is not main["_ts"] and _tile_flags(l["_ts"]):
            warn.append(f"layer '{l['name']}': tile properties of its tileset are ignored "
                        f"(flags come from the tileset of layer '{main['name']}')")
        del l["_ts"]

    out = {"format": 1, "mode": "platform", "tile": tw, "w": w, "h": h,
           "layers": layers}
    if flags:
        out["flags"] = {n: _ranges(ids) for n, ids in sorted(flags.items())}
    return out, warn


def to_lua(m, source=""):
    """LiteLua map dict -> text of map/<name>.lua"""
    def val(v):
        return f'"{v}"' if isinstance(v, str) else str(v)

    lines = ["-- LiteLua map (P8)" + (f", converted from {source}" if source else "")
             + " by tools/litelua.py map",
             "return {",
             f'  format = 1, mode = "platform", tile = {m["tile"]}, '
             f'w = {m["w"]}, h = {m["h"]},']
    if "flags" in m:
        lines.append("  flags = {")
        for n, ids in m["flags"].items():
            key = n if n.isidentifier() else f'["{n}"]'
            lines.append(f"    {key} = {{ {', '.join(val(i) for i in ids)} }},")
        lines.append("  },")
    lines.append("  layers = {")
    for l in m["layers"]:
        name = json.dumps(l["name"], ensure_ascii=False)
        tileset = json.dumps(l["tileset"], ensure_ascii=False)
        lines.append(f"    {{ name = {name}, tileset = {tileset}, data = {{")
        for row in l["data"]:
            lines.append("      { " + ",".join(str(v) for v in row) + " },")
        lines.append("    } },")
    lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def convert_file(src, out):
    src = pathlib.Path(src)
    tiled = json.loads(src.read_text(encoding="utf-8"))
    m, warn = convert(tiled, src.parent)
    pathlib.Path(out).write_text(to_lua(m, src.name), encoding="utf-8", newline="\n")
    return m, warn
