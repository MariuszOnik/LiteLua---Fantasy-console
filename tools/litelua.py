#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# LiteLua - PC tool for cartridges.
#
#   python tools/litelua.py pack <cart folder> [out.lcart] [--store]
#
# pack: folder -> .lcart (a ZIP with cart.lua at the top, D6). Files are
# deflated, except already compressed ones (PNG, ...) and WAV, which are
# stored: music is streamed straight from the archive (P7).
# Hidden files (starting with '.') are skipped. More commands come in P9.

import argparse
import pathlib
import sys
import zipfile

STORED_EXT = {".png", ".mas", ".wav", ".lcart", ".zip"}


def pack(src: pathlib.Path, out: pathlib.Path, store: bool) -> int:
    if not (src / "cart.lua").is_file():
        print(f"error: {src} has no cart.lua", file=sys.stderr)
        return 1
    if not (src / "main.lua").is_file():
        print(f"warning: {src} has no main.lua (needed unless 'entry' is set)",
              file=sys.stderr)

    files = sorted(p for p in src.rglob("*")
                   if p.is_file() and not any(part.startswith(".")
                                              for part in p.relative_to(src).parts))
    count = 0
    with zipfile.ZipFile(out, "w") as z:
        for p in files:
            name = p.relative_to(src).as_posix()  # '/' separators, as ZIP requires
            method = zipfile.ZIP_STORED
            if not store and p.suffix.lower() not in STORED_EXT:
                method = zipfile.ZIP_DEFLATED
            z.write(p, name, compress_type=method, compresslevel=9
                    if method == zipfile.ZIP_DEFLATED else None)
            count += 1

    print(f"{out}: {count} files, {out.stat().st_size} bytes")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="litelua", description="LiteLua cartridge tool")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pack", help="pack a cart folder into a .lcart file")
    p.add_argument("folder", type=pathlib.Path)
    p.add_argument("out", type=pathlib.Path, nargs="?",
                   help="output file (default: <folder name>.lcart)")
    p.add_argument("--store", action="store_true", help="do not compress")
    args = ap.parse_args()

    if args.cmd == "pack":
        out = args.out or pathlib.Path(args.folder.resolve().name + ".lcart")
        return pack(args.folder, out, args.store)
    return 1


if __name__ == "__main__":
    sys.exit(main())
