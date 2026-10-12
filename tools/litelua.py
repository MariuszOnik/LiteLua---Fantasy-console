#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# LiteLua - PC tool for cartridges.
#
#   python tools/litelua.py pack <cart folder> [out.lcart] [--store]
#   python tools/litelua.py song check|convert|render|import ...   (.lsong, D36, D37)
#
# pack: folder -> .lcart (a ZIP with cart.lua at the top, D6). Files are
# deflated, except already compressed ones (PNG, ...) and WAV, which are
# stored: music is streamed straight from the archive (P7).
# Hidden files (starting with '.') are skipped. More commands come in P9.
#
# song: .lsong music files (docs/LSONG.md): check validates, convert turns
# Lua data into JSON and back (by the output extension), render writes an
# approximate WAV preview, import turns a MIDI file into a chiptune
# arrangement (--list shows its parts first).

import argparse
import pathlib
import sys
import zipfile

import lsong
import midi
import midi_import

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

    p = sub.add_parser("song", help=".lsong music: check, convert, render")
    ssub = p.add_subparsers(dest="song_cmd", required=True)
    c = ssub.add_parser("check", help="validate a song")
    c.add_argument("file", type=pathlib.Path)
    c = ssub.add_parser("convert", help="Lua data <-> JSON (by the out extension)")
    c.add_argument("file", type=pathlib.Path)
    c.add_argument("out", type=pathlib.Path)
    c = ssub.add_parser("render", help="approximate WAV preview")
    c.add_argument("file", type=pathlib.Path)
    c.add_argument("out", type=pathlib.Path)
    c.add_argument("--rate", type=int, default=22050, help="Hz, default 22050")
    c.add_argument("--bits", type=int, choices=(8, 16), default=16)
    c.add_argument("--loops", type=int, default=1,
                   help="1 = once through; 2 = then the loop part once more")
    c.add_argument("--stereo", action="store_true",
                   help="stereo WAV: melody a bit left, chords a bit right (see --pan)")
    c.add_argument("--pan", action="append", default=[], metavar="TRACK=P",
                   help="stereo position of a track, -1 left .. 1 right (repeatable)")
    c = ssub.add_parser("import", help="MIDI -> .lsong (see --list first)")
    c.add_argument("file", type=pathlib.Path, help=".mid file")
    c.add_argument("out", type=pathlib.Path, nargs="?", help=".lsong or .lsong.json")
    c.add_argument("--list", action="store_true", help="show the MIDI parts (sources)")
    for role in midi_import.ROLES:
        c.add_argument(f"--{role}", metavar="N[,N]",
                       help=f"sources for the {role} track (default: automatic)")
    for role in midi_import.MELODIC:
        c.add_argument(f"--{role}-mode", choices=midi_import.MODES,
                       help=f"chords -> one note: default {midi_import.DEFAULT_MODE[role]}")
    c.add_argument("--tempo-mode", choices=("auto", "entries", "grid", "time"),
                   default="auto", help="tempo changes: entries (v1.1) keeps both; "
                   "with one tempo, grid keeps bars, time keeps timing")
    c.add_argument("--lsong", type=float, choices=(1, 1.1), default=1.1,
                   help="format version to write, default 1.1")
    c.add_argument("--ppq", type=int, default=24, help="ticks per quarter, default 24")
    c.add_argument("--bars", type=int, help="bars per pattern (default: best fit)")
    c.add_argument("--profile", choices=("nes", "extended"),
                   help="default: nes if the roles fit (2 pulse, triangle, noise)")
    c.add_argument("--split-drums", action="store_true",
                   help="hi-hats and cymbals on a second noise track (extended)")
    args = ap.parse_args()

    if args.cmd == "pack":
        out = args.out or pathlib.Path(args.folder.resolve().name + ".lcart")
        return pack(args.folder, out, args.store)
    if args.cmd == "song":
        return song(args)
    return 1


