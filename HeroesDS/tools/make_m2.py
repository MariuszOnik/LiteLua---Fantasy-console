"""Makes an invented piece of land split into provinces (the political map, Imperial Glory
style): height map, terrain, provinces, neighbours, names and owners -- all from one seed.

  python HeroesDS/tools/make_m2.py [--seed N] [--size 72] [--provinces 45] [--png out]
                                   [--cart] [--sd DIR]

Steps (all on a rows x cols grid of cells; corners are (rows + 1) x (cols + 1)):
  1. heights: value noise in octaves, lowered toward the edges -> land in the middle, sea
     around it; sea level so that about LAND of the inner cells are land. The grid has a
     MARGIN of open sea on every side: the land fades out before it (an extra pull down
     near the inner edge), so coastal provinces are not cut by the map edge and fleets
     can sail round. --coast (0..1) makes
     the shore more broken: the noise is read at places shifted by another noise
     (domain warping: bays, peninsulas, capes), its middle octaves count more and the
     edges pull down less (more islands and inlets)
  2. terrain by height: sea, beach, lowland, upland, mountain (snow on the peaks)
  3. provinces: capitals spread over the land (farthest-point sampling), every land cell
     goes to the capital it reaches cheapest -- climbing costs more, so borders follow
     ridges; then RELAX times each capital moves to the land cell nearest the middle of
     its province and the land is shared out again (Lloyd), so provinces get even and
     capitals sit inside; provinces under MIN_CELLS, or thin ones (fewer than MIN_CORE
     cells with all eight neighbours in the province: strips along a coast or a ridge),
     join the neighbour they share most border with
  4. neighbours (cells touching across an edge), names from syllables, owners: the six
     H4 factions, each growing a compact realm from a seed province
  5. sea zones: the sea is shared out the same way into zones of about SEA_ZONE_CELLS
     cells without an owner (fleets, transports, trade); they are numbered after the
     land provinces,
     and their neighbours are the next zones and the coastal provinces (ports)
--png writes a preview: the political view (land tinted with the owner, borders) next to
the natural one. --style picks how the land looks:
  relief  heights from the terrain, shaded slopes (default)
  flat    a paper map: no heights, pale owner colours on parchment, sea light blue
  board   a table model: every province a flat plate raised over the sea, its edges
          bevelled down, so the borders are grooves between the plates

--cart writes the cart carts/m2 (no game data in it):
  gfx/paper.png   16x16 frames of light grain (land: paper, sea: waves); frame
                  (base * GRAIN + variant) * 9 + top * 3 + left, where top / left is the
                  line on the cell's -row / -col side: 0 none, 1 ink (a land border or
                  the coast), 2 light blue (between sea zones). The line is part of the
                  frame, so every border is drawn once, by one cell
  data/map.lua    size, corner heights 0..255, terrain per cell, province per cell
                  (-1 none), frame per cell, provinces (name, capital, owner,
                  neighbours), the factions' colours and the corner colours of both
                  views (paper, relief) -- the same formulas as the cart's, which
                  recolours a province when its owner changes
"""
import argparse
import heapq
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

LAND = 0.55            # share of the cells that are land
RELAX = 4              # Lloyd steps for the provinces
MIN_CELLS = 20         # smaller provinces join a neighbour
MIN_CORE = 4           # thinner land provinces join a neighbour too
MARGIN = 6             # open sea around the land, in cells (on every side)
EDGE_FADE = 0.85       # the land starts fading at this part of the way to the inner edge
EDGE_PULL = 0.35       # how far down the fade pulls at the inner edge
SEA_ZONE_CELLS = 110   # sea cells per zone (before merging small ones): a fleet sails
                       # 2 zones a turn, so smaller zones mean more places to go
MIN_SEA_CELLS = 40
SEA, BEACH, LOW, UP, MOUNT = range(5)
TERRAIN = ["sea", "beach", "lowland", "upland", "mountain"]
FACTIONS = [            # name, color (H4: Life, Order, Death, Chaos, Nature, Might)
    ("Life", (230, 230, 240)), ("Order", (60, 110, 220)), ("Death", (120, 60, 150)),
    ("Chaos", (210, 50, 40)), ("Nature", (60, 170, 70)), ("Might", (220, 160, 40)),
]
SYLLABLES = ["ar", "bel", "cor", "dal", "en", "fal", "gor", "hal", "is", "kar", "lor", "mar",
             "nor", "or", "pel", "ran", "sil", "tor", "ul", "val", "wen", "yr", "zan", "eth",
             "ia", "on", "ost", "mir", "dun", "gal"]


