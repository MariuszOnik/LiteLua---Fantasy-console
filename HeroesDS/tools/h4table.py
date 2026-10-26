"""Reader for Heroes IV rule tables (table.*.h4d, mostly in text.h4r).

The layout follows the notes in tools/h4table.py of Anbrose/homm4-mac (MIT
License, (c) 2026 Anton Ozhigin); this is our own code. Every cell is a string:

  u32 rows
  either u32 columns, then (columns - 1) x str16 group labels ("Dmg", "Cost", ...)
  or     nothing (the heroes table)
  rows of: u16 n, n x str16                  the first row usually names the columns

str16 = u16 length + text in the game's Windows code page (cp1250 for the
Polish GOG release this project uses; set ENCODING for another language).

Usage:
  python h4table.py <Data dir> <table name> [out.tsv]     e.g. creatures
"""
import os
import struct
import sys

ENCODING = "cp1250"


def _str(b, p):
    n, = struct.unpack_from("<H", b, p)
    return b[p + 2:p + 2 + n].decode(ENCODING), p + 2 + n


def parse(b):
    """Returns (groups, rows): group labels and a list of rows (lists of strings)."""
    nrows, = struct.unpack_from("<I", b, 0)
    p, groups = 4, []
    ncols, high = struct.unpack_from("<HH", b, 4)
    if high == 0 and ncols < 256:
        p = 8
        for _ in range(max(0, ncols - 1)):
            s, p = _str(b, p)
            groups.append(s)
    rows = []
    while p + 2 <= len(b) and len(rows) < nrows:
        n, = struct.unpack_from("<H", b, p)
        p += 2
        row = []
        for _ in range(n):
            s, p = _str(b, p)
            row.append(s)
        rows.append(row)
    return groups, rows


def records(rows, header=0):
    """Rows below the header row as dicts by column name (empty names skipped)."""
    names = rows[header]
    out = []
    for r in rows[header + 1:]:
        out.append({n: (r[i] if i < len(r) else "") for i, n in enumerate(names) if n})
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import h4r
    groups, rows = parse(h4r.Library(argv[1]).read(f"table.{argv[2]}.h4d"))
    text = "\n".join("\t".join(c.replace("\t", " ").replace("\r", " ").replace("\n", "\\n") for c in r)
                     for r in rows)
    if len(argv) > 3:
        with open(argv[3], "w", encoding="utf-8") as f:
            f.write(text + "\n")
    else:
        sys.stdout.buffer.write(text.encode("utf-8", "replace") + b"\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
