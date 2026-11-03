#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# Writes the sound of the HeroesDS G1 cart (no sprites, no game data):
#   carts/g1/sfx/*.wav     chip-style battle effects, synthesised here (8-bit mono 16 kHz)
#   carts/g1/music/*.lsong a D minor battle march and the victory / defeat jingles
#                          (.lsong, docs/LSONG.md), played by the DS sound channels
#
#   python HeroesDS/tools/make_g1_sound.py

import math
import pathlib
import random
import sys
import wave

HERE = pathlib.Path(__file__).parent
CART = HERE.parent / "carts" / "g1"
sys.path.insert(0, str(HERE.parent.parent / "tools"))
import lsong  # noqa: E402

# ---------------------------------------------------------------- sound effects

RATE = 16000


class Noise:
    """NES-like 15-bit LFSR noise; step every `period` samples (bigger = darker)"""

    def __init__(self, short=False):
        self.r, self.short, self.acc, self.out = 1, short, 0.0, 1.0

    def next(self, period):
        self.acc += 1
        while self.acc >= period:
            self.acc -= period
            bit = (self.r ^ (self.r >> (6 if self.short else 1))) & 1
            self.r = (self.r >> 1) | (bit << 14)
            self.out = 1.0 if self.r & 1 else -1.0
        return self.out


def pulse(phase, duty):
    return 1.0 if (phase % 1.0) < duty else -1.0


def lerp(a, b, p):
    return a + (b - a) * p


def env(p, attack=0.01, curve=1.5):
    """Volume at p (0..1 of the sound): a quick attack, then a decay"""
    if p < attack:
        return p / attack
    return max(0.0, 1 - (p - attack) / (1 - attack)) ** curve


def render(seconds, fn):
    n = int(seconds * RATE)
    return [fn(i / RATE, i / max(1, n - 1)) for i in range(n)]


def save(name, samples, gain=0.9):
    path = CART / "sfx" / f"{name}.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    data = bytes(max(0, min(255, int(128 + 127 * gain * max(-1, min(1, s))))) for s in samples)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(RATE)
        w.writeframes(data)
    return path


def sweep_pulse(seconds, f0, f1, duty=0.5, curve=1.5, steps=0):
    """A pulse wave gliding f0 -> f1 (steps > 0: in that many NES-like steps)"""
    phase = [0.0]

    def fn(t, p):
        q = math.floor(p * steps) / steps if steps else p
        phase[0] += lerp(f0, f1, q) / RATE
        return pulse(phase[0], duty) * env(p, curve=curve)
    return render(seconds, fn)


def noise_burst(seconds, p0, p1, short=False, curve=1.5, attack=0.01):
    nz = Noise(short)
    return render(seconds, lambda t, p: nz.next(lerp(p0, p1, p)) * env(p, attack, curve))


def mix(*parts):
    n = max(len(s) for s, _ in parts)
    out = [0.0] * n
    for s, v in parts:
        for i, x in enumerate(s):
            out[i] += x * v
    return out


def concat(*parts):
    out = []
    for p in parts:
        out += p
    return out


def notes(seq, duty=0.5, gap=0.15):
    """(frequency, seconds) list as detached pulse notes"""
    out = []
    for f, s in seq:
        on = sweep_pulse(s * (1 - gap), f, f, duty, curve=0.8)
        out += on + [0.0] * int(s * gap * RATE)
    return out


def make_sfx():
    random.seed(7)
    made = {}
    # A footstep: a dull, very short tick (played on the hops of a walk)
    made["step"] = save("step", noise_burst(0.035, 14, 22, curve=2), 0.5)
    # Melee: a bright clang over a low thump
    made["sword"] = save("sword", mix(
        (noise_burst(0.16, 1.2, 6, short=True, curve=2.2), 0.55),
        (sweep_pulse(0.12, 140, 55, 0.5, curve=1.2), 0.6)))
    # A shot: a quick falling "fwip"
    made["arrow"] = save("arrow", mix(
        (sweep_pulse(0.13, 1400, 380, 0.25, curve=1.0), 0.5),
        (noise_burst(0.13, 2, 4, curve=1.3, attack=0.4), 0.35)), 0.8)
    # Hit by a shot: a short thunk
    made["thunk"] = save("thunk", mix(
        (sweep_pulse(0.09, 300, 90, 0.5, curve=1.4), 0.7),
        (noise_burst(0.06, 6, 12, curve=2), 0.4)))
    # A stack dies: a falling NES-step tone with a hiss tail
    made["die"] = save("die", mix(
        (sweep_pulse(0.38, 330, 90, 0.5, curve=0.7, steps=6), 0.6),
        (noise_burst(0.38, 6, 20, curve=1.2, attack=0.3), 0.3)))
    # Fireball: a rising whoosh, then the boom
    made["fire"] = save("fire", noise_burst(0.32, 12, 2, curve=0.5, attack=0.7), 0.8)
    made["boom"] = save("boom", mix(
        (noise_burst(0.55, 10, 40, curve=1.6), 0.8),
        (sweep_pulse(0.45, 90, 35, 0.5, curve=1.4), 0.5)))
    # Lightning: crackling noise gates and a high jittering zap
    nz, ph = Noise(), [0.0]

    def bolt(t, p):
        gate = 1.0 if random.random() < (0.9 if p < 0.15 else 0.35) else 0.0
        ph[0] += (1800 + random.uniform(-500, 500)) / RATE
        return (nz.next(1.0) * gate * 0.7 + pulse(ph[0], 0.125) * 0.35) * env(p, curve=1.1)
    made["bolt"] = save("bolt", render(0.42, bolt))
    # Ice: a fast falling glassy arpeggio
    seq = [([2637, 2349, 1976, 1568][k % 4] * (1 - k * 0.03), 0.04) for k in range(10)]
    ice = notes(seq, 0.125, 0.25)
    made["ice"] = save("ice", [x * env(i / (len(ice) - 1), curve=0.6) for i, x in enumerate(ice)], 0.7)
    # Interface: a blip on a touch, a rising two-note when the player's turn starts
    made["select"] = save("select", sweep_pulse(0.06, 880, 1320, 0.25, curve=1), 0.5)
    made["turn"] = save("turn", notes([(660, 0.07), (990, 0.11)], 0.25), 0.5)
    return made