def noise(rng, shape, octaves=5, warp=None, gain=0.5):
    """Value noise in [0, 1]: bilinear random grids, each octave twice as fine. warp:
    (dy, dx) arrays in [0, 1) of the shape: where each point reads the noise, shifted by
    up to that fraction of the grid. gain: how much each finer octave counts."""
    h, w = shape
    out = np.zeros(shape)
    amp, total = 1.0, 0.0
    y0 = np.linspace(0, 1, h, endpoint=False)[:, None] + np.zeros((1, w))
    x0 = np.linspace(0, 1, w, endpoint=False)[None, :] + np.zeros((h, 1))
    if warp is not None:
        y0, x0 = (y0 + warp[0]) % 1, (x0 + warp[1]) % 1
    for o in range(octaves):
        n = 2 ** (o + 2)
        g = rng.random((n + 1, n + 1))
        y, x = y0 * n, x0 * n
        yi, xi = y.astype(int), x.astype(int)
        fy, fx = y - yi, x - xi
        fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)       # smoothstep
        a, b = g[yi, xi], g[yi, xi + 1]
        c, d = g[yi + 1, xi], g[yi + 1, xi + 1]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        total += amp
        amp *= gain
    return out / total


def heights(rng, rows, cols, coast=0.0, margin=0):
    """Corner heights 0..1 (sea level at 0) and the cell heights over sea level, on a
    grid of rows x cols cells inside a margin of open sea (the grid is margin cells
    bigger on every side)."""
    R, C = rows + 2 * margin, cols + 2 * margin
    shape = (R + 1, C + 1)
    warp = None
    if coast > 0:
        warp = (noise(rng, shape, 3) * 0.35 * coast, noise(rng, shape, 3) * 0.35 * coast)
    h = noise(rng, shape, warp=warp, gain=0.5 + 0.15 * coast)
    y, x = np.mgrid[0:R + 1, 0:C + 1]
    # 0 in the middle, 1 at the inner edge (more out in the margin)
    d = np.maximum(np.abs((y - margin) / rows - 0.5), np.abs((x - margin) / cols - 0.5)) * 2
    h = h - (0.55 - 0.2 * coast) * d ** 2
    if margin:
        h = h - EDGE_PULL * (np.maximum(0, d - EDGE_FADE) / (1 - EDGE_FADE)) ** 2
    cells = (h[:-1, :-1] + h[1:, :-1] + h[:-1, 1:] + h[1:, 1:]) / 4
    sea = np.quantile(cells, 1 - LAND * rows * cols / (R * C))
    h = (h - sea) / (h.max() - sea)
    cells = cells - sea
    if margin:
        # whatever still rises in the margin sinks: the margin is open sea
        out = np.ones((R, C), bool)
        out[margin:R - margin, margin:C - margin] = False
        cells[out] = np.minimum(cells[out], -1e-3)
        corner_out = np.ones(shape, bool)
        corner_out[margin + 1:R - margin, margin + 1:C - margin] = False
        h[corner_out] = np.minimum(h[corner_out], 0)
    return h, cells


def terrain(cell_h):
    t = np.full(cell_h.shape, LOW)
    top = cell_h.max()
    t[cell_h <= 0] = SEA
    t[(cell_h > 0) & (cell_h < 0.04 * top)] = BEACH
    t[cell_h >= 0.45 * top] = UP
    t[cell_h >= 0.72 * top] = MOUNT
    return t


def neighbours4(r, c, rows, cols):
    for dr, dc in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        if 0 <= r + dr < rows and 0 <= c + dc < cols:
            yield r + dr, c + dc


def provinces(rng, terr, cell_h, count, sea=False):
    """Province number per cell (-1 = not shared out) and the capitals: the land, or
    with sea=True the sea (zones)."""
    rows, cols = terr.shape
    land = [(r, c) for r in range(rows) for c in range(cols) if (terr[r, c] == SEA) == sea]
    # capitals: farthest-point sampling over the land, starting anywhere
    caps = [land[rng.integers(len(land))]]
    dist = np.full(len(land), 1e9)
    pts = np.array(land)
    for _ in range(count - 1):
        dist = np.minimum(dist, ((pts - caps[-1]) ** 2).sum(1))
        caps.append(tuple(int(v) for v in pts[int(dist.argmax())]))
    for _ in range(RELAX):
        prov = share(terr, cell_h, caps, sea)
        caps = [middle(prov, i, caps[i]) for i in range(len(caps))]
    prov = share(terr, cell_h, caps, sea)
    return merge_small(prov, caps, MIN_SEA_CELLS if sea else MIN_CELLS, 0 if sea else MIN_CORE)


