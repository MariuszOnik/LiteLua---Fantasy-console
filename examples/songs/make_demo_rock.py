#!/usr/bin/env python3
# SPDX-License-Identifier: Zlib
#
# Writes demo_rock.mid: "Pixel Riff", an original test piece for the MIDI
# import (D37). MIDI format 1 with running status, a tempo change (130 ->
# 150 BPM at the chorus), power chords (polyphonic -> arpeggio), a lead
# melody, a bass and General MIDI drums with a crash and a tom fill.
#
#   python examples/songs/make_demo_rock.py
#   python tools/litelua.py song import examples/songs/demo_rock.mid demo_rock.lsong

import pathlib
import sys

HERE = pathlib.Path(__file__).parent
sys.path.insert(0, str(HERE.parent.parent / "tools"))
import midi  # noqa: E402

Q = 480
BAR = 4 * Q
E8 = Q // 2
ROOT = {"E": 52, "G": 55, "A": 57, "D": 50, "C": 48, "B": 47}

VERSE = [["E", "E", "E", "E", "G", "G", "A", "A"],
         ["E", "E", "E", "E", "D", "D", "C", "B"]] * 2
CHORUS = [["C"] * 8, ["D"] * 8, ["E"] * 8, ["E", "E", "E", "E", "D", "D", "B", "B"]] * 2

VERSE_LEAD = [None, None,
              [(71, 1), (69, 0.5), (67, 0.5), (64, 2)],
              [(62, 1), (64, 1), (67, 1), (69, 1)]]
CHORUS_LEAD = [[(76, 1), (74, 1), (71, 2)],
               [(72, 1), (74, 1), (76, 2)],
               [(79, 1), (78, 0.5), (76, 0.5), (74, 1), (71, 1)],
               [(76, 4)]] * 2


def main():
    guitar, lead, bass, drums = [(0, b"\xC0\x1D")], [(0, b"\xC1\x1E")], [(0, b"\xC2\x21")], []
    conductor = [(0, b"\xFF\x03\x0aPixel Riff"), (0, b"\xFF\x58\x04\x04\x02\x18\x08"),
                 midi.tempo_event(0, 130)]
    bars = VERSE + VERSE + CHORUS
    leads = VERSE_LEAD + VERSE_LEAD + CHORUS_LEAD
    chorus_start = len(VERSE) * 2
    conductor.append(midi.tempo_event(chorus_start * BAR, 150))

    for b, roots in enumerate(bars):
        o = b * BAR
        for k, r in enumerate(roots):
            t = o + k * E8
            root = ROOT[r]
            for p in (root, root + 7, root + 12):  # power chord
                guitar += midi.note_events(0, t, t + E8 - 30, p, 96)
            bass += midi.note_events(2, t, t + E8 - 20, root - 12, 100)
        t = o
        for item in leads[b] or []:
            p, beats = item
            lead += midi.note_events(1, t, t + int(beats * Q) - 20, p, 110)
            t += int(beats * Q)
        chorus = b >= chorus_start
        for k in range(8):
            t = o + k * E8
            drums += midi.note_events(9, t, t + 60, 51 if chorus else 42, 70)  # ride / hat
            if k in (0, 3, 4) or (chorus and k == 6):
                drums += midi.note_events(9, t + 10, t + 70, 36, 120)          # kick
            if k in (2, 6):
                drums += midi.note_events(9, t + 10, t + 70, 38, 110)          # snare
        if b in (0, chorus_start):
            drums += midi.note_events(9, o + 5, o + 400, 49, 120)              # crash
        if b == chorus_start - 1:  # tom fill into the chorus
            for k, p in enumerate((50, 48, 47, 45, 43, 41, 38, 38)):
                t = o + 3 * Q + k * Q // 8
                drums += midi.note_events(9, t + 15, t + 55, p, 115)

    data = midi.file_bytes([conductor, guitar, lead, bass, drums], 1, Q)
    (HERE / "demo_rock.mid").write_bytes(data)
    print(f"demo_rock.mid: {len(data)} bytes, {len(bars)} bars")


if __name__ == "__main__":
    main()
