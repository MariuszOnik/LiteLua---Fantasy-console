#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# Makes the music and sound effects of Runedeck, so the cart needs no third
# party files:
#   music/battle.lsong   A minor, dark and driving (normal fights)
#   music/boss.lsong     D minor, faster (the Ogre Chief)
#   music/victory.lsong  short fanfare, plays once
#   music/defeat.lsong   short falling theme, plays once
#   sfx/*.wav            8-bit mono 22050 Hz, synthesized here
#
#   python examples/carts/runedeck/make_audio.py

import math
import pathlib
import random
import struct
import sys
import wave

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE.parent.parent.parent / "tools"))
import lsong  # noqa: E402

BAR = 96  # ppq 24, 4/4
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    return 12 * (int(name[-1]) + 1) + NOTE[name[0]] + name[1:-1].count("#")


def melody(*bars, gap=2):
    """Bars of (note or None, ticks) -> notes"""
    notes, t = [], 0
    for bar in bars:
        start = t
        for name, length in bar:
            if name:
                notes.append({"t": t, "d": length - gap, "p": midi(name)})
            t += length
        assert t - start == BAR, f"bar at {start} has {t - start} ticks"
    return notes


ROOT = {"Am": 57, "F": 53, "G": 55, "E": 52, "Dm": 50, "Bb": 58, "C": 60, "A": 57}


def pad_chords(*bars):
    """Two arpeggiated chords per bar (half notes), minor ones with chord_min"""
    notes = []
    for b, bar in enumerate(bars):
        bar = bar if isinstance(bar, tuple) else (bar, bar)
        for k in range(2):
            ch = bar[k]
            n = {"t": b * BAR + k * 48, "d": 44, "p": ROOT[ch]}
            if ch.endswith("m"):
                n["i"] = "chord_min"
            notes.append(n)
    return notes


