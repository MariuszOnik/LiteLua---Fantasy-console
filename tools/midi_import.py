# SPDX-License-Identifier: Zlib
#
# LiteLua - MIDI -> .lsong v1 import (D37). The MIDI file stays the source:
# the import is a configurable arrangement for monophonic chiptune tracks,
# and the settings are stored in the song (x_import) so it can be repeated.
#
# Steps: sources (track + channel) -> roles (lead, lead2, chords, bass,
# drums; automatic or chosen) -> polyphony reduction per role (top, bottom,
# last, or arp = chords become NES arpeggios) -> GM drums to a kit ->
# quantization to the .lsong grid (the timing error is measured, not assumed)
# -> bars cut into patterns, repeated ones stored once.

import collections
import math
import pathlib

import midi

ROLES = ("lead", "lead2", "chords", "bass", "drums")
MODES = ("top", "bottom", "last", "arp")
DEFAULT_MODE = {"lead": "top", "lead2": "top", "chords": "arp", "bass": "bottom"}
DRUM_CHANNEL = 9

# General MIDI percussion (channel 10) -> drum of the kit
DRUM_CLASS = {35: "kick", 36: "kick", 37: "snare", 38: "snare", 39: "snare",
              40: "snare", 41: "tom", 43: "tom", 45: "tom", 47: "tom", 48: "tom",
              50: "tom", 42: "hat", 44: "hat", 46: "hat_open", 49: "crash",
              52: "crash", 55: "crash", 57: "crash", 51: "ride", 53: "ride", 59: "ride"}
DRUM_PRIORITY = ["kick", "snare", "tom", "crash", "hat_open", "hat", "ride"]
DRUM_TO = {"kick": 32, "snare": 64, "hat": 104, "hat_open": 100, "crash": 96, "ride": 108}
TOM_TO = {41: 44, 43: 48, 45: 52, 47: 55, 48: 58, 50: 62}
DRUM_INSTR = {
    "kick": {"type": "noise", "env": [1, 0.75, 0.45, 0.2, 0]},
    "snare": {"type": "noise", "volume": 0.8, "env": [1, 0.85, 0.65, 0.45, 0.3, 0.15, 0]},
    "tom": {"type": "noise", "volume": 0.7, "env": [1, 0.8, 0.55, 0.3, 0.1, 0]},
    "hat": {"type": "noise", "mode": "short", "volume": 0.4, "env": [1, 0.4, 0]},
    "hat_open": {"type": "noise", "volume": 0.35,
                 "env": [1, 0.8, 0.6, 0.45, 0.3, 0.2, 0.1, 0]},
    "crash": {"type": "noise", "volume": 0.4,
              "env": [1, 0.9, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3, 0.2, 0.1, 0]},
    "ride": {"type": "noise", "mode": "short", "volume": 0.3, "env": [1, 0.7, 0.5, 0.3, 0]},
}
MELODIC_INSTR = {
    "lead": {"type": "pulse", "duty": 0.25, "volume": 0.7,
             "env": [1, 0.9, 0.85, 0.8, 0.75, 0.7], "release": [0.4, 0.2]},
    "lead2": {"type": "pulse", "duty": 0.5, "volume": 0.55,
              "env": [1, 0.9, 0.85, 0.8, 0.75, 0.7], "release": [0.4, 0.2]},
    "chords": {"type": "pulse", "duty": 0.125, "volume": 0.4, "env": [1, 0.85, 0.7, 0.6]},
    "bass": {"type": "triangle", "volume": 0.9},
}
TIME_MODE_ERROR = 0.030  # Auto tempo mode: grid timing error above this -> time mode


class MidiImportError(Exception):
    pass


