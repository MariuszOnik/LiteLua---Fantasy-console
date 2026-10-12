# SPDX-License-Identifier: Zlib
#
# LiteLua - .lsong v1 songs (docs/LSONG.md, D36): a parser for the Lua data
# subset (nothing is executed), Lua and JSON writers, the validator and an
# approximate WAV renderer. Standard library only.

import json
import math
import re
import struct
import wave

MAX_FILE = 256 * 1024
MAX_DEPTH = 16
MAX_STRING = 512
NAME_RE = re.compile(r"^[a-z][a-z0-9_]{0,15}$")
LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for", "function",
    "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then",
    "true", "until", "while",
}


class LsongError(Exception):
    pass


# --- Lua data subset ----------------------------------------------------------

class _Lexer:
    """Tokens of the Lua data subset: { } [ ] = , ; - names strings numbers."""

    def __init__(self, text):
        self.s = text
        self.i = 0
        self.line = 1

    def error(self, msg):
        raise LsongError(f"line {self.line}: {msg}")

    def _long_bracket(self):
        # At '[': returns the closing bracket for [[ or [==[, or None
        m = re.compile(r"\[(=*)\[").match(self.s, self.i)
        if not m:
            return None
        self.i = m.end()
        return "]" + m.group(1) + "]"

    def _read_long(self, close):
        end = self.s.find(close, self.i)
        if end < 0:
            self.error("unfinished long string or comment")
        text = self.s[self.i:end]
        self.line += text.count("\n")
        self.i = end + len(close)
        return text

    def _skip(self):
        s = self.s
        while self.i < len(s):
            c = s[self.i]
            if c == "\n":
                self.line += 1
                self.i += 1
            elif c in " \t\r\f\v":
                self.i += 1
            elif s.startswith("--", self.i):
                self.i += 2
                if s.startswith("[", self.i):
                    close = self._long_bracket()
                    if close:
                        self._read_long(close)
                        continue
                while self.i < len(s) and s[self.i] != "\n":
                    self.i += 1
            else:
                break

    def _string(self, quote):
        s = self.s
        self.i += 1
        out = []
        esc = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f",
               "v": "\v", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}
        while True:
            if self.i >= len(s) or s[self.i] == "\n":
                self.error("unfinished string")
            c = s[self.i]
            if c == quote:
                self.i += 1
                return "".join(out)
            if c != "\\":
                out.append(c)
                self.i += 1
                continue
            self.i += 1
            c = s[self.i] if self.i < len(s) else ""
            if c in esc:
                out.append(esc[c])
                if c == "\n":
                    self.line += 1
                self.i += 1
            elif c == "x":
                h = s[self.i + 1:self.i + 3]
                if not re.fullmatch(r"[0-9a-fA-F]{2}", h):
                    self.error("bad \\x escape")
                out.append(chr(int(h, 16)))
                self.i += 3
            elif c.isdigit():
                m = re.compile(r"\d{1,3}").match(s, self.i)
                v = int(m.group())
                if v > 255:
                    self.error("bad decimal escape")
                out.append(chr(v))
                self.i = m.end()
            elif c == "z":
                self.i += 1
                while self.i < len(s) and s[self.i] in " \t\r\n\f\v":
                    if s[self.i] == "\n":
                        self.line += 1
                    self.i += 1
            elif c == "u":
                m = re.compile(r"u\{([0-9a-fA-F]{1,6})\}").match(s, self.i)
                if not m:
                    self.error("bad \\u escape")
                out.append(chr(int(m.group(1), 16)))
                self.i = m.end()
            else:
                self.error(f"bad escape \\{c}")

    NUM_RE = re.compile(r"0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?")

    def next(self):
        """Returns (kind, value): kind is one of { } [ ] = , ; - name str num eof"""
        self._skip()
        s = self.s
        if self.i >= len(s):
            return ("eof", None)
        c = s[self.i]
        if c in "{}]=,;-":
            self.i += 1
            return (c, None)
        if c == "[":
            close = self._long_bracket()
            if close:
                text = self._read_long(close)
                if text.startswith("\r\n"):
                    text = text[2:]
                elif text.startswith("\n"):
                    text = text[1:]
                return ("str", text)
            self.i += 1
            return ("[", None)
        if c in "\"'":
            return ("str", self._string(c))
        if c.isdigit() or (c == "." and self.i + 1 < len(s) and s[self.i + 1].isdigit()):
            m = self.NUM_RE.match(s, self.i)
            text = m.group()
            self.i = m.end()
            if self.i < len(s) and (s[self.i].isalnum() or s[self.i] in "._"):
                self.error(f"malformed number near '{text}{s[self.i]}'")
            if text[:2] in ("0x", "0X"):
                return ("num", int(text, 16))
            if re.fullmatch(r"\d+", text):
                return ("num", int(text))
            return ("num", float(text))
        m = re.compile(r"[A-Za-z_][A-Za-z0-9_]*").match(s, self.i)
        if m:
            self.i = m.end()
            return ("name", m.group())
        self.error(f"unexpected character '{c}'")