def drive_bass(*bars):
    """Eighth notes on the root, octave and fifth for the push"""
    shape = (0, 0, 12, 0, 0, 0, 7, 12)
    notes = []
    for b, bar in enumerate(bars):
        bar = bar if isinstance(bar, tuple) else (bar, bar)
        for k, off in enumerate(shape):
            root = ROOT[bar[k // 4]] - 12
            while root > 52:
                root -= 12
            notes.append({"t": b * BAR + k * 12, "d": 10, "p": root + off})
    return notes


KICK, SNARE, HAT, CRASH = 36, 38, 42, 49


def beat(bars, hits, fill_last=True):
    notes = []
    for b in range(bars):
        o = b * BAR
        hs = list(hits)
        if fill_last and b == bars - 1:
            hs = [h for h in hs if h[0] < 72] + [(72, SNARE), (78, SNARE), (84, SNARE), (90, SNARE)]
        for t, p in sorted(hs):
            notes.append({"t": o + t, "d": 6, "p": p})
    return notes


ROCK = [(0, KICK), (12, HAT), (24, SNARE), (36, HAT), (48, KICK), (60, HAT), (72, SNARE), (84, HAT)]
HEAVY = [(0, KICK), (12, HAT), (24, SNARE), (36, KICK), (48, KICK), (60, HAT), (72, SNARE), (84, HAT)]


def instruments(lead_duty=0.25):
    return {
        "lead": {"type": "pulse", "duty": lead_duty, "volume": 0.7,
                 "env": [1, 0.95, 0.9, 0.85, 0.8, 0.75], "release": [0.4, 0.2, 0.1],
                 "vibrato": {"depth": 0.15, "rate": 6, "delay": 12}},
        "chord_maj": {"type": "pulse", "duty": 0.125, "volume": 0.3,
                      "env": [1, 0.85, 0.7, 0.6, 0.5], "arp": [0, 4, 7]},
        "chord_min": {"type": "pulse", "duty": 0.125, "volume": 0.3,
                      "env": [1, 0.85, 0.7, 0.6, 0.5], "arp": [0, 3, 7]},
        "bass": {"type": "triangle", "volume": 0.9},
        "kick": {"type": "noise", "env": [1, 0.75, 0.45, 0.2, 0]},
        "snare": {"type": "noise", "volume": 0.8, "env": [1, 0.85, 0.65, 0.45, 0.3, 0.15, 0]},
        "hat": {"type": "noise", "mode": "short", "volume": 0.4, "env": [1, 0.4, 0]},
        "crash": {"type": "noise", "volume": 0.6,
                  "env": [1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.45, 0.4, 0.35, 0.3, 0.25, 0.2, 0.15, 0.1, 0.05, 0]},
        "drums": {"type": "kit", "drums": [
            {"p": KICK, "i": "kick", "to": 32}, {"p": SNARE, "i": "snare", "to": 64},
            {"p": HAT, "i": "hat", "to": 104}, {"p": CRASH, "i": "crash", "to": 96}]},
    }


TRACKS = [{"name": "lead", "instrument": "lead"}, {"name": "chords", "instrument": "chord_maj"},
          {"name": "bass", "instrument": "bass"}, {"name": "drums", "instrument": "drums"}]


def song(title, tempo, patterns, playlist, loop=2, lead_duty=0.25):
    s = {"lsong": 1, "title": title, "author": "Claude (Runedeck, LiteLua example)",
         "comment": "License: zlib, like LiteLua.", "tempo": tempo, "ppq": 24,
         "meter": [4, 4], "profile": "nes", "instruments": instruments(lead_duty),
         "tracks": TRACKS, "patterns": patterns, "playlist": playlist}
    s["loop"] = loop
    return s


def battle():
    prog_a = ("Am", "F", "G", "E", "Am", "F", ("Dm", "E"), "Am")
    prog_b = ("Dm", "Am", "E", "Am", "Dm", "Am", ("F", "E"), "E")
    a = melody(
        [("A4", 12), ("C5", 12), ("E5", 24), ("D5", 12), ("C5", 12), ("B4", 24)],
        [("A4", 24), ("F4", 12), ("A4", 12), ("C5", 36), (None, 12)],
        [("B4", 12), ("D5", 12), ("G5", 24), ("F5", 12), ("E5", 12), ("D5", 24)],
        [("E5", 48), ("G#4", 24), ("B4", 24)],
        [("A4", 12), ("C5", 12), ("E5", 24), ("A5", 24), ("G5", 12), ("E5", 12)],
        [("F5", 24), ("E5", 12), ("D5", 12), ("C5", 24), ("A4", 24)],
        [("D5", 24), ("F5", 24), ("E5", 24), ("G#5", 24)],
        [("A5", 48), (None, 48)],
    )
    b = melody(
        [("D5", 12), ("F5", 12), ("A5", 24), ("G5", 12), ("F5", 12), ("E5", 24)],
        [("C5", 12), ("E5", 12), ("A5", 36), (None, 12), ("G5", 24)],
        [("G#5", 24), ("F5", 12), ("E5", 12), ("D5", 24), ("B4", 24)],
        [("C5", 24), ("B4", 12), ("A4", 12), ("E5", 48)],
        [("F5", 24), ("A5", 24), ("D6", 36), ("C6", 12)],
        [("A5", 24), ("E5", 24), ("C5", 24), ("E5", 24)],
        [("F5", 24), ("A5", 24), ("G#5", 24), ("E5", 24)],
        [("E5", 72), (None, 24)],
    )
    patterns = {
        "intro": {"length": 2 * BAR, "notes": {
            "bass": drive_bass("Am", "Am"), "drums": beat(2, ROCK)}},
        "a": {"length": 8 * BAR, "notes": {
            "lead": a, "chords": pad_chords(*prog_a), "bass": drive_bass(*prog_a),
            "drums": beat(8, ROCK)}},
        "b": {"length": 8 * BAR, "notes": {
            "lead": b, "chords": pad_chords(*prog_b), "bass": drive_bass(*prog_b),
            "drums": beat(8, ROCK)}},
    }
    return song("Into the Ruins", 132, patterns,
                [{"pattern": "intro"}, {"pattern": "a"}, {"pattern": "b"},
                 {"pattern": "a"}, {"pattern": "b"}])


def boss():
    prog = ("Dm", "Dm", "Bb", "C", "Dm", "Dm", "Bb", "A")
    lead = melody(
        [("D5", 12), ("D5", 12), ("F5", 12), ("D5", 12), ("A5", 24), ("G5", 24)],
        [("F5", 12), ("E5", 12), ("D5", 12), ("C5", 12), ("D5", 48)],
        [("A#4", 12), ("D5", 12), ("F5", 24), ("A#5", 24), ("A5", 24)],
        [("G5", 24), ("E5", 24), ("C5", 24), ("E5", 24)],
        [("D6", 24), ("C6", 12), ("A5", 12), ("F5", 24), ("A5", 24)],
        [("G5", 12), ("F5", 12), ("E5", 12), ("F5", 12), ("D5", 48)],
        [("F5", 24), ("A#5", 24), ("D6", 24), ("C6", 24)],
        [("C#6", 48), ("A5", 24), ("E5", 24)],
    )
    patterns = {
        "intro": {"length": 2 * BAR, "notes": {
            "bass": drive_bass("Dm", "Dm"), "drums": beat(2, HEAVY)}},
        "fight": {"length": 8 * BAR, "notes": {
            "lead": lead, "chords": pad_chords(*prog), "bass": drive_bass(*prog),
            "drums": beat(8, HEAVY)}},
    }
    return song("Ogre Chief", 156, patterns,
                [{"pattern": "intro"}, {"pattern": "fight"}, {"pattern": "fight", "transpose": 2},
                 {"pattern": "fight"}], lead_duty=0.5)


def victory():
    lead = melody(
        [("C5", 12), ("E5", 12), ("G5", 12), ("C6", 36), (None, 24)],
        [("A5", 12), ("B5", 12), ("C6", 72)],
    )
    patterns = {"win": {"length": 2 * BAR, "notes": {
        "lead": lead,
        "chords": [{"t": 0, "d": 90, "p": 60}, {"t": 96, "d": 22, "p": 55}, {"t": 120, "d": 66, "p": 60}],
        "bass": [{"t": 0, "d": 46, "p": 48}, {"t": 48, "d": 46, "p": 43},
                 {"t": 96, "d": 22, "p": 43}, {"t": 120, "d": 66, "p": 48}],
        "drums": [{"t": 0, "d": 6, "p": KICK}, {"t": 72, "d": 6, "p": SNARE},
                  {"t": 84, "d": 6, "p": SNARE}, {"t": 120, "d": 6, "p": CRASH}],
    }}}
    return song("Victory", 150, patterns, [{"pattern": "win"}], loop=False)


def defeat():
    lead = melody(
        [("E5", 24), ("D5", 24), ("C5", 24), ("B4", 24)],
        [("A4", 84), (None, 12)],
        gap=4,
    )
    patterns = {"lose": {"length": 2 * BAR, "notes": {
        "lead": lead,
        "chords": [{"t": 0, "d": 46, "p": 57, "i": "chord_min"}, {"t": 48, "d": 46, "p": 52},
                   {"t": 96, "d": 84, "p": 57, "i": "chord_min"}],
        "bass": [{"t": 0, "d": 46, "p": 45}, {"t": 48, "d": 46, "p": 40}, {"t": 96, "d": 84, "p": 33}],
        "drums": [{"t": 96, "d": 6, "p": KICK}],
    }}}
    return song("Defeat", 84, patterns, [{"pattern": "lose"}], loop=False)


# --- Sound effects ------------------------------------------------------------

RATE = 22050


def write_wav(name, samples):
    path = HERE / "sfx" / (name + ".wav")
    path.parent.mkdir(exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(RATE)
        w.writeframes(bytes(int(max(-1.0, min(1.0, v)) * 120) + 128 for v in samples))


def synth(dur, freq, wave_="square", vol=0.6, env=lambda x: 1 - x, noise_mix=0.0, seed=1):
    """freq and env are functions of x = 0..1 (position in the sound)"""
    rnd = random.Random(seed)
    n = int(RATE * dur)
    out, ph, held, hold_n = [], 0.0, 0.0, 0
    for i in range(n):
        x = i / n
        ph += freq(x) / RATE
        if wave_ == "square":
            v = 1.0 if ph % 1 < 0.5 else -1.0
        elif wave_ == "tri":
            v = 4 * abs(ph % 1 - 0.5) - 1
        else:
            v = math.sin(2 * math.pi * ph)
        if noise_mix:
            # sample-and-hold noise: lower freq() = darker noise
            if hold_n <= 0:
                held, hold_n = rnd.uniform(-1, 1), max(1, int(RATE / max(1.0, freq(x) * 8)))
            hold_n -= 1
            v = v * (1 - noise_mix) + held * noise_mix
        out.append(v * vol * env(x))
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def make_sfx():
    s = {}
    s["pick"] = synth(0.04, lambda x: 1400, vol=0.35)
    s["deny"] = synth(0.08, lambda x: 180, vol=0.45) + [0] * 600 + synth(0.08, lambda x: 150, vol=0.45)
    s["slash"] = synth(0.18, lambda x: 2200 - 1800 * x, noise_mix=0.9, vol=0.7, env=lambda x: (1 - x) ** 2)
    s["hit"] = mix(synth(0.12, lambda x: 160 - 100 * x, "sine", vol=0.9),
                   synth(0.08, lambda x: 900, noise_mix=1.0, vol=0.5, env=lambda x: (1 - x) ** 3))
    s["hurt"] = mix(synth(0.22, lambda x: 110 - 60 * x, "square", vol=0.5),
                    synth(0.18, lambda x: 500, noise_mix=1.0, vol=0.6, env=lambda x: (1 - x) ** 2, seed=2))
    s["block"] = mix(synth(0.25, lambda x: 1250, vol=0.3, env=lambda x: (1 - x) ** 3),
                     synth(0.25, lambda x: 1870, vol=0.25, env=lambda x: (1 - x) ** 4),
                     synth(0.03, lambda x: 3000, noise_mix=1.0, vol=0.4))
    s["clang"] = mix(synth(0.12, lambda x: 900, vol=0.35, env=lambda x: (1 - x) ** 2),
                     synth(0.05, lambda x: 2500, noise_mix=1.0, vol=0.4))
    s["buff"] = sum((synth(0.06, lambda x, f=f: f, "tri", vol=0.6) for f in (523, 659, 784, 1047)), [])
    s["debuff"] = synth(0.35, lambda x: 500 - 300 * x + 40 * math.sin(x * 60), "square", vol=0.35)
    s["poison"] = sum((synth(0.05, lambda x, f=f: f + 400 * x, "sine", vol=0.6) for f in (300, 420, 340)), [])
    s["die"] = synth(0.5, lambda x: 900 - 800 * x, noise_mix=0.7, vol=0.6, env=lambda x: 1 - x)
    s["turn"] = mix(synth(0.15, lambda x: 880, "tri", vol=0.4, env=lambda x: (1 - x) ** 2),
                    [0] * 1300 + synth(0.2, lambda x: 1320, "tri", vol=0.35, env=lambda x: (1 - x) ** 2))
    s["card"] = synth(0.06, lambda x: 600 + 900 * x, noise_mix=0.6, vol=0.35)
    for name, data in s.items():
        write_wav(name, data)
    return list(s)


def main():
    out = HERE / "music"
    out.mkdir(exist_ok=True)
    for name, fn in (("battle", battle), ("boss", boss), ("victory", victory), ("defeat", defeat)):
        (out / (name + ".lsong")).write_text(lsong.to_lua(fn()), encoding="utf-8")
        print("music/" + name + ".lsong")
    print("sfx:", ", ".join(make_sfx()))


if __name__ == "__main__":
    main()
