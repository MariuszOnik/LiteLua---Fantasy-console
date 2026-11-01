"""Paper pictures for the map's "image" surface (styles/*.lua, make_m3.py), made by a
local ComfyUI (SDXL 1.0 base, 127.0.0.1:8188).

  python HeroesDS/tools/paperart.py OUT_DIR [--kind parchment|leather] [--seeds 1 2 3]

Writes OUT_DIR/<kind>_<seed>.png (1024 x 1024); pick one, put it next to the style file
and name it in map.image. make_m3.py makes it repeat without a seam.
"""
import argparse
import json
import os
import time
import urllib.parse
import urllib.request

HOST = "http://127.0.0.1:8188"
CHECKPOINT = "sd_xl_v10_vaefix.safetensors"
PROMPTS = {
    "parchment": "flat scan of an empty sheet of old parchment paper, aged vellum texture, "
                 "subtle stains, fibres, soft mottled warm beige, even lighting, top-down, "
                 "full frame, high detail",
    "leather": "flat scan of a piece of old brown leather, worn tanned hide texture, fine "
               "pores and soft creases, even lighting, top-down, full frame, high detail",
}
NEG = ("text, letters, writing, map, drawing, watermark, frame, border, edges, torn edge, "
       "shadow, objects, hands, table, vignette, folds, perspective")


def workflow(kind, seed):
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CHECKPOINT}},
        "3": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["1", 1], "text": PROMPTS[kind]}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["1", 1], "text": NEG}},
        "5": {"class_type": "EmptyLatentImage", "inputs": {"width": 1024, "height": 1024, "batch_size": 1}},
        "6": {"class_type": "KSampler", "inputs": {"model": ["1", 0], "positive": ["3", 0],
              "negative": ["4", 0], "latent_image": ["5", 0], "seed": seed, "steps": 28,
              "cfg": 6.5, "sampler_name": "dpmpp_2m", "scheduler": "karras", "denoise": 1.0}},
        "7": {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["1", 2]}},
        "8": {"class_type": "SaveImage", "inputs": {"images": ["7", 0], "filename_prefix": "paperart"}},
    }


def generate(kind, seed, dst):
    req = urllib.request.Request(HOST + "/prompt", json.dumps(
        {"prompt": workflow(kind, seed)}).encode(), {"Content-Type": "application/json"})
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


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("out")
    p.add_argument("--kind", default="parchment", choices=sorted(PROMPTS))
    p.add_argument("--seeds", type=int, nargs="+", default=[1, 2, 3])
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for seed in a.seeds:
        dst = os.path.join(a.out, "%s_%d.png" % (a.kind, seed))
        generate(a.kind, seed, dst)
        print(dst, flush=True)


if __name__ == "__main__":
    main()
