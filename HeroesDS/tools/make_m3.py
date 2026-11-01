"""Makes the political map for the 3DS (the land of make_m2.py, same seed): a flat map
in 3D -- one quad with a picture where all the detail lives (hand-drawn, fractal borders,
the coast's shadow, paper, waves) -- plus, per province and sea zone, its exact shape,
drawn only to light up the selected one. Owners' colours are put on by the 3DS.

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
  5. exact shapes: the top of each region by ear cutting (mapbox_earcut, holes included)
     and a strip inside its border (the selection outline)
  6. the picture (TEX x TEX, drawn twice as big and scaled down): sea lighter near the
     shore, the land's shadow on it, waves; land as pale paper, darker along its
     borders; lines (land/land, coast, sea/sea); and the region index of every pixel
     (taps on the 3DS) -- both with all mipmap levels, in the 3DS texture order
     (tile_order)
The file formats are in docs/FORMATS.md ("map3d.bin", "map_tex.bin").
"""
import argparse
import os
import struct
import sys
import zlib

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import make_m2 as m2  # noqa: E402

CHAIKIN = 1           # smoothing steps of the base line (takes the grid's stairs off)
BASE = 0.3            # Douglas-Peucker tolerance of the base line, in cells
ROUGH = {"land": 0.3, "coast": 0.36, "sea": 0.2}   # noisy edges: sideways shift / length
MIN_SEG = 0.2         # noisy edges stop at segments this long, in cells
OUTSIDE = -2          # region number of the space outside the grid
NEUTRAL = -1          # land without a province (tiny islets)
OUTLINE = 0.3         # width of the selection outline, in cells
TEX = 1024            # the picture's size (the largest 3DS texture)
SEA_RGB = (150, 190, 200)
PAPER_RGB = (252, 248, 238)
SEA_LINE = (200, 222, 228)
LAND_LINE = (70, 48, 30)
COAST_LINE = (40, 28, 18)
NEUTRAL_RGB = (190, 180, 160)
TINT = 0.62           # how strong the owners' colours are (1 = the faction colour)
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
    """Regions: name, owner, label point, the exact top (triangles) and an outline strip
    inside its border -- both only drawn for the selected region; the map itself is
    one flat quad with the texture (render_texture)."""
    prov = m["province"].copy()
    land = m["land"]
    rings, _, chains = region_rings(prov, land)
    off = np.array([prov.shape[1] / 2, prov.shape[0] / 2])
    regions = []
    for a in sorted(rings):
        kind = KIND_NEUTRAL if a == NEUTRAL else KIND_LAND if a < land else KIND_SEA
        pts2, tris = triangulate(rings[a])
        pts2 = pts2 - off
        verts = [(x, 0.0, z, 1.0) for x, z in pts2]
        idx = [int(i) for t in tris for i in t]   # drawn without culling
        top = len(idx)
        for ring in rings[a]:
            inner = ring_inset(ring - off, OUTLINE)
            v0, n = len(verts), len(ring)
            for (x, z), (x2, z2) in zip(ring - off, inner):
                verts += [(x, 0.0, z, 1.0), (x2, 0.0, z2, 1.0)]
            for i in range(n):
                a1, b1, a2, b2 = v0 + 2 * i, v0 + 2 * i + 1, v0 + 2 * ((i + 1) % n), v0 + 2 * ((i + 1) % n) + 1
                idx += [a1, b1, b2, a1, b2, a2]
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
                            rings=rings[a], verts=verts, idx=idx, top=top, neigh=neigh))
    return regions, chains


def ring_inset(p, w):
    """The ring's points moved w inward (into the region the ring belongs to)."""
    d = np.roll(p, -1, 0) - p
    d /= np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)[:, None]
    seg_n = np.stack([-d[:, 1], d[:, 0]], 1)
    vn = seg_n + np.roll(seg_n, 1, 0)
    vn /= np.maximum(np.hypot(vn[:, 0], vn[:, 1]), 1e-9)[:, None]
    cos = np.abs((vn * seg_n).sum(1))
    return p + vn * (w / np.maximum(cos, 0.5))[:, None]   # miter, limited


def blur(a, radius):
    from PIL import Image, ImageFilter
    img = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), float) / 255


def value_noise(rng, h, w, cells):
    """Smooth noise 0..1 from a coarse random grid, scaled up bilinearly."""
    from PIL import Image
    g = (rng.random((cells, cells)) * 255).astype(np.uint8)
    return np.asarray(Image.fromarray(g).resize((w, h), Image.BILINEAR), float) / 255


