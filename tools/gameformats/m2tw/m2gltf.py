"""One soldier of a Medieval II unit mesh -> glTF (bind pose, static), for a look in Blender.

python m2gltf.py MESH.mesh UNIT.texture OUT.gltf [variant] [kind=ATTACH.texture ...]
variant n picks the n-th part of each kind (wrapping), so different n = a different soldier.
UV space is two textures side by side: u < 0.5 the unit's (body, arms, legs, face),
u >= 0.5 an attachment set's; each kind of attachment (head0, shield0, primaryactive0...)
has its own set, given as kind=file (a kind prefix matches: primary=...).
"""
import io, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ig"))   # v3d.write_gltf
import m2mesh, v3d


def texture_png(path, out):
    d = open(path, "rb").read()
    Image.open(io.BytesIO(d[d.find(b"DDS "):])).save(out)  # 48-byte header, then a DDS
    return out


def pick(groups, variant):
    """One group of each kind; the variant-th of that kind (wrapping)."""
    kinds = {}
    for g in groups:
        kinds.setdefault(g[0], []).append(g)
    return [lst[variant % len(lst)] for lst in kinds.values()]


def soldier(groups, v, variant):
    parts = pick(groups, variant)
    used = np.unique(np.concatenate([g[2].ravel() for g in parts]))
    remap = np.full(len(v["pos"]), -1, np.int64)
    remap[used] = np.arange(len(used))
    tris = np.concatenate([remap[g[2]] for g in parts])
    return parts, used, tris


if __name__ == "__main__":
    mesh, tex, out = sys.argv[1:4]
    variant = int(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4].isdigit() else 0
    attach = dict(a.split("=", 1) for a in sys.argv[4:] if "=" in a)
    groups, v, bones = m2mesh.read(mesh)
    parts, used, tris = soldier(groups, v, variant)
    print("parts:", ", ".join(p[1] for p in parts))
    print(f"verts {len(used)}, tris {len(tris)}")
    base = os.path.splitext(out)[0]
    files = [tex]
    uv = v["uv"][used].copy()
    if attach:  # a soldier: two textures side by side (mounts use the whole texture)
        right = uv[:, 0] >= 0.5
        uv[right, 0] -= 0.5
        uv[:, 0] *= 2
    remap = np.full(len(v["pos"]), -1, np.int64)
    remap[used] = np.arange(len(used))
    prims = {}
    for kind, part, idx in parts:
        mat = 0
        if attach and v["uv"][idx[0, 0], 0] >= 0.5:  # an attachment: its kind's texture
            f = next((f for k, f in attach.items() if kind.startswith(k)), None)
            if f is None:
                print("no texture for", kind, "- left out")
                continue
            if f not in files:
                files.append(f)
            mat = files.index(f)
        prims.setdefault(mat, []).append(remap[idx])
    pngs = [texture_png(f, f"{base}_tex{i}.png") for i, f in enumerate(files)]
    ob = dict(pos=v["pos"][used].astype("<f4"), uv=uv.astype("<f4"),
              prims=[(np.concatenate(t).astype(np.uint16), m) for m, t in prims.items()])
    v3d.write_gltf(out, [ob], pngs, [], scale=1.0)
    print("wrote", out)
