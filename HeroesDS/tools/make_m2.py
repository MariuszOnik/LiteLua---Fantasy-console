"""Makes an invented piece of land split into provinces (the political map, Imperial Glory
style): height map, terrain, provinces, neighbours, names and owners -- all from one seed.

  python HeroesDS/tools/make_m2.py [--seed N] [--size 72] [--provinces 45] [--png out]
                                   [--cart] [--sd DIR]

Steps (all on a rows x cols grid of cells; corners are (rows + 1) x (cols + 1)):
  1. heights: value noise in octaves, lowered toward the edges -> land in the middle, sea
     around it; sea level so that about LAND of the cells are land
  2. terrain by height: sea, beach, lowland, upland, mountain (snow on the peaks)
  3. provinces: capitals spread over the land (farthest-point sampling), every land cell
     goes to the capital it reaches cheapest -- climbing costs more, so borders follow
     ridges; then RELAX times each capital moves to the land cell nearest the middle of
     its province and the land is shared out again (Lloyd), so provinces get even and
     capitals sit inside; provinces under MIN_CELLS join their biggest neighbour
  4. neighbours (cells touching across an edge), names from syllables, owners: the six
     H4 factions, each growing a compact realm from a seed province
--png writes a preview: the political view (land tinted with the owner, borders) next to
the natural one. --style picks how the land looks:
  relief  heights from the terrain, shaded slopes (default)
  flat    a paper map: no heights, pale owner colours on parchment, sea light blue
  board   a table model: every province a flat plate raised over the sea, its edges
          bevelled down, so the borders are grooves between the plates

--cart writes the cart carts/m2 (no game data in it):
  gfx/paper.png   16x16 frames of light grain (land: paper, sea: waves); frame
                  base * 16 + edges, edges = 1 if the cell's -row side is a border
                  (another province or the coast), 2 for its -col side: the ink line
                  is part of the frame, so every border is drawn once, by one cell
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
SEA, BEACH, LOW, UP, MOUNT = range(5)
TERRAIN = ["sea", "beach", "lowland", "upland", "mountain"]
FACTIONS = [            # name, color (H4: Life, Order, Death, Chaos, Nature, Might)
    ("Life", (230, 230, 240)), ("Order", (60, 110, 220)), ("Death", (120, 60, 150)),
    ("Chaos", (210, 50, 40)), ("Nature", (60, 170, 70)), ("Might", (220, 160, 40)),
]
SYLLABLES = ["ar", "bel", "cor", "dal", "en", "fal", "gor", "hal", "is", "kar", "lor", "mar",
             "nor", "or", "pel", "ran", "sil", "tor", "ul", "val", "wen", "yr", "zan", "eth",
             "ia", "on", "ost", "mir", "dun", "gal"]


def noise(rng, shape, octaves=5):
    """Value noise in [0, 1]: bilinear random grids, each octave twice as fine."""
    h, w = shape
    out = np.zeros(shape)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = 2 ** (o + 2)
        g = rng.random((n + 1, n + 1))
        y = np.linspace(0, n, h, endpoint=False)
        x = np.linspace(0, n, w, endpoint=False)
        yi, xi = y.astype(int), x.astype(int)
        fy, fx = (y - yi)[:, None], (x - xi)[None, :]
        fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)       # smoothstep
        a, b = g[yi][:, xi], g[yi][:, xi + 1]
        c, d = g[yi + 1][:, xi], g[yi + 1][:, xi + 1]
        out += amp * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        total += amp
        amp *= 0.5
    return out / total


def heights(rng, rows, cols):
    """Corner heights 0..1 (sea level at 0) and the sea level used."""
    h = noise(rng, (rows + 1, cols + 1))
    y, x = np.mgrid[0:rows + 1, 0:cols + 1]
    d = np.maximum(np.abs(y / rows - 0.5), np.abs(x / cols - 0.5)) * 2      # 0 middle, 1 edge
    h = h - 0.55 * d ** 2
    cells = (h[:-1, :-1] + h[1:, :-1] + h[:-1, 1:] + h[1:, 1:]) / 4
    sea = np.quantile(cells, 1 - LAND)
    h = (h - sea) / (h.max() - sea)
    return h, cells - sea


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


def provinces(rng, terr, cell_h, count):
    """Province number per cell (-1 = sea or no province) and the capitals."""
    rows, cols = terr.shape
    land = [(r, c) for r in range(rows) for c in range(cols) if terr[r, c] != SEA]
    # capitals: farthest-point sampling over the land, starting anywhere
    caps = [land[rng.integers(len(land))]]
    dist = np.full(len(land), 1e9)
    pts = np.array(land)
    for _ in range(count - 1):
        dist = np.minimum(dist, ((pts - caps[-1]) ** 2).sum(1))
        caps.append(tuple(int(v) for v in pts[int(dist.argmax())]))
    for _ in range(RELAX):
        prov = share(terr, cell_h, caps)
        caps = [middle(prov, i, caps[i]) for i in range(len(caps))]
    prov = share(terr, cell_h, caps)
    return merge_small(prov, caps)


def middle(prov, i, old):
    """The cell of province i nearest its centre of mass."""
    cells = np.argwhere(prov == i)
    if len(cells) == 0:
        return old
    mid = cells.mean(0)
    r, c = cells[int(((cells - mid) ** 2).sum(1).argmin())]
    return int(r), int(c)


def merge_small(prov, caps):
    """Provinces under MIN_CELLS join the neighbour they share most border with
    (islets without one keep no province); the rest are renumbered from 0."""
    while True:
        sizes = np.bincount(prov[prov >= 0], minlength=len(caps))
        small = [i for i in range(len(caps)) if 0 < sizes[i] < MIN_CELLS]
        if not small:
            break
        i = min(small, key=lambda k: sizes[k])
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


def share(terr, cell_h, caps):
    """Every land cell to the capital it reaches cheapest: a step costs 1 + climbing."""
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
            if terr[r2, c2] == SEA:
                continue
            step = 1 + 12 * max(0.0, cell_h[r2, c2] - cell_h[r, c]) + 4 * (terr[r2, c2] == MOUNT)
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


def owners(rng, n, adj, caps):
    """The six factions grow realms from far-apart provinces, one province at a time."""
    owner = [-1] * n
    seeds = [int(rng.integers(n))]
    while len(seeds) < len(FACTIONS):
        far = max(range(n), key=lambda i: min((caps[i][0] - caps[s][0]) ** 2
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
    return [o if o >= 0 else int(rng.integers(len(FACTIONS))) for o in owner]


def name(rng):
    n = int(rng.integers(2, 4))
    s = "".join(SYLLABLES[int(rng.integers(len(SYLLABLES)))] for _ in range(n))
    return s.capitalize()


def generate(seed=1, size=72, count=45):
    rng = np.random.default_rng(seed)
    h, cell_h = heights(rng, size, size)
    terr = terrain(cell_h)
    prov, caps = provinces(rng, terr, cell_h, count)
    adj = adjacency(prov)
    own = owners(rng, len(caps), adj, caps)
    names = [name(rng) for _ in caps]
    return dict(seed=seed, rows=size, cols=size, heights=h, cell_h=cell_h, terrain=terr,
                province=prov, capitals=caps, neighbours=adj, owner=own, names=names)


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
        if political and p >= 0:
            col = col * 0.5 + np.array(FACTIONS[m["owner"][p]][1]) * 0.5
        if t == MOUNT:
            col *= 0.82
        elif t == UP:
            col *= 0.93
        return tuple(int(v) for v in col)
    if style == "board":
        if t == SEA:
            col = np.array(NATURE[SEA], float)
        elif political and p >= 0:
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
    if political and p >= 0:
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
                ink = (90, 60, 40) if style == "flat" else (30, 20, 15)
                if c + 1 < cols and a != prov[r, c + 1] and a >= 0 <= prov[r, c + 1]:
                    d.line([pt(r, c + 1), pt(r + 1, c + 1)], fill=ink, width=1)
                if r + 1 < rows and a != prov[r + 1, c] and a >= 0 <= prov[r + 1, c]:
                    d.line([pt(r + 1, c), pt(r + 1, c + 1)], fill=ink, width=1)
        if political:
            for i, (r, c) in enumerate(m["capitals"]):
                x, y = pt(r, c)
                d.rectangle([x - 2, y - 2, x + 2, y + 2], fill=(0, 0, 0))
                d.text((x + 4, y - 6), m["names"][i], fill=(255, 255, 255))
        out.paste(img, (v * W, 0))
    out.save(path)


GRAIN = 4      # grain variants per base (land, sea)


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
            for edges in range(4):
                f = np.repeat(grain[:, :, None], 3, 2)
                if edges & 1:
                    f[0, :, :] = (0.30, 0.22, 0.16)    # ink along the -row side
                if edges & 2:
                    f[:, 0, :] = (0.30, 0.22, 0.16)    # ink along the -col side
                frames.append(f)
    per_row = 8
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

    def region(r, c):
        return prov[r, c] if terr[r, c] != SEA else -2
    out = []
    for r in range(rows):
        for c in range(cols):
            a = region(r, c)
            edges = 0
            if r > 0 and region(r - 1, c) != a and (a >= 0 or region(r - 1, c) >= 0):
                edges |= 1
            if c > 0 and region(r, c - 1) != a and (a >= 0 or region(r, c - 1) >= 0):
                edges |= 2
            base = 1 if terr[r, c] == SEA else 0
            out.append((base * GRAIN + int(rng.integers(GRAIN))) * 4 + edges)
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
        f.write(f"-- made by HeroesDS/tools/make_m2.py --seed {m['seed']} --cart\n")
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
        f.write("  provinces = {   -- 0-based numbers in province; r, c: capital\n")
        for i, (r, c) in enumerate(m["capitals"]):
            nb = ", ".join(str(j) for j in sorted(m["neighbours"].get(i, ())))
            f.write(f'    {{ name = "{m["names"][i]}", r = {r}, c = {c}, owner = {m["owner"][i]}, '
                    f'neighbours = {{ {nb} }} }},\n')
        f.write("  },\n}\n")
    print(f"  cart: {cart} (paper.png {sheet.width}x{sheet.height})")
    if sd is not None:
        cartkit.deploy(cart, sd)


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--seed", type=int, default=1)
    p.add_argument("--size", type=int, default=72)
    p.add_argument("--provinces", type=int, default=45)
    p.add_argument("--png")
    p.add_argument("--style", default="relief", choices=["relief", "flat", "board"])
    p.add_argument("--cart", action="store_true", help="write carts/m2")
    p.add_argument("--sd", default=r"D:\Programowanie\sdcard", help="copy the cart there ('' = no)")
    a = p.parse_args(argv[1:])
    m = generate(a.seed, a.size, a.provinces)
    sizes = np.bincount(m["province"][m["province"] >= 0])
    print(f"seed {a.seed}: {len(m['capitals'])} provinces, cells per province {sizes.min()}..{sizes.max()}, "
          f"neighbours {min(len(v) for v in m['neighbours'].values())}.."
          f"{max(len(v) for v in m['neighbours'].values())}")
    for f, (fname, _) in enumerate(FACTIONS):
        print(f"  {fname}: {sum(1 for o in m['owner'] if o == f)} provinces")
    if a.png:
        preview(m, a.png, style=a.style)
        print("->", a.png)
    if a.cart:
        write_cart(m, a.sd or None)


if __name__ == "__main__":
    main(sys.argv)