def render_texture(m, regions, chains, size=TEX, ss=2):
    """The map's picture without the owners' colours (land is pale paper -- the 3DS
    multiplies it by the owner's colour) and the region index of every pixel.
    Returns (rgb uint8 (size, size, 3), index uint8 (size, size); 255 = none)."""
    from PIL import Image, ImageDraw
    rows, cols = m["province"].shape
    big = size * ss
    k = big / cols                       # pixels per cell (the grid is square)
    rng = np.random.default_rng(m["seed"] + 1000)
    land_set = {i for i, r in enumerate(regions) if r["kind"] != KIND_SEA}

    # region index per pixel, from the exact triangles
    ids = Image.new("L", (big, big), 255)
    d = ImageDraw.Draw(ids)
    off = np.array([cols / 2, rows / 2])
    for i, r in enumerate(regions):
        v = r["verts"]
        t = r["idx"][:r["top"]]
        for j in range(0, len(t), 3):
            d.polygon([((v[q][0] + off[0]) * k, (v[q][2] + off[1]) * k) for q in t[j:j + 3]], fill=i)
    ids_big = np.asarray(ids)
    land = np.isin(ids_big, list(land_set)).astype(float)

    # lines: land/land, coast, sea/sea -- each a mask
    masks = {c: Image.new("L", (big, big), 0) for c in ("land", "coast", "sea")}
    width = {"land": 0.11, "coast": 0.15, "sea": 0.07}
    for (seq, closed), (pts, sides) in chains.cache.items():
        kind = chains.kind(sides)
        if kind == "edge":
            continue
        xy = [(float(x) * k, float(z) * k) for x, z in pts]
        if closed:
            xy.append(xy[0])
        ImageDraw.Draw(masks[kind]).line(xy, fill=255, width=max(1, round(width[kind] * k)), joint="curve")
    line = {c: np.asarray(mk, float) / 255 for c, mk in masks.items()}

    # sea: blue-green, lighter near the shore, the land's shadow, waves far out
    noise = value_noise(rng, big, big, 24) - 0.5
    near = blur(land, 0.9 * k)
    sea = np.empty((big, big, 3))
    sea[:] = SEA_RGB
    sea += noise[..., None] * 10
    sea += (np.array((235, 240, 225)) - sea) * np.clip(near * 1.6, 0, 1)[..., None] * 0.55
    shadow = np.roll(blur(land, 0.18 * k), (round(0.22 * k), round(0.22 * k)), (0, 1))
    sea *= (1 - 0.35 * np.clip(shadow, 0, 1))[..., None]
    waves = Image.new("L", (big, big), 0)
    wd = ImageDraw.Draw(waves)
    for _ in range(int(cols * rows / 9)):
        x, y = rng.uniform(0, big, 2)
        if near[int(y), int(x)] > 0.04:
            continue
        w = k * rng.uniform(0.7, 1.2)
        for s in (0, 1):
            wd.arc((x + s * w, y, x + (s + 1) * w, y + w * 0.6), 200 if s == 0 else 20, 340 if s == 0 else 160,
                   fill=255, width=max(1, round(0.06 * k)))
    sea *= (1 - 0.18 * np.asarray(waves, float) / 255)[..., None]

    # land: pale paper with grain, a little darker along its borders
    grain = value_noise(rng, big, big, 160) - 0.5
    paper = np.empty((big, big, 3))
    paper[:] = PAPER_RGB
    paper *= (1 + 0.05 * grain + 0.04 * noise)[..., None]
    edges = blur(np.clip(line["land"] + line["coast"], 0, 1), 0.35 * k)
    paper *= (1 - 0.22 * np.clip(edges * 2, 0, 1))[..., None]

    img = sea * (1 - land[..., None]) + paper * land[..., None]
    for c, col in (("sea", SEA_LINE), ("land", LAND_LINE), ("coast", COAST_LINE)):
        a = line[c][..., None]
        img = img * (1 - a) + np.array(col, float) * a
    img = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
    return np.asarray(img), ids_big[ss // 2::ss, ss // 2::ss].copy()


def tile_order(size):
    """Where pixel (row, col) of a picture goes in a 3DS texture: 8x8 tiles from the
    bottom row up, Morton order inside a tile. Returns the flat index per pixel."""
    y, x = np.mgrid[0:size, 0:size]
    yf = size - 1 - y
    tile = (yf // 8) * (size // 8) + x // 8
    xs, ys = x & 7, yf & 7
    morton = ((xs & 1) | ((ys & 1) << 1) | ((xs & 2) << 1) | ((ys & 2) << 2)
              | ((xs & 4) << 2) | ((ys & 4) << 3))
    return tile * 64 + morton


def mip_levels(img, nearest=False):
    """The picture at TEX, TEX/2, ... down to 8 (the 3DS mipmap levels); region indices
    are picked, not mixed."""
    from PIL import Image
    out, size = [img], img.shape[0]
    while size > 8:
        size //= 2
        if nearest:
            step = img.shape[0] // size
            out.append(img[step // 2::step, step // 2::step].copy())
        else:
            out.append(np.asarray(Image.fromarray(img).resize((size, size), Image.LANCZOS)))
    return out


def tiled(img):
    """The picture's bytes in the 3DS texture order."""
    size = img.shape[0]
    flat = img.reshape(size * size, -1)
    out = np.empty_like(flat)
    out[tile_order(size).ravel()] = flat
    return out.tobytes()


def tint_colors(m, regions):
    """Per region: the colour the 3DS multiplies the paper by (white for the sea)."""
    out = []
    for r in regions:
        if r["kind"] == KIND_SEA:
            out.append((255, 255, 255))
        elif r["kind"] == KIND_NEUTRAL or r["owner"] < 0:
            out.append(NEUTRAL_RGB)
        else:
            out.append(tuple(int(TINT * c + (1 - TINT) * 255) for c in m2.FACTIONS[r["owner"]][1]))
    return out


def write(path, m, regions, tex_path=None, tex=None):
    """map3d.bin (and map_tex.bin with the picture), see docs/FORMATS.md."""
    rows, cols = m["province"].shape
    nv = sum(len(r["verts"]) for r in regions)
    ni = sum(len(r["idx"]) for r in regions)
    head = struct.pack("<4sHHHHIIIf", b"HM3D", 3, len(regions), m["land"], len(m2.FACTIONS),
                       nv, ni, TEX, float(cols))
    for fname, col in m2.FACTIONS:
        head += struct.pack("<BBBx16s", *col, fname.encode())
    nlist, v0, i0 = b"", 0, 0
    for r in regions:
        head += struct.pack("<hbbB3x24s6f6I", r["id"], r["kind"], r["owner"], len(r["neigh"]),
                            r["name"].encode()[:23], r["cx"], r["cz"], *r["box"],
                            v0, len(r["verts"]), i0, len(r["idx"]), r["top"], 0)
        nlist += struct.pack("<%dh" % len(r["neigh"]), *r["neigh"])
        v0 += len(r["verts"])
        i0 += len(r["idx"])
    if len(nlist) % 4:
        nlist += b"\0\0"
    verts = b"".join(struct.pack("<4f", *v) for r in regions for v in r["verts"])
    idx = b"".join(struct.pack("<%dH" % len(r["idx"]), *r["idx"]) for r in regions)
    if len(idx) % 4:
        idx += b"\0\0"
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(head + nlist + verts + idx)
    if tex_path:
        rgb, ids = tex
        with open(tex_path, "wb") as f:
            f.write(b"".join(tiled(level) for level in mip_levels(rgb)))
            f.write(b"".join(tiled(level) for level in mip_levels(ids, nearest=True)))
    return nv, ni


def write_obj(path, regions):
    """Every region's exact top as an object, to look at in Blender."""
    with open(path, "w", encoding="utf-8") as f:
        base = 1
        for r in regions:
            f.write("o %s_%d\n" % (r["name"].replace(" ", "_") or "neutral", r["id"]))
            for x, y, z, _ in r["verts"]:
                f.write("v %.4f %.4f %.4f\n" % (x, y, -z))
            idx = r["idx"][:r["top"]]
            for t in range(0, len(idx), 3):
                f.write("f %d %d %d\n" % tuple(base + i for i in idx[t:t + 3]))
            base += len(r["verts"])


def preview(path, m, regions, tex):
    """The picture with the owners' colours, as the 3DS shows it from above."""
    from PIL import Image
    rgb, ids = tex
    tint = np.array(tint_colors(m, regions) + [(255, 255, 255)] * (256 - len(regions)), float)
    out = rgb.astype(float) * tint[ids] / 255
    Image.fromarray(out.astype(np.uint8)).save(path)


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
    regions, chains = build(m)
    tex = render_texture(m, regions, chains)
    tex_path = os.path.join(os.path.dirname(a.out), "map_tex.bin")
    nv, ni = write(a.out, m, regions, tex_path, tex)
    print("%s: %d regions (%d land), %d vertices, %d triangles (selection only), texture %d^2"
          % (a.out, len(regions), m["land"], nv, ni // 3, TEX))
    if a.png:
        preview(a.png, m, regions, tex)
    if a.obj:
        write_obj(a.obj, regions)


if __name__ == "__main__":
    main(sys.argv[1:])
