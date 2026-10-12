// SPDX-License-Identifier: Zlib
//
// LiteLua - sound (P7, D7, D34).
//
// Maxmod gets an empty sample bank of SOUND_SLOTS entries in RAM instead of a
// soundbank file: every cart loads its own files.
// - Sound effects: sfx/<name>.wav (PCM, 8 or 16 bit, mono or stereo, mixed
//   down to mono) is turned into a sample in Maxmod's MAS format in RAM and
//   put in a free slot of the bank; sfx() plays it by its slot number.
//   (Maxmod's "external sample" pointer does not work without a soundbank,
//   D34.) A sound object owns its sample; when it is collected the sample and
//   its slot are freed only after its last play has ended (the ARM7 reads
//   them while it plays).
// - Music, one at a time: music/<name>.mas (a module made by mmutil, played
//   from RAM) or music/<name>.wav streamed from the SD card through a ring
//   buffer of half a second: the stream callback (timer interrupt) copies
//   from the ring, ll_sound_update refills it from the file.
// All sound data is counted in the cart's memory limit (ll_mem_charge) and
// everything is stopped and freed when the cart ends (D14).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <maxmod9.h>
#include <mm_mas.h>
#include <nds.h>

#include "lauxlib.h"

#include "ll_chiptest.h"
#include "ll_log.h"
#include "ll_sound.h"

#define SOUND_MT "LiteLua.sound"
#define CACHE_KEY "LiteLua.sounds" // Registry: name -> sound (weak values)

#define STREAM_MAX_RATE 32768  // Highest stream rate of Maxmod
#define STREAM_READ_MAX 8192   // Bytes read from the file per update
#define WAV_HEADER_MAX 4096    // Chunks before the WAV data must fit here
#define SOUND_SLOTS 256        // Sounds loaded at the same time

// Maxmod's sample bank: one word per slot, the offset of a MAS sample from the
// start of main RAM (0 = free). The ARM7 reads it.
static mm_word sample_bank[SOUND_SLOTS] __attribute__((aligned(32)));

static const LLCart *cart;
static LLMem *mem;
static unsigned long stop_vblank; // Everything was stopped at this VBlank

// --- Deferred freeing -------------------------------------------------------

typedef struct Pending {
    struct Pending *next;
    void *data;
    int slot;              // Sample bank slot to free with it, or -1
    unsigned long free_at; // VBlank count
} Pending;

static Pending *pending;

static void slot_set(int slot, mm_word value)
{
    sample_bank[slot] = value;
    DC_FlushRange(&sample_bank[slot], sizeof(mm_word));
}

static bool reached(unsigned long vblank)
{
    return (long)(ll_vblanks() - vblank) >= 0;
}

// Frees 'data' (and sample bank 'slot', if not -1) at VBlank 'at': the ARM7
// may still read them until then
static void free_later(void *data, int slot, unsigned long at)
{
    Pending *p = malloc(sizeof(*p));
    if (p == NULL)
    {
        // Cannot wait: stop every sound effect so nothing reads it
        mmEffectCancelAll();
        if (slot >= 0)
            slot_set(slot, 0);
        free(data);
        return;
    }
    p->data = data;
    p->slot = slot;
    p->free_at = at;
    p->next = pending;
    pending = p;
}

static void free_due(bool all)
{
    for (Pending **pp = &pending; *pp;)
    {
        Pending *p = *pp;
        if (all || reached(p->free_at))
        {
            *pp = p->next;
            if (p->slot >= 0)
                slot_set(p->slot, 0);
            free(p->data);
            free(p);
        }
        else
        {
            pp = &p->next;
        }
    }
}

// --- WAV --------------------------------------------------------------------

typedef struct {
    int channels, bits;
    unsigned rate;
    uint32_t data_ofs, data_size;
} WavInfo;

static uint32_t rd16(const uint8_t *p)
{
    return p[0] | p[1] << 8;
}

