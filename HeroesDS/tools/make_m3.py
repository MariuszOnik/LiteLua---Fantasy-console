"""Makes the political map as 3D meshes for the 3DS (the land of make_m2.py, same seed):
every province and sea zone is a flat polygon with smooth, wavy borders, land provinces
are plates raised over the sea with walls down to it, and the borders are thin ribbons.

  python HeroesDS/tools/make_m3.py [--seed 77] [--coast 1] [--out 3ds/romfs/map3d.bin]
                                   [--png preview.png] [--obj map.obj]

Steps:
  1. make_m2.generate: provinces and sea zones on a grid of cells (region per cell)
  2. outlines: every region's border on the grid as closed rings of cell sides, walked
     so the region is always on the same side (holes come out the other way round); at a
     corner where the region touches itself diagonally the ring keeps to one cell
  3. chains: the rings are cut at junctions (corners where 3+ regions meet, or more than
     two border sides) into chains shared by the two regions on their sides; every chain
     is made once -- control points in the middle of its cell sides (so stairs become
     slopes), a Chaikin step, simplified -- so both neighbours get exactly the same border
  4. noisy edges: the smoothed line is cut into long segments, each segment's middle is
     pushed sideways at random by up to ROUGH x its length, then both halves the same way
     down to MIN_SEG (detail at every scale, like a hand-drawn map; Red Blob Games'
     "noisy edges"); a line crossing another one (or itself) is redone calmer
  5. triangles: the top of each region by ear cutting (mapbox_earcut, holes included);
     land gets walls down to the sea (shade from a fixed light; walls on the shore first,
     walls between land regions after -- the 3DS draws those only for a raised
     province); borders become ribbons a little over the surface (land/land, coast --
     inside the land only, sea/sea)
The file format is in docs/FORMATS.md ("map3d.bin").
"""
import argparse
import os
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import make_m2 as m2  # noqa: E402

LAND_H = 0.8          # top of the land plates (a cell is 1 x 1)
CHAIKIN = 1           # smoothing steps of the base line (takes the grid's stairs off)
BASE = 0.3            # Douglas-Peucker tolerance of the base line, in cells
ROUGH = {"land": 0.3, "coast": 0.36, "sea": 0.2}   # noisy edges: sideways shift / length
MIN_SEG = 0.2         # noisy edges stop at segments this long, in cells
OUTSIDE = -2          # region number of the space outside the grid
NEUTRAL = -1          # land without a province (tiny islets)
LIGHT = np.array((-0.5, -0.7))  # light comes from this side (x, z), for the walls
BORDER = {            # class: (width, height over the surface)
    0: (0.10, 0.015),   # land / land
    1: (0.22, 0.015),   # coast (inside the land)
    2: (0.08, 0.010),   # sea / sea
}
KIND_LAND, KIND_SEA, KIND_NEUTRAL = 0, 1, 2

# a cell's sides, walked clockwise on screen (row down, col right): the cell is on the
# right of every side; (corner from, corner to, neighbour cell offset)
SIDES = [((0, 0), (0, 1), (-1, 0)), ((0, 1), (1, 1), (0, 1)),
         ((1, 1), (1, 0), (1, 0)), ((1, 0), (0, 0), (0, -1))]


def region_at(prov, r, c):
    rows, cols = prov.shape
    return int(prov[r, c]) if 0 <= r < rows and 0 <= c < cols else OUTSIDE


def outlines(prov):
    """Rings per region: {region: [[corner, ...], ...]}, corners (row, col)."""
    rows, cols = prov.shape
    out = {}   # region -> {corner from: [(corner to, cell)]}
    for r in range(rows):
        for c in range(cols):
            a = int(prov[r, c])
            for (fr, fc), (tr, tc), (dr, dc) in SIDES:
                if region_at(prov, r + dr, c + dc) != a:
                    out.setdefault(a, {}).setdefault((r + fr, c + fc), []).append(((r + tr, c + tc), (r, c)))
    rings = {}
    for a, edges in out.items():
        left = sum(len(v) for v in edges.values())
        while left:
            start = next(k for k, v in edges.items() if v)
            ring, at, cell = [], start, None
            while True:
                opts = edges[at]
                if not opts:
                    break
                # keep to the cell we came along (a corner touching itself diagonally)
                k = next((i for i, (_, c2) in enumerate(opts) if c2 == cell), 0)
                nxt, cell = opts.pop(k)
                left -= 1
                ring.append(at)
                at = nxt
            rings.setdefault(a, []).append(ring)
    return rings


