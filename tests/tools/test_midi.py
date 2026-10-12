# SPDX-License-Identifier: Zlib
#
# Tests of tools/midi.py and tools/midi_import.py (D37):
#   python -m unittest discover -s tests/tools -v

import pathlib
import re
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import lsong  # noqa: E402
import midi  # noqa: E402
import midi_import  # noqa: E402

Q = 480  # Ticks per quarter in the test files


def notes_ev(ch, items):
    """items: (start_quarters, length_quarters, pitch[, vel])"""
    ev = []
    for it in items:
        s, l, p = it[:3]
        ev += midi.note_events(ch, int(s * Q), int((s + l) * Q), p, it[3] if len(it) > 3 else 100)
    return ev


def write(tmp, name, tracks, fmt=1):
    path = pathlib.Path(tmp) / name
    path.write_bytes(midi.file_bytes(tracks, fmt, Q))
    return path


def run_import(path, **kw):
    song, report = midi_import.import_midi(path, **kw)
    check = lsong.validate(song)
    return song, report, check


def timing_ms(report):
    line = next(x for x in report if x.startswith("timing"))
    return float(re.search(r"max ([\d.]+) ms", line).group(1))


class ReaderTest(unittest.TestCase):
    def test_format0_running_status(self):
        # Hand-made track: note on, then running status with velocity 0 as note off
        body = bytes([0x00, 0x90, 60, 100,     # C4 on
                      0x60, 64, 90,            # (running) E4 on, 96 ticks later
                      0x60, 60, 0,             # (running) C4 off (velocity 0)
                      0x00, 64, 0,             # (running) E4 off
                      0x00, 0xFF, 0x2F, 0x00])
        data = (b"MThd" + bytes([0, 0, 0, 6, 0, 0, 0, 1, 0, 96])
                + b"MTrk" + len(body).to_bytes(4, "big") + body)
        mf = midi.parse(data)
        self.assertEqual(mf.format, 0)
        self.assertEqual([(n.start, n.end, n.pitch, n.vel) for n in mf.notes],
                         [(0, 192, 60, 100), (96, 192, 64, 90)])

    def test_writer_uses_running_status(self):
        ev = notes_ev(0, [(0, 1, 60), (1, 1, 62), (2, 1, 64)])
        chunk = midi.track_bytes(ev)
        self.assertEqual(chunk.count(bytes([0x90])), 1)  # status written once
        mf = midi.parse(b"MThd" + bytes([0, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0]) + chunk)
        self.assertEqual([n.pitch for n in mf.notes], [60, 62, 64])

    def test_format1_tracks_names_and_channels(self):
        with tempfile.TemporaryDirectory() as tmp:
            conductor = [midi.tempo_event(0, 100), (0, b"\xFF\x03\x04Song"),
                         (0, b"\xFF\x58\x04\x03\x02\x18\x08")]  # 3/4
            path = write(tmp, "a.mid", [
                conductor,
                [(0, b"\xFF\x03\x04Lead")] + notes_ev(0, [(0, 1, 72)]),
                notes_ev(9, [(0, 0.25, 36)]) + notes_ev(1, [(0, 2, 40)]),
            ])
            mf = midi.read(path)
            self.assertEqual((mf.format, len(mf.notes)), (1, 3))
            self.assertEqual(mf.track_names[0], "Song")
            self.assertEqual(mf.time_sigs, [(0, 3, 4)])
            srcs = midi_import.sources(mf)
            self.assertEqual([(s.track, s.channel) for s in srcs], [(1, 0), (2, 1), (2, 9)])
            self.assertTrue(srcs[2].is_drums)

    def test_overlapping_same_pitch(self):
        ev = [(0, b"\x90\x3c\x64"), (240, b"\x90\x3c\x50"),
              (480, b"\x80\x3c\x00"), (720, b"\x80\x3c\x00")]
        mf = midi.parse(midi.file_bytes([ev], 0, Q))
        self.assertEqual([(n.start, n.end, n.vel) for n in mf.notes],
                         [(0, 480, 100), (240, 720, 80)])  # oldest note ends first

    def test_tempo_map_seconds(self):
        mf = midi.parse(midi.file_bytes([[midi.tempo_event(0, 120),
                                          midi.tempo_event(2 * Q, 60)]
                                         + notes_ev(0, [(0, 4, 60)])], 1, Q))
        sec = mf.seconds_of()
        self.assertAlmostEqual(sec(2 * Q), 1.0)
        self.assertAlmostEqual(sec(4 * Q), 3.0)

    def test_bad_files(self):
        good_head = b"MThd" + bytes([0, 0, 0, 6, 0, 1, 0, 1, 1, 0xE0])
        bad = [
            b"RIFF....",                                              # not MIDI
            b"MThd" + bytes([0, 0, 0, 6, 0, 2, 0, 1, 1, 0xE0]),      # format 2
            b"MThd" + bytes([0, 0, 0, 6, 0, 1, 0, 1, 0xE7, 0x28]),   # SMPTE
            good_head + b"MTrk\0\0\0\x04\x00\x3c\x64\x00",            # data byte first
            good_head + b"MTrk\0\0\0\x05\xff\xff\xff\xff\xff",        # VLQ too long
        ]
        for data in bad:
            with self.subTest(data=data[:12]):
                with self.assertRaises(midi.MidiError):
                    midi.parse(data)


class ImportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def test_reduction_modes_and_arp(self):
        # C major chord held for a bar, a melody above it
        chord = notes_ev(0, [(0, 4, 60), (0, 4, 64), (0, 4, 67)])
        path = write(self.tmp.name, "c.mid", [chord])
        for mode, expect in (("top", [67]), ("bottom", [60])):
            song, _, check = run_import(path, roles={"lead": [1]}, modes={"lead": mode})
            self.assertEqual(check.errors, [])
            notes = song["patterns"]["p1"]["notes"]["lead"]
            self.assertEqual([n["p"] for n in notes], expect)
        song, report, check = run_import(path, roles={"chords": [1]})
        self.assertEqual(check.errors, [])
        n = song["patterns"]["p1"]["notes"]["chords"][0]
        self.assertEqual(n["p"], 60)
        self.assertEqual(song["instruments"][n["i"]]["arp"], [0, 4, 7])
        self.assertFalse(any("not heard" in x for x in report))

    def test_unheard_notes_are_reported(self):
        path = write(self.tmp.name, "c.mid", [notes_ev(0, [(0, 4, 60), (0, 4, 64)])])
        _, report, _ = run_import(path, roles={"lead": [1]}, modes={"lead": "top"})
        self.assertTrue(any("1 of 2 notes not heard" in x for x in report))

    def test_gm_drums(self):
        drums = notes_ev(9, [(0, 0.25, 36), (0, 0.25, 42), (1, 0.25, 38),
                             (2, 0.25, 81), (3, 0.25, 45)])
        path = write(self.tmp.name, "d.mid", [drums])
        song, report, check = run_import(path)
        self.assertEqual(check.errors, [])
        kit = {d["p"]: d["i"] for d in song["instruments"]["kit"]["drums"]}
        self.assertEqual(kit, {36: "kick", 38: "snare", 81: "hat", 45: "tom"})
        played = [n["p"] for n in song["patterns"]["p1"]["notes"]["drums"]]
        self.assertEqual(played, [36, 38, 81, 45])   # kick wins over the hat at 0
        self.assertTrue(any("1 notes dropped" in x for x in report))
        self.assertTrue(any("not GM kit drums" in x for x in report))

    def test_repeated_bars_become_one_pattern(self):
        bar = [(b * 4 + k, 1, 60 + 2 * k) for b in range(8) for k in range(4)]
        path = write(self.tmp.name, "r.mid", [notes_ev(0, bar)])
        song, report, check = run_import(path, roles={"lead": [1]})
        self.assertEqual(check.errors, [])
        self.assertEqual(len(song["patterns"]), 1)
        self.assertEqual(song["playlist"], [{"pattern": "p1", "times": 8}])

    def test_tempo_change_v1_single_tempo(self):
        tracks = [[midi.tempo_event(0, 120), midi.tempo_event(4 * Q, 80)],
                  notes_ev(0, [(k, 1, 60 + k % 5) for k in range(8)])]
        path = write(self.tmp.name, "t.mid", tracks)
        song, report, check = run_import(path, roles={"lead": [1]}, version=1)
        self.assertEqual(check.errors, [])
        self.assertEqual(song["lsong"], 1)
        self.assertTrue(any("tempo: 1 changes" in x for x in report))
        self.assertTrue(any("tempo mode (automatic): time" in x for x in report))
        self.assertLess(timing_ms(report), 25)          # time mode keeps the timing
        _, report_g, _ = run_import(path, roles={"lead": [1]}, tempo_mode="grid", version=1)
        self.assertGreater(timing_ms(report_g), 300)     # one tempo cannot follow it
        self.assertEqual(song["x_import"]["tempo_mode"], "time")

    def test_tempo_change_v11_in_playlist(self):
        tracks = [[midi.tempo_event(0, 120), midi.tempo_event(4 * Q, 80)],
                  notes_ev(0, [(k, 1, 60 + k % 5) for k in range(8)])]
        path = write(self.tmp.name, "t.mid", tracks)
        song, report, check = run_import(path, roles={"lead": [1]})
        self.assertEqual(check.errors, [])
        self.assertEqual(song["lsong"], 1.1)
        self.assertEqual(song["x_import"]["tempo_mode"], "entries")
        self.assertEqual(song["tempo"], 120)
        self.assertEqual([e.get("tempo") for e in song["playlist"]], [None, 80])
        self.assertLess(timing_ms(report), 1)            # exact, not just close
        mf = midi.read(path)
        self.assertAlmostEqual(lsong.duration(song), mf.seconds_of()(8 * Q), places=6)

    def test_tempo_change_inside_a_bar(self):
        # 120 -> 60 BPM at beat 2.5 of bar 1; a long note crosses that point
        tracks = [[midi.tempo_event(0, 120), midi.tempo_event(int(2.5 * Q), 60)],
                  notes_ev(0, [(0, 1, 60), (1, 3, 64), (4, 4, 67)])]
        path = write(self.tmp.name, "m.mid", tracks)
        song, report, check = run_import(path, roles={"lead": [1]})
        self.assertEqual(check.errors, [])
        self.assertEqual(check.warnings, [])
        self.assertTrue(any("1 inside a bar" in x for x in report))
        self.assertLess(timing_ms(report), 1)
        first, second = (song["patterns"][e["pattern"]] for e in song["playlist"][:2])
        self.assertEqual(first["length"], 60)            # cut at the change
        tied = second["notes"]["lead"][0]
        self.assertEqual((tied["t"], tied["p"], tied.get("tie")), (0, 64, True))
        self.assertEqual(song["playlist"][1]["tempo"], 60)
        # Every note start keeps its MIDI time
        mf = midi.read(path)
        sec = mf.seconds_of()
        self.assertAlmostEqual(lsong.duration(song), sec(8 * Q), places=6)

    def test_one_tempo_keeps_grid(self):
        path = write(self.tmp.name, "g.mid", [[midi.tempo_event(0, 140)]
                                              + notes_ev(0, [(k / 2, 0.5, 60) for k in range(16)])])
        song, report, _ = run_import(path, roles={"lead": [1]})
        self.assertEqual(song["tempo"], 140)
        self.assertEqual(song["x_import"]["tempo_mode"], "grid")
        self.assertLess(timing_ms(report), 1)

    def test_auto_roles_and_render(self):
        tracks = [
            [midi.tempo_event(0, 150)],
            [(0, b"\xC0\x50")] + notes_ev(0, [(k, 1, 76 + k % 3) for k in range(8)]),
            [(0, b"\xC1\x21")] + notes_ev(1, [(k * 2, 2, 40) for k in range(4)]),
            notes_ev(2, [(k * 2, 2, p) for k in range(4) for p in (60, 64, 67)]),
            notes_ev(9, [(k, 0.25, 36 if k % 2 == 0 else 38) for k in range(8)]),
        ]
        path = write(self.tmp.name, "auto.mid", tracks)
        song, report, check = run_import(path)
        self.assertEqual(check.errors, [])
        roles = song["x_import"]["roles"]
        # The conductor track has no notes: sources are numbered 1..4
        self.assertEqual(roles, {"drums": [4], "bass": [2], "lead": [1], "chords": [3]})
        self.assertEqual([t["name"] for t in song["tracks"]],
                         ["lead", "chords", "bass", "drums"])
        out = pathlib.Path(self.tmp.name) / "auto.wav"
        seconds = lsong.render(lsong.parse_lua(lsong.to_lua(song)), out)
        self.assertAlmostEqual(seconds, 8 * 60 / 150 + 0.5, delta=0.2)

    def test_lead2_needs_extended(self):
        path = write(self.tmp.name, "x.mid", [notes_ev(0, [(0, 1, 60)]), notes_ev(1, [(0, 1, 64)])])
        with self.assertRaises(midi_import.MidiImportError):
            midi_import.import_midi(path, roles={"lead": [1], "lead2": [2]}, profile="nes")
        song, _, check = run_import(path, roles={"lead": [1], "lead2": [2]})
        self.assertEqual(song["profile"], "extended")
        self.assertEqual(check.errors, [])


if __name__ == "__main__":
    unittest.main()