def middle(prov, i, old):
    """The cell of province i nearest its centre of mass."""
    cells = np.argwhere(prov == i)
    if len(cells) == 0:
        return old
    mid = cells.mean(0)
    r, c = cells[int(((cells - mid) ** 2).sum(1).argmin())]
    return int(r), int(c)


def core_sizes(prov, n):
    """Per province: its cells whose eight neighbours are all in it too."""
    rows, cols = prov.shape
    p = np.pad(prov, 1, constant_values=-1)
    inner = prov >= 0
    for dr in (-1, 0, 1):
        for dc in (-1, 0, 1):
            inner &= p[1 + dr:1 + dr + rows, 1 + dc:1 + dc + cols] == prov
    return np.bincount(prov[inner], minlength=n)


def merge_small(prov, caps, min_cells, min_core=0):
    """Provinces under min_cells, or with a core (core_sizes) under min_core, join the
    neighbour they share most border with (islets without one keep no province); the
    rest are renumbered from 0."""
    while True:
        sizes = np.bincount(prov[prov >= 0], minlength=len(caps))
        cores = core_sizes(prov, len(caps)) if min_core else sizes
        small = [i for i in range(len(caps))
                 if 0 < sizes[i] and (sizes[i] < min_cells or cores[i] < min_core)]
        if not small:
            break
        i = min(small, key=lambda k: (cores[k], sizes[k]))
        border = {}
        for r, c in np.argwhere(prov == i):
            for r2, c2 in neighbours4(r, c, *prov.shape):
                j = prov[r2, c2]
                if j >= 0 and j != i:
                    border[j] = border.get(j, 0) + 1
        prov[prov == i] = max(border, key=border.get) if border else -1
    keep = [i for i in range(len(caps)) if (prov == i).any()]
    renum = np.full(len(caps) + 1, -1)
    for k, i in enumerate(keep):
        renum[i] = k
    prov = np.where(prov >= 0, renum[prov], -1)
    caps = [middle(prov, k, caps[i]) for k, i in enumerate(keep)]
    return prov, caps


def share(terr, cell_h, caps, sea=False):
    """Every land cell (sea cell) to the capital it reaches cheapest: a step costs
    1 + climbing on land, 1 at sea."""
    rows, cols = terr.shape
    best = np.full(terr.shape, np.inf)
    prov = np.full(terr.shape, -1)
    heap = [(0.0, i, r, c) for i, (r, c) in enumerate(caps)]
    for _, i, r, c in heap:
        best[r, c] = 0
        prov[r, c] = i
    heapq.heapify(heap)
    while heap:
        cost, i, r, c = heapq.heappop(heap)
        if cost > best[r, c]:
            continue
        for r2, c2 in neighbours4(r, c, rows, cols):
            if (terr[r2, c2] == SEA) != sea:
                continue
            step = 1 if sea else 1 + 12 * max(0.0, cell_h[r2, c2] - cell_h[r, c]) + 4 * (terr[r2, c2] == MOUNT)
            if cost + step < best[r2, c2]:
                best[r2, c2] = cost + step
                prov[r2, c2] = i
                heapq.heappush(heap, (cost + step, i, r2, c2))
    return prov


def adjacency(prov):
    rows, cols = prov.shape
    adj = {}
    for r in range(rows):
        for c in range(cols):
            a = prov[r, c]
            for r2, c2 in ((r + 1, c), (r, c + 1)):
                if r2 < rows and c2 < cols:
                    b = prov[r2, c2]
                    if a >= 0 and b >= 0 and a != b:
                        adj.setdefault(a, set()).add(b)
                        adj.setdefault(b, set()).add(a)
    return adj


