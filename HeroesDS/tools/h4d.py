"""Decoder for Heroes of Might and Magic IV sprite resources (.h4d) -> PNG.

The image record layout follows the notes in tools/h4sprite.py of
Anbrose/homm4-mac (MIT License, (c) 2026 Anton Ozhigin); this is our own code.

Image record (little endian):
  palette  u16 npal, u16 1, u16 speed, u8 0, (npal-1) x BGR    index 0 = transparent
  image    u16 len + name ("frame 002 004", "shadow 001", "base_frame", ...)
           u8 kind          4 = full image, 1 = delta over base_frame, 0 = empty
           u32 left, top, right, bottom                          box on the canvas
           (bottom-top) x (u16 x0, u16 x1, u32 offset)           opaque span per row
           span pixels      one palette index each, rows concatenated
           kind 4 only:     alpha, one nibble per span pixel (low first, 0..15),
                            then ceil((pixels+4)/64) summary nibbles (skipped)

actor_sequence files wrap the records in:
  header   u16 2, u16 kind (3 adds 6 bytes), u16 image count
  trailer  i32 origin x, i32 origin y, u16 n, n x (u16 len + name, u16 type)

The numbers in an image name list the animation frames that show it, so
"frame 002 004" is frame 2 and frame 4; shadows pair with frames the same way.

Usage:
  python h4d.py <archive.h4r> <resource name> <out_dir>
  python h4d.py <file.h4d> <out_dir>
Writes frame_NN.png (frames composited with shadow and base_frame on one box),
strip.png and meta.json.
"""
import json
import os
import struct
import sys
from dataclasses import dataclass, field

from PIL import Image