def parse_lua(text):
    """Parses 'return <value>' of the Lua data subset (docs/LSONG.md section 8).
    Nothing is executed: loops, functions and expressions are syntax errors."""
    if len(text.encode("utf-8")) > MAX_FILE:
        raise LsongError(f"file is larger than {MAX_FILE // 1024} KB")
    if text.startswith("﻿"):
        text = text[1:]
    lx = _Lexer(text)
    tok = [lx.next()]

    def peek():
        return tok[0]

    def take():
        t = tok[0]
        tok[0] = lx.next()
        return t

    def expect(kind):
        t = take()
        if t[0] != kind:
            lx.error(f"'{kind}' expected")
        return t

    def value(depth):
        kind, v = take()
        if kind == "{":
            if depth >= MAX_DEPTH:
                lx.error(f"tables nested deeper than {MAX_DEPTH}")
            return table(depth + 1)
        if kind == "str":
            if len(v) > MAX_STRING:
                lx.error(f"string longer than {MAX_STRING} characters")
            return v
        if kind == "num":
            return v
        if kind == "-":
            k2, v2 = take()
            if k2 != "num":
                lx.error("a number expected after '-'")
            return -v2
        if kind == "name" and v in ("true", "false"):
            return v == "true"
        if kind == "name" and v == "nil":
            lx.error("nil is not allowed (leave the field out)")
        if kind == "name":
            lx.error(f"'{v}' is not data (variables, calls and code are not allowed)")
        lx.error("a value expected")

    def table(depth):
        items, fields = [], {}
        while peek()[0] != "}":
            kind, v = peek()
            key = None
            if kind == "name" and v not in ("true", "false", "nil"):
                take()
                if peek()[0] != "=":
                    lx.error(f"'=' expected after '{v}' (code is not allowed)")
                take()
                key = v
            elif kind == "[":
                take()
                k2, kv = take()
                if k2 != "str":
                    lx.error("only string keys are allowed: [\"name\"] = value")
                expect("]")
                expect("=")
                key = kv
            val = value(depth)
            if key is None:
                items.append(val)
            else:
                if key in fields:
                    lx.error(f"key '{key}' appears twice")
                fields[key] = val
            if peek()[0] in (",", ";"):
                take()
            elif peek()[0] != "}":
                lx.error("',' or '}' expected")
        take()
        if items and fields:
            lx.error("a table mixes list items and keyed fields")
        return fields if fields else items

    kind, v = take()
    if kind != "name" or v != "return":
        lx.error("the file must start with 'return' followed by a table")
    result = value(0)
    if peek()[0] != "eof":
        lx.error("only one value may follow 'return'")
    return result


