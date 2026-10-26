"""Spell effects and sounds of Heroes IV for LiteLua (C4).

convert_effect(lib, name, scale, style) turns animation.spell.<name> into an atlas and a
meta like h4atlas.convert (no shadow). The file's trailer (homm4-mac CombatScreen.swift,
spell_visuals_spec 2.1): u16 version, u16 frame time (ms), i32 n, n x i32 image order
(empty: every image in turn), u8 use anchor x, u8 use anchor y, i32 anchor x, i32 anchor y
(canvas coordinates). The effect hangs on the stack's footprint centre raised by the
actor's height; its anchor is the file's where flagged, else the middle of the width and
the bottom of all its images (CombatEffectsRender.swift effectQuad).

wav(data) turns a sound.<name> entry into a WAV file: the entry is a 15-byte header
(u32 bits big-endian, u8 channels, u32 rate, u32 data length, u16 ?) and raw PCM (16-bit
signed little-endian or 8-bit unsigned). The WAV is 8-bit mono at half the rate (11025 Hz):
a quarter of the memory, which counts in the cart's Lua limit on the DS.

MISSILES: what each shooter shoots (homm4-mac CombatPlayback.swift creatureMissiles, the
exe's table 0xa73cb8); heroes of a magic class shoot "magic", others "arrow".
"""
import io
import struct
import wave

import h4atlas
import h4d

MISSILES = {"ballista": "heavy_bolt", "beholder": "beam", "centaur": "spear", "crossbowman": "arrow",
            "elf": "arrow", "cyclops": "boulder", "gargantuan": "boulder", "venom spawn": "spittle",
            "fire elemental": "fire_bolt", "halfling": "pebble", "mage": "magic", "monk": "magic",
            "evil sorceress": "magic", "orc": "axe", "titan": "lightning", "waspwort": "thorn"}


def trailer(seq):
    """(frame ms, order, use x, use y, anchor x, anchor y) of an animation.spell file"""
    b = seq.trailer
    p = 0

    def take(fmt):
        nonlocal p
        if p + struct.calcsize(fmt) > len(b):
            return 0
        v, = struct.unpack_from(fmt, b, p)
        p += struct.calcsize(fmt)
        return v
    version = take("<H")
    ms, order, fx, fy, ax, ay = 100, [], False, False, 0, 0
    if version <= 10:
        ms = take("<H") or 100
        n = take("<i")
        if 0 < n < 4096:
            order = [take("<i") for _ in range(n)]
        if version >= 2:
            fx, fy, ax, ay = bool(take("<B")), bool(take("<B")), take("<i"), take("<i")
    return ms, order, fx, fy, ax, ay


def convert_effect(lib, name, scale, style, colors=15):
    """(atlas, meta) of animation.spell.<name>, or None when there is none"""
    res = f"animation.spell.{name}.h4d"
    if res not in lib:
        return None
    seq = h4d.parse(lib.read(res))
    images = [i for i in seq.images if i.kind]
    if not images:
        return None
    style = h4atlas.STYLES[style] if isinstance(style, str) else style
    ms, order, fx, fy, ax, ay = trailer(seq)
    order = [i for i in order if 0 <= i < len(images)] or list(range(len(images)))
    canvas = h4atlas.union([i.box for i in images])
    pivot = (canvas[0] + ax if fx else (canvas[0] + canvas[2]) // 2, canvas[1] + ay if fy else canvas[3])
    pieces, rects, index = [], [], {}
    for n, img in enumerate(images):
        piece, ox, oy = h4atlas.scaled(img.rgba(), img.box, canvas, pivot, scale,
                                       lambda i: h4atlas.finish_frame(i, style))
        if piece:
            index[n] = len(pieces) + 1
            pieces.append(piece)
            rects.append((ox, oy))
    if not pieces:
        return None
    atlas, pos = h4atlas.build_atlas(pieces, colors, style.vivid)
    meta = dict(sequence=res, fps=max(1, round(1000 / ms)), hit=0, scale=scale, szoom=1, salpha=0,
                rects=[[x, y, p.width, p.height, ox, oy] for (x, y), p, (ox, oy) in zip(pos, pieces, rects)],
                frames=[index.get(i, 0) for i in order], srects=[], sframes=[])
    return atlas, meta


def wav(data):
    """WAV bytes (8-bit mono 11025 Hz) of a sound entry"""
    bits, = struct.unpack_from(">I", data, 0)
    channels = data[4]
    rate, length = struct.unpack_from("<II", data, 5)
    pcm = data[15:15 + length]
    if bits == 16:
        n = len(pcm) // 2
        samples = struct.unpack(f"<{n}h", pcm[:n * 2])
    else:
        samples = [v - 128 << 8 for v in pcm]
    if channels == 2:
        samples = [(samples[i] + samples[i + 1]) // 2 for i in range(0, len(samples) - 1, 2)]
    half = [(samples[i] + samples[i + 1]) // 2 for i in range(0, len(samples) - 1, 2)]
    out = bytes(max(0, min(255, (s >> 8) + 128)) for s in half)
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(rate // 2)
        w.writeframes(out)
    return buf.getvalue()
