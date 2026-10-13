// SPDX-License-Identifier: Zlib
//
// LiteLua - .lsong songs on the DS (P18 S1, D41).
//
// A loader turns a .lsong file (v1 / v1.1 now, v1.2 later) into a neutral
// model that the sequencer (ll_seq.c) plays: a list of segments, each "play
// for N ticks at this tempo; on track k play this clip of notes". A v1.1
// pattern and a v1.2 scene both become segments, so the sound side does not
// depend on how the file arranges its notes.

#ifndef LL_SONG_H__
#define LL_SONG_H__

#include <nds.h>

#define LL_SONG_TRACKS 8
#define LL_SONG_ENV 64
#define LL_SONG_ARP 32
#define LL_SONG_NONE 0xFF

enum { LL_KIND_PULSE, LL_KIND_TRIANGLE, LL_KIND_NOISE, LL_KIND_KIT };

typedef struct {
    u8 type;            // LL_KIND_*
    u8 volume;          // 0..127
    u8 duty;            // DS duty 0..6 (12.5% .. 87.5%)
    u8 env_n, rel_n, arp_n;
    u8 env[LL_SONG_ENV];      // Volume 0..127 per frame (1/60 s)
    u8 rel[LL_SONG_ENV];      // After the note ends; rel_n 0 = stop at once
    s8 arp[LL_SONG_ARP];      // Semitones per frame, repeating
    u16 vib_depth;            // Cents
    u16 vib_rate;             // Hz * 100
    u8 vib_delay;             // Frames
    u16 kit_first, kit_n;     // Kit: range in LLSong.kit
} LLInstr;

typedef struct {
    u8 p, instr, to;    // Note pitch, drum instrument, pitch played
} LLKitDrum;

typedef struct {
    u16 t, d;           // Start and length in ticks (cut: one note at a time)
    u8 p;               // MIDI pitch
    u8 v;               // Velocity 0..255
    u8 instr;           // Instrument, LL_SONG_NONE = the track's
    u8 tie : 1;         // Continues the note before it (v1.1)
    s8 slide;           // Semitones over the note
} LLNote;

typedef struct {
    u32 first;          // In LLSong.notes
    u16 count;
    s8 transpose;       // Clip transpose (v1.2), added to the segment's
} LLClip;

typedef struct {
    u32 length;         // Ticks
    u32 tempo_milli;    // BPM * 1000
    u8 times;
    s8 transpose;
    u16 pattern;        // Index in LLSong.pattern_clips (clips per track)
} LLSegment;

typedef struct {
    int tracks;
    u8 track_kind[LL_SONG_TRACKS];   // LL_KIND_PULSE / TRIANGLE / NOISE
    u8 track_instr[LL_SONG_TRACKS];
    int ppq;
    int loop;                        // Segment to jump to at the end, -1 = once
    int instr_count, kit_count, segment_count, pattern_count;
    u32 note_count;
    LLInstr *instr;
    LLKitDrum *kit;
    LLNote *notes;
    LLClip *pattern_clips;           // pattern_count * LL_SONG_TRACKS
    LLSegment *segments;
    size_t bytes;                    // Size of the whole block (one malloc)
} LLSong;

// Parses and compiles a .lsong text. The song is one malloc'ed block (free
// with free()); its size is in 'bytes'. On failure returns NULL with a
// message in 'err'.
LLSong *ll_song_load(const char *text, size_t len, const char *name, char *err,
                     size_t err_size);

#endif // LL_SONG_H__