def junctions(prov):
    """Corners where 3+ regions meet or that are not plain border corners."""
    rows, cols = prov.shape
    out = set()
    for r in range(rows + 1):
        for c in range(cols + 1):
            q = [region_at(prov, r - 1, c - 1), region_at(prov, r - 1, c),
                 region_at(prov, r, c), region_at(prov, r, c - 1)]
            sides = sum(q[i] != q[(i + 1) % 4] for i in range(4))
            if len(set(q)) >= 3 or sides > 2:
                out.add((r, c))
    return out


def chaikin(p, closed, steps):
    for _ in range(steps):
        if closed:
            q = np.roll(p, -1, 0)
            p = np.stack([0.75 * p + 0.25 * q, 0.25 * p + 0.75 * q], 1).reshape(-1, 2)
        else:
            a, b = p[:-1], p[1:]
            mid = np.stack([0.75 * a + 0.25 * b, 0.25 * a + 0.75 * b], 1).reshape(-1, 2)
            p = np.vstack([p[:1], mid, p[-1:]])
    return p


def simplify(p, tol):
    """Douglas-Peucker, ends kept."""
    if len(p) < 3:
        return p
    keep = np.zeros(len(p), bool)
    keep[0] = keep[-1] = True
    todo = [(0, len(p) - 1)]
    while todo:
        i, j = todo.pop()
        if j <= i + 1:
            continue
        a, b = p[i], p[j]
        d = b - a
        n = np.hypot(*d)
        seg = p[i + 1:j] - a
        dist = np.abs(d[0] * seg[:, 1] - d[1] * seg[:, 0]) / n if n > 1e-9 else np.hypot(seg[:, 0], seg[:, 1])
        k = int(dist.argmax())
        if dist[k] > tol:
            keep[i + 1 + k] = True
            todo += [(i, i + 1 + k), (i + 1 + k, j)]
    return p[keep]


def base_line(corners, closed):
    """The chain of grid corners without its stairs: control points in the middle of the
    cell sides, one Chaikin step, simplified to long segments (ends stay put)."""
    pts = np.array([(c, r) for r, c in corners], float)
    if closed:
        ctrl = (pts + np.roll(pts, -1, 0)) / 2
    else:
        ctrl = np.vstack([pts[:1], (pts[:-1] + pts[1:]) / 2, pts[-1:]])
    p = chaikin(ctrl, closed, CHAIKIN)
    if closed:
        return simplify(np.vstack([p, p[:1]]), BASE)[:-1]
    return simplify(p, BASE)


def roughen(p, closed, rough, seed):
    """Noisy edges: every segment's middle moves sideways by up to rough x its length,
    then both halves the same way, down to MIN_SEG -- detail at every scale."""
    if rough <= 0:
        return p
    rng = np.random.default_rng(seed)

    def split(a, b, out):
        d = b - a
        n = float(np.hypot(*d))
        if n < MIN_SEG:
            out.append(b)
            return
        m = (a + b) / 2 + np.array((-d[1], d[0])) * rng.uniform(-rough, rough)
        split(a, m, out)
        split(m, b, out)

    out = [p[0]]
    q = np.vstack([p, p[:1]]) if closed else p
    for a, b in zip(q[:-1], q[1:]):
        split(a, b, out)
    return np.array(out[:-1] if closed else out)


