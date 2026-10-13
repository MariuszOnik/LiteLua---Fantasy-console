// SPDX-License-Identifier: Zlib
//
// LiteLua - the chiptune sequencer (P18 S1, D41).
//
// A timer interrupt (timer 3; 0+1 are micros(), 2 the music stream) runs at
// the tick rate of the song (tempo * ppq / 60 Hz; the divider is chosen per
// tempo, so the rate is exact to < 0.01%). Each tick ends and starts notes;
// every 1/60 s of real time the voices are updated: volume envelope,
// release, arpeggio, vibrato and slide (the .lsong frames).
//
// Lessons of S0 (D40): the libnds "play" functions wait for the ARM7 and may
// not run in an interrupt, so the channels are set up when the song starts
// (silent) and the interrupt only sends "set" commands (frequency, volume,
// duty), which change the channel in place.
//
// Channels: pulse tracks 8..13 (PSG), noise 14..15 (PSG noise), triangle 6..7
// (a 32-step wave sample, looped). They are locked in Maxmod while a song
// plays, so sound effects and other music use the rest.

#include <string.h>

#include <maxmod9.h>
#include <nds.h>

#include "ll_seq.h"

#define FRAME_BUS (BUS_CLOCK / 60) // Bus cycles per envelope frame

// NES-like stepped triangle, signed 8-bit
static const s8 triangle[32] __attribute__((aligned(4))) = {
    120, 104, 88, 72, 56, 40, 24, 8, -8, -24, -40, -56, -72, -88, -104, -120,
    -120, -104, -88, -72, -56, -40, -24, -8, 8, 24, 40, 56, 72, 88, 104, 120,
};

// Hz * 16 of A4 .. G#5, and 2^(c/1200) for 0..99 cents in 1.15 fixed point
static const u16 octave_hz16[12] = {
    7040, 7459, 7902, 8372, 8870, 9397, 9956, 10548, 11175, 11840, 12544, 13290,
};
static u16 cent_mul[100];

// Sine for vibrato, 64 steps, -127..127
static s8 sine64[64];

typedef struct {
    int channel;        // -1: no channel
    u8 kind;
    // Clip of the current segment
    const LLNote *notes;
    int count, next;
    s8 clip_transpose;
    // Sounding note
    bool active, releasing, ended_now;
    const LLInstr *in;
    int pitch;          // MIDI, with transposition
    u8 vel;
    s8 slide;
    int remaining;      // Ticks until the note ends
    int length, elapsed; // Ticks, for the slide
    int age, rel_age;   // Frames
    // Last values sent
    u32 rate;
    u8 vol, duty;
} Voice;

static struct {
    const LLSong *song;
    bool on, loop, finished;
    int volume;         // 0..1024
    int segment, rep;
    u32 tick;           // In the segment
    u32 tick_bus;       // Bus cycles per tick at the current tempo
    u32 frame_acc;
    u32 tempo_milli;
    Voice v[LL_SONG_TRACKS];
} sq;

static void init_tables(void)
{
    static bool done;
    if (done)
        return;
    // 2^(c/1200) = e^(c * ln2 / 1200), by a short series (no FPU needed often)
    for (int c = 0; c < 100; c++)
    {
        float x = c * 0.000577622650f, term = 1, sum = 1; // ln 2 / 1200
        for (int k = 1; k < 6; k++)
        {
            term *= x / k;
            sum += term;
        }
        cent_mul[c] = (u16)(sum * 32768 + 0.5f);
    }
    for (int i = 0; i < 64; i++)
    {
        // sin by the same kind of series on -pi..pi
        float a = (i < 32 ? i : i - 64) * 0.0981747704f; // 2 pi / 64
        float a2 = a * a;
        float s = a * (1 - a2 / 6 * (1 - a2 / 20 * (1 - a2 / 42 * (1 - a2 / 72))));
        sine64[i] = (s8)(s * 127);
    }
    done = true;
}

// Frequency in Hz * 16 of a pitch in cents (MIDI note * 100)
static u32 hz16(int cents)
{
    int n = cents / 100 - 69, c = cents % 100;
    if (c < 0)
        c += 100, n--;
    int oct = n >= 0 ? n / 12 : (n - 11) / 12, k = n - oct * 12;
    u32 v = (u32)octave_hz16[k] * cent_mul[c] >> 15;
    if (oct >= 0)
        return oct > 8 ? 0xFFFFFFFF : v << oct;
    return oct < -16 ? 0 : v >> -oct;
}

// Channel rate for a pitch: PSG 8 steps per period, triangle 32, noise: the
// LFSR clock 440 * 2^((pitch - 21) / 12)
static u32 rate_of(u8 kind, int cents)
{
    u64 r;
    if (kind == LL_KIND_NOISE)
        r = hz16(cents + 4800) / 16;
    else
        r = (u64)hz16(cents) * (kind == LL_KIND_TRIANGLE ? 32 : 8) / 16;
    return r < 1 ? 1 : r > 65535 ? 65535 : (u32)r;
}

// --- Voices -----------------------------------------------------------------

