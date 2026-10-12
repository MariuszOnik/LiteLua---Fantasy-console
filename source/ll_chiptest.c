// SPDX-License-Identifier: Zlib
//
// LiteLua - S0 hardware test of live chiptune synthesis (D40, P18 S0).
//
// Pattern "a" of examples/songs/sky_hopper.lsong (ll_chiptest_song.inc) is
// played by a sequencer in the timer 3 interrupt at 60 Hz (timers 0+1 are
// micros(), timer 2 is the music stream of P7):
//   channel 8  pulse  melody (PSG, 25% duty, volume envelope per frame)
//   channel 9  pulse  chords as a 3-note arpeggio, one note per frame
//   channel 10 sample triangle bass (32-step NES-like wave, looped)
//   channel 14 noise  drums (kick with a falling pitch, snare, hi-hat)
// The channels are locked in Maxmod, so its effects and music use the others.
//
// The libnds "play" functions wait for an answer of the ARM7 (under a FIFO
// mutex), so they cannot be called from an interrupt. They only set the
// channels up when the test starts (volume 0); the interrupt then uses only
// the "set" commands, which send one FIFO word and return: a note on is
// frequency + volume, a note off is volume 0.
//
// Modes, to compare by ear: 0 = parameters change in place (the phase of the
// wave runs on); 1 = every note on and every arpeggio step restarts the
// channel (pause + resume), like retriggering a sample.

#include <string.h>

#include <maxmod9.h>
#include <nds.h>

#include "lauxlib.h"

#include "ll_chiptest.h"
#include "ll_log.h"

typedef struct {
    u16 t, d;
    u8 p, flag;
} ChipNote;

#include "ll_chiptest_song.inc"

#define CH_LEAD 8
#define CH_ARP 9
#define CH_TRI 10
#define CH_NOISE 14
#define CHANNELS (BIT(CH_LEAD) | BIT(CH_ARP) | BIT(CH_TRI) | BIT(CH_NOISE))
#define TICK_HZ 60
#define COUNT(a) (sizeof(a) / sizeof((a)[0]))

// NES-like stepped triangle, signed 8-bit
static const s8 triangle[32] __attribute__((aligned(4))) = {
    120, 104, 88, 72, 56, 40, 24, 8, -8, -24, -40, -56, -72, -88, -104, -120,
    -120, -104, -88, -72, -56, -40, -24, -8, 8, 24, 40, 56, 72, 88, 104, 120,
};

// Drums: noise clock (Hz), volume per frame; the kick falls in pitch
static const u8 env_kick[] = { 127, 100, 70, 40, 15 };
static const u8 env_snare[] = { 110, 95, 75, 55, 35, 20, 8 };
static const u8 env_hat[] = { 60, 25 };
static const u16 drum_clock[3] = { 3000, 14000, 52000 };

typedef struct {
    int next;      // Index of the next note in its table
    int age, len;  // Frames since the note started, its length; len 0 = off
    u8 pitch, flag;
    u8 vol;        // Last volume sent
} Voice;

static struct {
    bool on;
    int mode;
    u32 frame;
    Voice lead, arp, bass, drums;
    // Statistics (written in the interrupt)
    u32 ticks, msgs, late;
    u32 irq_max_us, irq_total_us;
    u32 gap_min_us, gap_max_us, last_tick;
} cs;

static u16 hz(int pitch)
{
    // 440 * 2^((pitch - 69) / 12) with a table of one octave
    static const u16 a4_octave[12] = { // Hz * 16 of A4 .. G#5
        7040, 7459, 7902, 8372, 8870, 9397, 9956, 10548, 11175, 11840, 12544, 13290,
    };
    int n = pitch - 69, oct = n >= 0 ? n / 12 : (n - 11) / 12, k = n - oct * 12;
    u32 v = a4_octave[k];
    v = oct >= 0 ? v << oct : v >> -oct;
    return (u16)((v + 8) / 16);
}

static void send_vol(Voice *v, int ch, u8 vol)
{
    if (v->vol == vol)
        return;
    soundSetVolume(ch, vol);
    v->vol = vol;
    cs.msgs++;
}

