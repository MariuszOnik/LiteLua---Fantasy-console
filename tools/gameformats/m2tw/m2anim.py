"""Medieval II unit animations (data/animations/pack.idx + pack.dat; reverse-engineered,
test use only) and baking them into vertex frames.

pack.idx: "ANIM.PACK" header, then per animation: u32 ?, u32 offset, u32 size, f32 1.0,
the same 5 bytes as at the start of its data, name\\0.
pack.dat at offset: u16 frames, u16 bones, u8 bones with translations,
  frames * bones quaternions (x, y, z, w) -- local rotations,
  frames * tbones translations (x, y, z) -- local offsets from the parent (bone lengths),
  more tracks after that (not used here).
Bone order is the mesh's (bone_pelvis, rthigh, ...); the hierarchy is not stored here, so it
is guessed from the mesh: each bone takes the earlier bone that puts its joint nearest to its
own vertices. The bind pose has no rotations (T-pose), only these offsets.
"""
import re, struct
import numpy as np

ANIMS = "C:/Program Files (x86)/Steam/steamapps/common/Medieval II Total War/mods/teutonic/data/animations/"


def index(path=ANIMS + "pack.idx"):
    d = open(path, "rb").read()
    out = {}
    for m in re.finditer(rb"(data/animations/[^\x00]+\.cas)\x00", d):
        off, size = struct.unpack_from("<2I", d, m.start() - 17)
        out[m.group(1).decode().lower()] = (off, size)
    return out


def read(name, idx=None, path=ANIMS + "pack.dat"):
    idx = idx or index()
    off, size = idx[name.lower()]
    with open(path, "rb") as f:
        f.seek(off)
        d = f.read(size)
    frames, bones, tb = struct.unpack_from("<HHB", d, 0)
    q = np.frombuffer(d, "<f4", frames * bones * 4, 5).reshape(frames, bones, 4)
    t = np.frombuffer(d, "<f4", frames * tb * 3, 5 + frames * bones * 16).reshape(frames, tb, 3)
    return q.astype(np.float64), t.astype(np.float64)


def quat_mat(q):
    x, y, z, w = q[..., 0], q[..., 1], q[..., 2], q[..., 3]
    m = np.empty(q.shape[:-1] + (3, 3))
    m[..., 0, 0] = 1 - 2 * (y * y + z * z); m[..., 0, 1] = 2 * (x * y - z * w); m[..., 0, 2] = 2 * (x * z + y * w)
    m[..., 1, 0] = 2 * (x * y + z * w); m[..., 1, 1] = 1 - 2 * (x * x + z * z); m[..., 1, 2] = 2 * (y * z - x * w)
    m[..., 2, 0] = 2 * (x * z - y * w); m[..., 2, 1] = 2 * (y * z + x * w); m[..., 2, 2] = 1 - 2 * (x * x + y * y)
    return m


def guess_parents(offsets, pos, bone, weight):
    """Parent of each animated bone from the mesh (vertices mostly on that bone)."""
    n = len(offsets)
    main = np.where(weight[:, 0] >= weight[:, 1], bone[:, 0], bone[:, 1])
    parents, world = [-1], [offsets[0]]
    for b in range(1, n):
        mine = pos[main == b]
        best, bp = None, 0
        for p in range(b):
            j = world[p] + offsets[b]
            near = pos[(main == b) | (main == p)]
            dist = np.min(np.linalg.norm(near - j, axis=1)) if len(near) else 9
            if len(mine) == 0:
                dist = np.linalg.norm(offsets[b]) * 0  # no vertices: any parent; take the closest joint
                dist = np.min([np.linalg.norm(world[p] + offsets[b] - w) for w in world])
            if best is None or dist < best:
                best, bp = dist, p
        parents.append(bp)
        world.append(world[bp] + offsets[b])
    return parents, np.array(world)


def bake(v, q, t, parents, fallback):
    """Vertex positions per frame. fallback[b] = animated bone that drives mesh bone b."""
    frames, nb = q.shape[:2]
    bind = np.zeros((nb, 3))
    for b in range(nb):
        bind[b] = (bind[parents[b]] if parents[b] >= 0 else 0) + t[0, b]
    out = []
    for f in range(frames):
        R = np.zeros((nb, 3, 3)); P = np.zeros((nb, 3))
        r = quat_mat(q[f])
        for b in range(nb):
            if parents[b] < 0:
                R[b], P[b] = r[b], t[f, b]
            else:
                p = parents[b]
                R[b] = R[p] @ r[b]
                P[b] = P[p] + R[p] @ t[f, b]
        acc = np.zeros_like(v["pos"], dtype=np.float64)
        for k in range(2):
            b = fallback[v["bone"][:, k]]
            local = v["pos"] - bind[b]
            moved = np.einsum("nij,nj->ni", R[b], local) + P[b]
            acc += v["weight"][:, k:k + 1] * moved
        out.append(acc.astype(np.float32))
    return out
