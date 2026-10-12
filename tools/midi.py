# SPDX-License-Identifier: Zlib
#
# LiteLua - Standard MIDI Files (SMF) for the song tools (D37): a reader for
# format 0 and 1 (running status, tempo map, time signatures, overlapping
# notes) and a small writer (tests, demo files, later .lsong -> MIDI export).
# Standard library only.

import struct


class MidiError(Exception):
    pass


class Note:
    __slots__ = ("track", "channel", "start", "end", "pitch", "vel", "program")

    def __init__(self, track, channel, start, end, pitch, vel, program):
        self.track, self.channel = track, channel
        self.start, self.end = start, end
        self.pitch, self.vel, self.program = pitch, vel, program

    def __repr__(self):
        return (f"Note(tr{self.track} ch{self.channel + 1} {self.start}-{self.end} "
                f"p{self.pitch} v{self.vel})")


class MidiFile:
    def __init__(self):
        self.format = 1
        self.division = 480        # Ticks per quarter note
        self.notes = []            # All notes, Note objects
        self.tempos = []           # [(tick, microseconds per quarter)], sorted
        self.time_sigs = []        # [(tick, numerator, denominator)]
        self.track_names = {}      # track index -> name
        self.length = 0            # Last tick of any track
        self.warnings = []

    def tempo_map(self):
        """[(tick, us per quarter)] starting at tick 0 (default 120 BPM)."""
        tm = sorted(self.tempos)
        if not tm or tm[0][0] > 0:
            tm.insert(0, (0, 500000))
        out = []
        for t, us in tm:  # Later events at the same tick win
            if out and out[-1][0] == t:
                out[-1] = (t, us)
            else:
                out.append((t, us))
        return out

    def seconds_of(self):
        """Returns a function tick -> seconds through the tempo map."""
        import bisect
        tm = self.tempo_map()
        ticks, secs = [], []
        sec = 0.0
        for k, (t, us) in enumerate(tm):
            if k:
                sec += (t - tm[k - 1][0]) * tm[k - 1][1] / 1e6 / self.division
            ticks.append(t)
            secs.append(sec)

        def f(tick):
            k = bisect.bisect_right(ticks, tick) - 1
            return secs[k] + (tick - ticks[k]) * tm[k][1] / 1e6 / self.division
        return f


def _vlq(data, i):
    value = 0
    for _ in range(4):
        if i >= len(data):
            raise MidiError("file ends inside a variable-length number")
        b = data[i]
        i += 1
        value = (value << 7) | (b & 0x7F)
        if not b & 0x80:
            return value, i
    raise MidiError("variable-length number longer than 4 bytes")


