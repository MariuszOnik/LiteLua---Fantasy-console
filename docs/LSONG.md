# `.lsong` v1.1 — LiteLua song format

A `.lsong` file describes a piece of chiptune music: notes, instruments and the
order of patterns. It describes **music, not hardware**: no DS registers, no
sample rates, no channel numbers of a sound chip. The same file is meant to be
written by people, by tools (MIDI converters, generators) and by language
models, edited in the LiteLua Music Studio on the DS, rendered to WAV on a PC,
and played by the LiteLua sequencer (D35, D36).

The sound is **inspired by the NES** (pulse, triangle and noise channels). It is
not an emulation of the NES or of the DS sound hardware; a renderer only has to
sound close.

## 1. Two notations, one model

The same data can be written in two ways:

- **Lua data** (`.lsong`): a `return` followed by one table constructor. This
  is what LiteLua reads on the DS. It is *data only*: see section 8.
- **JSON** (`.lsong.json`): the same structure, for tools on a PC.

`tools/litelua.py song convert` turns one into the other without loss. Field
names, types and rules are identical; this document shows Lua.

```lua
return {
  lsong = 1,
  title = "Sky Hopper",
  tempo = 150,
  ppq = 24,
  instruments = {
    lead = { type = "pulse", duty = 0.25, volume = 0.7 },
    bass = { type = "triangle" },
  },
  tracks = {
    { name = "lead", instrument = "lead" },
    { name = "bass", instrument = "bass" },
  },
  patterns = {
    a = {
      length = 96,
      notes = {
        lead = { { t = 0, d = 24, p = 72 }, { t = 24, d = 24, p = 76 } },
        bass = { { t = 0, d = 48, p = 48 } },
      },
    },
  },
  playlist = { { pattern = "a", times = 4 } },
}
```

## 2. Time and pitch

- **Ticks.** All times are integers in ticks. `ppq` is the number of ticks per
  **quarter note** (as in MIDI), whatever the meter is. With `ppq = 24`: a
  quarter = 24, an eighth = 12, a sixteenth = 6, an eighth triplet = 8, a 4/4
  bar = 96, a 6/8 bar = 72.
- **Tempo** is in quarter notes per minute (BPM). Changing the tempo never
  changes the rhythm.
- **Pitch** is a MIDI note number: 60 = C4 (middle C), 69 = A4 = 440 Hz, one
  step = one semitone.

## 3. Top level

| field | type | required | rules |
|---|---|---|---|
| `lsong` | number | yes | format version: `1`, or `1.1` when the file uses `tempo` in the playlist or `tie` (a v1.1 reader reads both) |
| `title` | string | no | at most 64 characters |
| `author` | string | no | at most 64 characters |
| `comment` | string | no | at most 512 characters |
| `tempo` | number | yes | 20 .. 400 |
| `ppq` | integer | no | 1 .. 96, default 24 |
| `meter` | `{num, den}` | no | num 1 .. 32, den 1, 2, 4, 8 or 16; only for editors (bar lines) |
| `profile` | string | no | `"nes"` (default) or `"extended"`, see 5 |
| `instruments` | map name → instrument | yes | 1 .. 32 entries |
| `tracks` | list of tracks | yes | 1 .. 8 entries |
| `patterns` | map name → pattern | yes | 1 .. 256 entries |
| `playlist` | list of entries | yes | 1 .. 256 entries |
| `loop` | integer or `false` | no | playlist entry to jump to at the end; default 1; `false` = play once |

**Names** (instruments, tracks, patterns): 1 .. 16 characters `a-z`, `0-9`,
`_`, starting with a letter. Unknown fields are an error (typos must not be
silently ignored), except fields starting with `x_`, which are kept for tools
and ignored by players.

## 4. Instruments

Every instrument has a `type`:

| type | sound | fields |
|---|---|---|
| `"pulse"` | square wave with a duty cycle | `duty` |
| `"triangle"` | stepped triangle (NES-like bass) | — |
| `"noise"` | noise; the note pitch sets its brightness | `mode` |
| `"kit"` | drum kit: maps notes to other instruments | `drums` |

