"""Style experiment: the same Heroes IV frames in three looks for the DS, side
by side, with the video memory each look would need. PC only, writes a PNG.

  python HeroesDS/tools/style_preview.py out.png

Styles (all as the DS would draw them: no per-pixel alpha):
  1 current   scale 0.5, 255 colors, alpha cut at 50 %, shadow at half size
  2 smooth    scale 0.5, 255 colors, edge pixels pre-blended with the ground
              color, dithered shadow at full size
  3 oldschool scale 0.375, 15 colors, more contrast, 1 px dark outline,
              dithered shadow
"""
import os
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import h4actor  # noqa: E402
import h4atlas  # noqa: E402
import h4d  # noqa: E402
import h4r  # noqa: E402

GROUND = (112, 104, 66)          # A battlefield-like dirt color
SHADOW_ALPHA = 0.45
SAMPLES = [("bandit", "wait", "sw", 3), ("bandit", "melee", "sw", 7), ("bandit", "melee", "sw", 9),
           ("black dragon", "wait", "sw", 2), ("black dragon", "melee", "sw", 5)]
CELL_W, CELL_H = 150, 120        # DS pixels per sample
ZOOM = 2                         # Like the melonDS window


def load(lib, actor, state, d):
    seq_name, st, act = h4atlas.sequence_name(lib, actor, state, d, "combat")
    seq = h4d.parse(lib.read(f"actor_sequence.{seq_name}.h4d"))
    dx, dy = act["draw_offset"]
    return seq, (-seq.origin[0] - dx, -seq.origin[1] - dy)


def resize(img, scale):
    w, h = max(1, round(img.width * scale)), max(1, round(img.height * scale))
    return img.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")


def cut(img, threshold):
    img = img.copy()
    img.putalpha(img.getchannel("A").point(lambda a: 255 if a >= threshold else 0))
    return img


def quantize(img, colors):
    """Opaque pixels to at most `colors` colors (like the converter)."""
    p = h4atlas.to_palette(img, colors)
    rgba = p.convert("RGBA")
    rgba.putalpha(img.getchannel("A"))
    return rgba


def matte(img, ground, threshold=40):
    """Blends edge pixels with the ground color, then cuts alpha low: soft look
    without per-pixel alpha (right only on grounds close to `ground`)."""
    out = Image.new("RGBA", img.size)
    px = []
    for r, g, b, a in h4atlas.pixels(img):
        if a < threshold:
            px.append((0, 0, 0, 0))
        else:
            k = a / 255
            px.append((round(r * k + ground[0] * (1 - k)), round(g * k + ground[1] * (1 - k)),
                       round(b * k + ground[2] * (1 - k)), 255))
    out.putdata(px)
    return out


def outline(img, color=(24, 16, 12, 255)):
    """1 px outline around opaque pixels (4 neighbours) in the transparent area."""
    w, h = img.size
    big = Image.new("RGBA", (w + 2, h + 2))
    big.paste(img, (1, 1))
    a = big.getchannel("A")
    grown = a.filter(ImageFilter.MaxFilter(3))
    ring = Image.new("RGBA", big.size, color)
    ring.putalpha(Image.eval(grown, lambda v: v).point(lambda v: 255 if v else 0))
    ring.alpha_composite(big)
    return ring, 1


def dither_shadow(img, alpha_floor=48):
    """Shadow as a checkerboard of dark pixels where the shadow is."""
    out = Image.new("RGBA", img.size)
    w = img.width
    px = []
    for i, (*_, a) in enumerate(h4atlas.pixels(img)):
        x, y = i % w, i // w
        px.append((0, 0, 0, 255) if a >= alpha_floor and (x + y) % 2 == 0 else (0, 0, 0, 0))
    out.putdata(px)
    return out


def frame_parts(seq, n):
    """(frame RGBA, box), (shadow RGBA, box) for frame n at full size."""
    parts = []
    for prefix in ("frame", "shadow"):
        layers = [i for i in seq.layers(prefix, n) if i.kind]
        parts.append(h4atlas.compose(seq, layers) if layers else (None, None))
    return parts