// Frequency first: a new note never sounds for a moment at the old pitch
static void send(Voice *v, u32 rate, int vol)
{
    if (vol && rate != v->rate)
    {
        soundSetFreq(v->channel, (u16)rate);
        v->rate = rate;
    }
    if (vol != v->vol)
    {
        soundSetVolume(v->channel, (u8)vol);
        v->vol = (u8)vol;
    }
}

// One frame of a voice (also at its note start)
static void update(Voice *v)
{
    if (!v->active)
        return;
    const LLInstr *in = v->in;
    int level;
    if (!v->releasing)
        level = in->env[v->age < in->env_n ? v->age : in->env_n - 1];
    else if (v->rel_age < in->rel_n)
        level = in->rel[v->rel_age];
    else
    {
        v->active = false;
        send(v, v->rate, 0);
        return;
    }
    int frame = v->releasing ? v->age + v->rel_age : v->age;
    int cents = (v->pitch + in->arp[frame % in->arp_n]) * 100;
    if (v->slide && v->length)
        cents += v->slide * 100 * (v->elapsed < v->length ? v->elapsed : v->length) / v->length;
    if (in->vib_depth && frame >= in->vib_delay)
    {
        // Phase in 1/64 turns: rate (Hz*100) * frames / 60 / 100 * 64
        u32 phase = (u32)in->vib_rate * (u32)(frame - in->vib_delay) * 64 / 6000;
        cents += in->vib_depth * sine64[phase & 63] / 127;
    }
    // 5/8: four loud voices plus sound effects must not clip the mixer
    int vol = in->volume * v->vel / 255 * level / 127 * sq.volume / 1024 * 5 / 8;
    send(v, rate_of(v->kind, cents), vol);
    if (v->releasing)
        v->rel_age++;
    else
        v->age++;
}

static void note_on(Voice *v, int track, const LLNote *n, int transpose)
{
    const LLSong *s = sq.song;
    const LLInstr *in = &s->instr[n->instr != LL_SONG_NONE ? n->instr : s->track_instr[track]];
    int pitch = n->p;
    if (in->type == LL_KIND_KIT)
    {
        const LLKitDrum *k = NULL;
        for (int i = 0; i < in->kit_n; i++)
            if (s->kit[in->kit_first + i].p == n->p)
                k = &s->kit[in->kit_first + i];
        if (k == NULL)
            return;
        in = &s->instr[k->instr];
        pitch = k->to;
    }
    else
        pitch += transpose;
    if (pitch < 0 || pitch > 127 || in->type != v->kind)
        return;

    // A tied note continues the note that has just reached its end
    if (n->tie && v->active && v->ended_now && v->pitch == pitch && v->in == in)
    {
        v->remaining = n->d;
        v->length += n->d;
        v->ended_now = false;
        return;
    }
    v->active = true;
    v->releasing = v->ended_now = false;
    v->in = in;
    v->pitch = pitch;
    v->vel = n->v;
    v->slide = n->slide;
    v->remaining = v->length = n->d;
    v->elapsed = 0;
    v->age = v->rel_age = 0;
    if (v->kind == LL_KIND_PULSE && in->duty != v->duty)
    {
        soundSetWaveDuty(v->channel, (DutyCycle)in->duty);
        v->duty = in->duty;
    }
    update(v);
}

// --- Timing -------------------------------------------------------------------

// Timer 3 at 'tempo_milli' * ppq / 60 Hz: the smallest divider that fits
static void set_tempo(u32 tempo_milli)
{
    static const u32 divs[4] = { 1, 64, 256, 1024 };
    static const u32 bits[4] = { TIMER_DIV_1, TIMER_DIV_64, TIMER_DIV_256, TIMER_DIV_1024 };
    u64 period = (u64)BUS_CLOCK * 60000 / ((u64)tempo_milli * (u32)sq.song->ppq);
    int k = 0;
    while (k < 3 && (period + divs[k] / 2) / divs[k] > 65535)
        k++;
    u32 count = (u32)((period + divs[k] / 2) / divs[k]);
    if (count > 65535)
        count = 65535;
    if (count < 1)
        count = 1;
    sq.tick_bus = count * divs[k];
    sq.tempo_milli = tempo_milli;
    TIMER_CR(3) = 0;
    TIMER_DATA(3) = (u16)(65536 - count);
    TIMER_CR(3) = TIMER_ENABLE | TIMER_IRQ_REQ | bits[k];
}

static void start_segment(int index)
{
    const LLSong *s = sq.song;
    const LLSegment *sg = &s->segments[index];
    sq.segment = index;
    sq.tick = 0;
    for (int t = 0; t < s->tracks; t++)
    {
        const LLClip *c = &s->pattern_clips[sg->pattern * LL_SONG_TRACKS + t];
        sq.v[t].notes = &s->notes[c->first];
        sq.v[t].count = c->count;
        sq.v[t].next = 0;
        sq.v[t].clip_transpose = c->transpose;
    }
    if (sg->tempo_milli != sq.tempo_milli)
        set_tempo(sg->tempo_milli);
}