static void send_freq(int ch, u32 rate)
{
    soundSetFreq(ch, rate > 65535 ? 65535 : (u16)rate);
    cs.msgs++;
}

static void restart(int ch)
{
    if (cs.mode == 1)
    {
        soundPause(ch); // Disable + enable: the channel starts again
        soundResume(ch);
        cs.msgs += 2;
    }
}

// Starts the note of a voice when its time has come; returns true if so
static bool note_on(Voice *v, const ChipNote *tab, int count, int pos)
{
    if (v->next >= count || tab[v->next].t != pos)
        return false;
    v->pitch = tab[v->next].p;
    v->flag = tab[v->next].flag;
    v->len = tab[v->next].d;
    v->age = 0;
    v->next++;
    return true;
}

static void tick_lead(int pos)
{
    Voice *v = &cs.lead;
    if (note_on(v, song_lead, COUNT(song_lead), pos))
    {
        send_freq(CH_LEAD, (u32)hz(v->pitch) * 8); // PSG: 8 steps per period
        restart(CH_LEAD);
    }
    else if (v->len)
        v->age++;
    if (!v->len)
        return;
    if (v->age >= v->len)
    {
        v->len = 0;
        send_vol(v, CH_LEAD, 0);
        return;
    }
    // Duty change in the middle of every second bar (click test)
    if (pos % 192 == 48 || pos % 192 == 144)
    {
        soundSetWaveDuty(CH_LEAD, pos % 192 == 48 ? DutyCycle_50 : DutyCycle_25);
        cs.msgs++;
    }
    int k = v->age < (int)COUNT(env_lead) ? v->age : (int)COUNT(env_lead) - 1;
    send_vol(v, CH_LEAD, (u8)(env_lead[k] * 70 / 127));
}

static void tick_arp(int pos)
{
    static const u8 major[3] = { 0, 4, 7 }, minor[3] = { 0, 3, 7 };
    Voice *v = &cs.arp;
    if (!note_on(v, song_chords, COUNT(song_chords), pos) && v->len)
        v->age++;
    if (!v->len)
        return;
    if (v->age >= v->len)
    {
        v->len = 0;
        send_vol(v, CH_ARP, 0);
        return;
    }
    const u8 *shape = v->flag ? minor : major;
    send_freq(CH_ARP, (u32)hz(v->pitch + shape[v->age % 3]) * 8);
    restart(CH_ARP);
    int k = v->age < (int)COUNT(env_chord_maj) ? v->age : (int)COUNT(env_chord_maj) - 1;
    send_vol(v, CH_ARP, (u8)(env_chord_maj[k] * 32 / 127));
}

static void tick_bass(int pos)
{
    Voice *v = &cs.bass;
    if (note_on(v, song_bass, COUNT(song_bass), pos))
    {
        send_freq(CH_TRI, (u32)hz(v->pitch) * 32); // 32 samples per period
        restart(CH_TRI);
        send_vol(v, CH_TRI, 100);
    }
    else if (v->len && ++v->age >= v->len)
    {
        v->len = 0;
        send_vol(v, CH_TRI, 0);
    }
}

static void tick_drums(int pos)
{
    static const u8 *const envs[3] = { env_kick, env_snare, env_hat };
    static const int lens[3] = { COUNT(env_kick), COUNT(env_snare), COUNT(env_hat) };
    Voice *v = &cs.drums;
    if (note_on(v, song_drums, COUNT(song_drums), pos))
    {
        v->len = lens[v->flag];
        send_freq(CH_NOISE, drum_clock[v->flag]);
        restart(CH_NOISE);
    }
    else if (v->len)
        v->age++;
    if (!v->len)
        return;
    if (v->age >= v->len)
    {
        v->len = 0;
        send_vol(v, CH_NOISE, 0);
        return;
    }
    if (v->flag == 0 && v->age > 0) // Kick: the pitch falls
        send_freq(CH_NOISE, drum_clock[0] >> v->age);
    send_vol(v, CH_NOISE, envs[v->flag][v->age]);
}