def parse(data):
    """Parses SMF bytes into a MidiFile."""
    if data[:4] != b"MThd":
        raise MidiError("not a MIDI file (no MThd header)")
    hlen = struct.unpack(">I", data[4:8])[0]
    fmt, ntrks, division = struct.unpack(">HHH", data[8:14])
    if fmt not in (0, 1):
        raise MidiError(f"MIDI format {fmt} is not supported (only 0 and 1)")
    if division & 0x8000:
        raise MidiError("SMPTE time division is not supported")
    if division == 0:
        raise MidiError("time division is 0")
    mf = MidiFile()
    mf.format, mf.division = fmt, division
    pos = 8 + hlen
    track = 0
    while pos + 8 <= len(data) and track < ntrks:
        cid, clen = data[pos:pos + 4], struct.unpack(">I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + clen]
        pos += 8 + clen
        if cid != b"MTrk":
            continue  # Unknown chunks are skipped, as the standard says
        if len(body) < clen:
            mf.warnings.append(f"track {track + 1} is cut short")
        _parse_track(mf, track, body)
        track += 1
    if track < ntrks:
        mf.warnings.append(f"header says {ntrks} tracks, found {track}")
    mf.notes.sort(key=lambda n: (n.start, n.pitch))
    return mf


def _parse_track(mf, track, d):
    i, tick, running = 0, 0, None
    open_notes = {}          # (channel, pitch) -> [(start, vel, program)] oldest first
    programs = [0] * 16
    stray_off = 0
    while i < len(d):
        delta, i = _vlq(d, i)
        tick += delta
        if i >= len(d):
            break
        status = d[i]
        if status & 0x80:
            i += 1
            # Meta events and sysex cancel running status (SMF 1.0)
            running = status if status < 0xF0 else None
        elif running is None:
            raise MidiError(f"track {track + 1}: data byte without a status "
                            f"(bad running status) at tick {tick}")
        else:
            status = running
        if status == 0xFF:
            if i >= len(d):
                break
            mtype = d[i]
            length, i = _vlq(d, i + 1)
            payload = d[i:i + length]
            i += length
            if mtype == 0x2F:
                break
            if mtype == 0x51 and length == 3:
                mf.tempos.append((tick, int.from_bytes(payload, "big")))
            elif mtype == 0x58 and length >= 2:
                mf.time_sigs.append((tick, payload[0], 2 ** payload[1]))
            elif mtype == 0x03 and track not in mf.track_names:
                mf.track_names[track] = payload.decode("latin-1").strip()
            continue
        if status in (0xF0, 0xF7):
            length, i = _vlq(d, i)
            i += length
            continue
        hi, ch = status & 0xF0, status & 0x0F
        n = 1 if hi in (0xC0, 0xD0) else 2
        args = d[i:i + n]
        i += n
        if len(args) < n:
            break
        if hi == 0xC0:
            programs[ch] = args[0]
        elif hi == 0x90 and args[1] > 0:
            open_notes.setdefault((ch, args[0]), []).append((tick, args[1], programs[ch]))
        elif hi == 0x80 or hi == 0x90:
            stack = open_notes.get((ch, args[0]))
            if stack:
                start, vel, prog = stack.pop(0)  # Overlapping same notes: oldest first
                mf.notes.append(Note(track, ch, start, tick, args[0], vel, prog))
            else:
                stray_off += 1
    mf.length = max(mf.length, tick)
    hanging = 0
    for (ch, pitch), stack in open_notes.items():
        for start, vel, prog in stack:
            mf.notes.append(Note(track, ch, start, max(tick, start + 1), pitch, vel, prog))
            hanging += 1
    if hanging:
        mf.warnings.append(f"track {track + 1}: {hanging} notes never end "
                           f"(ended at the track end)")
    if stray_off:
        mf.warnings.append(f"track {track + 1}: {stray_off} note-offs without a note")


def read(path):
    with open(path, "rb") as f:
        return parse(f.read())


# --- Writer -------------------------------------------------------------------

def _vlq_bytes(v):
    out = [v & 0x7F]
    v >>= 7
    while v:
        out.append(0x80 | (v & 0x7F))
        v >>= 7
    return bytes(reversed(out))


def track_bytes(events, running_status=True):
    """events: [(tick, bytes)] with full status bytes; returns an MTrk chunk."""
    out = bytearray()
    last, running = 0, None
    for tick, msg in sorted(events, key=lambda e: e[0]):
        out += _vlq_bytes(tick - last)
        last = tick
        status = msg[0]
        if (running_status and status & 0xF0 == 0x80 and running is not None
                and running == 0x90 | (status & 0x0F)):
            msg = bytes([running, msg[1], 0])  # Note off as note on, velocity 0
            status = running
        if running_status and status < 0xF0 and status == running:
            out += msg[1:]
        else:
            out += msg
            running = status if status < 0xF0 else None
    out += _vlq_bytes(0) + b"\xFF\x2F\x00"
    return b"MTrk" + struct.pack(">I", len(out)) + bytes(out)


def file_bytes(tracks, fmt=1, division=480):
    """tracks: list of event lists, see track_bytes."""
    head = b"MThd" + struct.pack(">IHHH", 6, fmt, len(tracks), division)
    return head + b"".join(track_bytes(t) for t in tracks)


def note_events(channel, start, end, pitch, vel=100):
    return [(start, bytes([0x90 | channel, pitch, vel])),
            (end, bytes([0x80 | channel, pitch, 0]))]


def tempo_event(tick, bpm):
    us = round(60e6 / bpm)
    return (tick, b"\xFF\x51\x03" + us.to_bytes(3, "big"))


GM_FAMILIES = ["piano", "chromatic perc.", "organ", "guitar", "bass", "strings",
               "ensemble", "brass", "reed", "pipe", "synth lead", "synth pad",
               "synth fx", "ethnic", "percussive", "sound fx"]