@dataclass
class SpriteImage:
    name: str
    kind: int
    box: tuple          # left, top, right, bottom
    rows: list          # (x0, x1, offset) per row
    pixels: bytes
    alpha: bytes        # nibbles; None for delta frames (opaque)
    palette: list       # RGB tuples, index 0 unused
    speed: int

    @property
    def frames(self):
        """Frame numbers this image is shown in (from the name)."""
        return [int(w) for w in self.name.split()[1:] if w.isdigit()]

    def rgba(self):
        left, top, right, bottom = self.box
        img = Image.new("RGBA", (max(right - left, 1), max(bottom - top, 1)))
        px = img.load()
        k = 0
        for y, (x0, x1, off) in enumerate(self.rows):
            for i in range(x1 - x0):
                idx = self.pixels[off + i]
                a = 15 if self.alpha is None else (self.alpha[k // 2] >> (4 * (k % 2))) & 15
                k += 1
                if idx and a:
                    px[x0 + i, y] = self.palette[idx] + (a * 17,)
        return img


@dataclass
class Sequence:
    images: list
    header: bytes
    trailer: bytes
    origin: tuple = None
    links: list = field(default_factory=list)

    def image(self, name):
        return next((i for i in self.images if i.name == name), None)

    def frame_count(self):
        return max((n for i in self.images for n in i.frames), default=0)

    def layers(self, prefix, n):
        return [i for i in self.images if i.name.startswith(prefix) and n in i.frames]

    def bounds(self):
        boxes = [i.box for i in self.images if i.kind]
        return (min(b[0] for b in boxes), min(b[1] for b in boxes),
                max(b[2] for b in boxes), max(b[3] for b in boxes))

    def render(self, n, shadow=True):
        """Frame n (1-based) composited on the common bounding box."""
        left, top, right, bottom = self.bounds()
        out = Image.new("RGBA", (right - left, bottom - top))
        parts = (self.layers("shadow", n) if shadow else []) + [self.image("base_frame")]
        parts += self.layers("frame", n)
        for img in parts:
            if img and img.kind:
                out.alpha_composite(img.rgba(), (img.box[0] - left, img.box[1] - top))
        return out


def _palette_at(b, pos):
    """True when a palette header followed by a plausible image name starts at pos."""
    if pos + 7 > len(b):
        return False
    npal, one = struct.unpack_from("<HH", b, pos)
    if not (1 <= npal <= 256 and one == 1 and b[pos + 6] == 0):
        return False
    q = pos + 7 + (npal - 1) * 3
    if q + 3 > len(b):
        return False
    n, = struct.unpack_from("<H", b, q)
    name = b[q + 2:q + 2 + n]
    return (1 <= n <= 512 and len(name) == n and all(32 <= c < 127 for c in name)
            and q + 2 + n < len(b) and b[q + 2 + n] in (0, 1, 4))


def _read_image(b, pos):
    npal, _, speed = struct.unpack_from("<HHH", b, pos)
    pos += 7
    palette = [None] + [tuple(b[pos + i * 3:pos + i * 3 + 3][::-1]) for i in range(npal - 1)]
    pos += (npal - 1) * 3
    n, = struct.unpack_from("<H", b, pos)
    name = b[pos + 2:pos + 2 + n].decode("latin-1")
    pos += 2 + n
    kind = b[pos]
    box = struct.unpack_from("<4I", b, pos + 1)
    pos += 17
    rows = [struct.unpack_from("<HHI", b, pos + i * 8) for i in range(box[3] - box[1])]
    pos += len(rows) * 8
    count = sum(x1 - x0 for x0, x1, _ in rows)
    pixels = b[pos:pos + count]
    pos += count
    alpha = None
    if kind == 4:
        alpha = b[pos:pos + (count + 1) // 2]
        pos += (count + 1) // 2
        if count:
            pos += ((count + 4 + 63) // 64 + 1) // 2
    return SpriteImage(name, kind, box, rows, pixels, alpha, palette, speed), pos


def parse(b):
    start = next((p for p in range(min(len(b), 4096)) if _palette_at(b, p)), None)
    if start is None:
        raise ValueError("no image records found")
    pos, images = start, []
    while _palette_at(b, pos):
        img, pos = _read_image(b, pos)
        images.append(img)
    seq = Sequence(images, b[:start], b[pos:])
    if b[:2] == b"\x02\x00" and len(seq.trailer) >= 10:
        seq.origin = struct.unpack_from("<ii", seq.trailer)
        n, = struct.unpack_from("<H", seq.trailer, 8)
        q = 10
        for _ in range(n):
            ln, = struct.unpack_from("<H", seq.trailer, q)
            name = seq.trailer[q + 2:q + 2 + ln].decode("latin-1")
            typ, = struct.unpack_from("<H", seq.trailer, q + 2 + ln)
            seq.links.append((name, typ))
            q += 4 + ln
    return seq


def export(seq, out):
    os.makedirs(out, exist_ok=True)
    frames = [seq.render(n) for n in range(1, seq.frame_count() + 1)]
    for n, img in enumerate(frames, 1):
        img.save(os.path.join(out, f"frame_{n:02}.png"))
    if frames:
        w, h = frames[0].size
        strip = Image.new("RGBA", (w * len(frames), h))
        for n, img in enumerate(frames):
            strip.paste(img, (n * w, 0))
        strip.save(os.path.join(out, "strip.png"))
    meta = dict(frames=len(frames), bounds=seq.bounds(), origin=seq.origin, links=seq.links,
                header=seq.header.hex(" "),
                images=[dict(name=i.name, kind=i.kind, box=i.box, speed=i.speed,
                             colors=len(i.palette) - 1) for i in seq.images])
    with open(os.path.join(out, "meta.json"), "w") as f:
        json.dump(meta, f, indent=1)
    return meta


def main(argv):
    if len(argv) == 4:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import h4r
        data = h4r.Archive(argv[1]).read(argv[2])
        out = argv[3]
    elif len(argv) == 3:
        data = open(argv[1], "rb").read()
        out = argv[2]
    else:
        print(__doc__)
        return 1
    meta = export(parse(data), out)
    print(f"{len(meta['images'])} images, {meta['frames']} frames -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
