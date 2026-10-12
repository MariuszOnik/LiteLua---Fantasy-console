# SPDX-License-Identifier: Zlib
#
# LiteLua - MIDI -> .lsong import (D37, v1.1: D38). The MIDI file stays the source:
# the import is a configurable arrangement for monophonic chiptune tracks,
# and the settings are stored in the song (x_import) so it can be repeated.
#
# Steps: sources (track + channel) -> roles (lead, lead2, chords, bass,
# drums; automatic or chosen) -> polyphony reduction per role (top, bottom,
# last, or arp = chords become NES arpeggios) -> GM drums to a kit ->
# quantization to the .lsong grid (the timing error is measured, not assumed)
# -> bars cut into patterns, repeated ones stored once. With .lsong v1.1 the
# tempo changes go into the playlist (patterns are also cut where the tempo
# changes inside a bar) and notes crossing pattern borders are tied.

import bisect
import collections
import pathlib

import midi

ROLES = ("lead", "lead2", "chords", "chords2", "bass", "drums", "cymbals")
MELODIC = ("lead", "lead2", "chords", "chords2", "bass")
DRUM_ROLES = ("drums", "cymbals")
ROLE_KIND = {"lead": "pulse", "lead2": "pulse", "chords": "pulse", "chords2": "pulse",
             "bass": "triangle", "drums": "noise", "cymbals": "noise"}
KIT_NAME = {"drums": "kit", "cymbals": "kit2"}
MODES = ("top", "second", "bottom", "last", "arp")
DEFAULT_MODE = {"lead": "top", "lead2": "top", "chords": "arp", "chords2": "arp",
                "bass": "bottom"}
DRUM_CHANNEL = 9

# General MIDI percussion (channel 10) -> drum of the kit
DRUM_CLASS = {35: "kick", 36: "kick", 37: "snare", 38: "snare", 39: "snare",
              40: "snare", 41: "tom", 43: "tom", 45: "tom", 47: "tom", 48: "tom",
              50: "tom", 42: "hat", 44: "hat", 46: "hat_open", 49: "crash",
              52: "crash", 55: "crash", 57: "crash", 51: "ride", 53: "ride", 59: "ride"}
DRUM_PRIORITY = ["kick", "snare", "tom", "crash", "hat_open", "hat", "ride"]
METAL = {"crash", "hat_open", "hat", "ride"}  # --split-drums: these go to "cymbals"
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
    "chords2": {"type": "pulse", "duty": 0.25, "volume": 0.35, "env": [1, 0.85, 0.7, 0.6]},
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
    if mode == "second":  # A second voice: the next note below the top one
        order = sorted(active, key=lambda k: (active[k].pitch, active[k].start), reverse=True)
        below = [k for k in order if active[k].pitch < active[order[0]].pitch]
        if not below:
            return None, None
        n = active[below[0]]
        return ("n", below[0]), [0, 0, n.pitch, n.vel, None]
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


def _vel(v, loudest):
    """Velocity relative to the loudest note of the role: the loudest notes
    need no 'v' (the instrument volume sets the level), quieter ones keep
    their difference (accents, dynamics)."""
    v = round(v / loudest, 2)
    return None if v >= 1 else v


