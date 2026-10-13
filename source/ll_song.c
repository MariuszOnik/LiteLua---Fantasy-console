// SPDX-License-Identifier: Zlib
//
// LiteLua - .lsong loader (P18 S1, D41): the text is read by the data parser
// (D38, nothing is run) into a temporary Lua state with its own memory limit,
// checked, and compiled into one block: instruments, kit drums, notes, clips
// (the notes of one track in one pattern) and segments (playlist entries).
// The full rules are checked by tools/litelua.py song check; here only what
// the player needs to be safe: types, ranges and names that exist.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"

#include "ll_data.h"
#include "ll_mem.h"
#include "ll_song.h"

#define PARSE_MEM_LIMIT (3 * 1024 * 1024) // Temporary, freed after loading
#define MAX_NOTES 16384

typedef struct {
    LLSong *song;
    char *err;
    size_t err_size;
} Ctx;

// --- Reading fields of the table at index t ---------------------------------

static bool has(lua_State *L, int t, const char *key)
{
    bool b = lua_getfield(L, t, key) != LUA_TNIL;
    lua_pop(L, 1);
    return b;
}

static lua_Number num(lua_State *L, int t, const char *key, lua_Number def,
                      lua_Number lo, lua_Number hi, const char *where)
{
    lua_Number v = def;
    int type = lua_getfield(L, t, key);
    if (type == LUA_TNUMBER)
        v = lua_tonumber(L, -1);
    else if (type != LUA_TNIL)
        luaL_error(L, "%s.%s must be a number", where, key);
    lua_pop(L, 1);
    if (v < lo || v > hi)
        luaL_error(L, "%s.%s must be %f .. %f", where, key, (double)lo, (double)hi);
    return v;
}

static int integer(lua_State *L, int t, const char *key, int def, int lo, int hi,
                   const char *where)
{
    int v = def;
    int type = lua_getfield(L, t, key);
    if (type == LUA_TNUMBER && lua_isinteger(L, -1))
        v = (int)lua_tointeger(L, -1);
    else if (type != LUA_TNIL)
        luaL_error(L, "%s.%s must be an integer", where, key);
    lua_pop(L, 1);
    if (v < lo || v > hi)
        luaL_error(L, "%s.%s must be %d .. %d", where, key, lo, hi);
    return v;
}

// Index of a name in the name table at 'names', or an error
static int index_of(lua_State *L, int names, const char *name, const char *what)
{
    if (lua_getfield(L, names, name) != LUA_TNUMBER)
        luaL_error(L, "unknown %s '%s'", what, name);
    int i = (int)lua_tointeger(L, -1);
    lua_pop(L, 1);
    return i;
}

static const char *string_field(lua_State *L, int t, const char *key, const char *where)
{
    if (lua_getfield(L, t, key) != LUA_TSTRING)
        luaL_error(L, "%s.%s must be a name", where, key);
    const char *s = lua_tostring(L, -1); // Stays valid: the table holds it
    lua_pop(L, 1);
    return s;
}