def render(style, seq, pivot, n):
    """Returns a list of (RGBA, x, y, opacity) relative to the ground point."""
    (frame, fbox), (shadow, sbox) = frame_parts(seq, n)
    scale = 0.375 if style == 3 else 0.5
    out = []
    if shadow:
        if style == 1:
            small = cut(resize(shadow, scale / 2), 48)
            small = small.resize((small.width * 2, small.height * 2), Image.NEAREST)
            sh, op = small, SHADOW_ALPHA
        else:
            sh, op = dither_shadow(resize(shadow, scale)), 0.6
        out.append((sh, round((sbox[0] - pivot[0]) * scale), round((sbox[1] - pivot[1]) * scale), op))
    img = resize(frame, scale)
    x, y = round((fbox[0] - pivot[0]) * scale), round((fbox[1] - pivot[1]) * scale)
    if style == 1:
        img = quantize(cut(img, 128), 255)
    elif style == 2:
        img = quantize(matte(img, GROUND), 255)
    else:
        rgb = img.convert("RGB")
        rgb = ImageEnhance.Contrast(rgb).enhance(1.35)
        rgb = ImageEnhance.Color(rgb).enhance(1.3)
        rgb = rgb.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=2))
        rgb.putalpha(img.getchannel("A"))
        img = quantize(cut(rgb, 110), 15)
        img, d = outline(img)
        x, y = x - d, y - d
    out.append((img, x, y, 1.0))
    return out


def vram(style, seq, pivot):
    """Bytes of video memory of the whole animation in this style."""
    scale = 0.375 if style == 3 else 0.5
    bpp = 4 if style == 3 else 8
    frames, shadows = [], []
    for key in {tuple(i.name for i in seq.layers("frame", n)) for n in range(1, seq.frame_count() + 1)}:
        layers = [seq.image(k) for k in key if seq.image(k).kind]
        if layers:
            f, _ = h4atlas.compose(seq, layers)
            bb = f.getbbox()
            frames.append((max(1, round((bb[2] - bb[0]) * scale)) + 2, max(1, round((bb[3] - bb[1]) * scale)) + 2))
    for key in {tuple(i.name for i in seq.layers("shadow", n)) for n in range(1, seq.frame_count() + 1)}:
        layers = [seq.image(k) for k in key if seq.image(k).kind]
        if layers:
            s, _ = h4atlas.compose(seq, layers)
            bb = s.getbbox()
            k = scale / 2 if style == 1 else scale
            shadows.append((max(1, round((bb[2] - bb[0]) * k)), max(1, round((bb[3] - bb[1]) * k))))
    W, H, _ = h4atlas.pack(frames)
    total = W * H * bpp // 8 + (512 if bpp == 8 else 32)
    if shadows:
        W, H, _ = h4atlas.pack(shadows)
        total += W * H // 2 + 32
    return total


def main(argv):
    out_path = argv[1] if len(argv) > 1 else "style_preview.png"
    lib = h4r.Library(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Data"))
    seqs = {}
    for actor, state, d, _ in SAMPLES:
        seqs.setdefault((actor, state, d), load(lib, actor, state, d))
    names = {1: "1 current: 0.5, 256 colors", 2: "2 smooth: 0.5, blended edges, dither shadow",
             3: "3 oldschool: 0.375, 16 colors, outline, dither shadow"}
    label_h = 12
    sheet = Image.new("RGB", (CELL_W * len(SAMPLES), (CELL_H + label_h) * 3), (0, 0, 0))
    draw = ImageDraw.Draw(sheet)
    for row, style in enumerate((1, 2, 3)):
        top = row * (CELL_H + label_h)
        mem = {}
        for (actor, state, d), (seq, pivot) in seqs.items():
            if state == "melee":
                mem[actor] = vram(style, seq, pivot)
        info = "  melee VRAM: " + ", ".join(f"{a} {v // 1024} KB" for a, v in mem.items())
        draw.text((2, top), names[style] + info, fill=(255, 255, 255))
        for col, (actor, state, d, n) in enumerate(SAMPLES):
            seq, pivot = seqs[(actor, state, d)]
            cell = Image.new("RGBA", (CELL_W, CELL_H), GROUND + (255,))
            gx, gy = CELL_W // 2, CELL_H - 18
            for img, x, y, op in render(style, seq, pivot, n):
                if op < 1:
                    a = img.getchannel("A").point(lambda v: round(v * op))
                    img = img.copy()
                    img.putalpha(a)
                cell.alpha_composite(img, (gx + x, gy + y))
            sheet.paste(cell.convert("RGB"), (col * CELL_W, top + label_h))
    sheet = sheet.resize((sheet.width * ZOOM, sheet.height * ZOOM), Image.NEAREST)
    sheet.save(out_path)
    print(out_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
