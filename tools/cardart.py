"""Card game art: generate with a local ComfyUI, convert to DS-ready PNGs.

  python tools/cardart.py gen CART [names...]   images from the "art" prompts
  python tools/cardart.py convert CART          raw images -> CART/gfx/*.png

CART is a cart folder with src/cards.lua, src/enemies.lua and optionally
src/items.lua (icons, saved as gfx/i_<item>.png; all pure data,
read with the parser of tools/lsong.py). Raw images go to
assets/<cart>/raw/ (not in git), DS images to CART/gfx/, and a preview
sheet (x3, on a mock card) to assets/<cart>/preview.png.

Generation: SDXL 1.0 + the Pixel Art XL LoRA (nerijs, CreativeML
OpenRAIL-M) through the ComfyUI HTTP API on 127.0.0.1:8188.
"""
import json, os, random, sys, time, urllib.parse, urllib.request
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lsong  # noqa: E402

HOST = "http://127.0.0.1:8188"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECKPOINT = "sd_xl_v10_vaefix.safetensors"
LORA = "pixel-art-xl.safetensors"

STYLE = {
    "card": "pixel art, {}, fantasy game item icon, single object centered, bold dark "
            "outline, flat colors, plain flat white background",
    "enemy": "pixel art, {}, fantasy game monster sprite, single character centered, "
             "bold dark outline, flat colors, plain flat white background",
    "item": "pixel art, {}, fantasy rpg inventory item icon, single object centered, "
            "bold dark outline, flat colors, plain flat white background",
}
NEG = ("text, letters, watermark, frame, border, signature, blurry, shadow, "
       "multiple objects, scenery, landscape, gradient background")
SIZES = {"card": (40, 34), "item": (32, 32)}  # enemies: their "size" field
COLORS = 15                  # + index 0 transparent = a 16-color palette
BG_TOL = 60                  # background distance (sum of |dR|+|dG|+|dB|)


def load_cart(cart):
    def data(name):
        with open(os.path.join(cart, "src", name), encoding="utf-8") as f:
            return lsong.parse_lua(f.read())
    jobs = {}
    for k, v in data("cards.lua").items():
        if isinstance(v, dict) and "art" in v:
            jobs[k] = ("card", v["art"], SIZES["card"])
    items = os.path.join(cart, "src", "items.lua")
    if os.path.exists(items):
        for k, v in data("items.lua").items():
            if isinstance(v, dict) and "art" in v:
                jobs["i_" + k] = ("item", v["art"], SIZES["item"])
    for k, v in data("enemies.lua").items():
        if isinstance(v, dict) and "art" in v:
            s = v.get("size", 64)
            jobs[k] = ("enemy", v["art"], (s, s))
    return jobs


def workflow(kind, prompt, seed):
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CHECKPOINT}},
        "2": {"class_type": "LoraLoader", "inputs": {"model": ["1", 0], "clip": ["1", 1],
              "lora_name": LORA, "strength_model": 1.0, "strength_clip": 1.0}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1],
              "text": STYLE[kind].format(prompt)}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 1], "text": NEG}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
        "6": {"class_type": "KSampler", "inputs": {"model": ["2", 0], "positive": ["3", 0],
              "negative": ["4", 0], "latent_image": ["5", 0], "seed": seed, "steps": 25,
              "cfg": 6.0, "sampler_name": "dpmpp_2m", "scheduler": "karras", "denoise": 1.0}},
        "7": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveImage", "inputs": {"images": ["7", 0], "filename_prefix": "cardart"}},
    }


def generate(kind, prompt, seed, dst):
    req = urllib.request.Request(HOST + "/prompt", json.dumps(
        {"prompt": workflow(kind, prompt, seed)}).encode(), {"Content-Type": "application/json"})
    pid = json.load(urllib.request.urlopen(req))["prompt_id"]
    while True:
        hist = json.load(urllib.request.urlopen(f"{HOST}/history/{pid}"))
        if pid in hist:
            h = hist[pid]
            if h.get("status", {}).get("status_str") == "error":
                raise RuntimeError(json.dumps(h["status"])[:2000])
            for node in h["outputs"].values():
                for img in node.get("images", []):
                    data = urllib.request.urlopen(f"{HOST}/view?{urllib.parse.urlencode(img)}").read()
                    with open(dst, "wb") as f:
                        f.write(data)
                    return
        time.sleep(2)