// Numbers 0..1 of list 'key' -> 0..127; returns the count
static int levels(lua_State *L, int t, const char *key, u8 *out, int max, const char *where)
{
    int n = 0;
    if (lua_getfield(L, t, key) == LUA_TTABLE)
    {
        n = (int)lua_rawlen(L, -1);
        if (n > max)
            luaL_error(L, "%s.%s has more than %d values", where, key, max);
        for (int i = 1; i <= n; i++)
        {
            lua_rawgeti(L, -1, i);
            lua_Number v = lua_tonumber(L, -1);
            if (!lua_isnumber(L, -1) || v < 0 || v > 1)
                luaL_error(L, "%s.%s values must be 0 .. 1", where, key);
            out[i - 1] = (u8)(v * 127 + 0.5f);
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
    return n;
}

static int note_cmp(const void *a, const void *b)
{
    return (int)((const LLNote *)a)->t - (int)((const LLNote *)b)->t;
}

// --- Compiling ----------------------------------------------------------------

static int compile(lua_State *L)
{
    Ctx *ctx = lua_touserdata(L, 2);
    const int S = 1;
    if (!lua_istable(L, S))
        return luaL_error(L, "a song must be a table");
    lua_Number version = num(L, S, "lsong", 0, 1, 1.1, "song");
    if (version != 1 && version != (lua_Number)1.1)
        return luaL_error(L, "lsong version %f is not supported (1, 1.1)", (double)version);
    lua_Number tempo = num(L, S, "tempo", 0, 20, 400, "song");
    int ppq = integer(L, S, "ppq", 24, 1, 96, "song");

    // Name tables: instruments (3), tracks (4), patterns (5)
    lua_settop(L, 2);
    lua_newtable(L);
    lua_newtable(L);
    lua_newtable(L);
    const int INS = 3, TRK = 4, PAT = 5;

    // Pass 1: count and number everything
    if (lua_getfield(L, S, "instruments") != LUA_TTABLE)
        return luaL_error(L, "song.instruments missing");
    int ins_t = lua_gettop(L);
    int instr_count = 0, kit_count = 0;
    lua_pushnil(L);
    while (lua_next(L, ins_t))
    {
        if (lua_type(L, -2) != LUA_TSTRING || !lua_istable(L, -1))
            return luaL_error(L, "song.instruments must map names to tables");
        if (instr_count >= 32)
            return luaL_error(L, "more than 32 instruments");
        if (lua_getfield(L, -1, "drums") == LUA_TTABLE)
            kit_count += (int)lua_rawlen(L, -1);
        lua_pop(L, 1);
        lua_pushvalue(L, -2);
        lua_pushinteger(L, instr_count++);
        lua_rawset(L, INS);
        lua_pop(L, 1);
    }

    if (lua_getfield(L, S, "tracks") != LUA_TTABLE)
        return luaL_error(L, "song.tracks missing");
    int trk_t = lua_gettop(L);
    int tracks = (int)lua_rawlen(L, trk_t);
    if (tracks < 1 || tracks > LL_SONG_TRACKS)
        return luaL_error(L, "song.tracks must have 1 .. 8 entries");
    for (int i = 1; i <= tracks; i++)
    {
        lua_rawgeti(L, trk_t, i);
        if (!lua_istable(L, -1))
            return luaL_error(L, "tracks[%d] must be a table", i);
        lua_pushstring(L, string_field(L, -1, "name", "track"));
        lua_pushinteger(L, i - 1);
        lua_rawset(L, TRK);
        lua_pop(L, 1);
    }

    if (lua_getfield(L, S, "patterns") != LUA_TTABLE)
        return luaL_error(L, "song.patterns missing");
    int pat_t = lua_gettop(L);
    int pattern_count = 0;
    u32 note_count = 0;
    lua_pushnil(L);
    while (lua_next(L, pat_t))
    {
        if (lua_type(L, -2) != LUA_TSTRING || !lua_istable(L, -1))
            return luaL_error(L, "song.patterns must map names to tables");
        if (pattern_count >= 256)
            return luaL_error(L, "more than 256 patterns");
        if (lua_getfield(L, -1, "notes") == LUA_TTABLE)
        {
            lua_pushnil(L);
            while (lua_next(L, -2))
            {
                if (lua_istable(L, -1))
                    note_count += (u32)lua_rawlen(L, -1);
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
        lua_pushvalue(L, -2);
        lua_pushinteger(L, pattern_count++);
        lua_rawset(L, PAT);
        lua_pop(L, 1);
    }
    if (note_count > MAX_NOTES)
        return luaL_error(L, "%d notes; at most %d", (int)note_count, MAX_NOTES);

    if (lua_getfield(L, S, "playlist") != LUA_TTABLE)
        return luaL_error(L, "song.playlist missing");
    int pl_t = lua_gettop(L);
    int segment_count = (int)lua_rawlen(L, pl_t);
    if (segment_count < 1 || segment_count > 256)
        return luaL_error(L, "song.playlist must have 1 .. 256 entries");

    // One block for everything
    // Every array starts 8-byte aligned: the ARM9 does not fault on an
    // unaligned word access, it silently reads and writes the wrong bytes
#define ALIGN8(n) (((n) + 7) & ~(size_t)7)
    size_t sz_song = ALIGN8(sizeof(LLSong));
    size_t sz_instr = ALIGN8(sizeof(LLInstr) * (size_t)instr_count);
    size_t sz_kit = ALIGN8(sizeof(LLKitDrum) * (size_t)kit_count);
    size_t sz_notes = ALIGN8(sizeof(LLNote) * note_count);
    size_t sz_clips = ALIGN8(sizeof(LLClip) * (size_t)pattern_count * LL_SONG_TRACKS);
    size_t sz_seg = ALIGN8(sizeof(LLSegment) * (size_t)segment_count);
    size_t bytes = sz_song + sz_instr + sz_kit + sz_notes + sz_clips + sz_seg;
    u8 *block = calloc(1, bytes);
    if (block == NULL)
        return luaL_error(L, "out of memory (%d KB)", (int)(bytes / 1024));
    LLSong *song = (LLSong *)block;
    ctx->song = song; // Freed by the caller if an error follows
    song->bytes = bytes;
    song->instr = (LLInstr *)(block + sz_song);
    song->kit = (LLKitDrum *)(block + sz_song + sz_instr);
    song->notes = (LLNote *)(block + sz_song + sz_instr + sz_kit);
    song->pattern_clips = (LLClip *)((u8 *)song->notes + sz_notes);
    song->segments = (LLSegment *)((u8 *)song->pattern_clips + sz_clips);
    song->ppq = ppq;
    song->tracks = tracks;
    song->instr_count = instr_count;
    song->pattern_count = pattern_count;
    song->segment_count = segment_count;

    // Pass 2: instruments
    lua_pushnil(L);
    while (lua_next(L, ins_t))
    {
        int t = lua_gettop(L);
        const char *name = lua_tostring(L, -2);
        LLInstr *in = &song->instr[index_of(L, INS, name, "instrument")];
        if (lua_getfield(L, t, "type") != LUA_TSTRING)
            return luaL_error(L, "instrument '%s' has no type", name);
        const char *type = lua_tostring(L, -1);
        lua_pop(L, 1);
        in->type = strcmp(type, "pulse") == 0 ? LL_KIND_PULSE
                 : strcmp(type, "triangle") == 0 ? LL_KIND_TRIANGLE
                 : strcmp(type, "noise") == 0 ? LL_KIND_NOISE
                 : strcmp(type, "kit") == 0 ? LL_KIND_KIT : 0xFF;
        if (in->type == 0xFF)
            return luaL_error(L, "instrument '%s': unknown type '%s'", name, type);
        in->volume = (u8)(num(L, t, "volume", 1, 0, 1, name) * 127 + 0.5f);
        lua_Number duty = num(L, t, "duty", 0.5, 0.125, 0.875, name);
        in->duty = (u8)(duty * 8 + 0.5f) - 1;
        in->env_n = (u8)levels(L, t, "env", in->env, LL_SONG_ENV, name);
        if (in->env_n == 0)
        {
            in->env[0] = 127;
            in->env_n = 1;
        }
        in->rel_n = (u8)levels(L, t, "release", in->rel, LL_SONG_ENV, name);
        if (lua_getfield(L, t, "arp") == LUA_TTABLE)
        {
            int n = (int)lua_rawlen(L, -1);
            if (n > LL_SONG_ARP)
                return luaL_error(L, "instrument '%s': arp too long", name);
            for (int i = 1; i <= n; i++)
            {
                lua_rawgeti(L, -1, i);
                int v = (int)lua_tointeger(L, -1);
                if (!lua_isinteger(L, -1) || v < -24 || v > 24)
                    return luaL_error(L, "instrument '%s': arp values -24 .. 24", name);
                in->arp[i - 1] = (s8)v;
                lua_pop(L, 1);
            }
            in->arp_n = (u8)n;
        }
        lua_pop(L, 1);
        if (in->arp_n == 0)
            in->arp_n = 1; // arp[0] = 0
        if (lua_getfield(L, t, "vibrato") == LUA_TTABLE)
        {
            int vt = lua_gettop(L);
            in->vib_depth = (u16)(num(L, vt, "depth", 0, 0, 2, name) * 100 + 0.5f);
            in->vib_rate = (u16)(num(L, vt, "rate", 0, 0, 20, name) * 100 + 0.5f);
            in->vib_delay = (u8)integer(L, vt, "delay", 0, 0, 255, name);
        }
        lua_pop(L, 1);
        if (in->type == LL_KIND_KIT)
        {
            in->kit_first = (u16)song->kit_count;
            if (lua_getfield(L, t, "drums") != LUA_TTABLE)
                return luaL_error(L, "kit '%s' has no drums", name);
            int dt = lua_gettop(L), n = (int)lua_rawlen(L, dt);
            for (int i = 1; i <= n; i++)
            {
                lua_rawgeti(L, dt, i);
                int d = lua_gettop(L);
                if (!lua_istable(L, d))
                    return luaL_error(L, "kit '%s': drums must be tables", name);
                LLKitDrum *k = &song->kit[song->kit_count++];
                k->p = (u8)integer(L, d, "p", -1, 0, 127, name);
                k->instr = (u8)index_of(L, INS, string_field(L, d, "i", name), "instrument");
                k->to = (u8)integer(L, d, "to", k->p, 0, 127, name);
                lua_pop(L, 1);
            }
            in->kit_n = (u16)n;
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
    // Drums of kits must be plain instruments
    for (int i = 0; i < song->kit_count; i++)
        if (song->instr[song->kit[i].instr].type == LL_KIND_KIT)
            return luaL_error(L, "a drum of a kit cannot be a kit");

    // Tracks: kind from the default instrument (a kit: its first drum)
    for (int i = 1; i <= tracks; i++)
    {
        lua_rawgeti(L, trk_t, i);
        int ti = (int)index_of(L, INS, string_field(L, -1, "instrument", "track"),
                               "instrument");
        const LLInstr *in = &song->instr[ti];
        u8 kind = in->type;
        if (kind == LL_KIND_KIT)
        {
            if (in->kit_n == 0)
                return luaL_error(L, "tracks[%d]: the kit has no drums", i);
            kind = song->instr[song->kit[in->kit_first].instr].type;
        }
        song->track_kind[i - 1] = kind;
        song->track_instr[i - 1] = (u8)ti;
        lua_pop(L, 1);
    }

    // Patterns: notes of each track, sorted and cut (one note at a time)
    static int lengths[256];
    u32 at = 0;
    lua_pushnil(L);
    while (lua_next(L, pat_t))
    {
        int pt = lua_gettop(L);
        const char *pname = lua_tostring(L, -2);
        int pi = index_of(L, PAT, pname, "pattern");
        int length = integer(L, pt, "length", -1, 1, ppq * 64, pname);
        if (lua_getfield(L, pt, "notes") == LUA_TTABLE)
        {
            int nt = lua_gettop(L);
            lua_pushnil(L);
            while (lua_next(L, nt))
            {
                if (lua_type(L, -2) != LUA_TSTRING || !lua_istable(L, -1))
                    return luaL_error(L, "pattern '%s': notes must map tracks to lists", pname);
                int track = index_of(L, TRK, lua_tostring(L, -2), "track");
                int lt = lua_gettop(L), n = (int)lua_rawlen(L, lt);
                LLClip *clip = &song->pattern_clips[pi * LL_SONG_TRACKS + track];
                clip->first = at;
                LLNote *notes = &song->notes[at];
                int count = 0;
                for (int i = 1; i <= n; i++)
                {
                    lua_rawgeti(L, lt, i);
                    int e = lua_gettop(L);
                    if (!lua_istable(L, e))
                        return luaL_error(L, "pattern '%s': a note must be a table", pname);
                    LLNote *no = &notes[count];
                    int t = integer(L, e, "t", -1, 0, length - 1, pname);
                    int d = integer(L, e, "d", -1, 1, 0x7FFFFFFF, pname);
                    no->t = (u16)t;
                    no->d = (u16)(d > length - t ? length - t : d);
                    no->p = (u8)integer(L, e, "p", -1, 0, 127, pname);
                    no->v = (u8)(num(L, e, "v", 1, 0, 1, pname) * 255 + 0.5f);
                    no->slide = (s8)integer(L, e, "s", 0, -24, 24, pname);
                    no->instr = LL_SONG_NONE;
                    if (has(L, e, "i"))
                        no->instr = (u8)index_of(L, INS, string_field(L, e, "i", pname),
                                                 "instrument");
                    if (lua_getfield(L, e, "tie") == LUA_TBOOLEAN)
                        no->tie = lua_toboolean(L, -1) && t == 0;
                    lua_pop(L, 2);
                    count++;
                }
                qsort(notes, (size_t)count, sizeof(LLNote), note_cmp);
                int kept = 0;
                for (int i = 0; i < count; i++)
                {
                    if (kept && notes[kept - 1].t == notes[i].t)
                        continue; // Same start: the file is invalid; keep the first
                    notes[kept++] = notes[i];
                }
                for (int i = 0; i + 1 < kept; i++)
                    if (notes[i].t + notes[i].d > notes[i + 1].t)
                        notes[i].d = notes[i + 1].t - notes[i].t;
                clip->count = (u16)kept;
                at += (u32)kept;
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 2); // notes, pattern
        lengths[pi] = length;
    }
    song->note_count = at;

    // Playlist -> segments; a tempo carries on until changed
    u32 tempo_milli = (u32)(tempo * 1000 + 0.5f);
    for (int i = 1; i <= segment_count; i++)
    {
        lua_rawgeti(L, pl_t, i);
        int e = lua_gettop(L);
        if (!lua_istable(L, e))
            return luaL_error(L, "playlist[%d] must be a table", i);
        LLSegment *sg = &song->segments[i - 1];
        int pi = index_of(L, PAT, string_field(L, e, "pattern", "playlist"), "pattern");
        sg->pattern = (u16)pi;
        sg->length = (u32)lengths[pi];
        sg->times = (u8)integer(L, e, "times", 1, 1, 64, "playlist");
        sg->transpose = (s8)integer(L, e, "transpose", 0, -24, 24, "playlist");
        if (has(L, e, "tempo"))
            tempo_milli = (u32)(num(L, e, "tempo", 120, 20, 400, "playlist") * 1000 + 0.5f);
        sg->tempo_milli = tempo_milli;
        lua_pop(L, 1);
    }
    int loop_type = lua_getfield(L, S, "loop");
    if (loop_type == LUA_TBOOLEAN && !lua_toboolean(L, -1))
        song->loop = -1;
    else
        song->loop = integer(L, S, "loop", 1, 1, segment_count, "song") - 1;
    lua_pop(L, 1);
    return 0;
}

LLSong *ll_song_load(const char *text, size_t len, const char *name, char *err,
                     size_t err_size)
{
    LLMem mem;
    ll_mem_init(&mem, PARSE_MEM_LIMIT);
    lua_State *L = lua_newstate(ll_mem_alloc, &mem);
    if (L == NULL)
    {
        snprintf(err, err_size, "%s: out of memory", name);
        return NULL;
    }
    static const LLDataLimits limits = { 256 * 1024, 16, 512 };
    Ctx ctx = { NULL, err, err_size };
    if (ll_data_parse(L, text, len, name, &limits, err, err_size))
    {
        lua_pushcfunction(L, compile);
        lua_insert(L, -2);
        lua_pushlightuserdata(L, &ctx);
        if (lua_pcall(L, 2, 0, 0) != LUA_OK)
        {
            snprintf(err, err_size, "%s: %s", name, lua_tostring(L, -1));
            free(ctx.song);
            ctx.song = NULL;
        }
    }
    lua_close(L);
    return ctx.song;
}