def owners(rng, n, adj, caps, by_sea=None):
    """The six factions grow realms from far-apart provinces, one province at a time.
    A province the realms cannot reach by land (an island) goes to the owner of the
    nearest capital across one of its sea zones (by_sea: province -> provinces sharing a
    sea zone with it); only one without any gets a random owner."""
    owner = [-1] * n
    # the realms start on the biggest piece of land, so none is stuck on an island
    main, seen = [], set()
    for start in range(n):
        if start in seen:
            continue
        part, todo = [], [start]
        seen.add(start)
        while todo:
            a = todo.pop()
            part.append(a)
            for b in adj.get(a, ()):
                if b not in seen:
                    seen.add(b)
                    todo.append(b)
        if len(part) > len(main):
            main = sorted(part)
    seeds = [main[int(rng.integers(len(main)))]]
    while len(seeds) < len(FACTIONS):
        far = max(main, key=lambda i: min((caps[i][0] - caps[s][0]) ** 2
                                              + (caps[i][1] - caps[s][1]) ** 2 for s in seeds))
        seeds.append(far)
    fronts = []
    for f, s in enumerate(seeds):
        owner[s] = f
        fronts.append([s])
    changed = True
    while changed:
        changed = False
        for f in range(len(FACTIONS)):
            grow = [b for a in fronts[f] for b in adj.get(a, ()) if owner[b] < 0]
            if grow:
                b = grow[int(rng.integers(len(grow)))]
                owner[b] = f
                fronts[f].append(b)
                changed = True
    left = [i for i in range(n) if owner[i] < 0]
    while left and by_sea:
        done = False
        for i in left:
            near = [j for j in by_sea.get(i, ()) if owner[j] >= 0]
            if near:
                j = min(near, key=lambda j: (caps[i][0] - caps[j][0]) ** 2 + (caps[i][1] - caps[j][1]) ** 2)
                owner[i] = owner[j]
                done = True
        left = [i for i in range(n) if owner[i] < 0]
        if not done:
            break
    return [o if o >= 0 else int(rng.integers(len(FACTIONS))) for o in owner]


def name(rng):
    n = int(rng.integers(2, 4))
    s = "".join(SYLLABLES[int(rng.integers(len(SYLLABLES)))] for _ in range(n))
    return s.capitalize()