def crossings(lines):
    """Keys of the lines {key: (points, closed)} whose segments cross any other segment
    (or their own); touching at a shared end does not count."""
    segs, grid = [], {}
    for key, (p, closed) in lines.items():
        q = np.vstack([p, p[:1]]) if closed else p
        n = len(q) - 1
        for i in range(n):
            a, b = q[i], q[i + 1]
            s = len(segs)
            segs.append((key, i, n, closed, a, b))
            for gx in range(int(np.floor(min(a[0], b[0]))), int(np.floor(max(a[0], b[0]))) + 1):
                for gz in range(int(np.floor(min(a[1], b[1]))), int(np.floor(max(a[1], b[1]))) + 1):
                    grid.setdefault((gx, gz), []).append(s)

    def orient(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])

    bad, seen = set(), set()
    for cell in grid.values():
        for x in range(len(cell)):
            for y in range(x + 1, len(cell)):
                s, t = cell[x], cell[y]
                if (s, t) in seen:
                    continue
                seen.add((s, t))
                k1, i1, n1, c1, a1, b1 = segs[s]
                k2, i2, n2, c2, a2, b2 = segs[t]
                if k1 == k2 and (abs(i1 - i2) <= 1 or (c1 and abs(i1 - i2) == n1 - 1)):
                    continue
                if (orient(a1, b1, a2) * orient(a1, b1, b2) < 0
                        and orient(a2, b2, a1) * orient(a2, b2, b1) < 0):
                    bad.update((k1, k2))
    return bad


class Chains:
    """Border chains, each made once and shared by the regions on both sides."""

    def __init__(self, prov, land):
        self.prov = prov
        self.land = land
        self.info = {}    # key -> (corners, closed, sides: (region walking it this way, other))
        self.cache = {}   # key -> (points, sides)

    def get(self, corners, closed, region):
        """Registers the chain; returns its key and whether the region walks it backwards."""
        if closed:
            i = corners.index(min(corners))
            fwd = corners[i:] + corners[:i]
            rev = fwd[:1] + fwd[1:][::-1]
            key, back = (tuple(min(fwd, rev)), True), fwd > rev
        else:
            fwd, rev = corners, corners[::-1]
            key, back = (tuple(min(fwd, rev)), False), fwd > rev
        if key not in self.info:
            seq = list(key[0])
            other = self.across(seq, closed, region, back)
            self.info[key] = (seq, closed, (region, other) if not back else (other, region))
        return key, back

    def kind(self, sides):
        if OUTSIDE in sides:
            return "edge"
        land = [s == NEUTRAL or 0 <= s < self.land for s in sides]
        return "land" if all(land) else "coast" if any(land) else "sea"

    def make(self):
        """Base lines, roughened; a line that crosses another gets calmer until none do."""
        base, scale = {}, {}
        for key, (seq, closed, sides) in self.info.items():
            base[key] = base_line(seq, closed)
            scale[key] = ROUGH.get(self.kind(sides), 0.0)
        lines = {}
        for attempt in range(6):
            todo = scale if attempt == 0 else bad
            for key in todo:
                seed = zlib.crc32(repr(key[0][:4]).encode()) + attempt
                lines[key] = (roughen(base[key], key[1], scale[key], seed), key[1])
            bad = crossings(lines)
            if not bad:
                break
            for key in bad:
                scale[key] = scale[key] * 0.5 if attempt < 4 else 0.0
        self.cache = {key: (lines[key][0], self.info[key][2]) for key in self.info}

    def outer(self, key):
        """Whether the chain is a shore (sea or the map edge on one side): its walls show."""
        return self.kind(self.info[key][2]) in ("coast", "edge")

    def points(self, key, back):
        pts = self.cache[key][0]
        return pts[::-1] if back else pts

    def across(self, seq, closed, region, back):
        """The region on the other side of the chain's first side."""
        (r1, c1), (r2, c2) = seq[0], seq[1]
        cells = [(min(r1, r2) - (r1 == r2), min(c1, c2) - (c1 == c2)), (min(r1, r2), min(c1, c2))]
        regs = [region_at(self.prov, r, c) for r, c in cells]
        return regs[0] if regs[1] == region else regs[1]


