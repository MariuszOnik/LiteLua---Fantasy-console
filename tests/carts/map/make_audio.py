#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# Music and sound effects of the map test cart (P8), made here so the cart
# needs no third party files:
#   music/grass_run.lsong   "Grass Run", a NES-style platformer tune in G major
#   sfx/jump.wav            rising square chirp
#   sfx/coin.wav            two-tone pickup
#   sfx/hurt.wav            noise burst falling down
#
#   python tests/carts/map/make_audio.py

import math
import pathlib
import random
import struct
import sys
import wave

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE.parent.parent.parent / "tools"))
import lsong  # noqa: E402

# --- music --------------------------------------------------------------------

BAR = 96  # ppq 24, 4/4
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    return 12 * (int(name[-1]) + 1) + NOTE[name[0]] + name[1:-1].count("#")


def melody(*bars):
    """Bars of (note or None, ticks) -> slightly detached notes"""
    notes, t = [], 0
    for bar in bars:
        start = t
        for name, length in bar:
            if name:
                notes.append({"t": t, "d": length - 2, "p": midi(name)})
            t += length
        assert t - start == BAR, f"bar at {start} has {t - start} ticks"
    return notes


ROOT = {"G": 55, "Em": 52, "C": 60, "D": 50, "Am": 57, "Bm": 59}


