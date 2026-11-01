"""Medieval II .mesh reader (reverse-engineered, test use only).

A boost::serialization binary archive. Unit meshes (e.g. ritterbruder_lod3.mesh):
  groups, each: u32 len + kind ("Legs", "Body", "head0", "shield0", "primaryactive0"...),
                u32 len + part name, [2 bytes of boost info before the first one],
                u32 triangles, triangles * 3 u16 -- indices into the shared vertex pool
  vertex pool, arrays of u32 count + data, in this order:
    uv 2f, bone weights 2f, position 3f (metres, Y up), bone indices (0, b2, b1, 0) u8,
    normal 3 u8 + pad
  bone names at the end ("bone_pelvis", ...).
A unit picks one part of each kind per soldier (variants), so one soldier is a few groups.
python m2mesh.py FILE.mesh   prints the groups and the arrays
"""
import re, struct, sys
import numpy as np

NAME = re.compile(rb"[\x20-\x7e]+")


def _string(d, p):
    n = struct.unpack_from("<I", d, p)[0]
    if 0 < n < 80 and NAME.fullmatch(d[p + 4:p + 4 + n]):
        return d[p + 4:p + 4 + n].decode("latin1"), p + 4 + n
    return None, p


def read(path):
    d = open(path, "rb").read()
    groups = []
    o = 0x20
    while o < len(d) - 16:
        kind, p = _string(d, o)
        if kind is None or not kind[0].isalpha():
            o += 1
            continue
        part, p2 = _string(d, p)
        if part is None:
            o += 1
            continue
        for skip in (0, 2):
            tris = struct.unpack_from("<I", d, p2 + skip)[0]
            if 0 < tris < 20000 and p2 + skip + 4 + tris * 6 <= len(d):
                break
        else:
            o += 1
            continue
        idx = np.frombuffer(d, "<u2", tris * 3, p2 + skip + 4).reshape(-1, 3).astype(np.int32)
        if groups and idx.min() < groups[-1][2].max() - 4000:  # not a group: stop at the pool
            break
        groups.append((kind, part, idx))
        o = last = p2 + skip + 4 + tris * 6
        if d.find(b"\0", o, o + 64) < 0:
            break
    n = int(max(g[2].max() for g in groups)) + 1
    marks = [m.start() for m in re.finditer(re.escape(struct.pack("<I", n)), d) if m.start() > last]
    bones_at = d.find(b"bone_")
    arrays = []
    for i, m in enumerate(marks):
        end = marks[i + 1] if i + 1 < len(marks) else bones_at
        stride = (end - m - 4) // n
        if stride in (4, 8, 12):
            arrays.append((m + 4, stride))
    assert [s for _, s in arrays][:5] == [8, 8, 12, 4, 4], arrays
    (uo, _), (wo, _), (po, _), (bo, _), (no, _) = arrays[:5]
    v = dict(
        uv=np.frombuffer(d, "<f4", n * 2, uo).reshape(n, 2),
        weight=np.frombuffer(d, "<f4", n * 2, wo).reshape(n, 2),
        pos=np.frombuffer(d, "<f4", n * 3, po).reshape(n, 3),
        bone=np.frombuffer(d, "u1", n * 4, bo).reshape(n, 4)[:, [2, 1]],  # (b2, b1) go with (w1, w2)
        normal=np.frombuffer(d, "u1", n * 4, no).reshape(n, 4)[:, :3].astype(np.float32) / 127.5 - 1,
    )
    w = v["weight"].copy()   # weights (0, 0): the whole vertex on its first bone
    w[w.sum(1) < 0.01] = (1, 0)
    v["weight"] = w
    bones = re.findall(rb"(bone_\w+)", d[bones_at:])
    return groups, v, [b.decode() for b in bones]


if __name__ == "__main__":
    groups, v, bones = read(sys.argv[1])
    for kind, part, idx in groups:
        print(f"{kind:18} {part:32} tris {len(idx):5} verts {idx.min():5}..{idx.max():5}")
    print("verts", len(v["pos"]), "pos", v["pos"].min(0), v["pos"].max(0))
    print("bones", len(bones), bones)