class Source:
    def __init__(self, index, track, channel, notes, name):
        self.index, self.track, self.channel = index, track, channel
        self.notes, self.name = notes, name
        progs = collections.Counter(n.program for n in notes)
        self.program = progs.most_common(1)[0][0] if notes else 0
        self.mean = sum(n.pitch for n in notes) / len(notes) if notes else 0
        self.poly = max_polyphony(notes)

    @property
    def is_drums(self):
        return self.channel == DRUM_CHANNEL

    def describe(self):
        lo = min((n.pitch for n in self.notes), default=0)
        hi = max((n.pitch for n in self.notes), default=0)
        kind = "drums (GM)" if self.is_drums else midi.GM_FAMILIES[self.program // 8]
        name = f'  "{self.name}"' if self.name else ""
        return (f"{self.index:3}  track {self.track + 1:2}  ch {self.channel + 1:2}  "
                f"{len(self.notes):5} notes  pitch {lo:3}-{hi:<3}  max {self.poly} at once"
                f"  {kind}{name}")


def max_polyphony(notes):
    ev = sorted([(n.start, 1) for n in notes] + [(n.end, -1) for n in notes])
    cur = best = 0
    for _, d in ev:
        cur += d
        best = max(best, cur)
    return best


def sources(mf):
    groups = collections.defaultdict(list)
    for n in mf.notes:
        if n.end > n.start:
            groups[(n.track, n.channel)].append(n)
    out = []
    for i, key in enumerate(sorted(groups)):
        track, ch = key
        out.append(Source(i + 1, track, ch, groups[key], mf.track_names.get(track, "")))
    return out


def auto_roles(srcs):
    """Drums: GM channel 10. Bass: a bass program or the lowest part. Chords:
    the most polyphonic part. Lead: the highest of the rest."""
    roles = {}
    drums = [s.index for s in srcs if s.is_drums]
    if drums:
        roles["drums"] = drums
    rest = [s for s in srcs if not s.is_drums]
    if not rest:
        return roles
    basses = [s for s in rest if 32 <= s.program < 40]
    low = min(rest, key=lambda s: s.mean)
    bass = min(basses, key=lambda s: s.mean) if basses else (low if low.mean < 55 else None)
    if bass and len(rest) > 1:
        roles["bass"] = [bass.index]
        rest = [s for s in rest if s is not bass]
    chords = max(rest, key=lambda s: (s.poly, len(s.notes)))
    if len(rest) > 1 and chords.poly >= 2:
        roles["chords"] = [chords.index]
        rest = [s for s in rest if s is not chords]
    lead = max(rest, key=lambda s: s.mean)
    roles["lead"] = [lead.index]
    return {r: roles[r] for r in ROLES if r in roles}


# --- Polyphony reduction --------------------------------------------------------

def reduce(notes, mode):
    """Notes of one role (MIDI ticks) -> monophonic notes
    [start, end, pitch, vel, chord] (chord: intervals for arp, else None),
    and the number of input notes that are heard nowhere."""
    starts, ends = collections.defaultdict(list), collections.defaultdict(list)
    for i, n in enumerate(notes):
        starts[n.start].append(i)
        ends[n.end].append(i)
    points = sorted(set(starts) | set(ends))
    active, heard, out = {}, set(), []
    cur_key, cur = None, None
    for p in points:
        for i in ends[p]:
            active.pop(i, None)
        for i in starts[p]:
            active[i] = notes[i]
        key, val = _select(active, mode)
        if key != cur_key:
            if cur:
                cur[1] = p
                out.append(cur)
            cur, cur_key = (list(val) if key else None), key
            if key:
                cur[0] = p
                heard.update(key[1] if isinstance(key[1], frozenset) else (key[1],))
    return out, len(notes) - len(heard)


def _select(active, mode):
    if not active:
        return None, None
    if mode == "arp" and len({n.pitch for n in active.values()}) > 1:
        pitches = sorted({n.pitch for n in active.values()})
        root = pitches[0]
        chord = tuple(p - root for p in pitches if p - root <= 24)[:4]
        vel = max(n.vel for n in active.values())
        return ("c", frozenset(active)), [0, 0, root, vel, chord]
    if mode == "bottom":
        i = min(active, key=lambda k: (active[k].pitch, -active[k].start))
    elif mode == "last":
        i = max(active, key=lambda k: (active[k].start, active[k].pitch))
    else:  # top (and arp with one pitch)
        i = max(active, key=lambda k: (active[k].pitch, active[k].start))
    n = active[i]
    return ("n", i), [0, 0, n.pitch, n.vel, None]


# --- Import -------------------------------------------------------------------

def _quantize_mono(notes, to_tick):
    """[start, end, pitch, vel, chord] in MIDI ticks -> sorted .lsong notes
    [t, e, pitch, vel, chord, src_start]; notes landing on a taken tick are
    dropped (counted)."""
    out, dropped = [], 0
    for s, e, p, v, c in sorted(notes, key=lambda n: n[0]):
        t, te = to_tick(s), to_tick(e)
        if out and out[-1][0] == t:
            dropped += 1
            continue
        out.append([t, max(te, t + 1), p, v, c, s])
    for a, b in zip(out, out[1:]):
        a[1] = min(a[1], b[0])
    return out, dropped


def _drums(notes, to_tick, ppq):
    """GM drum notes -> one drum at a time by priority, short notes"""
    hits, unmapped = {}, 0
    for n in notes:
        cls = DRUM_CLASS.get(n.pitch)
        if cls is None:
            cls, unmapped = "hat", unmapped + 1
        t = to_tick(n.start)
        cand = (DRUM_PRIORITY.index(cls), n.pitch, n.vel, n.start)
        if t not in hits or cand < hits[t]:
            hits[t] = cand
    dropped = len(notes) - len(hits)
    out = []
    times = sorted(hits)
    for k, t in enumerate(times):
        _, pitch, vel, src = hits[t]
        end = t + max(1, ppq // 4)
        if k + 1 < len(times):
            end = min(end, times[k + 1])
        out.append([t, end, pitch, vel, None, src])
    return out, dropped, unmapped


def _vel(v):
    v = round(v / 127, 2)
    return None if v >= 1 else v


def import_midi(path, roles=None, modes=None, tempo_mode="auto", ppq=24, bars=None,
                profile=None):
    """Returns (song, report lines). roles: {role: [source index]} or None for
    automatic; modes: {role: mode}."""
    mf = midi.read(path)
    srcs = sources(mf)
    if not srcs:
        raise MidiImportError("the MIDI file has no notes")
    by_index = {s.index: s for s in srcs}
    report = [f"MIDI format {mf.format}, {mf.division} ticks per quarter, "
              f"{len(mf.notes)} notes in {len(srcs)} sources"]
    report += [f"warning: {w}" for w in mf.warnings]

    if roles is None:
        roles = auto_roles(srcs)
        report.append("roles (automatic): " + ", ".join(
            f"{r} = {','.join(map(str, v))}" for r, v in roles.items()))
    for r, idxs in roles.items():
        if r not in ROLES:
            raise MidiImportError(f"unknown role '{r}'")
        for i in idxs:
            if i not in by_index:
                raise MidiImportError(f"there is no source {i} (see --list)")
    used = {i for v in roles.values() for i in v}
    unused = [s.index for s in srcs if s.index not in used]
    if unused:
        report.append(f"not used: sources {', '.join(map(str, unused))}")
    modes = {**DEFAULT_MODE, **(modes or {})}
    for r, m in modes.items():
        if r in ("lead", "lead2", "chords", "bass") and m not in MODES:
            raise MidiImportError(f"mode of {r} must be one of {', '.join(MODES)}")
    profile = profile or ("extended" if "lead2" in roles else "nes")
    if "lead2" in roles and profile != "extended":
        raise MidiImportError("lead2 needs --profile extended (more than 2 pulse tracks)")
    if not 1 <= ppq <= 96:
        raise MidiImportError("--ppq must be 1 .. 96")

    # Tempo: .lsong v1 has one tempo. Check what that costs.
    sec = mf.seconds_of()
    tm = mf.tempo_map()
    end_tick = max(n.end for n in mf.notes)
    total_s = sec(end_tick)
    tempo = 60 * (end_tick / mf.division) / total_s if total_s > 0 else 120
    bpms = [60e6 / us for _, us in tm if _ <= end_tick]
    changes = sum(1 for a, b in zip(bpms, bpms[1:]) if abs(b - a) / a > 0.005)
    if changes:
        report.append(f"warning: {changes} tempo changes ({min(bpms):.1f} .. "
                      f"{max(bpms):.1f} BPM); .lsong v1 has one tempo ({tempo:.2f} BPM)")

    def grid_tick(tick):
        return round(tick * ppq / mf.division)

    def time_tick(tick):
        return round(sec(tick) * tempo / 60 * ppq)

    def max_error(to_tick):
        starts = {n.start for n in mf.notes}
        return max(abs(to_tick(t) * 60 / (tempo * ppq) - sec(t)) for t in starts)

    if tempo_mode == "auto":
        tempo_mode = "grid" if max_error(grid_tick) <= TIME_MODE_ERROR else "time"
        if changes:
            report.append(f"tempo mode (automatic): {tempo_mode}")
    if tempo_mode not in ("grid", "time"):
        raise MidiImportError("--tempo-mode must be auto, grid or time")
    to_tick = grid_tick if tempo_mode == "grid" else time_tick
    if tempo_mode == "time" and changes:
        report.append("warning: time mode keeps the timing; bar lines and repeated "
                      "patterns follow the average tempo, not the music")

    # Meter (bars for patterns)
    sigs = sorted(mf.time_sigs)
    num, den = (sigs[0][1], sigs[0][2]) if sigs and sigs[0][0] == 0 else (4, 4)
    if len({(n_, d_) for _, n_, d_ in sigs}) > 1:
        report.append("warning: the meter changes; bars follow the first one "
                      f"({num}/{den})")
    if den not in (1, 2, 4, 8, 16):
        num, den = 4, 4
    bar = ppq * 4 * num // den

    # Roles -> monophonic notes in .lsong ticks
    parts, errors_s = {}, []
    for r in ROLES:
        if r not in roles:
            continue
        notes = [n for i in roles[r] for n in by_index[i].notes]
        if r == "drums":
            q, dropped, unmapped = _drums(notes, to_tick, ppq)
            if unmapped:
                report.append(f"drums: {unmapped} notes are not GM kit drums (played as hat)")
        else:
            mono, unheard = reduce(notes, modes[r])
            q, dropped = _quantize_mono(mono, to_tick)
            if unheard:
                report.append(f"{r}: {unheard} of {len(notes)} notes not heard "
                              f"(one note at a time, mode {modes[r]})")
        if dropped:
            report.append(f"{r}: {dropped} notes dropped (same tick after reduction"
                          f"{' / one drum at a time' if r == 'drums' else ''})")
        if q:
            parts[r] = q
            errors_s += [abs(n[0] * 60 / (tempo * ppq) - sec(n[5])) for n in q]
    if not parts:
        raise MidiImportError("no notes left in the chosen roles")
    report.append(f"timing ({tempo_mode} mode, {ppq} ticks per quarter): note starts "
                  f"off by max {max(errors_s) * 1000:.1f} ms, mean "
                  f"{sum(errors_s) / len(errors_s) * 1000:.1f} ms")

    # Arpeggio shapes -> instruments (at most 32 instruments in all)
    shapes = collections.Counter(n[4] for n in parts.get("chords", []) if n[4])
    drum_classes = sorted({DRUM_CLASS.get(n[2], "hat") for n in parts.get("drums", [])},
                          key=DRUM_PRIORITY.index)
    room = 32 - len([r for r in parts if r != "drums"]) - (1 + len(drum_classes)
                                                           if "drums" in parts else 0)
    arp_name = {s: f"arp{k + 1}" for k, (s, _) in enumerate(shapes.most_common(max(0, room)))}
    lost = sum(c for s, c in shapes.items() if s not in arp_name)
    if lost:
        report.append(f"chords: {lost} chords of rare shapes played as single notes")

    instruments = {r: dict(MELODIC_INSTR[r]) for r in parts if r != "drums"}
    for s, name in arp_name.items():
        instruments[name] = {**MELODIC_INSTR["chords"], "arp": list(s)}
    if "drums" in parts:
        for c in drum_classes:
            instruments[c] = dict(DRUM_INSTR[c])
        used_p = sorted({n[2] for n in parts["drums"]})
        instruments["kit"] = {"type": "kit", "drums": [
            {"p": p, "i": DRUM_CLASS.get(p, "hat"),
             "to": TOM_TO.get(p, DRUM_TO.get(DRUM_CLASS.get(p, "hat"), 64))} for p in used_p]}

    def note_dict(r, t, d, n):
        nd = {"t": t, "d": d, "p": n[2]}
        v = _vel(n[3])
        if v is not None:
            nd["v"] = v
        if r == "chords" and n[4] in arp_name:
            nd["i"] = arp_name[n[4]]
        return nd

    total = max(n[1] for q in parts.values() for n in q)
    options = [bars] if bars else [b for b in (1, 2, 4, 8, 16) if b * bar <= ppq * 64]
    best = None
    for b in options:
        if b * bar > ppq * 64:
            raise MidiImportError(f"--bars {b} is longer than 64 quarter notes")
        cand = _chunk(parts, total, b * bar, note_dict)
        cand["bars"] = b
        if cand["ok"] and (best is None or (cand["stored"], len(cand["playlist"]))
                           < (best["stored"], len(best["playlist"]))):
            best = cand
    if best is None:
        raise MidiImportError("the song does not fit .lsong v1 limits (256 patterns, 256 "
                           "playlist entries, 16384 notes); try fewer roles or --ppq 12")
    if best["split"]:
        report.append(f"warning: {best['split']} long notes cross pattern borders and "
                      "are played again there (v1 has no tied notes)")
    report.append(f"patterns: {best['bars']} bars each, {len(best['patterns'])} different "
                  f"of {best['chunks']}, playlist {len(best['playlist'])} entries, "
                  f"{best['stored']} notes stored")

    name = pathlib.Path(path).stem
    title = (mf.track_names.get(0) or name)[:64]
    song = {
        "lsong": 1,
        "title": title,
        "comment": f"Imported from {pathlib.Path(path).name} by litelua song import.",
        "tempo": round(min(400, max(20, tempo)), 3),
        "ppq": ppq,
        "meter": [num, den],
        "profile": profile,
        "instruments": instruments,
        "tracks": [{"name": r, "instrument": "kit" if r == "drums" else r}
                   for r in ROLES if r in parts],
        "patterns": best["patterns"],
        "playlist": best["playlist"],
        "x_import": {
            "source": pathlib.Path(path).name,
            "roles": {r: v for r, v in roles.items()},
            "modes": {r: modes[r] for r in parts if r != "drums"},
            "tempo_mode": tempo_mode, "ppq": ppq, "bars": best["bars"],
        },
    }
    if not 20 <= tempo <= 400:
        report.append(f"warning: average tempo {tempo:.1f} BPM is outside 20 .. 400")
    return song, report


def _chunk(parts, total, length, note_dict):
    """Cuts the notes into patterns of 'length' ticks; equal patterns are
    stored once, repeats become 'times' in the playlist."""
    count = math.ceil(total / length)
    chunks = [{r: [] for r in parts} for _ in range(count)]
    split = 0
    for r, q in parts.items():
        for n in q:
            t, e = n[0], n[1]
            first = True
            while t < e:
                c = t // length
                ce = min(e, (c + 1) * length)
                chunks[c][r].append(note_dict(r, t - c * length, ce - t, n))
                if not first:
                    split += 1
                first = False
                t = ce
    patterns, sig_name, playlist = {}, {}, []
    ok = True
    for ch in chunks:
        if any(len(v) > 1024 for v in ch.values()):
            ok = False
        sig = tuple((r, tuple(tuple(sorted(n.items())) for n in ch[r])) for r in parts)
        if sig not in sig_name:
            sig_name[sig] = f"p{len(sig_name) + 1}"
            patterns[sig_name[sig]] = {"length": length,
                                       "notes": {r: v for r, v in ch.items() if v}}
        nm = sig_name[sig]
        if playlist and playlist[-1]["pattern"] == nm and playlist[-1].get("times", 1) < 64:
            playlist[-1]["times"] = playlist[-1].get("times", 1) + 1
        else:
            playlist.append({"pattern": nm})
    stored = sum(len(v) for p in patterns.values() for v in p["notes"].values())
    ok = ok and len(patterns) <= 256 and len(playlist) <= 256 and stored <= 16384
    return {"ok": ok, "patterns": patterns, "playlist": playlist, "stored": stored,
            "split": split, "chunks": count}
