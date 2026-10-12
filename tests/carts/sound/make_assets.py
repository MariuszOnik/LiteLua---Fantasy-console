#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# Generates the sounds of the sound test cart (P7), so it needs no third
# party files:
#   sfx/beep.wav    8-bit mono 22050 Hz, a short chirp
#   sfx/boom.wav    16-bit stereo 32000 Hz, noise burst (tests the downmix)
#   music/tune.wav  8-bit mono 16000 Hz, a looping melody (streamed)
#   music/song.mas  4-channel MOD made here, converted with mmutil -d -m
#   music/sky.wav   examples/songs/sky_hopper.lsong rendered (not in git)
#   music/rock.wav  examples/songs/demo_rock.mid imported and rendered (not in git)
#
#   python tests/carts/sound/make_assets.py

import math
import pathlib
import random
import struct
import subprocess
import wave

HERE = pathlib.Path(__file__).parent
MMUTIL = pathlib.Path(r"C:\msys64\opt\wonderful\thirdparty\blocksds\core\tools\mmutil\mmutil.exe")
NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
         "G#": 8, "A": 9, "A#": 10, "B": 11}


def write_wav(path, rate, channels, bits, frames):
    """frames: list of tuples of floats -1..1 (one per channel)"""
    path.parent.mkdir(exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(bits // 8)
        w.setframerate(rate)
        data = bytearray()
        for fr in frames:
            for v in fr:
                v = max(-1.0, min(1.0, v))
                if bits == 8:
                    data.append(int(v * 127) + 128)
                else:
                    data += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(data))


def freq(note, octave):
    return 440.0 * 2 ** ((NOTES[note] + 12 * (octave - 4) - 9) / 12)


def beep():
    rate = 22050
    n = int(rate * 0.15)
    out, phase = [], 0.0
    for i in range(n):
        f = 600 + 900 * i / n
        phase += f / rate
        env = 1 - i / n
        out.append((0.6 * env * (1 if phase % 1 < 0.5 else -1),))
    write_wav(HERE / "sfx/beep.wav", rate, 1, 8, out)


def boom():
    rate = 32000
    n = int(rate * 0.6)
    rnd = random.Random(1)
    out, low = [], 0.0
    for i in range(n):
        low += (rnd.uniform(-1, 1) - low) * 0.08  # Low-pass noise
        env = (1 - i / n) ** 2
        out.append((low * 2.5 * env, low * 2.0 * env))
    write_wav(HERE / "sfx/boom.wav", rate, 2, 16, out)


def tune():
    rate = 16000
    melody = [("C", 5), ("E", 5), ("G", 5), ("C", 6), ("G", 5), ("E", 5),
              ("D", 5), ("F", 5), ("A", 5), ("D", 6), ("A", 5), ("F", 5),
              ("E", 5), ("G", 5), ("B", 5), ("E", 6), ("B", 5), ("G", 5),
              ("C", 5), ("G", 4), ("E", 4), ("G", 4), ("C", 5), ("C", 5)]
    step = int(rate * 0.18)
    out = []
    for note, octave in melody:
        f = freq(note, octave)
        for i in range(step):
            t = i / rate
            env = min(1.0, i / 200) * (1 - i / step) ** 0.5
            v = 0.5 * math.sin(2 * math.pi * f * t) + 0.15 * math.sin(4 * math.pi * f * t)
            out.append((v * env,))
    write_wav(HERE / "music/tune.wav", rate, 1, 8, out)


# --- A tiny ProTracker MOD ---------------------------------------------------

PERIODS = [856, 808, 762, 720, 678, 640, 604, 570, 538, 508, 480, 453]  # Octave 1


def period(note, octave):
    return PERIODS[NOTES[note]] >> (octave - 1)


def mod_song():
    square = bytes((64 if i < 16 else -64) & 0xFF for i in range(32))
    tri = bytes((int(-100 + 200 * (i / 16 if i < 16 else (32 - i) / 16))) & 0xFF
                for i in range(32))
    rnd = random.Random(2)
    noise = bytes(int(rnd.uniform(-90, 90) * (1 - i / 1500) ** 2) & 0xFF
                  for i in range(1500))
    samples = [  # name, data, volume, loop start, loop length (bytes)
        ("pulse", square, 40, 0, len(square)),
        ("triangle", tri, 64, 0, len(tri)),
        ("noise", noise, 48, 0, 0),
    ]

    head = bytearray(b"LiteLua test".ljust(20, b"\0"))
    for i in range(31):
        if i < len(samples):
            name, data, vol, ls, ll = samples[i]
            head += name.encode().ljust(22, b"\0")
            head += struct.pack(">HBBHH", len(data) // 2, 0, vol, ls // 2,
                                ll // 2 if ll else 1)
        else:
            head += b"\0" * 22 + struct.pack(">HBBHH", 0, 0, 0, 0, 1)
    head += bytes([2, 127]) + bytes([0, 1] + [0] * 126) + b"M.K."

    lead = ["C4", "E4", "G4", "E4", "F4", "A4", "C5", "A4",
            "G4", "B4", "D5", "B4", "C5", "G4", "E4", "C4"]
    bass = ["C2", "C2", "F2", "F2", "G2", "G2", "C2", "C2"]

    def cell(sample, note=None, effect=0, param=0):
        if note is None:
            return bytes(4)
        p = period(note[:-1], int(note[-1]) - 1)
        return bytes([(sample & 0xF0) | (p >> 8), p & 0xFF,
                      ((sample & 0x0F) << 4) | effect, param])

    patterns = b""
    for pat in range(2):
        for row in range(64):
            c0 = cell(1, lead[row // 4 % 16]) if row % 4 == 0 else bytes(4)
            c1 = cell(2, bass[row // 8]) if row % 8 == 0 else bytes(4)
            drum = row % 8 == 4 or (pat == 1 and row % 4 == 2)
            c2 = cell(3, "C3") if drum else bytes(4)
            patterns += c0 + c1 + c2 + bytes(4)

    mod = head + patterns + b"".join(s[1] for s in samples)
    path = HERE / "song.mod"
    path.write_bytes(mod)
    (HERE / "music").mkdir(exist_ok=True)
    out = HERE / "music/song.mas"
    out.unlink(missing_ok=True)  # mmutil would ask before overwriting
    subprocess.run([str(MMUTIL), "-d", "-m", str(path), "-o" + str(out)], check=True,
                   stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL)
    path.unlink()


def sky():
    import sys
    sys.path.insert(0, str(HERE.parents[2] / "tools"))
    import lsong
    song = lsong.load(HERE.parents[2] / "examples/songs/sky_hopper.lsong")
    lsong.render(song, HERE / "music/sky.wav", rate=22050, bits=16)


def rock():
    # The whole chain of D37: MIDI -> .lsong -> WAV
    import sys
    sys.path.insert(0, str(HERE.parents[2] / "tools"))
    import lsong
    import midi_import
    song, _ = midi_import.import_midi(HERE.parents[2] / "examples/songs/demo_rock.mid")
    lsong.render(song, HERE / "music/rock.wav", rate=22050, bits=16)


if __name__ == "__main__":
    beep()
    boom()
    tune()
    mod_song()
    sky()
    rock()
    for p in sorted((HERE / "sfx").iterdir()) + sorted((HERE / "music").iterdir()):
        print(p.relative_to(HERE), p.stat().st_size, "bytes")
