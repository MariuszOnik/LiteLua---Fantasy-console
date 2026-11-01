"""Knight for the 3DS army test: a Medieval II rider + horse -> romfs/knight.bin (one mesh,
one texture), in the format of make_army.py.

The game's assets stay local (private use, --m2 is where they were unpacked); the readers are
tools/gameformats/m2tw (m2mesh.py, m2anim.py, m2bake.py -- formats in their docstrings). Horse and
rider become one mesh (both have their origin in the saddle); their three textures are
shrunk into one atlas, a quarter each; the animation is baked into vertex frames.

  python make_knight.py [--unit teutonic|polish] [--m2 E:/AI/M2TW] [--anim run|charge]
                        [--variant 0] [--quarter 256] [--tris 700]
--tris makes a lighter copy (optimize.py: hidden triangles out, then collapses), *_lo.bin.
--anim idle,run puts several animations in one file, format "LLM2" (else "LLMS"):
  "LLM2", u16 verts, tris, frames (all), texsize, animations, 0,
  animations * (char name[8], u16 first frame, u16 frames, f32 seconds, f32 metres/s),
  then uv, triangles, frames, texture as in make_army.py.
"""
import argparse, os, struct, sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from make_army import tile_order  # noqa: E402

# per unit (battle_models.modeldb): rider mesh, its texture, attachment set, horse texture, output
U = "mods/teutonic/data/unit_models/"
UNITS = {
    "teutonic": (U + "_units/cm_standard/ritterbruder_lod3.mesh",
                 U + "_units/cm_standard/textures/cm_standard_teutonic_order.texture",
                 U + "attachmentsets/final teutonic heads_teutonic_order_diff.texture",
                 U + "mounts/barded_horse/textures/horse_barding_teutonic_order.texture", "knight.bin"),
    "polish": (U + "_units/en_pplate_plate/polish_knights_lod2.mesh",
               U + "_units/en_pplate_plate/textures/mtw2_en_pplate_poland.texture",
               U + "attachmentsets/final special heads_poland_diff.texture",
               U + "mounts/barded_horse/textures/horse_barding_poland.texture", "polish.bin"),
}
HORSE = U + "mounts/barded_horse/mount_barded_horse_lod2.mesh"
# animations: rider (lance) and horse, played together; 20 frames a second
A = "data/animations/"
ANIMS = {
    "idle": (A + "HR_lance/HR_lance_horse_req/HR_lance_fs_horse_stand_a_idle.cas", A + "fs_horse/fs_horse_stand_a_idle.cas"),
    "fidget": (A + "HR_lance/HR_lance_horse_req/HR_lance_fs_horse_stand_a_hf_idle_2.cas", A + "fs_horse/fs_horse_stand_a_hf_idle_2.cas"),
    "run": (A + "HR_lance/HR_lance_horse_req/HR_lance_fs_horse_run.cas", A + "fs_horse/fs_horse_run.cas"),
    "charge": (A + "HR_lance/HR_lance_horse_req/HR_lance_fs_horse_charge.cas", A + "fs_horse/fs_horse_charge.cas"),
}
SPEED = {"idle": 0.0, "fidget": 0.0, "charge": 9.0}   # metres per second (run: --speed)
FPS = 20.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--unit", default="teutonic", choices=sorted(UNITS))
    ap.add_argument("--m2", default="E:/AI/M2TW")
    ap.add_argument("--anim", default="run")              # several: idle,run -> LLM2 (see below)
    ap.add_argument("--out", default="")                  # output folder, default romfs/ here
    ap.add_argument("--variant", type=int, default=0)
    ap.add_argument("--quarter", type=int, default=256)   # texels per side of each texture
    ap.add_argument("--speed", type=float, default=7.0)   # metres per second, a gallop
    ap.add_argument("--tris", type=int, default=0)        # >0: lighter (optimize.py), file *_lo.bin
    a = ap.parse_args()
    sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "tools", "gameformats", "m2tw"))
    import m2anim, m2bake, m2gltf, m2mesh

    teu = os.path.join(a.m2, "teutonic")
    rider_mesh, rider_tex, attach_tex, horse_tex = (os.path.join(teu, p) for p in UNITS[a.unit][:4])
    out_name = UNITS[a.unit][4]
    idx = m2anim.index()
    rider, rprims = m2bake.part_mesh(*m2mesh.read(rider_mesh)[:2], a.variant, True)
    horse, hprims = m2bake.part_mesh(*m2mesh.read(os.path.join(teu, HORSE))[:2], a.variant, False)
    saddle = m2anim.read(m2bake.ANIMS[0][2], idx)[1][0, 0].copy()
    lift = np.array([0, saddle[1], 0])
    frames, table = [], []      # table: (name, first frame, frames, metres per second)
    for name in a.anim.split(","):
        rcas, hcas = ANIMS[name]
        rf = m2bake.frames_of(rider, rcas, m2bake.HUMAN, m2bake.RIDER_FALLBACK, idx, np.zeros(3))
        hf = m2bake.frames_of(horse, hcas, m2bake.HORSE_PARENTS, np.arange(len(m2bake.HORSE_PARENTS)), idx, saddle)
        bob = m2anim.read(hcas, idx)[1][:, 0] - saddle
        table.append((name, len(frames), len(rf), SPEED[name] if name in SPEED else a.speed))
        frames += [np.concatenate([h + lift, r + lift + m2bake.RIDER_OFFSET + bob[i]])
                   for i, (h, r) in enumerate(zip(hf, rf))]

    # atlas: horse top left, rider (unit) top right, attachments bottom left
    q = a.quarter
    slots = {("h", 0): (0, 0), ("r", 0): (q, 0), ("r", 1): (0, q)}
    atlas = Image.new("RGB", (2 * q, 2 * q), (40, 40, 40))
    for key, path in ((("h", 0), horse_tex), (("r", 0), rider_tex), (("r", 1), attach_tex)):
        tmp = os.path.join(HERE, "romfs", "_tex.png")
        m2gltf.texture_png(path, tmp)
        atlas.paste(Image.open(tmp).convert("RGB").resize((q, q), Image.LANCZOS), slots[key])
        os.remove(tmp)

    uvs, tris, base = [], [], 0
    for who, sub, prims in (("h", horse, hprims), ("r", rider, rprims)):
        uv = np.clip(sub["uv"].astype(np.float64), 0, 1)
        out = uv.copy()
        for t, m in prims:  # each texture's triangles: move their corners into its quarter
            corners = np.unique(t)
            sx, sy = slots[(who, m)]
            out[corners, 0] = (sx + uv[corners, 0] * q) / (2 * q)
            out[corners, 1] = (sy + uv[corners, 1] * q) / (2 * q)
            tris.append(t + base)
        uvs.append(out)
        base += len(sub["pos"])
    uv = np.concatenate(uvs).astype("<f4")
    tri = np.concatenate(tris)
    if a.tris:   # hidden triangles out, then collapses down to --tris (optimize.py)
        import optimize
        fr = np.array(frames)
        tri = tri[optimize.hidden(fr, tri)]
        fr, uv, tri = optimize.compact(fr, uv, tri)
        tri = optimize.decimate(fr, uv, tri, a.tris)
        fr, uv, tri = optimize.compact(fr, uv, tri)
        frames = list(fr)
        uv = uv.astype("<f4")
        out_name = out_name.replace(".bin", "_lo.bin")
    tri = tri.astype("<u2")
    nv, nt = len(uv), len(tri)

    if len(table) == 1:   # one animation: the army test's format
        out = bytearray(b"LLMS")
        out += struct.pack("<4H2f", nv, nt, len(frames), 2 * q, len(frames) / FPS, table[0][3])
    else:
        out = bytearray(b"LLM2")
        out += struct.pack("<6H", nv, nt, len(frames), 2 * q, len(table), 0)
        for name, first, count, speed in table:
            out += struct.pack("<8s2H2f", name.encode(), first, count, count / FPS, speed)
    out += uv.tobytes()
    out += tri.tobytes()
    if nt % 2:
        out += b"\0\0"
    for p in frames:
        out += p.astype("<f4").tobytes()
    out += tile_order(np.asarray(atlas)).astype("<u2").tobytes()
    dst = os.path.join(a.out or os.path.join(HERE, "romfs"), out_name)
    open(dst, "wb").write(out)
    atlas.save(os.path.join(a.m2, "out", f"{a.unit}_atlas.png"))
    print(f"{dst}: {nv} verts, {nt} tris, {len(frames)} frames ({a.anim}), texture {2 * q}, {len(out)} bytes")


if __name__ == "__main__":
    main()