def chords(*bars):
    """Off-beat stabs, two chords per bar when given as a pair"""
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
    """Root, fifth, octave, fifth: a walking bounce"""
    notes = []
    for b, bar in enumerate(bars):
        bar = bar if isinstance(bar, tuple) else (bar, bar)
        for beat in range(4):
            root = ROOT[bar[beat // 2]] - 12
            step = (0, 7, 12, 7)[beat]
            t = b * BAR + beat * 24
            notes.append({"t": t, "d": 10, "p": root + step})
            notes.append({"t": t + 12, "d": 8, "p": root + step})
    return notes


KICK, SNARE, HAT = 36, 38, 42


def drums(bars, fill_last=False):
    notes = []
    for b in range(bars):
        o = b * BAR
        hits = [(0, KICK), (24, SNARE), (36, KICK), (48, KICK), (72, SNARE)]
        hits += [(t, HAT) for t in (12, 60, 84)]
        if fill_last and b == bars - 1:
            hits = [h for h in hits if h[0] < 72] + [(72, SNARE), (78, SNARE),
                                                      (84, SNARE), (90, SNARE)]
        notes += [{"t": o + t, "d": 6, "p": p} for t, p in sorted(hits)]
    return notes


A_MELODY = melody(
    [("D5", 12), ("G5", 12), ("B5", 24), ("A5", 12), ("G5", 12), ("D5", 24)],
    [("E5", 12), ("G5", 12), ("B5", 12), ("E6", 12), ("D6", 24), ("B5", 24)],
    [("C6", 12), ("B5", 12), ("A5", 12), ("G5", 12), ("E5", 24), ("G5", 24)],
    [("F#5", 12), ("A5", 12), ("D6", 24), ("C6", 12), ("A5", 12), ("F#5", 24)],
    [("G5", 12), ("B5", 12), ("D6", 24), ("B5", 12), ("D6", 12), ("G6", 24)],
    [("E6", 12), ("D6", 12), ("B5", 12), ("G5", 12), ("E5", 24), ("G5", 24)],
    [("A5", 12), ("C6", 12), ("E6", 12), ("C6", 12), ("D6", 12), ("C6", 12), ("A5", 12),
     ("F#5", 12)],
    [("G5", 36), (None, 24), ("D5", 12), ("E5", 12), ("F#5", 12)],
)
A_CHORDS = ("G", "Em", "C", "D", "G", "Em", ("Am", "D"), "G")

B_MELODY = melody(
    [("E6", 24), ("D6", 12), ("C6", 12), ("G5", 24), ("C6", 24)],
    [("F#6", 24), ("E6", 12), ("D6", 12), ("A5", 24), ("D6", 24)],
    [("D6", 12), ("B5", 12), ("F#5", 12), ("B5", 12), ("E6", 24), ("B5", 24)],
    [("C6", 12), ("E6", 12), ("G6", 12), ("E6", 12), ("D6", 12), ("F#6", 12), ("A6", 24)],
)
B_CHORDS = ("C", "D", ("Bm", "Em"), ("C", "D"))

INTRO_LEAD = melody([(None, 96)], [(None, 48), ("D5", 12), ("E5", 12), ("F#5", 24)])

SONG = {
    "lsong": 1,
    "title": "Grass Run",
    "author": "Claude (LiteLua test)",
    "comment": "Music of the map test cart (P8). License: zlib, like LiteLua.",
    "tempo": 140,
    "ppq": 24,
    "meter": [4, 4],
    "profile": "nes",
    "instruments": {
        "lead": {"type": "pulse", "duty": 0.5, "volume": 0.7,
                 "env": [1, 0.9, 0.8, 0.75, 0.7],
                 "release": [0.4, 0.2, 0.1],
                 "vibrato": {"depth": 0.12, "rate": 6, "delay": 16}},
        "chord_maj": {"type": "pulse", "duty": 0.25, "volume": 0.3,
                      "env": [1, 0.75, 0.55, 0.4, 0.3], "arp": [0, 4, 7]},
        "chord_min": {"type": "pulse", "duty": 0.25, "volume": 0.3,
                      "env": [1, 0.75, 0.55, 0.4, 0.3], "arp": [0, 3, 7]},
        "bass": {"type": "triangle", "volume": 0.9},
        "kick": {"type": "noise", "env": [1, 0.7, 0.4, 0.15, 0]},
        "snare": {"type": "noise", "volume": 0.75,
                  "env": [1, 0.8, 0.6, 0.4, 0.25, 0.1, 0]},
        "hat": {"type": "noise", "mode": "short", "volume": 0.4, "env": [1, 0.35, 0]},
        "drums": {"type": "kit", "drums": [
            {"p": KICK, "i": "kick", "to": 30},
            {"p": SNARE, "i": "snare", "to": 70},
            {"p": HAT, "i": "hat", "to": 110},
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
            "chords": chords("G", "D"),
            "bass": bass("G", "D"),
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
        {"pattern": "a"},
        {"pattern": "b"},
        {"pattern": "a"},
        {"pattern": "b", "transpose": 2},
        {"pattern": "a"},
    ],
    "loop": 2,
}

# --- sound effects ------------------------------------------------------------

RATE = 16000


def write_wav(name, samples):
    path = HERE / "sfx" / (name + ".wav")
    path.parent.mkdir(exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(RATE)
        w.writeframes(bytes(int(max(-1, min(1, v)) * 120) + 128 for v in samples))


def square(f0, f1, seconds, volume=0.5, duty=0.5):
    n = int(RATE * seconds)
    out, phase = [], 0.0
    for i in range(n):
        f = f0 * (f1 / f0) ** (i / n)  # Exponential sweep
        phase = (phase + f / RATE) % 1
        env = (1 - i / n) ** 0.7
        out.append(volume * env * (1 if phase < duty else -1))
    return out


def jump():
    return square(320, 900, 0.14, 0.45, 0.25)


def coin():
    a = square(988, 988, 0.06, 0.4)   # B5
    b = square(1319, 1319, 0.16, 0.4)  # E6
    return [v * 1.0 for v in a] + b


def hurt():
    rnd = random.Random(7)
    n = int(RATE * 0.35)
    out, hold, phase = [], 0.0, 0.0
    for i in range(n):
        f = 900 * (120 / 900) ** (i / n)
        phase += f / RATE
        if phase >= 1:  # New noise value at the falling rate
            phase -= 1
            hold = rnd.uniform(-1, 1)
        out.append(0.6 * (1 - i / n) * hold)
    return out


def main():
    music = HERE / "music"
    music.mkdir(exist_ok=True)
    report = lsong.validate(SONG)
    for w in report.warnings:
        print("warning:", w)
    if report.errors:
        raise SystemExit("\n".join(report.errors))
    (music / "grass_run.lsong").write_text(lsong.to_lua(SONG), encoding="utf-8",
                                           newline="\n")
    print(f"music/grass_run.lsong: {lsong.duration(SONG):.1f} s")
    for name, fn in (("jump", jump), ("coin", coin), ("hurt", hurt)):
        s = fn()
        write_wav(name, s)
        print(f"sfx/{name}.wav: {len(s) / RATE:.2f} s")


if __name__ == "__main__":
    main()