Fields of `pulse`, `triangle` and `noise`:

| field | type | default | rules |
|---|---|---|---|
| `volume` | number | 1 | 0 .. 1 |
| `duty` | number | 0.5 | pulse only: 0.125, 0.25, 0.375, 0.5, 0.625, 0.75 or 0.875 (profile `nes`: 0.125, 0.25, 0.5, 0.75) |
| `mode` | string | `"long"` | noise only: `"long"` (hiss) or `"short"` (metallic) |
| `env` | list of numbers | `{1}` | volume envelope: one value 0 .. 1 per **frame** (1/60 s) from the note start; the last value is held while the note sounds; at most 64 values |
| `release` | list of numbers | none | values per frame after the note ends (the note then rings out); none = the note stops at once; at most 64 values |
| `arp` | list of integers | none | semitone offsets, one per frame, repeating (e.g. `{0, 4, 7}` = major chord); -24 .. 24; at most 32 values |
| `vibrato` | `{depth=, rate=, delay=}` | none | depth 0 .. 2 semitones, rate 0 .. 20 Hz, delay 0 .. 255 frames |

The final volume of a note is `instrument.volume × note.v × env`.

A `kit` has only `drums`, a list of mappings:

```lua
drums = {
  { p = 36, i = "kick",  to = 40 },  -- note 36 plays instrument kick at pitch 40
  { p = 38, i = "snare", to = 64 },
  { p = 42, i = "hat",   to = 90 },
}
```

| field | rules |
|---|---|
| `p` | the note pitch that triggers this drum, 0 .. 127, unique in the kit |
| `i` | an instrument of type `noise`, `pulse` or `triangle` (not `kit`); all drums of a kit have the same type |
| `to` | the pitch played, 0 .. 127; default = `p` |

A note of a kit whose pitch is not in `drums` is an error. Drum notes are not
transposed (section 7).

## 5. Tracks

A track is one **monophonic** voice: one note at a time, like a channel of
the NES.

| field | type | rules |
|---|---|---|
| `name` | name | unique among tracks |
| `instrument` | instrument name | the default instrument of the track |

The **kind** of a track is the type of its default instrument: `pulse`,
`triangle` or `noise`. All drums of a kit must be of one type, and that is the
kind of the kit (usually `noise`). Every note on the track must use an
instrument of the track's kind.

Profiles limit the tracks: `nes` — at most 2 pulse, 1 triangle, 1 noise;
`extended` — at most 6 pulse, 2 triangle, 2 noise, 8 in total. A player may
reject a song its hardware cannot play.

## 6. Patterns and notes

| field | type | rules |
|---|---|---|
| `length` | integer | ticks, 1 .. `ppq` × 64 (64 quarter notes) |
| `notes` | map track name → list of notes | tracks not listed are silent; at most 1024 notes per track |

A note:

| field | type | required | rules |
|---|---|---|---|
| `t` | integer | yes | start tick from the pattern start, 0 .. `length` − 1 |
| `d` | integer | yes | duration in ticks, ≥ 1 |
| `p` | integer | yes | MIDI pitch 0 .. 127 |
| `v` | number | no | velocity (volume) 0 .. 1, default 1 |
| `i` | instrument name | no | instrument for this note instead of the track's |
| `s` | integer | no | slide: the pitch moves this many semitones (-24 .. 24) evenly over the note |
| `tie` | `true` | no | v1.1, only at `t = 0`: the note continues the note that sounds at the end of what plays before it on this track (same pitch after transposition, same instrument) without a new attack; if there is none, it is played as a new note (the validator warns) |

**Collision rule (monophony).** Notes of a track are sorted by `t`. A note
that starts while the previous one still sounds **cuts** the previous one at
its own start (the validator warns). Two notes with the same `t` on one track
are an **error**. A note that lasts past the pattern end is cut at the end
(warning). The notes do not have to be listed in order.

## 7. Playlist and loop

The playlist is the song: pattern entries played one after another.

| field | type | default | rules |
|---|---|---|---|
| `pattern` | pattern name | — | required |
| `times` | integer | 1 | 1 .. 64, the pattern is played this many times in a row |
| `transpose` | integer | 0 | -24 .. 24 semitones, for all notes except drum notes |
| `tempo` | number | — | v1.1: 20 .. 400 BPM from this entry on, until another entry sets it |

