"""Make an animated (morph) model lighter, on its baked frames.

hidden(frames, tri)          triangles seen from some direction above the ground in some frame
decimate(frames, uv, tri, n) half-edge collapses down to about n triangles: every kept vertex is
                             an original one, so its frames and uv stay as they are; the error
                             of a collapse is summed over all frames (quadrics per frame), seams
                             and open edges are kept so nothing cracks.
compact(frames, uv, tri)     drop the vertices no triangle uses.

  python optimize.py MODEL.bin OUT.bin [triangles]   (format in make_army.py)
"""
import heapq, struct, sys
import numpy as np


def views(n_az=12, elevations=(5, 25, 50, 80)):
    for el in elevations:
        for k in range(n_az):
            a, e = np.radians(k * 360 / n_az), np.radians(el)
            yield np.array([np.cos(e) * np.sin(a), np.sin(e), np.cos(e) * np.cos(a)])


def _raster(p2, depth, tri, size):
    """Triangle id per pixel, nearest first (orthographic, p2 in pixels)."""
    zbuf = np.full((size, size), np.inf)
    ids = np.full((size, size), -1, np.int64)
    for t, (a, b, c) in enumerate(tri):
        pa, pb, pc = p2[a], p2[b], p2[c]
        x0, y0 = np.floor(np.minimum(np.minimum(pa, pb), pc)).astype(int)
        x1, y1 = np.ceil(np.maximum(np.maximum(pa, pb), pc)).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        den = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
        if abs(den) < 1e-9:
            continue
        ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1] + 0.5
        w0 = ((pb[1] - pc[1]) * (xs - pc[0]) + (pc[0] - pb[0]) * (ys - pc[1])) / den
        w1 = ((pc[1] - pa[1]) * (xs - pc[0]) + (pa[0] - pc[0]) * (ys - pc[1])) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= -0.01) & (w1 >= -0.01) & (w2 >= -0.01)
        if not inside.any():   # smaller than a pixel: its centre pixel
            inside = np.zeros_like(inside)
            cx, cy = ((pa + pb + pc) / 3).astype(int)
            if x0 <= cx <= x1 and y0 <= cy <= y1:
                inside[cy - y0, cx - x0] = True
        z = w0 * depth[a] + w1 * depth[b] + w2 * depth[c]
        sub_z, sub_id = zbuf[y0:y1 + 1, x0:x1 + 1], ids[y0:y1 + 1, x0:x1 + 1]
        win = inside & (z < sub_z)
        sub_z[win] = z[win]
        sub_id[win] = t
    return ids


def hidden(frames, tri, size=256, frame_step=4):
    """Bool per triangle: seen in at least one view of some frames."""
    seen = np.zeros(len(tri), bool)
    for f in range(0, len(frames), frame_step):
        p = frames[f].astype(np.float64)
        centre = (p.min(0) + p.max(0)) / 2
        r = np.linalg.norm(p - centre, axis=1).max()
        for d in views():
            right = np.cross([0, 1, 0], d)
            right /= np.linalg.norm(right)
            up = np.cross(d, right)
            q = p - centre
            p2 = np.stack([q @ right, -(q @ up)], 1) / (2 * r) * size + size / 2
            ids = _raster(p2, -(q @ d), tri, size)
            seen[np.unique(ids[ids >= 0])] = True
    return seen


def compact(frames, uv, tri):
    used = np.unique(tri)
    remap = np.full(len(uv), -1, np.int64)
    remap[used] = np.arange(len(used))
    return frames[:, used], uv[used], remap[tri]


def _plane_quadrics(p, tri):
    a, b, c = p[tri[:, 0]], p[tri[:, 1]], p[tri[:, 2]]
    n = np.cross(b - a, c - a)
    area = np.linalg.norm(n, axis=1, keepdims=True)
    n = n / np.maximum(area, 1e-12)
    plane = np.concatenate([n, -(n * a).sum(1, keepdims=True)], 1)
    return np.einsum("fi,fj->fij", plane, plane) * area[:, :, None]   # weighted by area