def generate(seed=1, size=72, count=45, coast=0.0):
    rng = np.random.default_rng(seed)
    h, cell_h = heights(rng, size, size, coast, MARGIN)
    terr = terrain(cell_h)
    size = size + 2 * MARGIN
    prov, caps = provinces(rng, terr, cell_h, count)
    land_adj = adjacency(prov)
    names = [name(rng) for _ in caps]
    n = len(caps)
    zones, centres = provinces(rng, terr, cell_h, max(1, int((terr == SEA).sum()) // SEA_ZONE_CELLS), sea=True)
    prov = np.where(zones >= 0, zones + n, prov)
    adj = adjacency(prov)
    by_sea = {i: {j for z in adj.get(i, ()) if z >= n for j in adj.get(z, ()) if j < n and j != i}
              for i in range(n)}
    own = owners(rng, n, land_adj, caps, by_sea)
    caps = caps + centres
    own = own + [-1] * len(centres)
    names = names + [name(rng) + " Sea" for _ in centres]
    return dict(seed=seed, coast=coast, rows=size, cols=size, heights=h, cell_h=cell_h, terrain=terr,
                province=prov, capitals=caps, neighbours=adj, owner=own, names=names, land=n)


NATURE = {SEA: (40, 80, 150), BEACH: (205, 190, 130), LOW: (95, 140, 60), UP: (125, 120, 70),
          MOUNT: (150, 140, 130)}


PARCHMENT = np.array((226, 210, 170), float)
PAPER_SEA = (170, 195, 205)


def board_heights(m):
    """Corner heights of the table model: 1 inside a province, lower on its edge (a
    corner touching another province or the sea), 0 out at sea."""
    prov = m["province"]
    rows, cols = prov.shape
    h = np.zeros((rows + 1, cols + 1))
    for r in range(rows + 1):
        for c in range(cols + 1):
            around = {prov[rr, cc] for rr in (r - 1, r) for cc in (c - 1, c)
                      if 0 <= rr < rows and 0 <= cc < cols}
            land = {p for p in around if p >= 0}
            if not land:
                h[r, c] = 0
            elif len(around) == 1:
                h[r, c] = 1
            else:
                h[r, c] = 0.55 if len(land) == 1 and -1 not in around else 0.3
    return h


def cell_color(m, r, c, political, style="relief"):
    t = m["terrain"][r, c]
    p = m["province"][r, c]
    if style == "flat":
        if t == SEA:
            return PAPER_SEA
        col = PARCHMENT.copy()
        if political and m["owner"][p] >= 0:
            col = col * 0.5 + np.array(FACTIONS[m["owner"][p]][1]) * 0.5
        if t == MOUNT:
            col *= 0.82
        elif t == UP:
            col *= 0.93
        return tuple(int(v) for v in col)
    if style == "board":
        if t == SEA:
            col = np.array(NATURE[SEA], float)
        elif political and p >= 0 and m["owner"][p] >= 0:
            col = np.array(FACTIONS[m["owner"][p]][1], float) * 0.75 + 40
        else:
            col = np.array(NATURE[t], float)
        h = m["board"]
        slope = (h[r, c] + h[r + 1, c]) - (h[r, c + 1] + h[r + 1, c + 1])
        return tuple(int(v) for v in np.clip(col * (1 + 0.35 * slope), 0, 255))
    col = np.array(NATURE[t], float)
    if t == MOUNT and m["cell_h"][r, c] > 0.88 * m["cell_h"].max():
        col = np.array((235, 235, 240), float)
    p = m["province"][r, c]
    if political and p >= 0 and m["owner"][p] >= 0:
        col = col * 0.55 + np.array(FACTIONS[m["owner"][p]][1]) * 0.45
    # light from the right (as the H4 editor): slope along the columns
    h = m["heights"]
    slope = (h[r, c] + h[r + 1, c]) - (h[r, c + 1] + h[r + 1, c + 1])
    return tuple(int(v) for v in np.clip(col * (1 + 1.5 * slope), 0, 255))


def preview(m, path, cw=16, lift=24, style="relief"):
    """Both views side by side; diamonds cw x cw/2, heights lift pixels at most."""
    rows, cols = m["rows"], m["cols"]
    hw, hh = cw // 2, cw // 4
    W, H = (rows + cols) * hw + 20, (rows + cols) * hh + lift + 20
    out = Image.new("RGB", (W * 2, H), (15, 15, 25))
    for v, political in enumerate((True, False)):
        img = Image.new("RGB", (W, H), (15, 15, 25))
        d = ImageDraw.Draw(img)
        if style == "relief":
            hgt = np.maximum(m["heights"], 0) * lift
        elif style == "board":
            m["board"] = board_heights(m)
            hgt = m["board"] * 6
        else:
            hgt = np.zeros_like(m["heights"])

        def pt(r, c):
            return (c - r) * hw + rows * hw + 10, (c + r) * hh - hgt[r, c] + lift + 10
        for s in range(rows + cols - 1):
            for r in range(max(0, s - cols + 1), min(rows, s + 1)):
                c = s - r
                poly = [pt(r, c), pt(r, c + 1), pt(r + 1, c + 1), pt(r + 1, c)]
                d.polygon(poly, fill=cell_color(m, r, c, political, style))
        prov = m["province"]
        for r in range(rows):
            for c in range(cols):
                a = prov[r, c]
                if style == "board":
                    continue        # the grooves are the borders
                for r2, c2, line in ((r, c + 1, [pt(r, c + 1), pt(r + 1, c + 1)]),
                                     (r + 1, c, [pt(r + 1, c), pt(r + 1, c + 1)])):
                    if r2 >= rows or c2 >= cols:
                        continue
                    b = prov[r2, c2]
                    if a == b or a < 0 or b < 0:
                        continue
                    at_sea = m["terrain"][r, c] == SEA and m["terrain"][r2, c2] == SEA
                    ink = (120, 160, 200) if at_sea else (90, 60, 40) if style == "flat" else (30, 20, 15)
                    d.line(line, fill=ink, width=1)
        if political:
            for i, (r, c) in enumerate(m["capitals"]):
                x, y = pt(r, c)
                if i >= m["land"]:
                    d.text((x - 12, y - 6), m["names"][i], fill=(70, 100, 140))
                    continue
                d.rectangle([x - 2, y - 2, x + 2, y + 2], fill=(0, 0, 0))
                d.text((x + 4, y - 6), m["names"][i], fill=(255, 255, 255))
        out.paste(img, (v * W, 0))
    out.save(path)


GRAIN = 4      # grain variants per base (land, sea)
INKS = {1: (0.30, 0.22, 0.16), 2: (0.36, 0.50, 0.68)}   # border lines: ink, sea zones
WIDTH = {1: 1, 2: 2}   # texels: sea-zone lines are wider (they are lighter than ink)


def paper_sheet(rng):
    """Frames 16x16: base 0 land / 1 sea, GRAIN variants, 16 edge combinations each."""
    tex = 16
    frames = []
    for base in range(2):
        for _ in range(GRAIN):
            g = noise(rng, (tex, tex), octaves=3)
            if base == 0:
                grain = 0.86 + 0.14 * g                 # paper: light, fine grain
            else:
                y = np.arange(tex)[:, None]
                grain = 0.84 + 0.10 * g + 0.06 * np.sin((y + 6 * g) * 0.8)   # waves
            for top in range(3):
                for left in range(3):
                    f = np.repeat(grain[:, :, None], 3, 2)
                    if top:
                        f[:WIDTH[top], :, :] = INKS[top]        # along the -row side
                    if left:
                        f[:, :WIDTH[left], :] = INKS[left]      # along the -col side
                    frames.append(f)
    per_row = 9
    rows = (len(frames) + per_row - 1) // per_row
    sheet = np.zeros((rows * tex, per_row * tex, 3))
    for i, f in enumerate(frames):
        sheet[i // per_row * tex:(i // per_row + 1) * tex, i % per_row * tex:(i % per_row + 1) * tex] = f
    img = Image.fromarray((sheet * 255).astype(np.uint8)).quantize(15, method=Image.Quantize.MEDIANCUT)
    idx = np.asarray(img, np.uint8) + 1                  # index 0 stays transparent
    out = Image.fromarray(idx, "P")
    out.putpalette([0, 0, 0] + img.getpalette()[:15 * 3])
    return out, tex


def cell_frames(m, rng):
    terr, prov = m["terrain"], m["province"]
    rows, cols = terr.shape

    def line(r, c, r2, c2):
        """0 none, 1 ink, 2 sea-zone line between cell (r, c) and (r2, c2)."""
        a, b = prov[r, c], prov[r2, c2]
        if a == b and (terr[r, c] == SEA) == (terr[r2, c2] == SEA):
            return 0
        if terr[r, c] == SEA and terr[r2, c2] == SEA:
            return 2
        return 1
    out = []
    for r in range(rows):
        for c in range(cols):
            top = line(r, c, r - 1, c) if r > 0 else 0
            left = line(r, c, r, c - 1) if c > 0 else 0
            base = 1 if terr[r, c] == SEA else 0
            out.append((base * GRAIN + int(rng.integers(GRAIN))) * 9 + top * 3 + left)
    return out


CART_PARCHMENT = (226, 210, 170)
CART_PAPER_SEA = (170, 195, 205)


def cart_cell_colors(m, hts, relief):
    """Cell colours of a view, as main.lua's cell_color (no selection)."""
    terr, prov = m["terrain"], m["province"]
    rows, cols = terr.shape
    out = np.zeros((rows, cols, 3))
    for r in range(rows):
        for c in range(cols):
            t, p = terr[r, c], prov[r, c]
            if relief:
                slope = (hts[r, c] + hts[r + 1, c] - hts[r, c + 1] - hts[r + 1, c + 1]) / 255
                out[r, c] = np.array(NATURE[t]) * (1 + 1.5 * slope)
            elif t == SEA:
                out[r, c] = CART_PAPER_SEA
            else:
                o = FACTIONS[m["owner"][p]][1] if p >= 0 else CART_PARCHMENT
                dark = 0.82 if t == MOUNT else 0.93 if t == UP else 1
                out[r, c] = (np.array(CART_PARCHMENT) + o) * 0.5 * dark
    return out


def cart_corner_colors(cells):
    """Each corner the mean of the cells around it, rounded as main.lua: 0xRRGGBB."""
    rows, cols, _ = cells.shape
    out = []
    for r in range(rows + 1):
        for c in range(cols + 1):
            around = [cells[rr, cc] for rr in (r - 1, r) for cc in (c - 1, c)
                      if 0 <= rr < rows and 0 <= cc < cols]
            mean = np.floor(np.sum(around, 0) / len(around) + 0.5).clip(0, 255).astype(int)
            out.append(int(mean[0]) << 16 | int(mean[1]) << 8 | int(mean[2]))
    return out


def write_cart(m, sd):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import cartkit
    cart = cartkit.cart_dir("m2")
    os.makedirs(os.path.join(cart, "gfx"), exist_ok=True)
    os.makedirs(os.path.join(cart, "data"), exist_ok=True)
    rng = np.random.default_rng(m["seed"] + 1000)
    sheet, tex = paper_sheet(rng)
    sheet.save(os.path.join(cart, "gfx", "paper.png"))
    rows, cols = m["rows"], m["cols"]
    hts = (np.maximum(m["heights"], 0) * 255).round().astype(int)

    def arr(xs):
        return "{" + ",".join(str(int(x)) for x in xs) + "}"
    with open(os.path.join(cart, "data", "map.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write(f"-- made by HeroesDS/tools/make_m2.py --seed {m['seed']} --coast {m['coast']} --cart\n")
        f.write(f"return {{\n  seed = {m['seed']}, rows = {rows}, cols = {cols}, tex = {tex},\n")
        f.write("  terrains = { " + ", ".join(f'"{t}"' for t in TERRAIN) + " },\n")
        f.write("  nature = { " + ", ".join(f"0x{r:02x}{g:02x}{b:02x}" for r, g, b in
                                         (NATURE[t] for t in range(len(TERRAIN)))) + " },\n")
        f.write("  factions = {\n")
        for name_, (r, g, b) in FACTIONS:
            f.write(f'    {{ name = "{name_}", color = 0x{r:02x}{g:02x}{b:02x} }},\n')
        f.write("  },\n")
        f.write(f"  heights = {arr(hts.ravel())},\n")
        f.write(f"  terrain = {arr(m['terrain'].ravel())},\n")
        f.write(f"  province = {arr(m['province'].ravel())},\n")
        f.write(f"  frames = {arr(cell_frames(m, rng))},\n")
        for view, relief in (("paper", False), ("relief", True)):
            f.write(f"  {view} = {arr(cart_corner_colors(cart_cell_colors(m, hts, relief)))},\n")
        f.write("  provinces = {   -- 0-based numbers in province; r, c: capital (sea zone: centre); owner -1 = none\n")
        for i, (r, c) in enumerate(m["capitals"]):
            nb = ", ".join(str(j) for j in sorted(m["neighbours"].get(i, ())))
            sea = ", sea = true" if i >= m["land"] else ""
            f.write(f'    {{ name = "{m["names"][i]}", r = {r}, c = {c}, owner = {m["owner"][i]}{sea}, '
                    f'neighbours = {{ {nb} }} }},\n')
        f.write("  },\n}\n")
    print(f"  cart: {cart} (paper.png {sheet.width}x{sheet.height})")
    if sd is not None:
        cartkit.deploy(cart, sd)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--seed", type=int, default=77)
    p.add_argument("--size", type=int, default=72)
    p.add_argument("--provinces", type=int, default=45)
    p.add_argument("--coast", type=float, default=1.0, help="0..1: how broken the shore is")
    p.add_argument("--png")
    p.add_argument("--style", default="relief", choices=["relief", "flat", "board"])
    p.add_argument("--cart", action="store_true", help="write carts/m2")
    p.add_argument("--sd", default=r"D:\Programowanie\sdcard", help="copy the cart there ('' = no)")
    a = p.parse_args(argv[1:])
    m = generate(a.seed, a.size, a.provinces, a.coast)
    sizes = np.bincount(m["province"][m["province"] >= 0])
    n = m["land"]
    land_nb = [len([j for j in m["neighbours"].get(i, ()) if j < n]) for i in range(n)]
    print(f"seed {a.seed}: {n} provinces, cells per province {sizes[:n].min()}..{sizes[:n].max()}, "
          f"land neighbours {min(land_nb)}..{max(land_nb)}; {len(sizes) - n} sea zones, cells "
          f"{sizes[n:].min()}..{sizes[n:].max()}, coastal provinces "
          f"{sum(1 for i in range(n) if any(j >= n for j in m['neighbours'].get(i, ())))}")
    for f, (fname, _) in enumerate(FACTIONS):
        print(f"  {fname}: {sum(1 for o in m['owner'] if o == f)} provinces")
    if a.png:
        preview(m, a.png, style=a.style)
        print("->", a.png)
    if a.cart:
        write_cart(m, a.sd or None)


if __name__ == "__main__":
    main(sys.argv)