(`times`, not `repeat`: `repeat` is a reserved word in Lua.)

The tempo of an entry is its own `tempo`, or the tempo of the entry before it
(the first entry: the song `tempo`). A tempo change inside a bar is written by
ending a pattern at that tick and continuing the notes with `tie` in the next
one, so no note moves.

At the end of the playlist the song jumps to entry `loop` (with that entry's tempo) (default 1 — the
whole song repeats; e.g. `loop = 2` skips an intro); `loop = false` plays the
song once. A transposed note must stay in 0 .. 127 (error otherwise).

## 8. Reading a `.lsong` safely

A `.lsong` file is **not run as Lua code**. Readers (the DS, the PC tool) use a
parser for a small *data subset* of Lua that cannot express loops, functions or
calls, so a broken or malicious file can only fail to load:

- optional comments `--` and `--[[ ]]`, then `return` and one value;
- values: tables `{ }`, strings (`"…"`, `'…'`, `[[…]]` with the usual escapes),
  numbers (decimal, hexadecimal, an optional leading `-`), `true`, `false`;
- table fields: `name = value`, `["key"] = value`, or a plain value (list
  item); separators `,` or `;`; a trailing separator is allowed;
- nothing else: no `nil`, no variables, no operators (except a leading `-` on
  a number), no expressions, no `..`.

A table is either a **list** (only plain values) or a **map** (only keyed
fields with string keys); mixing them is an error, so every table maps to
JSON exactly. An empty `{}` is accepted as an empty list or map.

## 9. Limits

| what | limit |
|---|---|
| file size | 256 KB |
| nesting depth | 16 |
| string length | 512 characters |
| notes in the whole song | 16384 |
| notes per track in one pattern | 1024 |
| instruments / tracks / patterns / playlist entries | 32 / 8 / 256 / 256 |
| playing time of the playlist once through | 30 minutes |

The limits keep a song small enough for the DS (a song of the maximum size is
about 100 KB after compiling) and make reading time predictable.

## 10. Tools

```
python tools/litelua.py song check   song.lsong          # validate, list errors and warnings
python tools/litelua.py song convert song.lsong song.lsong.json   # Lua -> JSON (and back)
python tools/litelua.py song render  song.lsong song.wav [--rate 22050] [--bits 16] [--loops 1] [--stereo] [--pan lead=-0.5]
python tools/litelua.py song import  song.mid --list            # the parts of a MIDI file
python tools/litelua.py song import  song.mid song.lsong [--lead 2 --chords 1 --bass 3 --drums 4]
```

`import` arranges a MIDI file (format 0 or 1) for the monophonic tracks: each
role (`lead`, `lead2`, `chords`, `bass`, `drums`) takes one or more parts of
the file, chords are reduced to one note (`--lead-mode top|bottom|last|arp`
etc.; `arp` turns chords into arpeggio instruments), General MIDI drums become
a `kit`, and repeated bars are stored once. It reports what it had to change:
notes not heard, drums dropped, and the measured timing error. A MIDI file with
tempo changes cannot be followed exactly by one `tempo` (v1): `--tempo-mode time`
keeps the timing, `grid` keeps the bars (`auto` picks `time` when `grid` would
be more than 30 ms off). The settings are stored in the song (`x_import`); the
MIDI file stays the source. With v1.1 (the default; `--lsong 1` for v1) tempo
changes are kept in the playlist (`--tempo-mode entries`), patterns are cut
where the tempo changes inside a bar, and notes crossing pattern borders are
tied.

`render --stereo` places the tracks left and right (melody a bit left, chords a bit
right, bass and drums in the middle; `--pan` changes it) — a choice of the renderer, the
file itself has no panning in v1.1. `render` is an **approximate preview** (pulse, NES-like triangle and noise
synthesized in software, envelopes per frame). The WAV can be played in a game
today with `music("song.wav")` (streamed, P7). The native player (P18 S1) will
play `.lsong` files directly.
