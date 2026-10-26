"""Converts one Heroes IV animation (actor, state, direction) to LiteLua files:
an atlas PNG with a palette, a shadow atlas PNG (1 color) and a Lua meta file.

  python h4atlas.py <Data dir> <actor> <state> <dir> <out_dir> [--scale 0.5]
                    [--colors 255] [--kind combat|adv] [--name NAME]

  python h4atlas.py HeroesDS/Data bandit melee sw out --scale 0.5

Writes out/gfx/NAME.png, out/gfx/NAME_sh.png and out/data/NAME.lua, where NAME
defaults to "<actor>_<state>_<dir>" (spaces -> "_"). The direction is looked up
in combat_actor / adv_actor, so a missing one gives the nearest drawn sequence.

Meta (Lua table):
  fps, hit (hit frame, 0 = none), scale, image, shadow (names for image()),
  rects = { {x, y, w, h, ox, oy}, ... }   atlas rectangles; ox, oy = where the
                                          rectangle's top left goes, relative
                                          to the actor's ground point
  frames = { r1, r2, ... }                rect index for every frame (1-based)
  srects, sframes                         the same for the shadow (0 = none);
                                          the shadow atlas is szoom times smaller:
                                          draw w * szoom x h * szoom (sspr)

LiteLua has no per-pixel alpha (D10): frame alpha is cut at 50 %, shadows keep
only their shape and are meant to be drawn with alpha() (DS_GRAPHICS.md).
"""
import argparse
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import h4actor  # noqa: E402
import h4d  # noqa: E402
import h4r  # noqa: E402

PAD = 1  # Empty pixels between atlas rectangles


def pixels(img):
    get = getattr(img, "get_flattened_data", None) or img.getdata
    return list(get())


def sequence_name(lib, actor, state, direction, kind):
    res = f"{kind}_actor.{actor}.h4d"
    a = h4actor.parse(lib.read(res), res)
    st = a["states"].get(state)
    if not st or direction not in st["dirs"]:
        raise ValueError(f"{actor}: no {state} {direction} in {res}")
    return st["dirs"][direction], st, a


def compose(seq, layers):
    """One RGBA image of several layers on their union box; returns (img, box)."""
    boxes = [i.box for i in layers]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
    img = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]))
    for layer in layers:
        img.alpha_composite(layer.rgba(), (layer.box[0] - box[0], layer.box[1] - box[1]))
    return img, box


def frame_images(seq, prefix):
    """Per frame number: key of its layers; and per key: (img, box). Base frame under frames."""
    base = seq.image("base_frame")
    keys, images = [], {}
    for n in range(1, seq.frame_count() + 1):
        layers = [i for i in seq.layers(prefix, n) if i.kind]
        if prefix == "frame" and base and base.kind:
            layers = [base] + layers
        key = tuple(i.name for i in layers)
        keys.append(key)
        if key and key not in images:
            images[key] = compose(seq, layers)
    return keys, images


def scaled(img, box, pivot, scale, cut):
    """Scales an RGBA image placed at box; returns (img, ox, oy) relative to pivot."""
    w = max(1, round(img.width * scale))
    h = max(1, round(img.height * scale))
    if (w, h) != img.size:
        img = img.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")
    alpha = img.getchannel("A").point(lambda a: 255 if a >= cut else 0)
    img.putalpha(alpha)
    bb = alpha.getbbox()
    ox = round((box[0] - pivot[0]) * scale)
    oy = round((box[1] - pivot[1]) * scale)
    if not bb:
        return None, ox, oy
    return img.crop(bb), ox + bb[0], oy + bb[1]


def pack(sizes):
    """Shelf packing; returns (W, H, positions) with power-of-two sides, smallest area."""
    order = sorted(range(len(sizes)), key=lambda i: -sizes[i][1])
    best = None
    for W in (8, 16, 32, 64, 128, 256, 512, 1024):
        if any(w + PAD > W for w, h in sizes):
            continue
        pos, x, y, row = [None] * len(sizes), 0, 0, 0
        for i in order:
            w, h = sizes[i]
            if x + w > W:
                x, y, row = 0, y + row + PAD, 0
            pos[i] = (x, y)
            x += w + PAD
            row = max(row, h)
        H = 8
        while H < y + row:
            H *= 2
        if H <= 1024 and (best is None or (W * H, max(W, H)) < (best[0] * best[1], max(best[0], best[1]))):
            best = (W, H, pos)
    if best is None:
        raise ValueError("animation does not fit a 1024x1024 atlas")
    return best