def parse_json(text):
    if len(text.encode("utf-8")) > MAX_FILE:
        raise LsongError(f"file is larger than {MAX_FILE // 1024} KB")

    def no_dupes(pairs):
        d = {}
        for k, v in pairs:
            if k in d:
                raise LsongError(f"key '{k}' appears twice")
            d[k] = v
        return d

    try:
        return json.loads(text, object_pairs_hook=no_dupes)
    except json.JSONDecodeError as e:
        raise LsongError(f"line {e.lineno}: {e.msg}") from None


def load(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    return parse_json(text) if str(path).lower().endswith(".json") else parse_lua(text)


# --- Writers ------------------------------------------------------------------

def _is_scalar(v):
    return not isinstance(v, (dict, list))


def _inline(v):
    """Short tables of scalars (notes, envelopes) are written on one line."""
    items = v.values() if isinstance(v, dict) else v
    return all(_is_scalar(x) for x in items) and len(v) <= 16


def _num(v):
    if isinstance(v, bool):
        raise LsongError("bool where a number is expected")
    if isinstance(v, int):
        return str(v)
    r = repr(float(v))
    return r if ("." in r or "e" in r or "inf" in r or "nan" in r) else r + ".0"


def _lua_str(s):
    out = ['"']
    for c in s:
        if c == '"':
            out.append('\\"')
        elif c == "\\":
            out.append("\\\\")
        elif c == "\n":
            out.append("\\n")
        elif ord(c) < 32 or ord(c) == 127:
            out.append(f"\\{ord(c)}")
        else:
            out.append(c)
    out.append('"')
    return "".join(out)


def _lua_key(k):
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k) and k not in LUA_KEYWORDS:
        return k
    return f"[{_lua_str(k)}]"


def _write(v, lua, indent):
    pad, inner = "  " * indent, "  " * (indent + 1)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return _num(v)
    if isinstance(v, str):
        return _lua_str(v) if lua else json.dumps(v, ensure_ascii=False)
    if isinstance(v, dict):
        if lua:
            parts = [f"{_lua_key(k)} = {_write(x, lua, indent + 1)}" for k, x in v.items()]
            open_, close = "{", "}"
        else:
            parts = [f"{json.dumps(k, ensure_ascii=False)}: {_write(x, lua, indent + 1)}"
                     for k, x in v.items()]
            open_, close = "{", "}"
    else:
        parts = [_write(x, lua, indent + 1) for x in v]
        open_, close = ("{", "}") if lua else ("[", "]")
    if not parts:
        return open_ + close
    if _inline(v):
        return open_ + (" " if lua else "") + ", ".join(parts) + (" " if lua else "") + close
    sep = ",\n" + inner
    return open_ + "\n" + inner + sep.join(parts) + ("," if lua else "") + "\n" + pad + close


def to_lua(song):
    return "-- LiteLua song (.lsong v1, docs/LSONG.md)\nreturn " + _write(song, True, 0) + "\n"


def to_json(song):
    return _write(song, False, 0) + "\n"


# --- Validation ---------------------------------------------------------------

TOP_FIELDS = {"lsong", "title", "author", "comment", "tempo", "ppq", "meter",
              "profile", "instruments", "tracks", "patterns", "playlist", "loop"}
INSTR_FIELDS = {
    "pulse": {"type", "volume", "duty", "env", "release", "arp", "vibrato"},
    "triangle": {"type", "volume", "env", "release", "arp", "vibrato"},
    "noise": {"type", "volume", "mode", "env", "release", "arp", "vibrato"},
    "kit": {"type", "drums"},
}
DUTIES = (0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875)
NES_DUTIES = (0.125, 0.25, 0.5, 0.75)
PROFILE_LIMITS = {
    "nes": {"pulse": 2, "triangle": 1, "noise": 1, "total": 4},
    "extended": {"pulse": 6, "triangle": 2, "noise": 2, "total": 8},
}
MAX_NOTES = 16384
MAX_TRACK_NOTES = 1024
MAX_SECONDS = 30 * 60