static void timer_handler(void)
{
    u32 t0 = cpuGetTiming();
    if (cs.ticks)
    {
        u32 gap = timerTicks2usec(t0 - cs.last_tick);
        if (gap < cs.gap_min_us)
            cs.gap_min_us = gap;
        if (gap > cs.gap_max_us)
            cs.gap_max_us = gap;
        if (gap > 1000000 / TICK_HZ + 2000)
            cs.late++;
    }
    cs.last_tick = t0;

    int pos = cs.frame % CHIP_SONG_LENGTH;
    if (pos == 0)
        cs.lead.next = cs.arp.next = cs.bass.next = cs.drums.next = 0;
    tick_lead(pos);
    tick_arp(pos);
    tick_bass(pos);
    tick_drums(pos);
    cs.frame++;
    cs.ticks++;

    u32 us = timerTicks2usec(cpuGetTiming() - t0);
    cs.irq_total_us += us;
    if (us > cs.irq_max_us)
        cs.irq_max_us = us;
}

void ll_chiptest_stop(void)
{
    if (!cs.on)
        return;
    timerStop(3);
    irqDisable(IRQ_TIMER3);
    soundKill(CH_LEAD);
    soundKill(CH_ARP);
    soundKill(CH_TRI);
    soundKill(CH_NOISE);
    mmUnlockChannels(CHANNELS);
    cs.on = false;
    ll_log("chiptest: stopped after %lu ticks", (unsigned long)cs.ticks);
}

// chiptest.start([mode]): mode 0 = in place, 1 = restart channels
static int l_start(lua_State *L)
{
    int mode = (int)luaL_optinteger(L, 1, 0);
    luaL_argcheck(L, mode == 0 || mode == 1, 1, "mode 0 or 1");
    ll_chiptest_stop();
    memset(&cs, 0, sizeof(cs));
    cs.mode = mode;
    cs.gap_min_us = 0xFFFFFFFF;

    mmLockChannels(CHANNELS);
    soundEnable();
    DC_FlushRange(triangle, sizeof(triangle));
    // Set the channels up now (these calls wait for the ARM7): silent
    soundPlayPSGChannel(CH_LEAD, DutyCycle_25, 3520, 0, 40);
    soundPlayPSGChannel(CH_ARP, DutyCycle_12, 3520, 0, 88);
    soundPlaySampleChannel(CH_TRI, triangle, SoundFormat_8Bit, sizeof(triangle),
                           3520, 0, 64, true, 0);
    soundPlayNoiseChannel(CH_NOISE, 8000, 0, 64);

    cs.on = true;
    timerStart(3, ClockDivider_1024, TIMER_FREQ_1024(TICK_HZ), timer_handler);
    ll_log("chiptest: started, mode %d", mode);
    return 0;
}

static int l_stop(lua_State *L)
{
    (void)L;
    ll_chiptest_stop();
    return 0;
}

// chiptest.stats() -> table
static int l_stats(lua_State *L)
{
    lua_createtable(L, 0, 8);
    lua_pushboolean(L, cs.on);
    lua_setfield(L, -2, "on");
    lua_pushinteger(L, cs.mode);
    lua_setfield(L, -2, "mode");
    lua_pushinteger(L, cs.ticks);
    lua_setfield(L, -2, "ticks");
    lua_pushinteger(L, cs.msgs);
    lua_setfield(L, -2, "msgs");
    lua_pushinteger(L, cs.late);
    lua_setfield(L, -2, "late");
    lua_pushinteger(L, cs.irq_max_us);
    lua_setfield(L, -2, "irq_max_us");
    lua_pushinteger(L, cs.ticks ? cs.irq_total_us / cs.ticks : 0);
    lua_setfield(L, -2, "irq_avg_us");
    lua_pushinteger(L, cs.ticks > 1 ? cs.gap_min_us : 0);
    lua_setfield(L, -2, "gap_min_us");
    lua_pushinteger(L, cs.gap_max_us);
    lua_setfield(L, -2, "gap_max_us");
    return 1;
}

void ll_chiptest_register(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        { "start", l_start },
        { "stop", l_stop },
        { "stats", l_stats },
        { NULL, NULL },
    };
    luaL_newlib(L, funcs);
    lua_setglobal(L, "chiptest");
}
