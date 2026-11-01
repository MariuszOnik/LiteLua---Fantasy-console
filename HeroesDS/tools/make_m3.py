"""Makes the political map for the 3DS (the land of make_m2.py, same seed): a flat map
in 3D -- textures where all the detail lives (hand-drawn, fractal borders, the coast's
shadow, paper, waves), TILES x TILES of them plus one of the whole map for far views --
plus, per province and sea zone, its exact shape, drawn only to light up the selected
one. Owners' colours are put on by the 3DS.

  python HeroesDS/tools/make_m3.py [--seed 77] [--size 72] [--provinces 45] [--coast 1]
                                   [--tiles 2] [--out 3ds/romfs] [--png preview.png]
                                   [--obj map.obj]

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
  5. counties: every land province is split into about cells / COUNTY_CELLS counties
     (seeds spread over it, cells to the nearest seed inside the province, Lloyd steps);
     the chains are made on the county grid, so a province's border is its counties'
  6. exact shapes: the top of each region by ear cutting (mapbox_earcut, holes included)
     and a strip inside its border (the selection outline); the counties' shapes for
     the county index of every pixel; the borders between provinces as lines (the 3DS
     draws those between realms -- they change in the game)
  7. the pictures (each TEX x TEX, drawn twice as big and scaled down; one per tile and
     one of the whole map): sea lighter near the shore, the land's shadow on it, waves;
     land as pale paper, darker along its borders; and the county index of every pixel
     (taps on the 3DS) -- both with all mipmap levels, in the 3DS texture order
     (tile_order), zlib-packed. Every level gets its own lines (LINES): the coast always,
     province and sea-zone lines from K_PROVINCE pixels per cell, county lines from
     K_COUNTY -- so the GPU, picking the level by distance, shows less detail far away. Noise and waves are
     laid over the whole map and every tile is drawn with a margin, so tiles meet
     without seams
The file formats are in docs/FORMATS.md ("map3d.bin", "map tiles").
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
ROUGH = {"land": 0.3, "coast": 0.36, "sea": 0.2, "county": 0.25}   # noisy edges: shift / length
MIN_SEG = 0.2         # noisy edges stop at segments this long, in cells
OUTSIDE = -2          # region number of the space outside the grid
NEUTRAL = -1          # land without a province (tiny islets)
OUTLINE = 0.3         # width of the selection outline, in cells
TEX = 1024            # a texture's size (the largest the 3DS has)
NO_REGION = 0xFFFF    # region index of a pixel outside every region
SEA_RGB = (150, 190, 200)
PAPER_RGB = (252, 248, 238)
SEA_LINE = (200, 222, 228)
LAND_LINE = (70, 48, 30)
COAST_LINE = (40, 28, 18)
COUNTY_LINE = (120, 95, 70)
NEUTRAL_RGB = (190, 180, 160)
COUNTY_CELLS = 12     # cells per county (a province is split into about cells / this)
K_PROVINCE = 3.0      # province lines from this many texture pixels per cell on
K_COUNTY = 14.0       # county lines from this many
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
    """Border chains between the cells of a grid of counties, each made once and shared by
    the counties on both sides. prov_of maps a county to its province (region) number."""

    def __init__(self, grid, prov_of, land):
        self.grid = grid
        self.prov_of = prov_of
        self.land = land
        self.info = {}    # key -> (corners, closed, sides: (county walking it this way, other))
        self.cache = {}   # key -> (points, sides)

    @staticmethod
    def key_of(corners, closed):
        if closed:
            i = corners.index(min(corners))
            fwd = corners[i:] + corners[:i]
            rev = fwd[:1] + fwd[1:][::-1]
            return (tuple(min(fwd, rev)), True), fwd > rev
        fwd, rev = corners, corners[::-1]
        return (tuple(min(fwd, rev)), False), fwd > rev

    def get(self, corners, closed, county):
        """Registers the chain; returns its key and whether the county walks it backwards."""
        key, back = self.key_of(corners, closed)
        if key not in self.info:
            seq = list(key[0])
            other = self.across(seq, county)
            self.info[key] = (seq, closed, (county, other) if not back else (other, county))
        return key, back

    def find(self, corners, closed):
        """A chain already registered (a province's border is made of its counties')."""
        key, back = self.key_of(corners, closed)
        assert key in self.info, "province border not on county borders"
        return key, back

    def kind(self, sides):
        """county (inside a province), land (between provinces), coast, sea, edge."""
        if OUTSIDE in sides:
            return "edge"
        pa, pb = (self.prov_of(s) for s in sides)
        if pa == pb:
            return "county"
        land = [p == NEUTRAL or 0 <= p < self.land for p in (pa, pb)]
        return "land" if all(land) else "coast" if any(land) else "sea"

    def provinces(self, key):
        return tuple(self.prov_of(s) for s in self.info[key][2])

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

    def points(self, key, back):
        pts = self.cache[key][0]
        return pts[::-1] if back else pts

    def across(self, seq, county):
        """The county on the other side of the chain's first side."""
        (r1, c1), (r2, c2) = seq[0], seq[1]
        cells = [(min(r1, r2) - (r1 == r2), min(c1, c2) - (c1 == c2)), (min(r1, r2), min(c1, c2))]
        regs = [region_at(self.grid, r, c) for r, c in cells]
        return regs[0] if regs[1] == county else regs[1]