def import_midi(path, roles=None, modes=None, tempo_mode="auto", ppq=24, bars=None,
                profile=None, version=1.1, split_drums=False):
    """Returns (song, report lines). roles: {role: [source index]} or None for
    automatic; modes: {role: mode}; version: .lsong 1 or 1.1 (tempo changes
    in the playlist and tied notes); split_drums: cymbals and hi-hats of the
    drums go to a second noise track "cymbals" (profile extended)."""
    mf = midi.read(path)
    srcs = sources(mf)
    if not srcs:
        raise MidiImportError("the MIDI file has no notes")
    if version not in (1, 1.1):
        raise MidiImportError("--lsong must be 1 or 1.1")
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
        if r in MELODIC and m not in MODES:
            raise MidiImportError(f"mode of {r} must be one of {', '.join(MODES)}")
    kinds = collections.Counter(ROLE_KIND[r] for r in roles)
    if split_drums and "drums" in roles and "cymbals" not in roles:
        kinds["noise"] += 1
    nes_ok = kinds["pulse"] <= 2 and kinds["triangle"] <= 1 and kinds["noise"] <= 1
    if profile is None:
        profile = "nes" if nes_ok else "extended"
    elif profile == "nes" and not nes_ok:
        raise MidiImportError("these roles need --profile extended (NES Classic has "
                              "2 pulse, 1 triangle and 1 noise track)")
    if not 1 <= ppq <= 96:
        raise MidiImportError("--ppq must be 1 .. 96")

    # Tempo map of the file, in .lsong grid ticks
    sec = mf.seconds_of()
    end_tick = max(n.end for n in mf.notes)
    total_s = sec(end_tick)
    avg = 60 * (end_tick / mf.division) / total_s if total_s > 0 else 120

    def grid_tick(tick):
        return round(tick * ppq / mf.division)

    changes = []  # [(grid tick, bpm)], first at 0
    for t, us in mf.tempo_map():
        if t > end_tick:
            break
        bpm = 60e6 / us
        gt = grid_tick(t)
        if changes and changes[-1][0] == gt:
            changes[-1] = (gt, bpm)
        elif not changes or abs(bpm - changes[-1][1]) / changes[-1][1] > 0.001:
            changes.append((gt, bpm))
    n_changes = len(changes) - 1
    if n_changes:
        bpms = [b for _, b in changes]
        report.append(f"tempo: {n_changes} changes ({min(bpms):.1f} .. {max(bpms):.1f} BPM)")

    if tempo_mode == "auto":
        if n_changes and version == 1.1:
            tempo_mode = "entries"
        else:
            tempo_mode = "grid"
            if n_changes:
                err = max(abs(grid_tick(n.start) * 60 / (avg * ppq) - sec(n.start))
                          for n in mf.notes)
                tempo_mode = "grid" if err <= TIME_MODE_ERROR else "time"
        if n_changes:
            report.append(f"tempo mode (automatic): {tempo_mode}")
    if tempo_mode not in ("entries", "grid", "time"):
        raise MidiImportError("--tempo-mode must be auto, entries, grid or time")
    if tempo_mode == "entries" and version != 1.1:
        raise MidiImportError("tempo mode entries needs .lsong 1.1")
    if tempo_mode != "entries":
        changes = [(0, avg)]
        if n_changes:
            report.append(f"warning: .lsong {version} with tempo mode {tempo_mode} has one "
                          f"tempo ({avg:.2f} BPM): "
                          + ("bars are kept, the timing is not" if tempo_mode == "grid"
                             else "the timing is kept, bars and repeated patterns follow "
                                  "the average tempo, not the music"))

    def time_tick(tick):
        return round(sec(tick) * avg / 60 * ppq)

    to_tick = time_tick if tempo_mode == "time" else grid_tick

    # Seconds of a .lsong tick with the tempo of the song (one or per entry)
    ch_ticks = [t for t, _ in changes]
    ch_secs, acc = [], 0.0
    for k, (t, b) in enumerate(changes):
        if k:
            acc += (t - changes[k - 1][0]) * 60 / (changes[k - 1][1] * ppq)
        ch_secs.append(acc)

    def song_seconds(t):
        k = max(0, bisect.bisect_right(ch_ticks, t) - 1)
        return ch_secs[k] + (t - ch_ticks[k]) * 60 / (changes[k][1] * ppq)

    # Meter: bar lines follow the time signatures of the file (patterns are
    # cut at bar lines, so repeated bars are found even when the meter changes)
    sigs = sorted(mf.time_sigs)
    num, den = (sigs[0][1], sigs[0][2]) if sigs and sigs[0][0] == 0 else (4, 4)
    if den not in (1, 2, 4, 8, 16):
        num, den = 4, 4
    meters = len({(n_, d_) for _, n_, d_ in sigs})
    if meters > 1:
        report.append(f"meter: {meters} different time signatures; bar lines follow them "
                      f"(.lsong keeps only the first, {num}/{den}, for editors)")
    bar_lines = _bar_lines(mf, sigs, end_tick, to_tick)

    # Roles -> monophonic notes in .lsong ticks
    drum_notes = {r: [n for i in roles.get(r, []) for n in by_index[i].notes]
                  for r in DRUM_ROLES}
    if split_drums:
        metal = [n for n in drum_notes["drums"] if DRUM_CLASS.get(n.pitch, "hat") in METAL]
        ids = {id(n) for n in metal}
        drum_notes["drums"] = [n for n in drum_notes["drums"] if id(n) not in ids]
        drum_notes["cymbals"] += metal
    parts, errors_s = {}, []
    for r in ROLES:
        if r in DRUM_ROLES:
            notes = drum_notes[r]
            if not notes:
                continue
            q, dropped, unmapped = _drums(notes, to_tick, ppq)
            if unmapped:
                report.append(f"{r}: {unmapped} notes are not GM kit drums (played as hat)")
        else:
            if r not in roles:
                continue
            notes = [n for i in roles[r] for n in by_index[i].notes]
            mono, unheard = reduce(notes, modes[r])
            q, dropped = _quantize_mono(mono, to_tick)
            if unheard and modes[r] != "second":
                report.append(f"{r}: {unheard} of {len(notes)} notes not heard "
                              f"(one note at a time, mode {modes[r]})")
            if modes[r] == "second":
                report.append(f"{r}: {len(q)} notes of a second voice (mode second)")
        if dropped:
            report.append(f"{r}: {dropped} notes dropped (same tick after reduction"
                          f"{' / one drum at a time' if r in DRUM_ROLES else ''})")
        if q:
            parts[r] = q
            errors_s += [abs(song_seconds(n[0]) - sec(n[5])) for n in q]
    if not parts:
        raise MidiImportError("no notes left in the chosen roles")
    report.append(f"timing ({tempo_mode} mode, {ppq} ticks per quarter): note starts "
                  f"off by max {max(errors_s) * 1000:.1f} ms, mean "
                  f"{sum(errors_s) / len(errors_s) * 1000:.1f} ms")

    # Arpeggio shapes -> instruments (at most 32 instruments in all)
    shapes = collections.Counter(n[4] for r in ("chords", "chords2")
                                 for n in parts.get(r, []) if n[4])
    drum_classes = sorted({DRUM_CLASS.get(n[2], "hat") for r in DRUM_ROLES
                           for n in parts.get(r, [])}, key=DRUM_PRIORITY.index)
    kits = [r for r in DRUM_ROLES if r in parts]
    room = 32 - len([r for r in parts if r in MELODIC]) - len(drum_classes) - len(kits)
    arp_name = {s: f"arp{k + 1}" for k, (s, _) in enumerate(shapes.most_common(max(0, room)))}
    lost = sum(c for s, c in shapes.items() if s not in arp_name)
    if lost:
        report.append(f"chords: {lost} chords of rare shapes played as single notes")

    instruments = {r: dict(MELODIC_INSTR[r]) for r in parts if r in MELODIC}
    for s, name in arp_name.items():
        instruments[name] = {**MELODIC_INSTR["chords"], "arp": list(s)}
    for c in drum_classes:
        instruments[c] = dict(DRUM_INSTR[c])
    for r in kits:
        used_p = sorted({n[2] for n in parts[r]})
        instruments[KIT_NAME[r]] = {"type": "kit", "drums": [
            {"p": p, "i": DRUM_CLASS.get(p, "hat"),
             "to": TOM_TO.get(p, DRUM_TO.get(DRUM_CLASS.get(p, "hat"), 64))} for p in used_p]}

    loudest = {r: max(n[3] for n in q) or 127 for r, q in parts.items()}

    def note_dict(r, t, d, n, tie):
        nd = {"t": t, "d": d, "p": n[2]}
        v = _vel(n[3], loudest[r])
        if v is not None:
            nd["v"] = v
        if r in ("chords", "chords2") and n[4] in arp_name:
            nd["i"] = arp_name[n[4]]
        if tie:
            nd["tie"] = True
        return nd

    total = max(n[1] for q in parts.values() for n in q)
    cuts = [t for t, _ in changes[1:] if 0 < t < total]
    lines = [t for t in bar_lines if t < total]
    options = [bars] if bars else [1, 2, 4, 8, 16]
    best = None
    for b in options:
        if b < 1:
            raise MidiImportError("--bars must be at least 1")
        borders = sorted(set(lines[::b]) | set(cuts) | {0}) + [total]
        if any(y - x > ppq * 64 for x, y in zip(borders, borders[1:])):
            continue  # A pattern would be longer than 64 quarter notes
        cand = _chunk(parts, borders, note_dict, version == 1.1, changes)
        cand["bars"] = b
        if cand["ok"] and (best is None or (cand["stored"], len(cand["playlist"]))
                           < (best["stored"], len(best["playlist"]))):
            best = cand
    if best is None:
        raise MidiImportError("the song does not fit .lsong limits (256 patterns, 256 "
                              "playlist entries, 16384 notes); try fewer roles or --ppq 12")
    if best["split"]:
        report.append(f"{best['split']} notes cross pattern borders: " + (
            "tied (no new attack)" if version == 1.1
            else "warning: played again there (.lsong 1 has no tied notes)"))
    if tempo_mode == "entries" and n_changes:
        mid = sum(1 for t in cuts if t not in set(bar_lines))
        report.append(f"tempo changes kept in the playlist: {len(cuts)}"
                      + (f", {mid} inside a bar (patterns cut there)" if mid else ""))
    report.append(f"patterns: {best['bars']} bars each, {len(best['patterns'])} different "
                  f"of {best['chunks']}, playlist {len(best['playlist'])} entries, "
                  f"{best['stored']} notes stored")

    uses_11 = best["tied"] or any("tempo" in e for e in best["playlist"])
    name = pathlib.Path(path).stem
    title = (mf.track_names.get(0) or name)[:64]
    first = changes[0][1]
    song = {
        "lsong": 1.1 if uses_11 else 1,
        "title": title,
        "comment": f"Imported from {pathlib.Path(path).name} by litelua song import.",
        "tempo": round(min(400, max(20, first)), 3),
        "ppq": ppq,
        "meter": [num, den],
        "profile": profile,
        "instruments": instruments,
        "tracks": [{"name": r, "instrument": KIT_NAME.get(r, r)}
                   for r in ROLES if r in parts],
        "patterns": best["patterns"],
        "playlist": best["playlist"],
        "x_import": {
            "source": pathlib.Path(path).name,
            "roles": {r: v for r, v in roles.items()},
            "modes": {r: modes[r] for r in parts if r in MELODIC},
            "split_drums": split_drums,
            "tempo_mode": tempo_mode, "ppq": ppq, "bars": best["bars"],
            "lsong": version,
        },
    }
    if any(not 20 <= b <= 400 for _, b in changes):
        report.append("warning: a tempo is outside 20 .. 400 BPM")
    return song, report