def region_rings(prov, land):
    """{region: [ring points (N, 2) x, z]} with rough shared borders, per ring whether
    the side from point i to i + 1 is a shore (its wall shows), and the chains."""
    rings = outlines(prov)
    junc = junctions(prov)
    chains = Chains(prov, land)
    plan = []   # (region, [(key, back, closed)])
    for a, rs in rings.items():
        if a == OUTSIDE:
            continue
        for ring in rs:
            cut = [i for i, v in enumerate(ring) if v in junc]
            if not cut:
                plan.append((a, [chains.get(ring, True, a) + (True,)]))
                continue
            ring = ring[cut[0]:] + ring[:cut[0]]
            cut = [i - cut[0] for i in cut] + [len(ring)]
            parts = []
            for i, j in zip(cut, cut[1:]):
                seg = ring[i:j + 1] if j < len(ring) else ring[i:] + ring[:1]
                parts.append(chains.get(seg, False, a) + (False,))
            plan.append((a, parts))
    chains.make()
    out, walls = {}, {}
    for a, parts in plan:
        if parts[0][2]:
            pts = chains.points(*parts[0][:2])
            seen = [chains.outer(parts[0][0])] * len(pts)
        else:
            lines = [chains.points(key, back)[:-1] for key, back, _ in parts]
            pts = np.vstack(lines)
            seen = [chains.outer(key) for (key, _, _), q in zip(parts, lines) for _ in q]
        out.setdefault(a, []).append(pts)
        walls.setdefault(a, []).append(np.array(seen))
    return out, walls, chains


def area(p):
    x, y = p[:, 0], p[:, 1]
    return 0.5 * float((x * np.roll(y, -1) - np.roll(x, -1) * y).sum())


def inside(pt, ring):
    x, y = pt
    xs, ys = ring[:, 0], ring[:, 1]
    xs2, ys2 = np.roll(xs, -1), np.roll(ys, -1)
    cross = (ys > y) != (ys2 > y)
    with np.errstate(divide="ignore", invalid="ignore"):
        xi = xs + (y - ys) * (xs2 - xs) / (ys2 - ys)
    return bool((cross & (x < xi)).sum() % 2)


def triangulate(rings):
    """Triangles over the rings (outer rings and holes go round opposite ways)."""
    import mapbox_earcut as earcut
    # a single cell walked by SIDES has positive area in (x, z) = (col, row)
    outers = [p for p in rings if area(p) > 0]
    holes = [p for p in rings if area(p) < 0]
    groups = [[o] for o in outers]
    for h in holes:
        for g in sorted(groups, key=lambda g: abs(area(g[0]))):
            if inside(h.mean(0), g[0]) or inside(h[0], g[0]):
                g.append(h)
                break
    verts, tris = [], []
    base = 0
    for g in groups:
        pts = np.vstack(g).astype(np.float32)
        ends = np.cumsum([len(p) for p in g]).astype(np.uint32)
        t = earcut.triangulate_float32(pts, ends).reshape(-1, 3)
        verts.append(pts)
        tris.append(t + base)
        base += len(pts)
    return np.vstack(verts), np.vstack(tris) if tris else np.zeros((0, 3), int)