def song_import(args) -> int:
    try:
        if args.list:
            mf = midi.read(args.file)
            print(f"{args.file}: MIDI format {mf.format}, {mf.division} ticks per quarter")
            for w in mf.warnings:
                print(f"warning: {w}")
            for s in midi_import.sources(mf):
                print(s.describe())
            return 0
        if args.out is None:
            print("error: give an output file (or --list)", file=sys.stderr)
            return 1
        roles = {}
        for role in midi_import.ROLES:
            v = getattr(args, role)
            if v:
                roles[role] = [int(x) for x in v.split(",")]
        modes = {r: getattr(args, f"{r}_mode") for r in midi_import.MELODIC
                 if getattr(args, f"{r}_mode")}
        data, report = midi_import.import_midi(
            args.file, roles or None, modes, args.tempo_mode, args.ppq, args.bars,
            args.profile, 1.1 if args.lsong == 1.1 else 1, args.split_drums)
    except (midi.MidiError, midi_import.MidiImportError, OSError, ValueError) as e:
        print(f"{args.file}: {e}", file=sys.stderr)
        return 1
    for line in report:
        print(line)
    check = lsong.validate(data)
    for e in check.errors:
        print(f"error: {e}", file=sys.stderr)
    if check.errors:
        return 1
    is_json = args.out.name.lower().endswith(".json")
    text = lsong.to_json(data) if is_json else lsong.to_lua(data)
    size = len(text.encode("utf-8"))
    if size > lsong.MAX_FILE:
        print(f"error: the song would be {size // 1024} KB; .lsong files may have at most "
              f"{lsong.MAX_FILE // 1024} KB (try --ppq 24, --bars 4 or fewer roles)",
              file=sys.stderr)
        return 1
    args.out.write_text(text, encoding="utf-8", newline="\n")
    print(f"{args.out}: {lsong.duration(data):.1f} s, {len(text)} bytes, "
          f"{len(check.warnings)} validator warnings")
    return 0


def song(args) -> int:
    if args.song_cmd == "import":
        return song_import(args)
    try:
        data = lsong.load(args.file)
    except (lsong.LsongError, OSError) as e:
        print(f"{args.file}: {e}", file=sys.stderr)
        return 1
    report = lsong.validate(data)
    for w in report.warnings:
        print(f"warning: {w}", file=sys.stderr)
    for e in report.errors:
        print(f"error: {e}", file=sys.stderr)
    if report.errors:
        print(f"{args.file}: {len(report.errors)} errors", file=sys.stderr)
        return 1

    if args.song_cmd == "check":
        notes = sum(len(v) for p in data["patterns"].values()
                    for v in (p.get("notes") or {}).values())
        print(f"{args.file}: ok, {len(data['tracks'])} tracks, "
              f"{len(data['patterns'])} patterns, {notes} notes, "
              f"{lsong.duration(data):.1f} s, {len(report.warnings)} warnings")
    elif args.song_cmd == "convert":
        is_json = args.out.name.lower().endswith(".json")
        text = lsong.to_json(data) if is_json else lsong.to_lua(data)
        args.out.write_text(text, encoding="utf-8", newline="\n")
        print(f"{args.out}: {'JSON' if is_json else 'Lua data'}, {len(text)} bytes")
    elif args.song_cmd == "render":
        if args.rate < 4000 or args.rate > 48000:
            print("error: --rate must be 4000 .. 48000", file=sys.stderr)
            return 1
        pans = {}
        for item in args.pan:
            name, _, value = item.partition("=")
            try:
                pans[name] = float(value)
            except ValueError:
                print(f"error: --pan {item}: use TRACK=number", file=sys.stderr)
                return 1
            if name not in {t["name"] for t in data["tracks"]}:
                print(f"error: --pan: there is no track '{name}'", file=sys.stderr)
                return 1
        seconds = lsong.render(data, args.out, args.rate, args.bits, max(1, args.loops),
                               args.stereo or bool(pans), pans)
        print(f"{args.out}: {seconds:.1f} s, {args.rate} Hz, {args.bits} bit, "
              f"{'stereo' if args.stereo or args.pan else 'mono'} (approximate preview)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