def _bar_lines(mf, sigs, end_tick, to_tick):
    """Ticks (.lsong) where bars start, following the time signatures."""
    out, tick, k = [], 0, 0
    num, den = 4, 4
    while tick < end_tick:
        while k < len(sigs) and sigs[k][0] <= tick:
            num, den = sigs[k][1], sigs[k][2]
            k += 1
        out.append(to_tick(tick))
        length = mf.division * 4 * num // den
        nxt = tick + max(1, length)
        if k < len(sigs) and tick < sigs[k][0] < nxt:
            nxt = sigs[k][0]  # A new meter starts inside this bar
        tick = nxt
    return sorted(set(out))


def _chunk(parts, borders, note_dict, tie_ok, changes):
    """Cuts the notes into patterns between the borders (bars, and tempo
    changes); equal patterns are stored once, repeats become 'times'. Notes
    crossing a border continue as tied notes (v1.1) or are played again."""
    count = len(borders) - 1
    chunks = [{r: [] for r in parts} for _ in range(count)]
    split = tied = 0
    for r, q in parts.items():
        for n in q:
            t, e = n[0], n[1]
            first = True
            while t < e:
                c = bisect.bisect_right(borders, t) - 1
                ce = min(e, borders[c + 1])
                tie = not first and tie_ok
                chunks[c][r].append(note_dict(r, t - borders[c], ce - t, n, tie))
                if not first:
                    split += 1
                    tied += tie
                first = False
                t = ce
    ch_ticks = [t for t, _ in changes]
    patterns, sig_name, playlist = {}, {}, []
    ok, prev_bpm = True, changes[0][1]
    for k, ch in enumerate(chunks):
        a, b = borders[k], borders[k + 1]
        if any(len(v) > 1024 for v in ch.values()):
            ok = False
        sig = (b - a,) + tuple((r, tuple(tuple(sorted(n.items())) for n in ch[r]))
                               for r in parts)
        if sig not in sig_name:
            sig_name[sig] = f"p{len(sig_name) + 1}"
            patterns[sig_name[sig]] = {"length": b - a,
                                       "notes": {r: v for r, v in ch.items() if v}}
        nm = sig_name[sig]
        bpm = changes[bisect.bisect_right(ch_ticks, a) - 1][1]
        new_tempo = abs(bpm - prev_bpm) > 1e-9
        prev_bpm = bpm
        if (playlist and not new_tempo and playlist[-1]["pattern"] == nm
                and playlist[-1].get("times", 1) < 64):
            playlist[-1]["times"] = playlist[-1].get("times", 1) + 1
        else:
            entry = {"pattern": nm}
            if new_tempo:
                entry["tempo"] = round(bpm, 3)
            playlist.append(entry)
    stored = sum(len(v) for p in patterns.values() for v in p["notes"].values())
    ok = ok and len(patterns) <= 256 and len(playlist) <= 256 and stored <= 16384
    return {"ok": ok, "patterns": patterns, "playlist": playlist, "stored": stored,
            "split": split, "tied": tied, "chunks": count}