class Report:
    def __init__(self):
        self.errors, self.warnings = [], []

    def err(self, path, msg):
        self.errors.append(f"{path}: {msg}")

    def warn(self, path, msg):
        self.warnings.append(f"{path}: {msg}")


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _unknown(r, path, d, allowed):
    for k in d:
        if k not in allowed and not k.startswith("x_"):
            r.err(path, f"unknown field '{k}'")


def _int(r, path, v, lo, hi):
    if not _is_int(v):
        r.err(path, "must be an integer")
        return False
    if not lo <= v <= hi:
        r.err(path, f"must be {lo} .. {hi}, not {v}")
        return False
    return True


def _numr(r, path, v, lo, hi):
    if not _is_num(v):
        r.err(path, "must be a number")
        return False
    if not lo <= v <= hi:
        r.err(path, f"must be {lo} .. {hi}, not {v}")
        return False
    return True


def _map(r, path, v, lo=0, hi=None):
    if isinstance(v, list) and not v:
        v = {}
    if not isinstance(v, dict):
        r.err(path, "must be a table of named fields")
        return None
    if hi is not None and not lo <= len(v) <= hi:
        r.err(path, f"must have {lo} .. {hi} entries, not {len(v)}")
    return v


def _list(r, path, v, lo, hi):
    if isinstance(v, dict) and not v:
        v = []
    if not isinstance(v, list):
        r.err(path, "must be a list")
        return None
    if not lo <= len(v) <= hi:
        r.err(path, f"must have {lo} .. {hi} entries, not {len(v)}")
    return v


def _num_list(r, path, v, lo, hi, n, integer=False):
    v = _list(r, path, v, 1, n)
    if v is None:
        return
    for i, x in enumerate(v):
        (_int if integer else _numr)(r, f"{path}[{i + 1}]", x, lo, hi)


def _instrument_kind(instruments, name):
    """pulse/triangle/noise, the kind of a kit's drums, or None if unknown."""
    ins = instruments.get(name)
    if not isinstance(ins, dict):
        return None
    if ins.get("type") != "kit":
        return ins.get("type")
    kinds = {_instrument_kind(instruments, d.get("i")) for d in ins.get("drums", [])
             if isinstance(d, dict) and instruments.get(d.get("i"), {}).get("type") != "kit"}
    return kinds.pop() if len(kinds) == 1 else None