static void seq_tick(void)
{
    if (!sq.on || sq.finished)
        return;
    const LLSong *s = sq.song;
    const LLSegment *sg = &s->segments[sq.segment];

    // Notes that end now (a tied note may continue them below)
    for (int t = 0; t < s->tracks; t++)
    {
        Voice *v = &sq.v[t];
        if (v->active && !v->releasing)
        {
            v->elapsed++;
            if (--v->remaining <= 0)
                v->ended_now = true;
        }
    }
    // Notes that start now
    for (int t = 0; t < s->tracks; t++)
    {
        Voice *v = &sq.v[t];
        while (v->next < v->count && v->notes[v->next].t == sq.tick)
            note_on(v, t, &v->notes[v->next++], sg->transpose + v->clip_transpose);
        if (v->ended_now)
        {
            v->ended_now = false;
            v->releasing = true; // Release envelope, or silence at once
            update(v);
        }
    }
    // Envelope frames: 60 per second of real time
    sq.frame_acc += sq.tick_bus;
    while (sq.frame_acc >= FRAME_BUS)
    {
        sq.frame_acc -= FRAME_BUS;
        for (int t = 0; t < s->tracks; t++)
            update(&sq.v[t]);
    }

    if (++sq.tick < sg->length)
        return;
    if (++sq.rep < sg->times)
    {
        start_segment(sq.segment); // The same pattern again
        return;
    }
    sq.rep = 0;
    int next = sq.segment + 1;
    if (next >= s->segment_count)
    {
        if (!sq.loop || s->loop < 0)
        {
            sq.finished = true;
            for (int t = 0; t < s->tracks; t++)
                send(&sq.v[t], sq.v[t].rate, 0);
            return;
        }
        next = s->loop;
    }
    start_segment(next);
}

// --- Control ------------------------------------------------------------------

static u32 channel_mask(const LLSong *s, int *channels)
{
    int pulse = 8, noise = 14, tri = 6;
    u32 mask = 0;
    for (int t = 0; t < s->tracks; t++)
    {
        int ch = -1;
        if (s->track_kind[t] == LL_KIND_PULSE && pulse <= 13)
            ch = pulse++;
        else if (s->track_kind[t] == LL_KIND_NOISE && noise <= 15)
            ch = noise++;
        else if (s->track_kind[t] == LL_KIND_TRIANGLE && tri <= 7)
            ch = tri++;
        channels[t] = ch;
        if (ch >= 0)
            mask |= BIT(ch);
    }
    return mask;
}

static u32 locked;

void ll_seq_play(const LLSong *song, bool loop, int volume)
{
    ll_seq_stop();
    init_tables();
    memset(&sq, 0, sizeof(sq));
    sq.song = song;
    sq.loop = loop;
    sq.volume = volume;

    int channels[LL_SONG_TRACKS];
    locked = channel_mask(song, channels);
    mmLockChannels(locked);
    // Maxmod handles its commands in its own frame on the ARM7, later than
    // libnds handles sound commands, and locking a channel switches it off
    // (REG_SOUNDXCNT = 0). Set the channels up only after the lock is done,
    // or the lock silences them again.
    for (int i = 0; i < 3; i++)
        swiWaitForVBlank();
    soundEnable();
    DC_FlushRange(triangle, sizeof(triangle));
    for (int t = 0; t < song->tracks; t++)
    {
        Voice *v = &sq.v[t];
        v->channel = channels[t];
        v->kind = song->track_kind[t];
        v->duty = 3; // 50 %
        if (v->channel < 0)
        {
            v->kind = 0xFF; // No channel left: the track is silent
            continue;
        }
        // Set up now (these wait for the ARM7), silent
        if (v->kind == LL_KIND_PULSE)
            soundPlayPSGChannel(v->channel, DutyCycle_50, 3520, 0, 64);
        else if (v->kind == LL_KIND_NOISE)
            soundPlayNoiseChannel(v->channel, 8000, 0, 64);
        else
            soundPlaySampleChannel(v->channel, triangle, SoundFormat_8Bit,
                                   sizeof(triangle), 14080, 0, 64, true, 0);
    }

    sq.on = true;
    irqSet(IRQ_TIMER3, seq_tick);
    irqEnable(IRQ_TIMER3);
    sq.tempo_milli = 0;
    start_segment(0); // Sets the timer
}

void ll_seq_stop(void)
{
    if (!sq.on)
        return;
    TIMER_CR(3) = 0;
    irqDisable(IRQ_TIMER3);
    sq.on = false;
    for (int t = 0; t < LL_SONG_TRACKS; t++)
        if (sq.v[t].channel >= 0 && sq.v[t].kind != 0xFF && t < sq.song->tracks)
            soundKill(sq.v[t].channel);
    mmUnlockChannels(locked);
    locked = 0;
}

void ll_seq_volume(int volume)
{
    sq.volume = volume < 0 ? 0 : volume > 1024 ? 1024 : volume;
}

bool ll_seq_finished(void)
{
    return sq.on && sq.finished;
}