def build(m):
    prov = m["province"].copy()
    land = m["land"]
    rings, walls, chains = region_rings(prov, land)
    off = np.array([prov.shape[1] / 2, prov.shape[0] / 2])
    regions = []
    for a in sorted(rings):
        kind = KIND_NEUTRAL if a == NEUTRAL else KIND_LAND if a < land else KIND_SEA
        top_y = 0.0 if kind == KIND_SEA else LAND_H
        pts2, tris = triangulate(rings[a])
        pts2 = pts2 - off
        verts = [(x, top_y, z, 1.0) for x, z in pts2]
        idx = [int(i) for t in tris for i in t]   # drawn without culling
        top = len(idx)
        shore, inner = [], []
        if kind != KIND_SEA:
            for ring, outer in zip(rings[a], walls[a]):
                p = ring - off
                d = np.roll(p, -1, 0) - p
                n = np.stack([d[:, 1], -d[:, 0]], 1)            # out of the region
                n /= np.maximum(np.hypot(n[:, 0], n[:, 1]), 1e-9)[:, None]
                vn = n + np.roll(n, 1, 0)                        # per point: both sides
                vn /= np.maximum(np.hypot(vn[:, 0], vn[:, 1]), 1e-9)[:, None]
                shade = 0.45 + 0.45 * np.maximum(0.0, vn @ (LIGHT / np.hypot(*LIGHT)))
                v0, k = len(verts), len(p)
                for (x, z), sh in zip(p, shade):
                    verts += [(x, top_y, z, float(sh)), (x, 0.0, z, float(sh))]
                for i in range(k):
                    t1, b1 = v0 + 2 * i, v0 + 2 * i + 1
                    t2, b2 = v0 + 2 * ((i + 1) % k), v0 + 2 * ((i + 1) % k) + 1
                    (shore if outer[i] else inner).extend((t1, b2, t2, t1, b1, b2))
        idx += shore
        coast = len(idx)
        idx += inner
        assert len(verts) < 65536, (a, len(verts))
        xs, zs = pts2[:, 0], pts2[:, 1]
        if a >= 0:
            r, c = m["capitals"][a]
            cx, cz = c + 0.5 - off[0], r + 0.5 - off[1]
            name, owner = m["names"][a], m["owner"][a]
        else:
            cx, cz, name, owner = float(xs.mean()), float(zs.mean()), "", -1
        neigh = sorted(int(b) for b in m["neighbours"].get(a, ()) if b >= 0) if a >= 0 else []
        regions.append(dict(id=a, kind=kind, owner=owner, name=name, cx=cx, cz=cz,
                            box=(float(xs.min()), float(zs.min()), float(xs.max()), float(zs.max())),
                            verts=verts, idx=idx, top=top, coast=coast, neigh=neigh))
    borders = {k: [] for k in BORDER}
    for (seq, closed), (pts, (ra, rb)) in chains.cache.items():
        if OUTSIDE in (ra, rb):
            continue   # the sea at the map edge: no line
        # ra walks the chain this way round, so it lies on the ribbon's + side
        land_a = ra == NEUTRAL or 0 <= ra < land
        land_b = rb == NEUTRAL or 0 <= rb < land
        if land_a and land_b:
            cls, lo, hi = 0, -0.5, 0.5
        elif land_a or land_b:
            cls = 1
            lo, hi = (0.0, 1.0) if land_a else (-1.0, 0.0)
        else:
            cls, lo, hi = 2, -0.5, 0.5
        w, lift = BORDER[cls]
        y = (LAND_H if cls < 2 else 0.0) + lift
        borders[cls] += ribbon(pts - off, closed, w * lo, w * hi, y)
    return regions, borders, chains


def ribbon(p, closed, lo, hi, y):
    """Triangles (x, y, z) of a strip from lo to hi along the right-hand normal."""
    n = len(p)
    if closed:
        p = np.vstack([p, p[:1]])
    d = np.diff(p, axis=0)
    d /= np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)[:, None]
    seg_n = np.stack([-d[:, 1], d[:, 0]], 1)   # into the region walking this way round
    vn = np.zeros_like(p)
    vn[:-1] += seg_n
    vn[1:] += seg_n
    if closed:
        vn[0] += seg_n[-1]
        vn[-1] = vn[0]
    ln = np.hypot(vn[:, 0], vn[:, 1])
    vn /= np.maximum(ln, 1e-9)[:, None]
    # miter, limited
    cos = np.ones(len(p))
    cos[:-1] = np.minimum(cos[:-1], np.abs((vn[:-1] * seg_n).sum(1)))
    vn /= np.maximum(cos, 0.5)[:, None]
    a, b = p + vn * lo, p + vn * hi
    out = []
    for i in range(len(p) - 1):
        q = [(a[i][0], y, a[i][1]), (b[i][0], y, b[i][1]), (b[i + 1][0], y, b[i + 1][1]), (a[i + 1][0], y, a[i + 1][1])]
        out += [q[0], q[1], q[2], q[0], q[2], q[3]]
    return out


