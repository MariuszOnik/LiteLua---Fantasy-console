"""Reader for Heroes of Might and Magic IV resource archives (.h4r).

Layout (reverse engineered, little endian):
  header:    "H4R\\x05", u32 dir_offset
  directory: u32 count, then count entries:
             u32 offset, u32 packed_size, u32 size, u32 time,
             u16 len + name, u16 len + source path, u16 len + alias, u32 (always 3)
  data:      each entry is a gzip stream (or raw when packed_size == size)

An entry with an alias has no data of its own (offset and packed_size are 0);
it stands for the entry named by the alias.

The archive also keeps an older copy of the directory right after the header;
the one at dir_offset is authoritative.

Usage:
  python h4r.py list <archive> [substring]
  python h4r.py extract <archive> <name> <out_file>
"""
import gzip
import os
import struct
import sys
import zlib
from dataclasses import dataclass


@dataclass
class Entry:
    name: str
    offset: int
    packed_size: int
    size: int
    time: int
    path: str
    alias: str


class Archive:
    def __init__(self, filename):
        self.filename = filename
        self.f = open(filename, "rb")
        magic, dir_offset = struct.unpack("<4sI", self.f.read(8))
        if magic != b"H4R\x05":
            self.f.close()
            raise ValueError(f"{filename}: not an h4r archive")
        self.f.seek(dir_offset)
        self.entries = {}
        self.order = []
        count, = struct.unpack("<I", self.f.read(4))
        for _ in range(count):
            offset, packed, size, time = struct.unpack("<4I", self.f.read(16))
            name = self._str()
            path = self._str()
            alias = self._str()
            self.f.read(4)
            e = Entry(name, offset, packed, size, time, path, alias)
            self.entries[name.lower()] = e
            self.order.append(e)

    def _str(self):
        n, = struct.unpack("<H", self.f.read(2))
        return self.f.read(n).decode("latin-1")

    def find(self, sub=""):
        sub = sub.lower()
        return [e for e in self.order if sub in e.name.lower()]

    def read(self, name):
        e = name if isinstance(name, Entry) else self.entries[name.lower()]
        if e.alias:
            return self.read(e.alias)
        self.f.seek(e.offset)
        raw = self.f.read(e.packed_size)
        if raw[:2] == b"\x1f\x8b":
            data = gzip.decompress(raw)
        elif e.packed_size == e.size:
            data = raw
        else:
            data = zlib.decompress(raw)
        if len(data) != e.size:
            raise ValueError(f"{e.name}: size {len(data)} != {e.size}")
        return data


class Library:
    """All archives of a game Data folder; a name is looked up in the newest first.

    The order is our assumption (overrides and expansions over the base game);
    the same name in two archives is rare outside the *_override files.
    """
    ORDER = ("storm_override", "x2_override", "updates", "storm", "x2", "heroes4", "text", "music")

    def __init__(self, data_dir):
        found = {os.path.splitext(f)[0].lower(): f for f in os.listdir(data_dir) if f.lower().endswith(".h4r")}
        names = [n for n in self.ORDER if n in found] + sorted(n for n in found if n not in self.ORDER)
        self.archives = [Archive(os.path.join(data_dir, found[n])) for n in names]

    def entry(self, name):
        for a in self.archives:
            e = a.entries.get(name.lower())
            if e:
                return a, e
        raise KeyError(name)

    def __contains__(self, name):
        return any(name.lower() in a.entries for a in self.archives)

    def read(self, name):
        a, e = self.entry(name)
        return a.read(e)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    cmd, arc = argv[1], Archive(argv[2])
    if cmd == "list":
        for e in arc.find(argv[3] if len(argv) > 3 else ""):
            print(f"{e.size:>10} {e.name}")
    elif cmd == "extract":
        with open(argv[4], "wb") as f:
            f.write(arc.read(argv[3]))
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