def validate(song):
    r = Report()
    if not isinstance(song, dict):
        r.err("song", "must be a table of named fields")
        return r
    _unknown(r, "song", song, TOP_FIELDS)
    for f in ("lsong", "tempo", "instruments", "tracks", "patterns", "playlist"):
        if f not in song:
            r.err("song", f"'{f}' is missing")
    if "lsong" in song and song["lsong"] != 1:
        r.err("lsong", f"version {song['lsong']!r}; this tool reads version 1")
    for f, n in (("title", 64), ("author", 64), ("comment", 512)):
        if f in song and not (isinstance(song[f], str) and len(song[f]) <= n):
            r.err(f, f"must be a string of at most {n} characters")
    if "tempo" in song:
        _numr(r, "tempo", song["tempo"], 20, 400)
    ppq = song.get("ppq", 24)
    if not _int(r, "ppq", ppq, 1, 96):
        ppq = 24
    if "meter" in song:
        m = song["meter"]
        if not (isinstance(m, list) and len(m) == 2):
            r.err("meter", "must be {num, den}")
        else:
            _int(r, "meter[1]", m[0], 1, 32)
            if m[1] not in (1, 2, 4, 8, 16) or not _is_int(m[1]):
                r.err("meter[2]", "must be 1, 2, 4, 8 or 16")
    profile = song.get("profile", "nes")
    if profile not in PROFILE_LIMITS:
        r.err("profile", "must be \"nes\" or \"extended\"")
        profile = "nes"

    # Instruments
    instruments = _map(r, "instruments", song.get("instruments", {}), 1, 32) or {}
    for name, ins in instruments.items():
        p = f"instruments.{name}"
        if not NAME_RE.match(name):
            r.err(p, "bad name (a-z, 0-9, _, starting with a letter, at most 16)")
        if not isinstance(ins, dict):
            r.err(p, "must be a table of named fields")
            continue
        t = ins.get("type")
        if t not in INSTR_FIELDS:
            r.err(p, "type must be \"pulse\", \"triangle\", \"noise\" or \"kit\"")
            continue
        _unknown(r, p, ins, INSTR_FIELDS[t])
        if "volume" in ins:
            _numr(r, p + ".volume", ins["volume"], 0, 1)
        if "duty" in ins:
            if ins["duty"] not in DUTIES:
                r.err(p + ".duty", "must be 0.125, 0.25, 0.375, 0.5, 0.625, 0.75 or 0.875")
            elif profile == "nes" and ins["duty"] not in NES_DUTIES:
                r.err(p + ".duty", "profile nes allows 0.125, 0.25, 0.5 and 0.75")
        if "mode" in ins and ins["mode"] not in ("long", "short"):
            r.err(p + ".mode", "must be \"long\" or \"short\"")
        if "env" in ins:
            _num_list(r, p + ".env", ins["env"], 0, 1, 64)
        if "release" in ins:
            _num_list(r, p + ".release", ins["release"], 0, 1, 64)
        if "arp" in ins:
            _num_list(r, p + ".arp", ins["arp"], -24, 24, 32, integer=True)
        if "vibrato" in ins:
            vb = _map(r, p + ".vibrato", ins["vibrato"])
            if vb is not None:
                _unknown(r, p + ".vibrato", vb, {"depth", "rate", "delay"})
                _numr(r, p + ".vibrato.depth", vb.get("depth", 0), 0, 2)
                _numr(r, p + ".vibrato.rate", vb.get("rate", 0), 0, 20)
                _int(r, p + ".vibrato.delay", vb.get("delay", 0), 0, 255)
        if t == "kit":
            drums = _list(r, p + ".drums", ins.get("drums"), 1, 128) or []
            seen, kinds = set(), set()
            for i, d in enumerate(drums):
                dp = f"{p}.drums[{i + 1}]"
                if not isinstance(d, dict):
                    r.err(dp, "must be {p =, i =, to =}")
                    continue
                _unknown(r, dp, d, {"p", "i", "to"})
                if _int(r, dp + ".p", d.get("p"), 0, 127):
                    if d["p"] in seen:
                        r.err(dp + ".p", f"pitch {d['p']} is mapped twice")
                    seen.add(d["p"])
                if "to" in d:
                    _int(r, dp + ".to", d["to"], 0, 127)
                target = instruments.get(d.get("i"))
                if not isinstance(target, dict):
                    r.err(dp + ".i", f"unknown instrument {d.get('i')!r}")
                elif target.get("type") == "kit":
                    r.err(dp + ".i", "a drum cannot be a kit")
                else:
                    kinds.add(target.get("type"))
            if len(kinds) > 1:
                r.err(p + ".drums", "all drums of a kit must have the same type")

    # Tracks
    tracks = _list(r, "tracks", song.get("tracks", []), 1, 8) or []
    track_kind, counts = {}, {"pulse": 0, "triangle": 0, "noise": 0}
    for i, tr in enumerate(tracks):
        p = f"tracks[{i + 1}]"
        if not isinstance(tr, dict):
            r.err(p, "must be {name =, instrument =}")
            continue
        _unknown(r, p, tr, {"name", "instrument"})
        name = tr.get("name")
        if not isinstance(name, str) or not NAME_RE.match(name):
            r.err(p + ".name", "bad or missing name")
            continue
        if name in track_kind:
            r.err(p + ".name", f"track '{name}' appears twice")
        kind = _instrument_kind(instruments, tr.get("instrument"))
        if tr.get("instrument") not in instruments:
            r.err(p + ".instrument", f"unknown instrument {tr.get('instrument')!r}")
        elif kind is None:
            r.err(p + ".instrument", "the kit has no valid drums")
        else:
            counts[kind] += 1
        track_kind[name] = kind
    lim = PROFILE_LIMITS[profile]
    for k in ("pulse", "triangle", "noise"):
        if counts[k] > lim[k]:
            r.err("tracks", f"profile {profile} allows at most {lim[k]} {k} tracks, not {counts[k]}")
    if len(tracks) > lim["total"]:
        r.err("tracks", f"profile {profile} allows at most {lim['total']} tracks")

    # Patterns
    patterns = _map(r, "patterns", song.get("patterns", {}), 1, 256) or {}
    total_notes, used_instr = 0, {tr.get("instrument") for tr in tracks if isinstance(tr, dict)}
    for pname, pat in patterns.items():
        p = f"patterns.{pname}"
        if not NAME_RE.match(pname):
            r.err(p, "bad name (a-z, 0-9, _, starting with a letter, at most 16)")
        if not isinstance(pat, dict):
            r.err(p, "must be {length =, notes =}")
            continue
        _unknown(r, p, pat, {"length", "notes"})
        length = pat.get("length")
        if not _int(r, p + ".length", length, 1, ppq * 64):
            length = None
        notes = _map(r, p + ".notes", pat.get("notes", {})) or {}
        for tname, lst in notes.items():
            tp = f"{p}.notes.{tname}"
            if tname not in track_kind:
                r.err(tp, f"there is no track '{tname}'")
                continue
            lst = _list(r, tp, lst, 0, MAX_TRACK_NOTES)
            if lst is None:
                continue
            total_notes += len(lst)
            good = []
            for i, n in enumerate(lst):
                np_ = f"{tp}[{i + 1}]"
                if not isinstance(n, dict):
                    r.err(np_, "a note must be {t =, d =, p =}")
                    continue
                _unknown(r, np_, n, {"t", "d", "p", "v", "i", "s"})
                ok = all([
                    _int(r, np_ + ".t", n.get("t"), 0, (length or 1 << 30) - 1),
                    _int(r, np_ + ".d", n.get("d"), 1, 1 << 30),
                    _int(r, np_ + ".p", n.get("p"), 0, 127)])
                if "v" in n:
                    _numr(r, np_ + ".v", n["v"], 0, 1)
                if "s" in n:
                    _int(r, np_ + ".s", n["s"], -24, 24)
                tr_ins = next((tr.get("instrument") for tr in tracks
                               if isinstance(tr, dict) and tr.get("name") == tname), None)
                ins_name = n.get("i", tr_ins)
                if "i" in n:
                    used_instr.add(n["i"])
                    if n["i"] not in instruments:
                        r.err(np_ + ".i", f"unknown instrument {n['i']!r}")
                        continue
                    if _instrument_kind(instruments, n["i"]) != track_kind[tname]:
                        r.err(np_ + ".i", f"instrument '{n['i']}' does not fit "
                                          f"a {track_kind[tname]} track")
                ins = instruments.get(ins_name)
                if ok and isinstance(ins, dict) and ins.get("type") == "kit":
                    if n["p"] not in {d.get("p") for d in ins.get("drums", []) if isinstance(d, dict)}:
                        r.err(np_ + ".p", f"pitch {n['p']} is not a drum of kit '{ins_name}'")
                if ok:
                    good.append((n["t"], n["d"], i + 1))
            good.sort()
            for a, b in zip(good, good[1:]):
                if a[0] == b[0]:
                    r.err(tp, f"notes {a[2]} and {b[2]} start at the same tick {a[0]}")
                elif a[0] + a[1] > b[0]:
                    r.warn(tp, f"note {a[2]} is cut by note {b[2]} (one note at a time)")
            if length:
                for t, d, i in good:
                    if t + d > length:
                        r.warn(f"{tp}[{i}]", "lasts past the pattern end (cut there)")
    if total_notes > MAX_NOTES:
        r.err("patterns", f"{total_notes} notes; at most {MAX_NOTES}")
    kit_drums = {d.get("i") for ins in instruments.values() if isinstance(ins, dict)
                 for d in (ins.get("drums") if isinstance(ins.get("drums"), list) else [])
                 if isinstance(d, dict)}
    for name in instruments:
        if name not in used_instr and name not in kit_drums:
            r.warn(f"instruments.{name}", "is never used")

    # Playlist
    playlist = _list(r, "playlist", song.get("playlist", []), 1, 256) or []
    used_pat, total_ticks = set(), 0
    for i, e in enumerate(playlist):
        p = f"playlist[{i + 1}]"
        if not isinstance(e, dict):
            r.err(p, "must be {pattern =, times =, transpose =}")
            continue
        _unknown(r, p, e, {"pattern", "times", "transpose"})
        pat = patterns.get(e.get("pattern"))
        if not isinstance(pat, dict):
            r.err(p + ".pattern", f"unknown pattern {e.get('pattern')!r}")
            continue
        used_pat.add(e["pattern"])
        times = e.get("times", 1)
        _int(r, p + ".times", times, 1, 64)
        tr = e.get("transpose", 0)
        if _int(r, p + ".transpose", tr, -24, 24) and tr:
            for tname, lst in (pat.get("notes") or {}).items():
                tr_ins = next((t.get("instrument") for t in tracks
                               if isinstance(t, dict) and t.get("name") == tname), None)
                for n in lst if isinstance(lst, list) else []:
                    if not isinstance(n, dict) or not _is_int(n.get("p")):
                        continue
                    ins = instruments.get(n.get("i", tr_ins))
                    if isinstance(ins, dict) and ins.get("type") == "kit":
                        continue
                    if not 0 <= n["p"] + tr <= 127:
                        r.err(p + ".transpose", f"moves a note of track '{tname}' "
                                                f"out of 0 .. 127")
                        break
        if _is_int(times) and _is_int(pat.get("length")):
            total_ticks += times * pat["length"]
    for name in patterns:
        if name not in used_pat:
            r.warn(f"patterns.{name}", "is not in the playlist")
    loop = song.get("loop", 1)
    if loop is not False:
        _int(r, "loop", loop, 1, max(1, len(playlist)))
    tempo = song.get("tempo")
    if _is_num(tempo) and tempo > 0 and total_ticks:
        seconds = total_ticks * 60 / (tempo * ppq)
        if seconds > MAX_SECONDS:
            r.err("playlist", f"plays {seconds / 60:.0f} minutes; at most 30")
    return r