def write(path, m, regions, borders):
    """map3d.bin, see docs/FORMATS.md."""
    head = struct.pack("<4sHHHH", b"HM3D", 2, len(regions), m["land"], len(m2.FACTIONS))
    nv = sum(len(r["verts"]) for r in regions)
    ni = sum(len(r["idx"]) for r in regions)
    nb = sum(len(v) for v in borders.values())
    head += struct.pack("<IIIf", nv, ni, nb, LAND_H)
    for fname, col in m2.FACTIONS:
        head += struct.pack("<BBBx16s", *col, fname.encode())
    body, nlist, v0, i0 = b"", b"", 0, 0
    for r in regions:
        head += struct.pack("<hbbB3x24s6f6I", r["id"], r["kind"], r["owner"], len(r["neigh"]),
                            r["name"].encode()[:23], r["cx"], r["cz"], *r["box"],
                            v0, len(r["verts"]), i0, len(r["idx"]), r["top"], r["coast"])
        nlist += struct.pack("<%dh" % len(r["neigh"]), *r["neigh"])
        v0 += len(r["verts"])
        i0 += len(r["idx"])
    verts = b"".join(struct.pack("<4f", *v) for r in regions for v in r["verts"])
    idx = b"".join(struct.pack("<%dH" % len(r["idx"]), *r["idx"]) for r in regions)
    if len(idx) % 4:
        idx += b"\0\0"
    bhead = b"".join(struct.pack("<I", len(borders[k])) for k in sorted(borders))
    bverts = b"".join(struct.pack("<3f", *v) for k in sorted(borders) for v in borders[k])
    if len(nlist) % 4:
        nlist += b"\0\0"
    body = bhead + nlist + verts + idx + bverts
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(head + body)
    return nv, ni, nb


def write_obj(path, regions):
    """Every region as an object (top and all walls), to look at in Blender."""
    with open(path, "w", encoding="utf-8") as f:
        base = 1
        for r in regions:
            f.write("o %s_%d\n" % (r["name"].replace(" ", "_") or "neutral", r["id"]))
            for x, y, z, _ in r["verts"]:
                f.write("v %.4f %.4f %.4f\n" % (x, y, -z))
            idx = r["idx"]
            for t in range(0, len(idx), 3):
                f.write("f %d %d %d\n" % tuple(base + i for i in idx[t:t + 3]))
            base += len(r["verts"])


def preview(path, m, regions, borders, scale=10):
    from PIL import Image, ImageDraw
    rows, cols = m["province"].shape
    img = Image.new("RGB", (cols * scale, rows * scale), (20, 40, 80))
    d = ImageDraw.Draw(img)
    off = np.array([cols / 2, rows / 2])

    def xy(x, z):
        return ((x + off[0]) * scale, (z + off[1]) * scale)
    for r in regions:
        if r["kind"] == KIND_SEA:
            col = (110, 150, 190) if r["id"] % 2 else (100, 140, 185)
        elif r["kind"] == KIND_NEUTRAL:
            col = (180, 170, 150)
        else:
            col = tuple(int(0.55 * c + 0.45 * p) for c, p in zip(m2.FACTIONS[r["owner"]][1], m2.PARCHMENT))
        v = r["verts"]
        idx = r["idx"][:r["top"]]
        for t in range(0, len(idx), 3):
            d.polygon([xy(v[i][0], v[i][2]) for i in idx[t:t + 3]], fill=col)
    for cls, col in ((2, (150, 185, 215)), (0, (70, 50, 30)), (1, (30, 20, 10))):
        tri = borders[cls]
        for t in range(0, len(tri), 3):
            d.polygon([xy(p[0], p[2]) for p in tri[t:t + 3]], fill=col)
    for r in regions:
        if r["kind"] == KIND_LAND:
            d.text(xy(r["cx"], r["cz"]), r["name"], fill=(0, 0, 0), anchor="mm")
    img.save(path)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--seed", type=int, default=77)
    p.add_argument("--size", type=int, default=72)
    p.add_argument("--provinces", type=int, default=45)
    p.add_argument("--coast", type=float, default=1.0)
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    p.add_argument("--out", default=os.path.join(here, "3ds", "romfs", "map3d.bin"))
    p.add_argument("--png")
    p.add_argument("--obj", help="also write a Wavefront .obj (one object per region) for Blender")
    a = p.parse_args(argv)
    m = m2.generate(a.seed, a.size, a.provinces, a.coast)
    regions, borders, _ = build(m)
    nv, ni, nb = write(a.out, m, regions, borders)
    print("%s: %d regions (%d land), %d vertices, %d triangles, %d border triangles, %d KB"
          % (a.out, len(regions), m["land"], nv, ni // 3, nb // 3, os.path.getsize(a.out) // 1024))
    if a.png:
        preview(a.png, m, regions, borders)
    if a.obj:
        write_obj(a.obj, regions)


if __name__ == "__main__":
    main(sys.argv[1:])