# ---------------------------------------------------------------------- music

BAR = 96  # ppq 24, 4/4
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    return 12 * (int(name[-1]) + 1) + NOTE[name[0]] + name[1:-1].count("#")


def melody(*bars, detach=2):
    notes_, t = [], 0
    for bar in bars:
        start = t
        for name, length in bar:
            if name:
                notes_.append({"t": t, "d": length - detach, "p": midi(name)})
            t += length
        assert t - start == BAR, f"bar at {start} has {t - start} ticks"
    return notes_


# Chord roots for the stabs; the bass plays them two octaves down
ROOT = {"Dm": 62, "A#": 58, "C": 60, "Gm": 55, "A": 57, "F": 53, "D": 62}


def chords(*bars):
    out = []
    for b, bar in enumerate(bars):
        bar = bar if isinstance(bar, tuple) else (bar, bar)
        for k, t in enumerate((12, 36, 60, 84)):
            ch = bar[k // 2]
            n = {"t": b * BAR + t, "d": 9, "p": ROOT[ch]}
            if ch.endswith("m"):
                n["i"] = "chord_min"
            out.append(n)
    return out


def bass(*bars):
    """A march: root, root, octave, fifth on the eighths of each half bar"""
    out = []
    for b, bar in enumerate(bars):
        bar = bar if isinstance(bar, tuple) else (bar, bar)
        for half in range(2):
            root = ROOT[bar[half]] - 24
            for k, off in enumerate((0, 0, 12, 7)):
                out.append({"t": b * BAR + half * 48 + k * 12, "d": 10, "p": root + off})
    return out


KICK, SNARE, HAT = 36, 38, 42


def drums(bars, fill_last=True):
    out = []
    for b in range(bars):
        o = b * BAR
        hits = [(0, KICK), (48, KICK), (24, SNARE), (72, SNARE)]
        hits += [(t, HAT) for t in (12, 36, 60, 84)]
        if b % 2 == 1:
            hits += [(30, SNARE), (78, SNARE)]          # march drag
        if fill_last and b == bars - 1:
            hits = [h for h in hits if h[0] < 72] + [(t, SNARE) for t in (72, 78, 84, 90)]
        out += [{"t": o + t, "d": 5, "p": p} for t, p in sorted(set(hits))]
    return out


def snare_march(bars):
    """The intro: only a snare march with a roll at the end"""
    out = []
    for b in range(bars):
        o = b * BAR
        ts = [0, 24, 36, 48, 72] if b < bars - 1 else [0, 24, 48, 60, 66, 72, 78, 84, 90]
        out += [{"t": o + t, "d": 5, "p": SNARE, "v": 0.8 if t % 24 else 1} for t in ts]
    return out


A_MELODY = melody(
    [("D5", 24), ("A4", 12), ("D5", 12), ("F5", 24), ("E5", 12), ("D5", 12)],
    [("C5", 12), ("D5", 12), ("E5", 12), ("F5", 12), ("E5", 24), ("A4", 24)],
    [("D5", 24), ("A#4", 12), ("D5", 12), ("F5", 24), ("A#5", 24)],
    [("A5", 12), ("G5", 12), ("F5", 12), ("E5", 12), ("G5", 48)],
    [("F5", 24), ("E5", 12), ("D5", 12), ("A5", 24), ("G5", 12), ("F5", 12)],
    [("G5", 12), ("F5", 12), ("D5", 12), ("A#4", 12), ("D5", 24), ("F5", 24)],
    [("G5", 24), ("A#5", 24), ("A5", 24), ("C#6", 24)],
    [("D6", 36), (None, 36), ("A4", 12), ("C#5", 12)],
)
A_CHORDS = ("Dm", "Dm", "A#", "C", "Dm", "A#", ("Gm", "A"), "Dm")

B_MELODY = melody(
    [("F5", 12), ("F5", 12), ("A#5", 24), ("C6", 12), ("A#5", 12), ("A5", 24)],
    [("A5", 12), ("A5", 12), ("D6", 24), ("C6", 12), ("A#5", 12), ("F5", 24)],
    [("G5", 12), ("A#5", 12), ("D6", 24), ("E6", 24), ("C6", 24)],
    [("A5", 48), ("E5", 24), ("C#5", 24)],
)
B_CHORDS = (("A#", "C"), ("Dm", "A#"), ("Gm", "C"), "A")

INSTRUMENTS = {
    "lead": {"type": "pulse", "duty": 0.25, "volume": 0.7,
             "env": [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7],
             "release": [0.4, 0.2, 0.08],
             "vibrato": {"depth": 0.2, "rate": 6, "delay": 12}},
    "chord_maj": {"type": "pulse", "duty": 0.125, "volume": 0.3,
                  "env": [1, 0.8, 0.6, 0.45, 0.35], "arp": [0, 4, 7]},
    "chord_min": {"type": "pulse", "duty": 0.125, "volume": 0.3,
                  "env": [1, 0.8, 0.6, 0.45, 0.35], "arp": [0, 3, 7]},
    "bass": {"type": "triangle", "volume": 0.9},
    "kick": {"type": "noise", "env": [1, 0.7, 0.4, 0.15, 0]},
    "snare": {"type": "noise", "volume": 0.75, "env": [1, 0.8, 0.6, 0.4, 0.25, 0.1, 0]},
    "hat": {"type": "noise", "mode": "short", "volume": 0.35, "env": [1, 0.35, 0]},
    "drums": {"type": "kit", "drums": [
        {"p": KICK, "i": "kick", "to": 30},
        {"p": SNARE, "i": "snare", "to": 62},
        {"p": HAT, "i": "hat", "to": 104},
    ]},
}
TRACKS = [
    {"name": "lead", "instrument": "lead"},
    {"name": "chords", "instrument": "chord_maj"},
    {"name": "bass", "instrument": "bass"},
    {"name": "drums", "instrument": "drums"},
]

BATTLE = {
    "lsong": 1,
    "title": "HeroesDS Battle March",
    "author": "Claude (HeroesDS G1)",
    "comment": "D minor chip march for the G1 test battle. License: zlib, like LiteLua.",
    "tempo": 132,
    "ppq": 24,
    "meter": [4, 4],
    "profile": "nes",
    "instruments": INSTRUMENTS,
    "tracks": TRACKS,
    "patterns": {
        "intro": {"length": 2 * BAR, "notes": {
            "lead": melody([(None, 96)], [(None, 72), ("A4", 12), ("C#5", 12)]),
            "bass": bass("Dm", "A"),
            "drums": snare_march(2),
        }},
        "a": {"length": 8 * BAR, "notes": {
            "lead": A_MELODY, "chords": chords(*A_CHORDS),
            "bass": bass(*A_CHORDS), "drums": drums(8),
        }},
        "b": {"length": 4 * BAR, "notes": {
            "lead": B_MELODY, "chords": chords(*B_CHORDS),
            "bass": bass(*B_CHORDS), "drums": drums(4),
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


def jingle(title, lead, chord_bars, bass_bars, tempo):
    bars = len(lead)
    return {
        "lsong": 1, "title": title, "author": "Claude (HeroesDS G1)",
        "comment": "License: zlib, like LiteLua.", "tempo": tempo, "ppq": 24,
        "meter": [4, 4], "profile": "nes", "instruments": INSTRUMENTS, "tracks": TRACKS,
        "patterns": {"j": {"length": bars * BAR, "notes": {
            "lead": melody(*lead, detach=1),
            "chords": chords(*chord_bars),
            "bass": bass(*bass_bars),
        }}},
        "playlist": [{"pattern": "j"}],
        "loop": False,
    }


VICTORY = jingle("HeroesDS Victory", [
    [("D5", 12), ("F#5", 12), ("A5", 12), ("D6", 36), ("C#6", 12), ("D6", 12)],
    [("E6", 24), ("F#6", 72)],
], [("D", "D"), ("A", "D")], [("D", "D"), ("A", "D")], 120)

DEFEAT = jingle("HeroesDS Defeat", [
    [("A5", 24), ("G5", 24), ("F5", 24), ("E5", 24)],
    [("D5", 72), (None, 24)],
], [("Dm", "C"), ("A#", "Dm")], [("Dm", "C"), ("A#", "Dm")], 84)

def make_music():
    out = CART / "music"
    out.mkdir(parents=True, exist_ok=True)
    made = []
    for name, song in (("battle", BATTLE), ("victory", VICTORY), ("defeat", DEFEAT)):
        p = out / f"{name}.lsong"
        p.write_text(lsong.to_lua(song), encoding="utf-8", newline="\n")
        made.append(p)
    return made


if __name__ == "__main__":
    for p in list(make_sfx().values()) + make_music():
        print(p.relative_to(HERE.parent))