static uint32_t rd32(const uint8_t *p)
{
    return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

// Reads the format and finds the data chunk of a WAV file. 'buf' holds the
// start of the file ('len' bytes, the whole file for sound effects). Only
// PCM, 8 or 16 bit, mono or stereo.
static bool wav_parse(const uint8_t *buf, size_t len, WavInfo *w, char *err,
                      size_t err_size)
{
    if (len < 12 || memcmp(buf, "RIFF", 4) != 0 || memcmp(buf + 8, "WAVE", 4) != 0)
    {
        snprintf(err, err_size, "not a WAV file");
        return false;
    }

    bool fmt = false;
    size_t pos = 12;
    while (pos + 8 <= len)
    {
        const uint8_t *c = buf + pos + 8;
        uint32_t size = rd32(buf + pos + 4);
        if (memcmp(buf + pos, "fmt ", 4) == 0)
        {
            if (size < 16 || pos + 8 + 16 > len)
                break;
            unsigned tag = rd16(c);
            if (tag == 0xfffe && size >= 26 && pos + 8 + 26 <= len)
                tag = rd16(c + 24); // WAVE_FORMAT_EXTENSIBLE: the sub format
            w->channels = rd16(c + 2);
            w->rate = rd32(c + 4);
            w->bits = rd16(c + 14);
            if (tag != 1 || (w->bits != 8 && w->bits != 16)
                || (w->channels != 1 && w->channels != 2))
            {
                snprintf(err, err_size, "only PCM WAV files, 8 or 16 bit, mono "
                         "or stereo, are supported");
                return false;
            }
            if (w->rate < 1000 || w->rate > 48000)
            {
                snprintf(err, err_size, "sample rate %u Hz (1000 .. 48000)", w->rate);
                return false;
            }
            fmt = true;
        }
        else if (memcmp(buf + pos, "data", 4) == 0 && fmt)
        {
            w->data_ofs = pos + 8;
            w->data_size = size;
            return true;
        }
        pos += 8 + size + (size & 1);
    }
    snprintf(err, err_size, "no sound data in the WAV file");
    return false;
}

// "jump" -> <dir>/jump<ext>; a name that has the extension is used as it is
static void cart_path(lua_State *L, const char *dir, const char *name,
                      const char *ext, char *rel, size_t size)
{
    char path[LL_PATH_MAX];
    size_t len = strlen(name), ext_len = strlen(ext);
    bool has_ext = len > ext_len && strcasecmp(name + len - ext_len, ext) == 0;
    snprintf(path, sizeof(path), "%s/%s%s", dir, name, has_ext ? "" : ext);
    if (!ll_path_clean(path, rel, size))
        luaL_error(L, "bad name '%s'", name);
}

// --- Sound effects ----------------------------------------------------------

// A sample in Maxmod's MAS format: prefix, sample header, then the data
#define SAMPLE_HEADER (sizeof(mm_mas_prefix) + sizeof(mm_mas_ds_sample))

typedef struct {
    void *block;              // The MAS sample, NULL after collection
    int slot;                 // Its slot in the sample bank
    size_t bytes;             // Counted in the cart memory
    unsigned rate, samples;
    unsigned long last_play;  // VBlank of the last sfx() call
    unsigned long busy_until; // VBlank when the longest play ends
} LLSound;

// Mono, signed sample data from the WAV data (stereo is mixed down)
static void wav_to_mono(const uint8_t *src, const WavInfo *w, unsigned samples,
                        void *out)
{
    if (w->bits == 8)
    {
        int8_t *o = out;
        for (unsigned i = 0; i < samples; i++)
        {
            int v = src[0] - 128;
            if (w->channels == 2)
                v = (v + src[1] - 128) / 2;
            o[i] = (int8_t)v;
            src += w->channels;
        }
    }
    else
    {
        int16_t *o = out;
        for (unsigned i = 0; i < samples; i++)
        {
            int v = (int16_t)rd16(src);
            if (w->channels == 2)
                v = (v + (int16_t)rd16(src + 2)) / 2;
            o[i] = (int16_t)v;
            src += 2 * w->channels;
        }
    }
}

// Loads sfx/<name>.wav, or returns the sound already loaded
static int load_sound(lua_State *L, const char *name)
{
    lua_getfield(L, LUA_REGISTRYINDEX, CACHE_KEY);
    if (lua_getfield(L, -1, name) == LUA_TUSERDATA)
    {
        lua_remove(L, -2);
        return 1;
    }
    lua_pop(L, 1);

    if (cart == NULL)
        return luaL_error(L, "sounds can only be loaded by a cart");

    char rel[LL_PATH_MAX];
    cart_path(L, "sfx", name, ".wav", rel, sizeof(rel));
    size_t size;
    uint8_t *file = (uint8_t *)ll_cart_read(cart, rel, &size);
    if (file == NULL)
        return luaL_error(L, "cannot read %s", rel);

    char err[160];
    WavInfo w;
    if (!wav_parse(file, size, &w, err, sizeof(err)))
    {
        free(file);
        return luaL_error(L, "%s: %s", rel, err);
    }
    if (w.data_size > size - w.data_ofs)
        w.data_size = size - w.data_ofs; // Truncated file: what is there
    unsigned samples = w.data_size / (w.channels * w.bits / 8);
    size_t bytes = ((size_t)samples * (w.bits / 8) + 3) & ~(size_t)3;
    if (samples == 0)
    {
        free(file);
        return luaL_error(L, "%s: no sound data", rel);
    }

    int slot = 0;
    while (slot < SOUND_SLOTS && sample_bank[slot] != 0)
        slot++;
    if (slot == SOUND_SLOTS)
    {
        // Unused sounds may still hold slots: collect them and look again
        lua_gc(L, LUA_GCCOLLECT);
        free_due(false);
        for (slot = 0; slot < SOUND_SLOTS && sample_bank[slot] != 0; slot++)
            ;
        if (slot == SOUND_SLOTS)
        {
            free(file);
            return luaL_error(L, "%s: too many sounds loaded (%d)", rel, SOUND_SLOTS);
        }
    }

    LLSound *s = lua_newuserdatauv(L, sizeof(LLSound), 0);
    memset(s, 0, sizeof(*s));
    luaL_setmetatable(L, SOUND_MT);

    // Errors (out of memory) leave the file buffer: free it first if so
    if (!ll_mem_charge(mem, bytes))
    {
        lua_gc(L, LUA_GCCOLLECT);
        if (!ll_mem_charge(mem, bytes))
        {
            free(file);
            return luaL_error(L, "not enough memory for %s (%u KB, cart limit "
                              "%u KB)", rel, (unsigned)(bytes / 1024),
                              (unsigned)(mem->limit / 1024));
        }
    }
    uint8_t *b = calloc(1, SAMPLE_HEADER + bytes);
    if (b == NULL || ((uintptr_t)b >> 24) != 0x02) // Bank: offsets in main RAM
    {
        free(b);
        ll_mem_release(mem, bytes);
        free(file);
        return luaL_error(L, "%s: out of memory", rel);
    }
    mm_mas_prefix *prefix = (mm_mas_prefix *)b;
    mm_mas_ds_sample *smp = (mm_mas_ds_sample *)(b + sizeof(mm_mas_prefix));
    wav_to_mono(file + w.data_ofs, &w, samples, smp->data);
    free(file);
    prefix->size = sizeof(mm_mas_ds_sample) + bytes;
    prefix->type = MAS_TYPE_SAMPLE_NDS;
    smp->loop_start = 0;
    smp->length = bytes / 4;
    smp->format = w.bits == 8 ? MM_SFORMAT_8BIT : MM_SFORMAT_16BIT;
    smp->repeat_mode = MM_SREPEAT_OFF;
    smp->default_frequency = w.rate * 1024 / 32768;
    smp->point = 0; // The data follows the header
    DC_FlushRange(b, SAMPLE_HEADER + bytes); // The ARM7 reads main RAM
    slot_set(slot, (uintptr_t)b - 0x2000000);

    s->block = b;
    s->slot = slot;
    s->bytes = bytes;
    s->rate = w.rate;
    s->samples = samples;

    lua_pushvalue(L, -1);
    lua_setfield(L, -3, name); // Cache
    lua_remove(L, -2);
    return 1;
}

static LLSound *check_sound(lua_State *L, int i)
{
    LLSound *s = luaL_checkudata(L, i, SOUND_MT);
    if (s->block == NULL)
        luaL_argerror(L, i, "sound is closed");
    return s;
}

// sound(name) -> sound
static int l_sound(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    lua_settop(L, 1);
    return load_sound(L, name);
}

static int clamp(int v, int lo, int hi)
{
    return v < lo ? lo : v > hi ? hi : v;
}

// sfx(snd, [volume], [pan], [pitch]) -> handle or nil
static int l_sfx(lua_State *L)
{
    LLSound *s = check_sound(L, 1);
    lua_Number vol = luaL_optnumber(L, 2, 1);
    lua_Number pan = luaL_optnumber(L, 3, 0);
    lua_Number pitch = luaL_optnumber(L, 4, 1);
    luaL_argcheck(L, pitch >= 1.0 / 16 && pitch <= 16, 4, "pitch must be 1/16 .. 16");

    mm_sound_effect e = {
        .id = s->slot,
        .rate = (mm_hword)(pitch * 1024 + 0.5),
        .handle = 0,
        .volume = (mm_byte)clamp((int)(vol * 255 + 0.5), 0, 255),
        .panning = (mm_byte)clamp((int)(128 + pan * 128), 0, 255),
    };
    mm_sfxhand h = mmEffectEx(&e);

    // When this play ends (+2 VBlanks for the ARM7), for freeing the data
    unsigned long now = ll_vblanks();
    uint64_t frames = (uint64_t)s->samples * 60 * 1024 / ((uint64_t)s->rate * e.rate);
    unsigned long end = now + (unsigned long)frames + 2;
    if (!reached(s->busy_until) && s->last_play >= stop_vblank)
        end = (long)(end - s->busy_until) > 0 ? end : s->busy_until;
    s->busy_until = end;
    s->last_play = now;

    if (h == 0)
        lua_pushnil(L); // No free channel
    else
        lua_pushinteger(L, h);
    return 1;
}

// sfx_stop([handle]): stops one sound effect, or all
static int l_sfx_stop(lua_State *L)
{
    if (lua_isnoneornil(L, 1))
        mmEffectCancelAll();
    else
        mmEffectCancel((mm_sfxhand)luaL_checkinteger(L, 1));
    return 0;
}

static int sound_gc(lua_State *L)
{
    LLSound *s = luaL_checkudata(L, 1, SOUND_MT);
    if (s->block == NULL)
        return 0;
    ll_mem_release(mem, s->bytes);
    unsigned long at = ll_vblanks() + 2;
    if (s->last_play >= stop_vblank && (long)(s->busy_until - at) > 0)
        at = s->busy_until; // Still playing: free when it ends
    free_later(s->block, s->slot, at);
    s->block = NULL;
    return 0;
}

// snd.length (seconds), snd.rate (Hz)
static int sound_index(lua_State *L)
{
    LLSound *s = luaL_checkudata(L, 1, SOUND_MT);
    const char *key = luaL_checkstring(L, 2);
    if (strcmp(key, "length") == 0)
        lua_pushnumber(L, (lua_Number)s->samples / s->rate);
    else if (strcmp(key, "rate") == 0)
        lua_pushinteger(L, s->rate);
    else
        lua_pushnil(L);
    return 1;
}

static int sound_tostring(lua_State *L)
{
    LLSound *s = luaL_checkudata(L, 1, SOUND_MT);
    lua_pushfstring(L, "sound %d Hz, %d samples", (int)s->rate, (int)s->samples);
    return 1;
}

// --- Music ------------------------------------------------------------------

enum { MUSIC_NONE, MUSIC_MAS, MUSIC_WAV };

static struct {
    int type;
    int volume;      // 0..1024, kept for the next music of the cart
    void *mas;       // MUSIC_MAS: the module
    size_t bytes;    // Counted in the cart memory (module or ring)

    // MUSIC_WAV
    FILE *file;
    long data_start, data_size, pos;
    bool loop, eof, eight_bit;
    int frame_bytes; // Bytes per sample frame (all channels)
    uint8_t *ring;
    uint32_t ring_size;
    volatile uint32_t rd, wr; // Total bytes taken / put (wrap around)
} music;

// Stream callback, in the timer interrupt: copies from the ring, silence
// when the ring is empty (the file could not be read fast enough)
static mm_word stream_cb(mm_word length, mm_addr dest, mm_stream_formats format)
{
    (void)format;
    uint32_t need = length * music.frame_bytes;
    uint32_t avail = music.wr - music.rd;
    uint32_t n = avail < need ? avail : need;
    uint8_t *out = dest;
    uint32_t at = music.rd % music.ring_size;
    uint32_t first = music.ring_size - at < n ? music.ring_size - at : n;
    memcpy(out, music.ring + at, first);
    memcpy(out + first, music.ring, n - first);
    memset(out + n, 0, need - n);
    music.rd += n;
    return length;
}

// Reads the WAV data into the ring (up to 'max' bytes)
static void stream_fill(uint32_t max)
{
    while (max > 0 && !music.eof)
    {
        uint32_t free_bytes = music.ring_size - (music.wr - music.rd);
        uint32_t at = music.wr % music.ring_size;
        uint32_t n = music.ring_size - at; // Up to the end of the ring
        if (n > free_bytes)
            n = free_bytes;
        if (n > max)
            n = max;
        if ((long)n > music.data_size - music.pos)
            n = music.data_size - music.pos;
        n -= n % music.frame_bytes;
        if (n == 0)
        {
            if (music.pos < music.data_size)
                return; // The ring is full
            if (!music.loop)
            {
                music.eof = true;
                return;
            }
            fseek(music.file, music.data_start, SEEK_SET);
            music.pos = 0;
            continue;
        }

        size_t got = fread(music.ring + at, 1, n, music.file);
        got -= got % music.frame_bytes;
        if (got == 0)
        {
            music.eof = true; // Read error: play what is in the ring
            return;
        }
        if (music.eight_bit) // WAV 8-bit is unsigned, the DS wants signed
            for (size_t i = 0; i < got; i++)
                music.ring[at + i] ^= 0x80;
        music.pos += got;
        music.wr += got; // After the data: the interrupt may read it now
        max -= got;
    }
}

static void music_stop(void)
{
    if (music.type == MUSIC_MAS)
    {
        mmStop();
        free_later(music.mas, -1, ll_vblanks() + 2);
        music.mas = NULL;
    }
    else if (music.type == MUSIC_WAV)
    {
        mmStreamClose();
        fclose(music.file);
        music.file = NULL;
        free_later(music.ring, -1, ll_vblanks() + 2);
        music.ring = NULL;
    }
    if (music.type != MUSIC_NONE && mem)
        ll_mem_release(mem, music.bytes);
    music.type = MUSIC_NONE;
    music.bytes = 0;
}

static void play_mas(char *data, size_t size, bool loop)
{
    music.mas = data;
    DC_FlushRange(data, size); // The ARM7 plays it from main RAM
    mmSetModuleVolume(music.volume);
    mmPlayMAS((uintptr_t)data, loop ? MM_PLAY_LOOP : MM_PLAY_ONCE, MM_MAIN);
    music.type = MUSIC_MAS;
}

static void play_wav(lua_State *L, const char *rel, bool loop)
{
    char err[160];
    long size;
    FILE *f = ll_cart_open_stream(cart, rel, &size, err, sizeof(err));
    if (f == NULL)
        luaL_error(L, "%s", err);

    // The header: chunks before the data must fit in WAV_HEADER_MAX bytes
    uint8_t hdr[WAV_HEADER_MAX];
    long start = ftell(f);
    size_t got = fread(hdr, 1, size < WAV_HEADER_MAX ? (size_t)size : sizeof(hdr), f);
    WavInfo w;
    if (!wav_parse(hdr, got, &w, err, sizeof(err)))
    {
        fclose(f);
        luaL_error(L, "%s: %s", rel, err);
    }
    if (w.rate > STREAM_MAX_RATE)
    {
        fclose(f);
        luaL_error(L, "%s: %u Hz; streamed music can have at most %d Hz", rel,
                   w.rate, STREAM_MAX_RATE);
    }

    int frame_bytes = w.channels * w.bits / 8;
    long data_size = w.data_size;
    if (data_size > size - (long)w.data_ofs)
        data_size = size - (long)w.data_ofs;
    data_size -= data_size % frame_bytes;
    if (data_size <= 0)
    {
        fclose(f);
        luaL_error(L, "%s: no sound data", rel);
    }

    // Half a second of sound, in 4 KB steps
    uint32_t ring_size = (w.rate * frame_bytes / 2 + 4095) & ~4095u;
    if (!ll_mem_charge(mem, ring_size))
    {
        lua_gc(L, LUA_GCCOLLECT);
        if (!ll_mem_charge(mem, ring_size))
        {
            fclose(f);
            luaL_error(L, "not enough memory to stream %s", rel);
        }
    }
    uint8_t *ring = malloc(ring_size);
    if (ring == NULL)
    {
        ll_mem_release(mem, ring_size);
        fclose(f);
        luaL_error(L, "%s: out of memory", rel);
    }

    music.type = MUSIC_WAV;
    music.bytes = ring_size;
    music.file = f;
    music.data_start = start + w.data_ofs;
    music.data_size = data_size;
    music.pos = 0;
    music.loop = loop;
    music.eof = false;
    music.eight_bit = w.bits == 8;
    music.frame_bytes = frame_bytes;
    music.ring = ring;
    music.ring_size = ring_size;
    music.rd = music.wr = 0;
    fseek(f, music.data_start, SEEK_SET);
    stream_fill(ring_size); // Full before it starts

    mm_stream stream = {
        .sampling_rate = w.rate,
        .buffer_length = 1024,
        .callback = stream_cb,
        .format = (w.bits == 8 ? 0 : 2) | (w.channels == 2 ? 1 : 0),
        .timer = MM_TIMER2, // Timers 0 and 1 are micros()
        .manual = false,
    };
    mmStreamOpen(&stream);
    mmStreamVolume(music.volume * 127 / 1024);
}

// music([name], [loop]): plays music/<name>.mas or music/<name>.wav (looped
// unless loop is false); music() stops it
static int l_music(lua_State *L)
{
    music_stop();
    if (lua_isnoneornil(L, 1))
        return 0;
    const char *name = luaL_checkstring(L, 1);
    bool loop = lua_isnoneornil(L, 2) || lua_toboolean(L, 2);
    if (cart == NULL)
        return luaL_error(L, "music can only be played by a cart");

    size_t len = strlen(name);
    bool wav = len > 4 && strcasecmp(name + len - 4, ".wav") == 0;
    char rel[LL_PATH_MAX];
    if (!wav)
    {
        cart_path(L, "music", name, ".mas", rel, sizeof(rel));
        size_t size;
        char *data = ll_cart_read(cart, rel, &size);
        if (data)
        {
            if (!ll_mem_charge(mem, size))
            {
                lua_gc(L, LUA_GCCOLLECT);
                if (!ll_mem_charge(mem, size))
                {
                    free(data);
                    return luaL_error(L, "not enough memory for %s (%u KB)",
                                      rel, (unsigned)(size / 1024));
                }
            }
            music.bytes = size;
            play_mas(data, size, loop);
            return 0;
        }
        bool has_ext = len > 4 && strcasecmp(name + len - 4, ".mas") == 0;
        if (has_ext)
            return luaL_error(L, "cannot read %s", rel);
    }
    cart_path(L, "music", name, ".wav", rel, sizeof(rel));
    play_wav(L, rel, loop);
    return 0;
}

// music_volume(v): volume of the music, 0 .. 1
static int l_music_volume(lua_State *L)
{
    lua_Number v = luaL_checknumber(L, 1);
    music.volume = clamp((int)(v * 1024 + 0.5), 0, 1024);
    mmSetModuleVolume(music.volume);
    if (music.type == MUSIC_WAV)
        mmStreamVolume(music.volume * 127 / 1024);
    return 0;
}

// --- Lifecycle --------------------------------------------------------------

void ll_sound_init(void)
{
    // No soundbank file: an empty bank of sample slots in RAM, filled by
    // sound(). Modules are played from RAM with mmPlayMAS.
    mm_ds_system sys = {
        .mod_count = 0,
        .samp_count = SOUND_SLOTS,
        .mem_bank = sample_bank,
        .fifo_channel = FIFO_MAXMOD,
    };
    if (!mmInit(&sys))
        ll_log("sound: Maxmod init failed");
    DC_FlushRange(sample_bank, sizeof(sample_bank));
    music.volume = 1024;
}

void ll_sound_begin(const LLCart *c, LLMem *m)
{
    cart = c;
    mem = m;
    music.volume = 1024;
    mmSetModuleVolume(1024);
    mmSetEffectsVolume(1024);
}

void ll_sound_update(void)
{
    if (music.type == MUSIC_WAV)
    {
        stream_fill(STREAM_READ_MAX);
        if (music.eof && music.rd == music.wr)
            music_stop(); // Played to the end
    }
    if (pending)
        free_due(false);
}

void ll_sound_stop_all(void)
{
    ll_chiptest_stop();
    music_stop();
    mmEffectCancelAll();
    stop_vblank = ll_vblanks();
    // Nothing plays anymore: what waits for a play to end can go soon
    for (Pending *p = pending; p; p = p->next)
        p->free_at = stop_vblank + 2;
}

void ll_sound_end(void)
{
    ll_sound_stop_all(); // Also for sounds collected by lua_close
    while (pending)
    {
        swiWaitForVBlank();
        free_due(false);
    }
    mem = NULL;
}

void ll_sound_register(lua_State *L)
{
    static const luaL_Reg meta[] = {
        { "__gc", sound_gc },
        { "__index", sound_index },
        { "__tostring", sound_tostring },
        { NULL, NULL },
    };
    luaL_newmetatable(L, SOUND_MT);
    luaL_setfuncs(L, meta, 0);
    lua_pop(L, 1);

    // Loaded sounds by name; weak values so unused sounds can be collected
    lua_newtable(L);
    lua_newtable(L);
    lua_pushliteral(L, "v");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    lua_setfield(L, LUA_REGISTRYINDEX, CACHE_KEY);

    lua_register(L, "sound", l_sound);
    lua_register(L, "sfx", l_sfx);
    lua_register(L, "sfx_stop", l_sfx_stop);
    lua_register(L, "music", l_music);
    lua_register(L, "music_volume", l_music_volume);
}