def dist(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def remove_bg(img):
    """Flood fill from the border; a pixel joins the background when it is
    close to the border color it was reached from."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    seen = bytearray(w * h)
    stack = [(x, y, px[x, y]) for x in range(w) for y in (0, h - 1)]
    stack += [(x, y, px[x, y]) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y, ref = stack.pop()
        i = y * w + x
        if seen[i] or dist(px[x, y], ref) > BG_TOL:
            continue
        seen[i] = 1
        px[x, y] = (0, 0, 0, 0)
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                stack.append((nx, ny, ref))
    return img


def to_ds(path, tw, th):
    src = Image.open(path).convert("RGB")
    # Pixel Art XL draws on a ~8 px grid: shrink (keeping 2 px per art
    # pixel, so large subjects still fill the target), then remove the
    # background on clean pixels
    rgba = remove_bg(src.resize((src.width // 4, src.height // 4), Image.NEAREST))
    rgba = rgba.crop(rgba.getchannel("A").getbbox() or (0, 0, rgba.width, rgba.height))
    s = min(tw / rgba.width, th / rgba.height)
    if s >= 1:  # small subject: grow by a whole number, pixels stay sharp
        s = int(s)
        nw, nh = rgba.width * s, rgba.height * s
        small = rgba.resize((nw, nh), Image.NEAREST)
    else:
        nw, nh = max(1, round(rgba.width * s)), max(1, round(rgba.height * s))
        small = rgba.resize((nw, nh), Image.BOX)
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    canvas.alpha_composite(small, ((tw - nw) // 2, th - nh))  # stand on the bottom
    alpha = canvas.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
    rgb = Image.new("RGB", canvas.size)
    rgb.paste(canvas, mask=alpha)
    q = rgb.quantize(COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out = Image.new("P", canvas.size, 0)
    qd, ad, od = q.load(), alpha.load(), out.load()
    for y in range(th):
        for x in range(tw):
            if ad[x, y]:
                od[x, y] = qd[x, y] + 1
    pal = q.getpalette()[: COLORS * 3]
    out.putpalette([255, 0, 255] + pal + [0] * (3 * (16 - COLORS - 1)))
    out.info["transparency"] = 0
    return out


def mock_card(art):
    card = Image.new("RGBA", (48, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 0, 47, 63), 3, fill=(70, 52, 40), outline=(220, 190, 120))
    d.rectangle((3, 10, 44, 46), fill=(20, 20, 28))
    card.alpha_composite(art.convert("RGBA"), (4, 11))
    d.ellipse((-2, -2, 9, 9), fill=(40, 90, 200), outline=(230, 230, 255))
    d.rectangle((4, 49, 43, 60), fill=(200, 185, 150))
    return card


def preview(items, dst, scale=3, per_row=8):
    cw, ch = 48 * scale + 8, 64 * scale + 8
    rows = (len(items) + per_row - 1) // per_row
    sheet = Image.new("RGB", (per_row * cw + 8, rows * ch + 8), (24, 24, 32))
    for i, (kind, img) in enumerate(items):
        x0, y0 = 8 + (i % per_row) * cw, 8 + (i // per_row) * ch
        tile = mock_card(img) if kind == "card" else img.convert("RGBA")
        f = scale if kind == "card" else max(1, 48 * scale // img.width)
        big = tile.resize((tile.width * f, tile.height * f), Image.NEAREST)
        sheet.paste(big, (x0, y0), big)
    sheet.save(dst)


def main(argv):
    if len(argv) < 2 or argv[0] not in ("gen", "convert"):
        print(__doc__)
        return 2
    cmd, cart = argv[0], argv[1]
    name = os.path.basename(os.path.normpath(cart))
    raw = os.path.join(ROOT, "assets", name, "raw")
    os.makedirs(raw, exist_ok=True)
    jobs = load_cart(cart)
    if cmd == "gen":
        for key in argv[2:] or jobs:
            kind, prompt, _ = jobs[key]
            t0 = time.time()
            generate(kind, prompt, random.Random(key).randrange(2 ** 31), os.path.join(raw, key + ".png"))
            print(f"{key:10} {time.time() - t0:4.0f}s", flush=True)
        return 0
    gfx = os.path.join(cart, "gfx")
    os.makedirs(gfx, exist_ok=True)
    items = []
    for key, (kind, _, (tw, th)) in jobs.items():
        src = os.path.join(raw, key + ".png")
        if not os.path.exists(src):
            print("missing", src)
            continue
        img = to_ds(src, tw, th)
        img.save(os.path.join(gfx, key + ".png"), optimize=True)
        items.append((kind, img))
    preview(items, os.path.join(ROOT, "assets", name, "preview.png"))
    print(f"{len(items)} images -> {gfx}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