def duration(song):
    """Seconds of the playlist played once."""
    ppq = song.get("ppq", 24)
    ticks = sum(e.get("times", 1) * song["patterns"][e["pattern"]]["length"]
                for e in song["playlist"])
    return ticks * 60 / (song["tempo"] * ppq)


# --- Renderer -----------------------------------------------------------------

FRAME_RATE = 60
TRI_STEPS = [15 - i for i in range(16)] + list(range(16))  # NES-like 32 steps


def _events(song, loops):
    """Per track: notes in absolute ticks [(start, end, pitch, vel, ins, slide)],
    and the total length in ticks."""
    instruments = song["instruments"]
    tracks = song["tracks"]
    entries = list(song["playlist"])
    loop = song.get("loop", 1)
    if loop is not False and loops > 1:
        entries += entries[loop - 1:] * (loops - 1)
    out = {tr["name"]: [] for tr in tracks}
    pos = 0
    for e in entries:
        pat = song["patterns"][e["pattern"]]
        length = pat["length"]
        for _ in range(e.get("times", 1)):
            for tr in tracks:
                notes = sorted((pat.get("notes") or {}).get(tr["name"], []) or [],
                               key=lambda n: n["t"])
                for k, n in enumerate(notes):
                    end = min(n["t"] + n["d"], length)
                    if k + 1 < len(notes):
                        end = min(end, notes[k + 1]["t"])
                    ins_name = n.get("i", tr["instrument"])
                    ins = instruments[ins_name]
                    pitch = n["p"]
                    if ins["type"] == "kit":
                        drum = next(d for d in ins["drums"] if d["p"] == pitch)
                        ins = instruments[drum["i"]]
                        pitch = drum.get("to", drum["p"])
                    else:
                        pitch += e.get("transpose", 0)
                    out[tr["name"]].append((pos + n["t"], pos + end, pitch,
                                            n.get("v", 1), ins, n.get("s", 0)))
            pos += length
    return out, pos