def decimate(frames, uv, tri, target):
    """Collapses on welded points (vertices at the same place in every frame are one point,
    e.g. both sides of a uv seam); each triangle corner keeps an original vertex for its uv."""
    frames = frames.astype(np.float64)
    nf = len(frames)
    key = np.round(np.concatenate([frames[0], frames[nf // 2]], 1) * 1e4).astype(np.int64)
    _, gid = np.unique(key, axis=0, return_inverse=True)
    gid = gid.ravel()
    ng = gid.max() + 1
    gpos = np.zeros((nf, ng, 3))
    gpos[:, gid] = frames
    tri = [list(t) for t in tri]                       # original vertex per corner
    alive = [True] * len(tri)
    gt = [set() for _ in range(ng)]                    # triangles touching each point
    for i, t in enumerate(tri):
        for v in t:
            gt[gid[v]].add(i)
    Q = np.zeros((nf, ng, 4, 4))
    G = gid[np.array(tri)]
    for f in range(nf):
        K = _plane_quadrics(gpos[f], G)
        for k in range(3):
            np.add.at(Q[f], G[:, k], K)

    def g_edges_of(i):
        g = [gid[x] for x in tri[i]]
        return [tuple(sorted((g[k], g[(k + 1) % 3]))) for k in range(3)]

    def edge_count(a, b):
        return sum(1 for i in gt[a] if alive[i] and b in [gid[x] for x in tri[i]])

    def boundary(a):
        nbrs = {gid[x] for i in gt[a] if alive[i] for x in tri[i]} - {a}
        return any(edge_count(a, b) == 1 for b in nbrs)

    def cost(v, u):
        h = np.concatenate([gpos[:, u], np.ones((nf, 1))], 1)
        return float(np.einsum("fi,fij,fj->", h, Q[:, v] + Q[:, u], h))

    heap = []
    for i in range(len(tri)):
        for a, b in g_edges_of(i):
            heapq.heappush(heap, (cost(a, b), a, b))
            heapq.heappush(heap, (cost(b, a), b, a))
    count = len(tri)
    gone = np.zeros(ng, bool)
    p = gpos[0]
    while count > target and heap:
        c, v, u = heapq.heappop(heap)
        if gone[v] or gone[u] or v == u:
            continue
        shared = [i for i in gt[v] if alive[i] and u in [gid[x] for x in tri[i]]]
        if not shared:
            continue
        if boundary(v) and edge_count(v, u) != 1:     # border points slide only along the border
            continue
        # no flipped triangles (frame 0) and no corner left without a uv twin
        ok, swap = True, {}
        for i in shared:                               # same uv island: corner v -> its u
            cv = next(x for x in tri[i] if gid[x] == v)
            swap[cv] = next(x for x in tri[i] if gid[x] == u)
        for i in gt[v]:
            if not alive[i] or i in shared:
                continue
            t = tri[i]
            cv = next(x for x in t if gid[x] == v)
            if cv not in swap:                         # an island not on this edge: nearest uv of u
                twins = [x for x in np.nonzero(gid == u)[0]]
                swap[cv] = min(twins, key=lambda x: np.sum((uv[x] - uv[cv]) ** 2))
            g = [gid[x] for x in t]
            old = np.cross(p[g[1]] - p[g[0]], p[g[2]] - p[g[0]])
            g2 = [u if x == v else x for x in g]
            new = np.cross(p[g2[1]] - p[g2[0]], p[g2[2]] - p[g2[0]])
            if np.dot(old, new) <= 0.2 * np.linalg.norm(old) * np.linalg.norm(new) + 1e-12:
                ok = False
                break
        if not ok:
            continue
        for i in list(gt[v]):
            if not alive[i]:
                continue
            if i in shared:
                alive[i] = False
                count -= 1
                for x in tri[i]:
                    gt[gid[x]].discard(i)
            else:
                tri[i] = [swap[x] if gid[x] == v else x for x in tri[i]]
                gt[u].add(i)
        gt[v] = set()
        gone[v] = True
        Q[:, u] += Q[:, v]
        for i in gt[u]:
            for x in tri[i]:
                w = gid[x]
                if w != u:
                    heapq.heappush(heap, (cost(u, w), u, w))
                    heapq.heappush(heap, (cost(w, u), w, u))
    return np.array([t for t, a in zip(tri, alive) if a], np.int64)


def read(path):
    d = open(path, "rb").read()
    hdr = d[:20]
    nv, nt, nf, ts = struct.unpack_from("<4H", d, 4)
    p = 20
    uv = np.frombuffer(d, "<f4", nv * 2, p).reshape(nv, 2); p += nv * 8
    tri = np.frombuffer(d, "<u2", nt * 3, p).reshape(nt, 3).astype(np.int64); p += (nt * 6 + 3) & ~3
    frames = np.frombuffer(d, "<f4", nf * nv * 3, p).reshape(nf, nv, 3); p += nf * nv * 12
    return hdr, uv, tri, frames, d[p:]


def write(path, hdr, uv, tri, frames, tex):
    out = bytearray(hdr)
    struct.pack_into("<2H", out, 4, len(uv), len(tri))
    out += uv.astype("<f4").tobytes()
    out += tri.astype("<u2").tobytes()
    if len(tri) % 2:
        out += b"\0\0"
    out += frames.astype("<f4").tobytes()
    out += tex
    open(path, "wb").write(out)


if __name__ == "__main__":
    src, dst = sys.argv[1:3]
    target = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    hdr, uv, tri, frames, tex = read(src)
    print(f"start: {len(uv)} verts, {len(tri)} tris")
    seen = hidden(frames, tri)
    tri = tri[seen]
    frames, uv, tri = compact(frames, uv, tri)
    print(f"visible: {len(uv)} verts, {len(tri)} tris")
    if target:
        tri = decimate(frames, uv, tri, target)
        frames, uv, tri = compact(frames, uv, tri)
        print(f"decimated: {len(uv)} verts, {len(tri)} tris")
    write(dst, hdr, uv, tri, frames, tex)