def plan_rings(grid, junc, look):
    """Every region's rings of a grid cut into chains at the junctions:
    [(region, [(key, back, closed)])]; look(corners, closed, region) -> (key, back)."""
    plan = []
    for a, rs in outlines(grid).items():
        if a == OUTSIDE:
            continue
        for ring in rs:
            cut = [i for i, v in enumerate(ring) if v in junc]
            if not cut:
                plan.append((a, [look(ring, True, a) + (True,)]))
                continue
            ring = ring[cut[0]:] + ring[:cut[0]]
            cut = [i - cut[0] for i in cut] + [len(ring)]
            parts = []
            for i, j in zip(cut, cut[1:]):
                seg = ring[i:j + 1] if j < len(ring) else ring[i:] + ring[:1]
                parts.append(look(seg, False, a) + (False,))
            plan.append((a, parts))
    return plan


def assemble(plan, chains):
    """{region: [ring points (N, 2) x, z]} from the made chains."""
    out = {}
    for a, parts in plan:
        if parts[0][2]:
            pts = chains.points(*parts[0][:2])
        else:
            pts = np.vstack([chains.points(key, back)[:-1] for key, back, _ in parts])
        out.setdefault(a, []).append(pts)
    return out


def counties(m, rng):
    """Every land province split into about cells / COUNTY_CELLS counties (seeds spread
    over it, cells to the nearest seed by steps inside the province, a few Lloyd steps);
    a sea zone or land without a province is one county. Returns the county per cell
    (OUTSIDE where no region) and per county its province number."""
    prov = m["province"]
    land = m["land"]
    rows, cols = prov.shape
    grid = np.full(prov.shape, OUTSIDE)
    owner = []
    for p in sorted(int(v) for v in np.unique(prov)):
        cells = [tuple(int(v) for v in c) for c in np.argwhere(prov == p)]
        n = max(1, round(len(cells) / COUNTY_CELLS)) if 0 <= p < land else 1
        if n == 1:
            for r, c in cells:
                grid[r, c] = len(owner)
            owner.append(p)
            continue
        pts = np.array(cells)
        seeds = [cells[int(rng.integers(len(cells)))]]
        dist = np.full(len(cells), 1e9)
        for _ in range(n - 1):
            dist = np.minimum(dist, ((pts - seeds[-1]) ** 2).sum(1))
            seeds.append(cells[int(dist.argmax())])
        inside = set(cells)
        for step in range(4):
            near = {}
            todo = []
            for i, s in enumerate(seeds):
                near[s] = i
                todo.append(s)
            while todo:          # breadth first from all seeds at once
                nxt = []
                for r, c in todo:
                    for q in m2.neighbours4(r, c, rows, cols):
                        if q in inside and q not in near:
                            near[q] = near[(r, c)]
                            nxt.append(q)
                todo = nxt
            if step == 3:
                break
            for i in range(len(seeds)):
                mine = np.array([q for q in cells if near[q] == i])
                mid = mine.mean(0)
                seeds[i] = tuple(int(v) for v in mine[((mine - mid) ** 2).sum(1).argmin()])
            seeds = list(dict.fromkeys(seeds))
        first = len(owner)
        used = sorted(set(near.values()))
        renum = {i: first + k for k, i in enumerate(used)}
        for q in cells:
            grid[q] = renum[near[q]]
        owner += [p] * len(used)
    return grid, owner


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
    """Regions (provinces, sea zones, land without a province): name, owner, label point,
    the exact top (triangles) and an outline strip inside its border -- both only drawn
    for the selected region. Counties: region, name, label point, exact shape (for the
    pictures). Borders between provinces as lines (the 3DS draws the ones between
    realms). The map itself is textures (Painter)."""
    prov = m["province"].copy()
    land = m["land"]
    rng = np.random.default_rng(m["seed"] + 77)
    cgrid, cprov = counties(m, rng)
    chains = Chains(cgrid, lambda c: OUTSIDE if c == OUTSIDE else cprov[c], land)
    junc = junctions(cgrid)
    cplan = plan_rings(cgrid, junc, chains.get)
    pplan = plan_rings(prov, junc, lambda corners, closed, a: chains.find(corners, closed))
    chains.make()
    crings = assemble(cplan, chains)
    rings = assemble(pplan, chains)
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
                            verts=verts, idx=idx, top=top, neigh=neigh))
    index = {r["id"]: i for i, r in enumerate(regions)}

    county_list = []
    for c, p in enumerate(cprov):
        pts2, tris = triangulate(crings[c])
        cells = np.argwhere(cgrid == c)
        mid = cells.mean(0)
        r, col = cells[((cells - mid) ** 2).sum(1).argmin()]
        reg = regions[index[p]]
        own = 0 <= p < land and (cprov.count(p) > 1)
        county_list.append(dict(region=index[p], name=m2.name(rng) if own else reg["name"],
                                cx=col + 0.5 - off[0], cz=r + 0.5 - off[1],
                                pts=pts2 - off, tris=tris))

    borders = []
    for key, (pts, _) in chains.cache.items():
        if chains.kind(chains.info[key][2]) != "land":
            continue
        pa, pb = chains.provinces(key)
        borders.append(dict(a=index[pa], b=index[pb], pts=pts - off, closed=key[1]))
    return regions, county_list, borders, chains


