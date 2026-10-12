# SPDX-License-Identifier: Zlib
#
# Tests of tools/lsong.py (.lsong v1, D36):
#   python -m unittest discover -s tests/tools -v

import copy
import math
import pathlib
import struct
import sys
import tempfile
import unittest
import wave

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import lsong  # noqa: E402

EXAMPLE = ROOT / "examples" / "songs" / "sky_hopper.lsong"


def minimal():
    return {
        "lsong": 1, "tempo": 120,
        "instruments": {"lead": {"type": "pulse"}},
        "tracks": [{"name": "lead", "instrument": "lead"}],
        "patterns": {"a": {"length": 96, "notes": {"lead": [{"t": 0, "d": 24, "p": 69}]}}},
        "playlist": [{"pattern": "a"}],
    }


def errors(song):
    return lsong.validate(song).errors


def warnings(song):
    return lsong.validate(song).warnings


class ParserTest(unittest.TestCase):
    def test_example_round_trip(self):
        song = lsong.load(EXAMPLE)
        self.assertEqual(errors(song), [])
        via_json = lsong.parse_json(lsong.to_json(song))
        via_lua = lsong.parse_lua(lsong.to_lua(via_json))
        self.assertEqual(via_json, song)
        self.assertEqual(via_lua, song)

    def test_lua_syntax(self):
        text = """-- comment
        --[==[ long
        comment ]==]
        return { a = 1, ["b c"] = -2.5e1, s = 'x\\ty', l = [[
line]], list = { 1, 0x10; true, false, }, }"""
        self.assertEqual(lsong.parse_lua(text), {
            "a": 1, "b c": -25.0, "s": "x\ty", "l": "line",
            "list": [1, 16, True, False]})

    def test_code_is_rejected(self):
        bad = [
            "while true do end",
            "return (function() while true do end end)()",
            "local t = {} return t",
            "return { a = 1 .. 2 }",
            "return { a = 1 + 2 }",
            "return { a = x }",
            "return { f = print }",
            "return { a = string.rep('x', 1e9) }",
            "return { a = nil }",
            "return {} {}",
            "return { [1] = 2 }",
            "return { 1, a = 2 }",
            "return { a = 1, a = 2 }",
            "\x1bLua",
            "return { 'unterminated }",
            "return { a = 1",
            "return { a = 01x }",
        ]
        for text in bad:
            with self.subTest(text=text):
                with self.assertRaises(lsong.LsongError):
                    lsong.parse_lua(text)

    def test_limits(self):
        with self.assertRaises(lsong.LsongError):
            lsong.parse_lua("return {" * 17 + "}" * 17)
        lsong.parse_lua("return " + "{" * 16 + "}" * 16)
        with self.assertRaises(lsong.LsongError):
            lsong.parse_lua("return { s = '" + "x" * 513 + "' }")
        with self.assertRaises(lsong.LsongError):
            lsong.parse_lua("return { s = '" + "x" * 300000 + "' }")

    def test_json(self):
        with self.assertRaises(lsong.LsongError):
            lsong.parse_json('{"a": 1, "a": 2}')
        with self.assertRaises(lsong.LsongError):
            lsong.parse_json('{"a": }')


