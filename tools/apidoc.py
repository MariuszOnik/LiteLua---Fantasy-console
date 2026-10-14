#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# LiteLua - generates docs/API.md from the data files in docs/api/*.lua.
# The files only contain literals (see docs/api/README.md), so a small parser
# of Lua table constructors is enough.
#
# Usage: python tools/apidoc.py

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
API_DIR = ROOT / "docs" / "api"
OUT = ROOT / "docs" / "API.md"

# Module order in the generated document; others follow alphabetically
ORDER = ["core", "input", "gfx", "map", "sound", "files", "sys", "lua", "system"]

TOKEN_RE = re.compile(r"""
    (?P<ws>\s+)
  | (?P<lcomment>--\[(?P<lceq>=*)\[.*?\](?P=lceq)\])
  | (?P<comment>--[^\n]*)
  | (?P<lstring>\[(?P<lseq>=*)\[(?P<lsbody>.*?)\](?P=lseq)\])
  | (?P<string>"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')
  | (?P<number>0[xX][0-9a-fA-F]+|\d+(?:\.\d*)?(?:[eE][-+]?\d+)?)
  | (?P<name>[A-Za-z_][A-Za-z0-9_]*)
  | (?P<op>\.\.|[{}=,;\-])
""", re.VERBOSE | re.DOTALL)

ESCAPES = {"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def unescape(body):
    return re.sub(r"\\(.)", lambda m: ESCAPES.get(m.group(1), m.group(1)),
                  body, flags=re.DOTALL)


def tokenize(src, path):
    pos = 0
    while pos < len(src):
        m = TOKEN_RE.match(src, pos)
        if not m:
            sys.exit(f"{path}: unexpected text at offset {pos}: {src[pos:pos + 20]!r}")
        pos = m.end()
        kind = m.lastgroup
        if kind in ("ws", "comment", "lcomment"):
            continue
        if kind == "lstring":
            body = m.group("lsbody")
            if body.startswith("\r\n"):
                body = body[2:]
            elif body.startswith("\n"):
                body = body[1:]
            yield ("string", body)
        elif kind == "string":
            yield ("string", unescape(m.group(kind)[1:-1]))
        elif kind == "number":
            yield ("number", m.group(kind))
        elif kind in ("name", "op"):
            yield (m.group(kind), None)
        else:
            yield (kind, None)


class Parser:
    def __init__(self, tokens, path):
        self.toks = list(tokens)
        self.i = 0
        self.path = path

    def peek(self):
        return self.toks[self.i][0] if self.i < len(self.toks) else None

    def take(self, kind=None):
        tok = self.toks[self.i]
        if kind and tok[0] != kind:
            sys.exit(f"{self.path}: expected {kind!r}, got {tok[0]!r}")
        self.i += 1
        return tok

    def value(self):
        k = self.peek()
        if k == "{":
            return self.table()
        if k == "string":
            s = self.take()[1]
            while self.peek() == "..":
                self.take()
                s += self.take("string")[1]
            return s
        if k == "-":
            self.take()
            return -self.number()
        if k == "number":
            return self.number()
        if k in ("true", "false", "nil"):
            self.take()
            return {"true": True, "false": False, "nil": None}[k]
        sys.exit(f"{self.path}: unexpected token {k!r}")

    def number(self):
        text = self.take("number")[1]
        return int(text, 0) if re.fullmatch(r"0[xX].*|\d+", text) else float(text)

    def table(self):
        self.take("{")
        items, fields = [], {}
        while self.peek() != "}":
            k = self.peek()
            nxt = self.toks[self.i + 1][0] if self.i + 1 < len(self.toks) else None
            if k not in ("string", "number", "{", "-", "true", "false", "nil") and nxt == "=":
                self.take()
                self.take("=")
                fields[k] = self.value()
            else:
                items.append(self.value())
            if self.peek() in (",", ";"):
                self.take()
        self.take("}")
        if fields and items:
            sys.exit(f"{self.path}: mixed list/record tables are not supported")
        return fields if fields else items

    def chunk(self):
        self.take("return")
        v = self.value()
        if self.i != len(self.toks):
            sys.exit(f"{self.path}: trailing tokens after the returned table")
        return v


def load(path):
    src = path.read_text(encoding="utf-8")
    return Parser(tokenize(src, path), path).chunk()


def render_entry(e):
    out = [f"### `{e['name']}`", "", "```lua", e["sig"], "```", ""]
    if e.get("kind") not in (None, "function"):
        out[0] += f" — {e['kind']}"
    out.append(e.get("desc", ""))
    out.append("")
    if e.get("args"):
        out.append("| Argument | Type | Description |")
        out.append("|---|---|---|")
        for name, typ, desc in e["args"]:
            out.append(f"| `{name}` | {typ} | {desc} |")
        out.append("")
    if e.get("ret"):
        out.append("Returns: " + "; ".join(f"{typ} — {desc}" for typ, desc in e["ret"]))
        out.append("")
    if e.get("example"):
        out += ["Example:", "", "```lua", e["example"].rstrip(), "```", ""]
    return out


def main():
    mods = {p.stem: load(p) for p in API_DIR.glob("*.lua")}
    names = [n for n in ORDER if n in mods] + sorted(n for n in mods if n not in ORDER)

    out = ["# LiteLua API", "",
           "Generated by `tools/apidoc.py` from `docs/api/*.lua` — do not edit by hand.", ""]
    for n in names:
        m = mods[n]
        out.append(f"- [{m['title']}](#{m['title'].lower().replace(' ', '-')}) — {m['summary']}")
    out.append("")

    for n in names:
        m = mods[n]
        out += [f"## {m['title']}", "", m["summary"], ""]
        for e in m["entries"]:
            out += render_entry(e)

    OUT.write_text("\n".join(out), encoding="utf-8", newline="\n")
    print(f"{OUT.relative_to(ROOT)}: {sum(len(mods[n]['entries']) for n in names)} entries "
          f"in {len(names)} modules")


if __name__ == "__main__":
    main()