def line_normals(p, closed):
    """Per point: the unit side normal, mitred (limited) where the line bends."""
    q = np.vstack([p, p[:1]]) if closed else p
    d = np.diff(q, axis=0)
    d /= np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)[:, None]
    seg_n = np.stack([-d[:, 1], d[:, 0]], 1)
    vn = np.zeros((len(p), 2))
    if closed:
        vn += seg_n + np.roll(seg_n, 1, 0)
    else:
        vn[:-1] += seg_n
        vn[1:] += seg_n
    vn /= np.maximum(np.hypot(vn[:, 0], vn[:, 1]), 1e-9)[:, None]
    near = np.vstack([seg_n, seg_n[-1:]])[:len(p)]
    cos = np.abs((vn * near).sum(1))
    return vn / np.maximum(cos, 0.5)[:, None]


def ring_inset(p, w):
    """The ring's points moved w inward (into the region the ring belongs to)."""
    return p + line_normals(p, True) * w


def blur(a, radius):
    from PIL import Image, ImageFilter
    img = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return np.asarray(img.filter(ImageFilter.GaussianBlur(radius)), float) / 255


class Noise:
    """Smooth noise -0.5..0.5 over the whole map: a random grid every `period` cells,
    read bilinearly at any place, so neighbouring tiles match at their edges."""

    def __init__(self, rng, world, period):
        self.period = period
        n = int(world / period) + 3
        self.grid = rng.random((n, n)) - 0.5

    def at(self, xs, zs):
        u, v = xs / self.period, zs / self.period
        i, j = np.floor(u).astype(int), np.floor(v).astype(int)
        fu, fv = u - i, v - j
        g = self.grid
        i = np.clip(i, 0, g.shape[1] - 2)
        j = np.clip(j, 0, g.shape[0] - 2)
        return ((g[j, i] * (1 - fu) + g[j, i + 1] * fu) * (1 - fv)
                + (g[j + 1, i] * (1 - fu) + g[j + 1, i + 1] * fu) * fv)


# lines: width in cells, least width in pixels of the level, colour, from how many pixels
# per cell of a mipmap level on they are drawn (coarser levels -- far views -- leave
# county and then province lines out; realms' borders are drawn by the 3DS)
LINES = {
    "sea":    (0.07, 0.7, SEA_LINE, K_PROVINCE),
    "county": (0.06, 0.8, COUNTY_LINE, K_COUNTY),
    "land":   (0.11, 1.0, LAND_LINE, K_PROVINCE),
    "coast":  (0.15, 1.2, COAST_LINE, 0.0),
}