def to_palette(atlas, colors):
    """RGBA (alpha 0/255) -> 'P' image: index 0 transparent, 1..colors opaque."""
    px = pixels(atlas)
    opaque = [p[:3] for p in px if p[3]]
    sample = Image.new("RGB", (max(1, len(opaque)), 1))
    sample.putdata(opaque or [(0, 0, 0)])
    pal = sample.quantize(colors=colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    idx = atlas.convert("RGB").quantize(palette=pal, dither=Image.Dither.NONE)
    out = Image.new("P", atlas.size)
    out.putdata([i + 1 if p[3] else 0 for i, p in zip(pixels(idx), px)])
    used = pal.getpalette()[:colors * 3]
    out.putpalette([0, 0, 0] + used)
    out.info["transparency"] = 0
    return out


def build_atlas(pieces, colors):
    """pieces: list of RGBA images. Returns ('P' image, [(x, y)])."""
    W, H, pos = pack([p.size for p in pieces])
    atlas = Image.new("RGBA", (W, H))
    for p, xy in zip(pieces, pos):
        atlas.paste(p, xy)
    return to_palette(atlas, colors), pos


def convert(lib, actor, state, direction, scale=0.5, colors=255, kind="combat", shadow_zoom=2):
    """Returns (atlas, shadow_atlas or None, meta dict without the image names).

    Shadows are stored shadow_zoom times smaller and drawn enlarged (they are
    soft and see-through anyway); their ox, oy are in screen pixels like the
    frames', their w, h in atlas pixels."""
    seq_name, st, act = sequence_name(lib, actor, state, direction, kind)
    seq = h4d.parse(lib.read(f"actor_sequence.{seq_name}.h4d"))
    dx, dy = act.get("draw_offset", (0, 0))
    pivot = (-seq.origin[0] - dx, -seq.origin[1] - dy)
    meta = dict(sequence=seq_name, fps=st["fps"], hit=st["hit_frame"], scale=scale, szoom=shadow_zoom)
    result = {}
    for prefix, cut, zoom in (("frame", 128, 1), ("shadow", 48, shadow_zoom)):
        keys, images = frame_images(seq, prefix)
        rects, pieces, index = [], [], {}
        for key, (img, box) in images.items():
            piece, ox, oy = scaled(img, box, pivot, scale / zoom, cut)
            ox, oy = ox * zoom, oy * zoom
            if piece:
                index[key] = len(pieces) + 1
                pieces.append(piece)
                rects.append([ox, oy])
        frames = [index.get(k, 0) for k in keys]
        if not pieces:
            result[prefix] = (None, [], frames)
            continue
        if prefix == "shadow":
            for p in pieces:
                p.putdata([(0, 0, 0, a) for *_, a in pixels(p)])
            atlas, pos = build_atlas(pieces, 1)
        else:
            atlas, pos = build_atlas(pieces, colors)
        rects = [[x, y, p.width, p.height, ox, oy] for (x, y), p, (ox, oy) in zip(pos, pieces, rects)]
        result[prefix] = (atlas, rects, frames)
    atlas, meta["rects"], meta["frames"] = result["frame"]
    shadow, meta["srects"], meta["sframes"] = result["shadow"]
    return atlas, shadow, meta


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, dict):
        return "{\n" + "".join(f"  {k} = {lua(x)},\n" for k, x in v.items()) + "}"
    if isinstance(v, (list, tuple)):
        if v and isinstance(v[0], (list, tuple)):
            return "{\n" + "".join(f"    {lua(x)},\n" for x in v) + "  }"
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, float):
        return repr(v)
    return str(v)


def write(out_dir, name, atlas, shadow, meta, image_prefix=""):
    os.makedirs(os.path.join(out_dir, "gfx", image_prefix), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "data"), exist_ok=True)
    meta = dict(meta, image=image_prefix + name, shadow=image_prefix + name + "_sh" if shadow else False)
    atlas.save(os.path.join(out_dir, "gfx", image_prefix, name + ".png"), optimize=True)
    if shadow:
        shadow.save(os.path.join(out_dir, "gfx", image_prefix, name + "_sh.png"), optimize=True)
    with open(os.path.join(out_dir, "data", name + ".lua"), "w", encoding="utf-8") as f:
        f.write(f"-- {meta['sequence']}: generated by HeroesDS/tools/h4atlas.py from the original game\n")
        f.write("return " + lua(meta) + "\n")
    return meta


def main(argv):
    p = argparse.ArgumentParser(description="Heroes IV animation -> LiteLua atlas")
    p.add_argument("data"), p.add_argument("actor"), p.add_argument("state"), p.add_argument("dir")
    p.add_argument("out")
    p.add_argument("--scale", type=float, default=0.5)
    p.add_argument("--colors", type=int, default=255)
    p.add_argument("--kind", default="combat", choices=("combat", "adv"))
    p.add_argument("--name")
    a = p.parse_args(argv[1:])
    lib = h4r.Library(a.data)
    atlas, shadow, meta = convert(lib, a.actor, a.state, a.dir, a.scale, a.colors, a.kind)
    name = a.name or f"{a.actor}_{a.state}_{a.dir}".replace(" ", "_")
    write(a.out, name, atlas, shadow, meta)
    print(f"{name}: {len(meta['frames'])} frames, atlas {atlas.width}x{atlas.height}"
          + (f", shadow {shadow.width}x{shadow.height}" if shadow else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
