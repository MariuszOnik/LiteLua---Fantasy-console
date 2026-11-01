"""Bake a Medieval II rider + horse into vertex frames (morph), glTF for a look in Blender.

python m2bake.py OUT.gltf [variant]
Both meshes have their origin in the saddle (rider: pelvis, horse: bone_H_Saddle); the
horse's root offset of the first frame (saddle height) is taken away, so only the bobbing
stays, then everything is lifted by it so the hooves stand on y = 0.
"""
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "ig"))   # v3d.write_gltf
import m2anim, m2gltf, m2mesh, v3d

D = "E:/AI/M2TW/teutonic/mods/teutonic/data/unit_models/"
RIDER = D + "_units/cm_standard/ritterbruder_lod3.mesh"
RIDER_TEX = D + "_units/cm_standard/textures/cm_standard_teutonic_order.texture"
ATTACH_TEX = D + "attachmentsets/final teutonic heads_teutonic_order_diff.texture"
HORSE = D + "mounts/barded_horse/mount_barded_horse_lod2.mesh"
HORSE_TEX = D + "mounts/barded_horse/textures/horse_barding_teutonic_order.texture"
HUMAN = [-1, 0, 1, 2, 0, 4, 5, 6, 6, 5, 9, 10, 11, 5, 13, 14, 15, 0, 17, 18]
HORSE_PARENTS = [-1, 0, 1, 2, 3, 2, 5, 6, 7, 2, 9, 10, 11, 0, 13, 0, 15, 16, 17, 0, 19, 20, 21]
RIDER_OFFSET = np.array([0.0, 0.38, 0.70])   # descr_mount.txt, barded horse: rider_offset
# rider mesh bones 20.. (weapon01, weapon, weapon02, weapon03, shield01, shield): hands
# jaw and eyebrow (helmets hang on it) carry a fixed turn in the animations: ride the head
RIDER_FALLBACK = np.array([0, 1, 2, 3, 4, 5, 6, 6, 6] + list(range(9, 20)) + [12, 12, 12, 12, 16, 16])
ANIMS = [("run", "data/animations/HR_lance/HR_lance_horse_req/HR_lance_fs_horse_run.cas",
          "data/animations/fs_horse/fs_horse_run.cas"),
         ("charge", "data/animations/HR_lance/HR_lance_horse_req/HR_lance_fs_horse_charge.cas",
          "data/animations/fs_horse/fs_horse_charge.cas")]


def part_mesh(groups, v, variant, attach):
    """One soldier's (or horse's) parts: sub-vertex set, remapped triangles per texture."""
    # spare weapons hang on bones the animations do not move here: keep the lance and shield
    groups = [g for g in groups if g[0] not in ("primaryactive1", "secondaryactive0", "secondaryactive1")]
    parts, used, _ = m2gltf.soldier(groups, v, variant)
    remap = np.full(len(v["pos"]), -1, np.int64)
    remap[used] = np.arange(len(used))
    uv = v["uv"][used].copy()
    prims = {}
    for kind, part, idx in parts:
        mat = 1 if attach and v["uv"][idx[0, 0], 0] >= 0.5 else 0
        prims.setdefault(mat, []).append(remap[idx])
    if attach:
        right = uv[:, 0] >= 0.5
        uv[right, 0] -= 0.5
        uv[:, 0] *= 2
    sub = {k: (a[used] if k != "uv" else uv) for k, a in v.items()}
    return sub, [(np.concatenate(t), m) for m, t in sorted(prims.items())]


def frames_of(sub, cas, parents, fallback, idx, root_bind):
    q, t = m2anim.read(cas, idx)
    t = t.copy()
    t[:, 0] -= root_bind
    return m2anim.bake(sub, q, t, parents, fallback)


if __name__ == "__main__":
    out = sys.argv[1]
    variant = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    idx = m2anim.index()
    rg, rv, _ = m2mesh.read(RIDER)
    hg, hv, _ = m2mesh.read(HORSE)
    rider, rprims = part_mesh(rg, rv, variant, True)
    horse, hprims = part_mesh(hg, hv, variant, False)
    _, ht0 = m2anim.read(ANIMS[0][2], idx)
    saddle = ht0[0, 0].copy()   # the horse's root offset: saddle height
    lift = np.array([0, saddle[1], 0])
    anims = []
    for name, rcas, hcas in ANIMS:
        rf = frames_of(rider, rcas, HUMAN, RIDER_FALLBACK, idx, np.zeros(3))
        hf = frames_of(horse, hcas, HORSE_PARENTS, np.arange(len(HORSE_PARENTS)), idx, saddle)
        bob = m2anim.read(hcas, idx)[1][:, 0] - saddle   # the saddle's bobbing: the rider rides it
        print(name, "frames", len(rf), len(hf))
        anims.append((name, [[(None, f + lift) for f in hf],
                             [(None, f + lift + RIDER_OFFSET + bob[i]) for i, f in enumerate(rf)]]))
    base = os.path.splitext(out)[0]
    pngs = [m2gltf.texture_png(HORSE_TEX, base + "_tex0.png"),
            m2gltf.texture_png(RIDER_TEX, base + "_tex1.png"),
            m2gltf.texture_png(ATTACH_TEX, base + "_tex2.png")]
    objs = [dict(pos=(horse["pos"] + lift).astype("<f4"), uv=horse["uv"].astype("<f4"),
                 prims=[(t.astype(np.uint16), 0) for t, m in hprims]),
            dict(pos=(rider["pos"] + lift + RIDER_OFFSET).astype("<f4"), uv=rider["uv"].astype("<f4"),
                 prims=[(t.astype(np.uint16), 1 + m) for t, m in rprims])]
    print("tris horse", sum(len(t) for t, _ in hprims), "rider", sum(len(t) for t, _ in rprims))
    v3d.write_gltf(out, objs, pngs, anims, scale=1.0, fps=20)
    print("wrote", out)