class Painter:
    """Draws any square window of the map (a tile, or the whole map small): the picture
    without owners' colours and the county index per pixel, every mipmap level with the
    lines that suit its scale."""

    def __init__(self, m, county_list, chains):
        self.m, self.counties, self.chains = m, county_list, chains
        rows, cols = m["province"].shape
        self.world = cols
        self.off = np.array([cols / 2, rows / 2])
        rng = np.random.default_rng(m["seed"] + 1000)
        self.big_noise = Noise(rng, cols, 3.5)
        self.grain = Noise(rng, cols, 0.5)
        # wave marks: (x, z, size) in cells, kept or dropped per window by the shore
        n = int(cols * rows / 9)
        self.waves = np.column_stack([rng.uniform(0, cols, n), rng.uniform(0, rows, n),
                                      rng.uniform(0.7, 1.2, n)])
        self.lines = [(chains.kind(sides), pts, key[1]) for key, (pts, sides) in chains.cache.items()]
        self.lines = [ln for ln in self.lines if ln[0] != "edge"]

    def paint(self, x0, z0, span, size, land_counties, ss=2):
        """Window [x0, x0 + span] x [z0, z0 + span] (cells, from the grid's corner) at
        size x size pixels. Returns (rgb levels [(s, s, 3) uint8, s = size .. 8], county
        index levels [(s, s) uint16]; NO_REGION = none)."""
        from PIL import Image, ImageDraw
        k = size * ss / span                  # pixels per cell, while drawing level 0
        pad = int(np.ceil(3.0 * k))           # blurs and shadows reach over the edge
        big = size * ss + 2 * pad
        ox, oz = x0 - pad / k, z0 - pad / k   # cell at pixel (0, 0)
        x1, z1 = ox + big / k, oz + big / k

        def px(x, z):
            return (x - ox) * k, (z - oz) * k

        ids = Image.new("I", (big, big), NO_REGION)
        d = ImageDraw.Draw(ids)
        for i, c in enumerate(self.counties):
            p = c["pts"] + self.off
            if p[:, 0].max() < ox or p[:, 0].min() > x1 or p[:, 1].max() < oz or p[:, 1].min() > z1:
                continue
            for t in c["tris"]:
                d.polygon([px(*p[q]) for q in t], fill=i)
        ids_big = np.asarray(ids, np.int64)
        land = np.isin(ids_big, land_counties).astype(float)

        # borders of land (coast and between provinces), for the paper's darker edges
        edge = Image.new("L", (big, big), 0)
        ed = ImageDraw.Draw(edge)
        for kind, pts, closed in self.lines:
            if kind in ("land", "coast"):
                xy = [px(float(x), float(z)) for x, z in pts]
                ed.line(xy + xy[:1] if closed else xy, fill=255, width=max(1, round(0.12 * k)), joint="curve")
        edges = blur(np.asarray(edge, float) / 255, 0.35 * k)

        cx = ox + (np.arange(big) + 0.5) / k
        cz = oz + (np.arange(big) + 0.5) / k
        xs, zs = np.meshgrid(cx, cz)
        noise = self.big_noise.at(xs, zs)
        grain = self.grain.at(xs, zs)

        # sea: blue-green, lighter near the shore, the land's shadow, waves far out
        near = blur(land, 0.9 * k)
        sea = np.empty((big, big, 3))
        sea[:] = SEA_RGB
        sea += noise[..., None] * 10
        sea += (np.array((235, 240, 225)) - sea) * np.clip(near * 1.6, 0, 1)[..., None] * 0.55
        shadow = np.roll(blur(land, 0.18 * k), (round(0.22 * k), round(0.22 * k)), (0, 1))
        sea *= (1 - 0.35 * np.clip(shadow, 0, 1))[..., None]
        waves = Image.new("L", (big, big), 0)
        wd = ImageDraw.Draw(waves)
        inside = ((self.waves[:, 0] > ox - 2) & (self.waves[:, 0] < x1) & (self.waves[:, 1] > oz - 2)
                  & (self.waves[:, 1] < z1))
        for wx, wz, ws in self.waves[inside]:
            x, y = px(wx, wz)
            if 0 <= x < big and 0 <= y < big and near[int(y), int(x)] > 0.04:
                continue
            w = k * ws
            for s in (0, 1):
                wd.arc((x + s * w, y, x + (s + 1) * w, y + w * 0.6), 200 if s == 0 else 20,
                       340 if s == 0 else 160, fill=255, width=max(1, round(0.06 * k)))
        sea *= (1 - 0.18 * np.asarray(waves, float) / 255)[..., None]

        # land: pale paper with grain, a little darker along its borders
        paper = np.empty((big, big, 3))
        paper[:] = PAPER_RGB
        paper *= (1 + 0.05 * grain + 0.04 * noise)[..., None]
        paper *= (1 - 0.22 * np.clip(edges * 2, 0, 1))[..., None]

        base = sea * (1 - land[..., None]) + paper * land[..., None]
        base = base[pad:pad + size * ss, pad:pad + size * ss]
        base = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8))
        ids_big = ids_big[pad:pad + size * ss, pad:pad + size * ss]
        ids0 = ids_big[ss // 2::ss, ss // 2::ss].astype(np.uint16)

        # every level: the background scaled, then its own lines on top
        levels, s = [], size
        while True:
            kl = s * ss / span                  # drawing pixels per cell at this level
            img = np.asarray(base.resize((s * ss, s * ss), Image.LANCZOS), float)
            for kind in ("sea", "county", "land", "coast"):
                width, least, col, k_from = LINES[kind]
                if s / span < k_from:
                    continue
                mask = Image.new("L", (s * ss, s * ss), 0)
                md = ImageDraw.Draw(mask)
                w = max(least * ss, width * kl)
                for kd, pts, closed in self.lines:
                    if kd != kind:
                        continue
                    if (pts[:, 0].max() < x0 - 1 or pts[:, 0].min() > x0 + span + 1
                            or pts[:, 1].max() < z0 - 1 or pts[:, 1].min() > z0 + span + 1):
                        continue
                    xy = [((x - x0) * kl, (z - z0) * kl) for x, z in pts]
                    md.line(xy + xy[:1] if closed else xy, fill=255, width=max(1, round(w)), joint="curve")
                a = np.asarray(mask, float)[..., None] / 255
                img = img * (1 - a) + np.array(col, float) * a
            img = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((s, s), Image.LANCZOS)
            levels.append(np.asarray(img))
            if s <= 8:
                break
            s //= 2
        return levels, mip_levels(ids0, nearest=True)


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
    """The picture at its size, half, ... down to 8 (the 3DS mipmap levels); indices
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


def rgb565(img):
    r, g, b = (img[..., i].astype(np.uint16) for i in range(3))
    return ((r >> 3) << 11 | (g >> 2) << 5 | (b >> 3)).astype("<u2")


def write_tile(path, rgb_levels, id_levels):
    """One texture with all mipmap levels: zlib(paper RGB565) and zlib(county index u16),
    see docs/FORMATS.md ("map tiles")."""
    paper = b"".join(tiled(rgb565(level)) for level in rgb_levels)
    index = b"".join(tiled(level.astype("<u2")) for level in id_levels)
    with open(path, "wb") as f:
        f.write(b"HT01")
        for raw in (paper, index):
            packed = zlib.compress(raw, 9)
            f.write(struct.pack("<II", len(raw), len(packed)) + packed)
            if len(packed) % 4:
                f.write(b"\0" * (4 - len(packed) % 4))


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


def write(path, m, regions, county_list, borders, tiles=1):
    """map3d.bin, see docs/FORMATS.md."""
    rows, cols = m["province"].shape
    nv = sum(len(r["verts"]) for r in regions)
    ni = sum(len(r["idx"]) for r in regions)
    head = struct.pack("<4sHHHHIIIfHH", b"HM3D", 5, len(regions), m["land"], len(m2.FACTIONS),
                       nv, ni, TEX, float(cols), tiles, len(county_list))
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
    for c in county_list:
        head += struct.pack("<H2x20sff", c["region"], c["name"].encode()[:19], c["cx"], c["cz"])
    if len(nlist) % 4:
        nlist += b"\0\0"
    verts = b"".join(struct.pack("<4f", *v) for r in regions for v in r["verts"])
    idx = b"".join(struct.pack("<%dH" % len(r["idx"]), *r["idx"]) for r in regions)
    if len(idx) % 4:
        idx += b"\0\0"
    # borders between provinces as triangle strips: per point (x, z, nx, nz) on both sides
    table, strips, start = b"", [], 0
    for b in borders:
        p = b["pts"]
        if b["closed"]:
            p = np.vstack([p, p[:1]])
        n = line_normals(p, False)
        for (x, z), (nx, nz) in zip(p, n):
            strips.append(struct.pack("<4f", x, z, nx, nz))
            strips.append(struct.pack("<4f", x, z, -nx, -nz))
        table += struct.pack("<HHII", b["a"], b["b"], start, 2 * len(p))
        start += 2 * len(p)
    lines = struct.pack("<II", len(borders), start) + table + b"".join(strips)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as f:
        f.write(head + nlist + verts + idx + lines)
    return nv, ni


def write_textures(folder, m, regions, county_list, chains, tiles, png=None):
    """overview.bin (the whole map in one texture) and tiles/<col>_<row>.bin."""
    painter = Painter(m, county_list, chains)
    land = [i for i, c in enumerate(county_list) if regions[c["region"]]["kind"] != KIND_SEA]
    world = painter.world
    tdir = os.path.join(folder, "tiles")
    os.makedirs(tdir, exist_ok=True)
    for fname in os.listdir(tdir):
        os.remove(os.path.join(tdir, fname))
    over = painter.paint(0, 0, world, TEX, land)
    write_tile(os.path.join(folder, "overview.bin"), *over)
    span = world / tiles
    full = None
    if png:
        full = (np.zeros((TEX * tiles, TEX * tiles, 3), np.uint8),
                np.zeros((TEX * tiles, TEX * tiles), np.uint16))
    for ty in range(tiles):
        for tx in range(tiles):
            rgb, ids = painter.paint(tx * span, ty * span, span, TEX, land)
            write_tile(os.path.join(tdir, "%d_%d.bin" % (tx, ty)), rgb, ids)
            if full:
                full[0][ty * TEX:(ty + 1) * TEX, tx * TEX:(tx + 1) * TEX] = rgb[0]
                full[1][ty * TEX:(ty + 1) * TEX, tx * TEX:(tx + 1) * TEX] = ids[0]
            print("  tile %d,%d" % (tx, ty), flush=True)
    if png:
        preview(png, m, regions, county_list, full)
        base, ext = os.path.splitext(png)
        for lv in (0, 1, 2):   # the overview's levels: what far views show
            preview(base + "_over%d" % lv + ext, m, regions, county_list, (over[0][lv], over[1][lv]))


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


def preview(path, m, regions, county_list, tex):
    """The picture with the owners' colours, as the 3DS shows it from above."""
    from PIL import Image
    rgb, ids = tex
    region_tint = tint_colors(m, regions)
    tint = np.full((NO_REGION + 1, 3), 255.0)
    tint[:len(county_list)] = [region_tint[c["region"]] for c in county_list]
    out = rgb.astype(float) * tint[ids] / 255
    Image.fromarray(out.astype(np.uint8)).save(path)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--seed", type=int, default=77)
    p.add_argument("--size", type=int, default=72)
    p.add_argument("--provinces", type=int, default=45)
    p.add_argument("--coast", type=float, default=1.0)
    p.add_argument("--tiles", type=int, default=2, help="textures per side of the map")
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    p.add_argument("--out", default=os.path.join(here, "3ds", "romfs"), help="romfs folder")
    p.add_argument("--png", help="preview of the full-size picture with owners' colours")
    p.add_argument("--obj", help="also write a Wavefront .obj (one object per region) for Blender")
    a = p.parse_args(argv)
    m = m2.generate(a.seed, a.size, a.provinces, a.coast)
    regions, county_list, borders, chains = build(m)
    assert len(county_list) < NO_REGION
    for old in ("map_tex.bin",):
        if os.path.exists(os.path.join(a.out, old)):
            os.remove(os.path.join(a.out, old))
    nv, ni = write(os.path.join(a.out, "map3d.bin"), m, regions, county_list, borders, a.tiles)
    print("%s: %d regions (%d land), %d counties, %d province borders, %d vertices, "
          "%dx%d tiles of %d^2" % (a.out, len(regions), m["land"], len(county_list), len(borders),
                                   nv, a.tiles, a.tiles, TEX), flush=True)
    write_textures(a.out, m, regions, county_list, chains, a.tiles, a.png)
    if a.obj:
        write_obj(a.obj, regions)


if __name__ == "__main__":
    main(sys.argv[1:])