def _freq(pitch):
    return 440.0 * 2 ** ((pitch - 69) / 12)


def _render_track(notes, total, rate, tick_s):
    buf = [0.0] * total
    lfsr = 1
    phase = 0.0
    spf = rate / FRAME_RATE
    for k, (t0, t1, pitch, vel, ins, slide) in enumerate(notes):
        start = int(t0 * tick_s * rate)
        off = int(t1 * tick_s * rate)
        release = ins.get("release") or []
        stop = off + int(len(release) * spf)
        if k + 1 < len(notes):
            stop = min(stop, int(notes[k + 1][0] * tick_s * rate))
        stop = min(stop, total)
        kind = ins["type"]
        duty = ins.get("duty", 0.5)
        env = ins.get("env") or [1]
        arp = ins.get("arp") or [0]
        vib = ins.get("vibrato") or {}
        depth, vrate, vdelay = vib.get("depth", 0), vib.get("rate", 0), vib.get("delay", 0)
        tap = 6 if ins.get("mode") == "short" else 1
        amp_base = ins.get("volume", 1) * vel * 0.22
        note_len = max(1, off - start)
        s = start
        frame = 0
        while s < stop:
            e = min(stop, start + int((frame + 1) * spf))
            if s < off:
                level = env[min(frame, len(env) - 1)]
            else:
                rf = int((s - off) / spf)
                level = release[min(rf, len(release) - 1)]
            semis = pitch + arp[frame % len(arp)]
            if slide:
                semis += slide * min(1.0, (s - start) / note_len)
            if depth and frame >= vdelay:
                semis += depth * math.sin(2 * math.pi * vrate * (frame - vdelay) / FRAME_RATE)
            amp = amp_base * level
            if kind == "noise":
                step = 440.0 * 2 ** ((semis - 21) / 12) / rate
                for i in range(s, e):
                    phase += step
                    if phase >= 1:
                        phase -= int(phase)
                        bit = (lfsr ^ (lfsr >> tap)) & 1
                        lfsr = (lfsr >> 1) | (bit << 14)
                    buf[i] += amp if lfsr & 1 == 0 else -amp
            elif kind == "triangle":
                step = _freq(semis) / rate
                for i in range(s, e):
                    phase = (phase + step) % 1.0
                    buf[i] += amp * (TRI_STEPS[int(phase * 32)] / 7.5 - 1)
            else:
                step = _freq(semis) / rate
                for i in range(s, e):
                    phase = (phase + step) % 1.0
                    buf[i] += amp if phase < duty else -amp
            s = e
            frame += 1
    return buf


def render(song, path, rate=22050, bits=16, loops=1):
    """Approximate preview (not an emulation): writes a mono WAV. Returns seconds."""
    tick_s = 60 / (song["tempo"] * song.get("ppq", 24))
    events, ticks = _events(song, loops)
    total = int(ticks * tick_s * rate) + rate // 2  # Room for the last release
    mix = [0.0] * total
    for notes in events.values():
        tb = _render_track(notes, total, rate, tick_s)
        for i, v in enumerate(tb):
            mix[i] += v
    # DC blocker (like the output filter of a console), then clip
    out = bytearray()
    prev_x = prev_y = 0.0
    a = 1 - 2 * math.pi * 30 / rate
    for x in mix:
        y = x - prev_x + a * prev_y
        prev_x, prev_y = x, y
        y = max(-1.0, min(1.0, y))
        if bits == 8:
            out.append(int(y * 127) + 128)
        else:
            out += struct.pack("<h", int(y * 32767))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(bits // 8)
        w.setframerate(rate)
        w.writeframes(bytes(out))
    return total / rate