class ValidatorTest(unittest.TestCase):
    def test_minimal_ok(self):
        self.assertEqual(errors(minimal()), [])
        self.assertEqual(warnings(minimal()), [])

    def test_required_and_unknown_fields(self):
        s = minimal()
        del s["tempo"]
        s["temp"] = 120
        e = errors(s)
        self.assertTrue(any("'tempo' is missing" in x for x in e))
        self.assertTrue(any("unknown field 'temp'" in x for x in e))
        s = minimal()
        s["x_editor"] = {"zoom": 2}
        self.assertEqual(errors(s), [])

    def test_ranges(self):
        cases = [
            (lambda s: s.update(tempo=10), "tempo"),
            (lambda s: s.update(ppq=0), "ppq"),
            (lambda s: s.update(lsong=2), "version"),
            (lambda s: s.update(loop=5), "loop"),
            (lambda s: s["patterns"]["a"]["notes"]["lead"][0].update(p=128), ".p"),
            (lambda s: s["patterns"]["a"]["notes"]["lead"][0].update(d=0), ".d"),
            (lambda s: s["patterns"]["a"]["notes"]["lead"][0].update(t=96), ".t"),
            (lambda s: s["patterns"]["a"]["notes"]["lead"][0].update(v=1.5), ".v"),
            (lambda s: s["instruments"]["lead"].update(duty=0.3), "duty"),
            (lambda s: s["instruments"]["lead"].update(duty=0.375), "profile nes"),
            (lambda s: s["instruments"]["lead"].update(env=[1, 2]), "env"),
            (lambda s: s["instruments"]["lead"].update(arp=[0, 30]), "arp"),
            (lambda s: s["playlist"][0].update(times=0), "times"),
            (lambda s: s["playlist"][0].update(pattern="zz"), "unknown pattern"),
            (lambda s: s["tracks"][0].update(instrument="zz"), "unknown instrument"),
            (lambda s: s.update(title="x" * 65), "title"),
        ]
        for change, text in cases:
            s = minimal()
            change(s)
            with self.subTest(text=text):
                self.assertTrue(any(text in x for x in errors(s)), errors(s))

    def test_extended_profile_allows_more_duties(self):
        s = minimal()
        s["profile"] = "extended"
        s["instruments"]["lead"]["duty"] = 0.375
        self.assertEqual(errors(s), [])

    def test_monophony(self):
        s = minimal()
        s["patterns"]["a"]["notes"]["lead"] = [
            {"t": 0, "d": 48, "p": 60}, {"t": 24, "d": 24, "p": 62}]
        self.assertEqual(errors(s), [])
        self.assertTrue(any("is cut by note" in x for x in warnings(s)))
        s["patterns"]["a"]["notes"]["lead"].append({"t": 24, "d": 6, "p": 64})
        self.assertTrue(any("same tick" in x for x in errors(s)))
        s = minimal()
        s["patterns"]["a"]["notes"]["lead"] = [{"t": 90, "d": 12, "p": 60}]
        self.assertTrue(any("past the pattern end" in x for x in warnings(s)))

    def test_profile_track_limits(self):
        s = minimal()
        s["tracks"] += [{"name": "b", "instrument": "lead"},
                        {"name": "c", "instrument": "lead"}]
        self.assertTrue(any("at most 2 pulse" in x for x in errors(s)))
        s["profile"] = "extended"
        self.assertEqual(errors(s), [])

    def test_kit_and_instrument_change(self):
        s = minimal()
        s["instruments"].update({
            "n": {"type": "noise"}, "tri": {"type": "triangle"},
            "kit": {"type": "kit", "drums": [{"p": 36, "i": "n", "to": 30}]}})
        s["tracks"].append({"name": "drums", "instrument": "kit"})
        s["tracks"].append({"name": "bass", "instrument": "tri"})
        s["patterns"]["a"]["notes"]["drums"] = [{"t": 0, "d": 6, "p": 36}]
        self.assertEqual(errors(s), [])
        s["patterns"]["a"]["notes"]["drums"].append({"t": 12, "d": 6, "p": 37})
        self.assertTrue(any("not a drum" in x for x in errors(s)))
        s["patterns"]["a"]["notes"]["drums"].pop()
        # A pulse instrument on the triangle track does not fit
        s["patterns"]["a"]["notes"]["bass"] = [{"t": 0, "d": 6, "p": 40, "i": "lead"}]
        self.assertTrue(any("does not fit" in x for x in errors(s)))
        # Mixed drum types in one kit
        s["patterns"]["a"]["notes"]["bass"] = []
        s["instruments"]["kit"]["drums"].append({"p": 38, "i": "tri"})
        self.assertTrue(any("same type" in x for x in errors(s)))

    def test_transpose_range_and_drums(self):
        s = minimal()
        s["patterns"]["a"]["notes"]["lead"][0]["p"] = 120
        s["playlist"][0]["transpose"] = 12
        self.assertTrue(any("out of 0 .. 127" in x for x in errors(s)))

    def test_size_limits(self):
        s = minimal()
        s["patterns"]["a"]["length"] = 24 * 64
        s["patterns"]["a"]["notes"]["lead"] = [
            {"t": i, "d": 1, "p": 60} for i in range(1025)]
        self.assertTrue(any("1024" in x for x in errors(s)))
        s = minimal()
        s["patterns"]["a"]["length"] = 24 * 64
        s["playlist"] = [{"pattern": "a", "times": 64}] * 3  # 3 x 64 x 32 s
        self.assertTrue(any("at most 30" in x for x in errors(s)))


