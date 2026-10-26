"""Reader for Heroes IV actor descriptions: combat_actor.*.h4d and adv_actor.*.h4d.

Both list the actor's animations ("states"); each names one actor_sequence per
direction. Field meanings follow the notes in Anbrose/homm4-mac
(native/Sources/H4Engine/CombatActor.swift, AdvActor.swift; MIT License,
(c) 2026 Anton Ozhigin), checked against the GOG data; this is our own code.

Strings are u16 len + latin-1 bytes. Directions are always stored in the order
ne, e, se, s, sw, w, nw, n; an empty name means the actor has no such animation,
and a four-direction animation repeats the nearest drawn one (bandit die: e -> se).

combat_actor (version 0..6, only 5 and 6 in the data):
  u16 version, u8 footprint (cells per side on the combat grid), u8 height,
  u16 prewalk, walk loop, postwalk distances (world units, 16 per cell),
  v>=6: 8 x (i32 x, y, z) missile launch offsets per direction,
  u16 count, count x (name, u8 fps, v>=5: u8 hit frame, 8 x sequence),
  v>=4: i32 dx, dy draw offset added to every sprite box.

adv_actor (version 3):
  u16 version, u8 depth, u16 prewalk, walk loop, postwalk distances,
  u16 count, count x (name, u8 fps, 8 x sequence),
  i32 x, y model offset, i32 x, y owner flag point.

Usage:
  python h4actor.py <archive.h4r> <resource name>
"""
import struct
import sys

DIRECTIONS = ("ne", "e", "se", "s", "sw", "w", "nw", "n")


class _Reader:
    def __init__(self, b):
        self.b, self.pos = b, 0

    def take(self, fmt):
        v = struct.unpack_from("<" + fmt, self.b, self.pos)
        self.pos += struct.calcsize("<" + fmt)
        return v if len(v) > 1 else v[0]

    def str(self):
        n = self.take("H")
        s = self.b[self.pos:self.pos + n]
        if len(s) != n:
            raise ValueError("string past the end")
        self.pos += n
        return s.decode("latin-1")

    def left(self):
        return len(self.b) - self.pos


def _states(r, hit_frame):
    states = {}
    for _ in range(r.take("H")):
        name = r.str()
        fps = r.take("B")
        hit = r.take("B") if hit_frame else 0
        seqs = [r.str() for _ in DIRECTIONS]
        states[name] = dict(fps=fps, hit_frame=hit, dirs={d: s for d, s in zip(DIRECTIONS, seqs) if s})
    return states


def parse_combat(b):
    r = _Reader(b)
    v = r.take("H")
    if v > 6:
        raise ValueError(f"combat_actor version {v}")
    a = dict(kind="combat", version=v, footprint=1, height=0, distances=(16, 64, 16),
             launch=[], draw_offset=(0, 0))
    if v >= 1:
        a["footprint"] = b[2]
    if v >= 2:
        a["height"] = b[3]
    if v >= 3:
        a["distances"] = struct.unpack_from("<3H", b, 4)
    r.pos = 10
    if v >= 6:
        a["launch"] = [r.take("3i") for _ in DIRECTIONS]
    a["states"] = _states(r, v >= 5)
    if v >= 4 and r.left() >= 8:
        a["draw_offset"] = r.take("2i")
    a["rest"] = b[r.pos:]
    return a


def parse_adv(b):
    r = _Reader(b)
    v = r.take("H")
    if v != 3:
        raise ValueError(f"adv_actor version {v}")
    a = dict(kind="adv", version=v, depth=r.take("B"), distances=r.take("3H"))
    a["states"] = _states(r, False)
    a["offset"] = r.take("2i")
    a["flag"] = r.take("2i")
    a["rest"] = b[r.pos:]
    return a


def parse(b, name):
    """name: resource name, decides the layout."""
    n = name.lower()
    if n.startswith("combat_actor."):
        return parse_combat(b)
    if n.startswith("adv_actor."):
        return parse_adv(b)
    raise ValueError(f"{name}: not an actor")


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 1
    import h4r
    a = parse(h4r.Archive(argv[1]).read(argv[2]), argv[2])
    for k, v in a.items():
        if k not in ("states", "rest"):
            print(f"{k}: {v}")
    for name, s in a["states"].items():
        dirs = " ".join(f"{d}={s['dirs'][d].rsplit('.', 1)[-1]}" if d in s["dirs"] else f"{d}=-" for d in DIRECTIONS)
        print(f"  {name:13} {s['fps']:2} fps hit {s['hit_frame']:2}  {dirs}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
