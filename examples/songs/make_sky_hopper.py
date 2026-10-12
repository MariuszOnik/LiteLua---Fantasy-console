#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# Writes sky_hopper.lsong (and .lsong.json): the example song of the .lsong
# format (docs/LSONG.md). A cheerful NES-style platformer tune in C major:
# pulse lead, arpeggio chords on the second pulse, bouncing triangle bass,
# noise drums. Notes are written here as (name, length) lists.
#
#   python examples/songs/make_sky_hopper.py

import pathlib
import sys

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE.parent.parent / "tools"))
import lsong  # noqa: E402

BAR = 96  # ppq 24, 4/4
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    return 12 * (int(name[-1]) + 1) + NOTE[name[0]] + name[1:-1].count("#")


def melody(*bars):
    """Bars of (note or None, ticks) -> notes, slightly detached (NES bounce)"""
    notes, t = [], 0
    for bar in bars:
        start = t
        for name, length in bar:
            if name:
                notes.append({"t": t, "d": length - 2, "p": midi(name)})
            t += length
        assert t - start == BAR, f"bar at {start} has {t - start} ticks"
    return notes


ROOT = {"C": 60, "Am": 57, "F": 53, "G": 55, "Em": 52, "Dm": 50}


def chords(*bars):
    """One or two chords per bar: stabs on the off-beats, major/minor arpeggio"""
    notes = []
    for b, bar in enumerate(bars):
        bar = bar if isinstance(bar, tuple) else (bar, bar)
        for k, t in enumerate((12, 36, 60, 84)):
            ch = bar[k // 2]
            n = {"t": b * BAR + t, "d": 10, "p": ROOT[ch]}
            if ch.endswith("m"):
                n["i"] = "chord_min"
            notes.append(n)
    return notes


def bass(*bars):
    """Root on the beat, octave up on the off-beat"""
    notes = []
    for b, bar in enumerate(bars):
        bar = bar if isinstance(bar, tuple) else (bar, bar)
        for beat in range(4):
            root = ROOT[bar[beat // 2]] - 12
            t = b * BAR + beat * 24
            notes.append({"t": t, "d": 11, "p": root})
            notes.append({"t": t + 12, "d": 11, "p": root + 12})
    return notes


KICK, SNARE, HAT = 36, 38, 42


def drums(bars, fill_last=False):
    notes = []
    for b in range(bars):
        o = b * BAR
        hits = [(0, KICK), (48, KICK), (24, SNARE), (12, HAT), (36, HAT), (60, HAT)]
        if fill_last and b == bars - 1:
            hits += [(72, SNARE), (78, SNARE), (84, SNARE), (90, SNARE)]
        else:
            hits += [(72, SNARE), (84, HAT)]
        notes += [{"t": o + t, "d": 6, "p": p} for t, p in sorted(hits)]
    return notes


A_MELODY = melody(
    [("E5", 12), ("G5", 12), ("C6", 24), ("B5", 12), ("G5", 12), ("E5", 24)],
    [("A5", 12), ("C6", 12), ("E6", 24), ("D6", 12), ("C6", 12), ("A5", 24)],
    [("F5", 12), ("A5", 12), ("C6", 12), ("A5", 12), ("F5", 12), ("A5", 12), ("C6", 24)],
    [("B5", 12), ("D6", 12), ("G6", 24), ("F6", 12), ("D6", 12), ("B5", 12), ("G5", 12)],
    [("E5", 12), ("G5", 12), ("C6", 12), ("E6", 12), ("D6", 12), ("C6", 12), ("G5", 24)],
    [("A5", 12), ("C6", 12), ("E6", 12), ("A6", 12), ("G6", 12), ("E6", 12), ("C6", 24)],
    [("F6", 12), ("E6", 12), ("D6", 12), ("C6", 12), ("B5", 12), ("C6", 12), ("D6", 24)],
    [("C6", 36), (None, 24), ("G5", 12), ("A5", 12), ("B5", 12)],
)
A_CHORDS = ("C", "Am", "F", "G", "C", "Am", ("F", "G"), "C")

B_MELODY = melody(
    [("C6", 12), ("A5", 12), ("C6", 12), ("F6", 24), ("E6", 12), ("D6", 12), ("C6", 12)],
    [("D6", 12), ("B5", 12), ("D6", 12), ("G6", 24), ("F6", 12), ("E6", 12), ("D6", 12)],
    [("E6", 12), ("D6", 12), ("B5", 12), ("G5", 12), ("C6", 12), ("E6", 12), ("A6", 24)],
    [("F6", 12), ("E6", 12), ("D6", 12), ("A5", 12), ("B5", 24), ("D6", 12), ("G6", 12)],
)
B_CHORDS = ("F", "G", ("Em", "Am"), ("Dm", "G"))

INTRO_LEAD = melody([(None, 96)], [(None, 60), ("G5", 12), ("A5", 12), ("B5", 12)])

song = {
    "lsong": 1,
    "title": "Sky Hopper",
    "author": "Claude (LiteLua example)",
    "comment": "Example song of the .lsong v1 format. License: zlib, like LiteLua.",
    "tempo": 150,
    "ppq": 24,
    "meter": [4, 4],
    "profile": "nes",
    "instruments": {
        "lead": {"type": "pulse", "duty": 0.25, "volume": 0.75,
                 "env": [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7],
                 "release": [0.45, 0.25, 0.1],
                 "vibrato": {"depth": 0.15, "rate": 6, "delay": 14}},
        "chord_maj": {"type": "pulse", "duty": 0.125, "volume": 0.35,
                      "env": [1, 0.8, 0.65, 0.5, 0.4], "arp": [0, 4, 7]},
        "chord_min": {"type": "pulse", "duty": 0.125, "volume": 0.35,
                      "env": [1, 0.8, 0.65, 0.5, 0.4], "arp": [0, 3, 7]},
        "bass": {"type": "triangle", "volume": 0.9},
        "kick": {"type": "noise", "env": [1, 0.75, 0.45, 0.2, 0]},
        "snare": {"type": "noise", "volume": 0.8,
                  "env": [1, 0.85, 0.65, 0.45, 0.3, 0.15, 0]},
        "hat": {"type": "noise", "mode": "short", "volume": 0.45, "env": [1, 0.4, 0]},
        "drums": {"type": "kit", "drums": [
            {"p": KICK, "i": "kick", "to": 32},
            {"p": SNARE, "i": "snare", "to": 64},
            {"p": HAT, "i": "hat", "to": 104},
        ]},
    },
    "tracks": [
        {"name": "lead", "instrument": "lead"},
        {"name": "chords", "instrument": "chord_maj"},
        {"name": "bass", "instrument": "bass"},
        {"name": "drums", "instrument": "drums"},
    ],
    "patterns": {
        "intro": {"length": 2 * BAR, "notes": {
            "lead": INTRO_LEAD,
            "chords": chords("C", "G"),
            "bass": bass("C", "G"),
            "drums": drums(2, fill_last=True),
        }},
        "a": {"length": 8 * BAR, "notes": {
            "lead": A_MELODY,
            "chords": chords(*A_CHORDS),
            "bass": bass(*A_CHORDS),
            "drums": drums(8, fill_last=True),
        }},
        "b": {"length": 4 * BAR, "notes": {
            "lead": B_MELODY,
            "chords": chords(*B_CHORDS),
            "bass": bass(*B_CHORDS),
            "drums": drums(4, fill_last=True),
        }},
    },
    "playlist": [
        {"pattern": "intro"},
        {"pattern": "a", "times": 2},
        {"pattern": "b"},
        {"pattern": "b", "transpose": 2},
        {"pattern": "a"},
    ],
    "loop": 2,
}

if __name__ == "__main__":
    (HERE / "sky_hopper.lsong").write_text(lsong.to_lua(song), encoding="utf-8", newline="\n")
    (HERE / "sky_hopper.lsong.json").write_text(lsong.to_json(song), encoding="utf-8",
                                                newline="\n")
    print("sky_hopper.lsong, sky_hopper.lsong.json")