class Version11Test(unittest.TestCase):
    def song11(self):
        s = minimal()
        s["lsong"] = 1.1
        s["patterns"]["b"] = {"length": 96, "notes": {"lead": [
            {"t": 0, "d": 48, "p": 69, "tie": True}]}}
        s["patterns"]["a"]["notes"]["lead"] = [{"t": 0, "d": 96, "p": 69}]
        s["playlist"] = [{"pattern": "a"}, {"pattern": "b", "tempo": 60}]
        s["loop"] = False
        return s

    def test_v1_files_still_valid(self):
        self.assertEqual(errors(lsong.load(EXAMPLE)), [])
        self.assertEqual(lsong.load(EXAMPLE)["lsong"], 1)

    def test_new_fields_need_v11(self):
        s = self.song11()
        self.assertEqual(errors(s), [])
        self.assertEqual(warnings(s), [])
        s["lsong"] = 1
        e = errors(s)
        self.assertTrue(any(".tie: needs lsong = 1.1" in x for x in e))
        self.assertTrue(any(".tempo: needs lsong = 1.1" in x for x in e))

    def test_tie_rules(self):
        s = self.song11()
        s["patterns"]["b"]["notes"]["lead"][0]["t"] = 6
        self.assertTrue(any("only a note at t = 0" in x for x in errors(s)))
        s = self.song11()
        s["patterns"]["b"]["notes"]["lead"][0]["p"] = 70   # nothing to continue
        self.assertEqual(errors(s), [])
        self.assertTrue(any("does not continue" in x for x in warnings(s)))
        s = self.song11()
        s["patterns"]["b"]["notes"]["lead"][0]["tie"] = False
        self.assertTrue(any("must be true" in x for x in errors(s)))

    def test_tempo_per_entry_and_loop(self):
        s = self.song11()
        self.assertAlmostEqual(lsong.duration(s), 2.0 + 4.0)   # 120 then 60 BPM
        s["loop"] = 2   # the loop restores the tempo of entry 2 (60)
        with tempfile.TemporaryDirectory() as d:
            seconds = lsong.render(s, pathlib.Path(d) / "x.wav", loops=2)
        self.assertAlmostEqual(seconds, 6.0 + 4.0 + 0.5, delta=0.01)

    def test_tie_has_no_new_attack(self):
        s = self.song11()
        s["instruments"]["lead"]["env"] = [1, 0.8, 0.6, 0.4, 0.3]   # decays
        s["playlist"] = [{"pattern": "a"}, {"pattern": "b"}]
        tied, rate = render(s)
        s["patterns"]["b"]["notes"]["lead"][0].pop("tie")
        again, _ = render(s)
        at = int(2.0 * rate)   # pattern border
        window = slice(at + 50, at + 300)
        self.assertLess(max(abs(x) for x in tied[window]), 0.5 * max(abs(x) for x in again[window]))


def render(song, rate=22050):
    with tempfile.TemporaryDirectory() as d:
        path = pathlib.Path(d) / "x.wav"
        lsong.render(song, path, rate=rate)
        with wave.open(str(path)) as w:
            n = w.getnframes()
            return list(struct.unpack(f"<{n}h", w.readframes(n))), w.getframerate()


def crossings_hz(samples, rate, start, end):
    seg = samples[int(start * rate):int(end * rate)]
    ups = sum(1 for a, b in zip(seg, seg[1:]) if a < 0 <= b)
    return ups / (end - start)


class RendererTest(unittest.TestCase):
    def test_pitch_pulse_and_triangle(self):
        for kind in ("pulse", "triangle"):
            s = minimal()
            s["instruments"]["lead"] = {"type": kind}
            s["patterns"]["a"]["notes"]["lead"] = [{"t": 0, "d": 96, "p": 69}]  # A4, 2 s
            samples, rate = render(s)
            hz = crossings_hz(samples, rate, 0.2, 1.8)
            with self.subTest(kind=kind):
                self.assertAlmostEqual(hz, 440, delta=4.4)

    def test_monophonic_cut_and_timing(self):
        s = minimal()
        s["patterns"]["a"]["notes"]["lead"] = [
            {"t": 0, "d": 96, "p": 57}, {"t": 48, "d": 48, "p": 69}]  # A3 cut by A4
        samples, rate = render(s)
        self.assertAlmostEqual(crossings_hz(samples, rate, 0.1, 0.9), 220, delta=3)
        self.assertAlmostEqual(crossings_hz(samples, rate, 1.1, 1.9), 440, delta=5)

    def test_envelope_and_silence(self):
        s = minimal()
        s["instruments"]["lead"]["env"] = [1, 0.5, 0]
        samples, rate = render(s)
        early = max(abs(x) for x in samples[:int(0.01 * rate)])
        late = max(abs(x) for x in samples[int(0.2 * rate):int(0.4 * rate)])
        self.assertGreater(early, 1000)
        self.assertLess(late, 200)

    def test_noise_and_example(self):
        song = lsong.load(EXAMPLE)
        samples, rate = render(song)
        self.assertAlmostEqual(len(samples) / rate, lsong.duration(song) + 0.5, delta=0.1)
        peak = max(abs(x) for x in samples)
        self.assertGreater(peak, 10000)
        self.assertLess(peak, 32767)
        rms = math.sqrt(sum(x * x for x in samples) / len(samples))
        self.assertGreater(rms, 1500)

    def test_loops(self):
        s = minimal()
        s["patterns"]["b"] = copy.deepcopy(s["patterns"]["a"])
        s["playlist"].append({"pattern": "b"})
        s["loop"] = 2
        once, rate = render(s)
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "x.wav"
            seconds = lsong.render(s, path, loops=3)
        self.assertAlmostEqual(seconds - len(once) / rate, 4.0, delta=0.01)  # 2 x pattern b


if __name__ == "__main__":
    unittest.main()
