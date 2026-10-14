// SPDX-License-Identifier: Zlib
//
// LiteLua - tile maps (P8, D50): map/<name>.lua files with up to 4 layers,
// drawn by C, with tile flags for collisions. Preset "platform" only; the
// 'mode' field leaves room for more presets (iso, D48).
//
// Lua API:
//   m = tilemap(name)              loads map/<name>.lua
//   m:draw([layer])                draws the visible tiles (all layers in order)
//   m:get(tx, ty, [layer]) -> id   0 = empty (also outside the map)
//   m:set(tx, ty, id, [layer])
//   m:cell(px, py) -> tx, ty       pixel -> tile
//   m:hit(x, y, w, h, [flag], [layer]) -> tx, ty | nil
//   m:flag(id, name) -> boolean
//   m:find(id, [layer]) -> { {x =, y =}, ... }
//   m.w, m.h, m.tile, m.layers
//
// Tile coordinates start at 0, like image frames. The cells of all layers
// live in one userdata block, so they count in the cart's memory limit.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"

#include "ll_cart.h"
#include "ll_data.h"
#include "ll_gfx.h"
#include "ll_image.h"
#include "ll_map.h"

#define MAP_MT "LiteLua.map"
#define MAP_DIR "map/"
#define MAX_LAYERS 4
#define MAX_FLAGS 8
#define MAX_TILE 4095
#define MAX_SIDE 4096   // Cells per side
#define MAX_CELLS (512 * 1024)
#define MAP_NAME_MAX 16

typedef struct {
    char name[MAP_NAME_MAX];
    uint16_t *cells;
} Layer;

typedef struct {
    int w, h, tile;
    int nlayers;
    Layer layers[MAX_LAYERS];
    int nflags;
    char flag_names[MAX_FLAGS][MAP_NAME_MAX];
    int max_id;        // Highest tile id with flags
    uint8_t *flags;    // max_id + 1 bit masks
    // Followed by the cells of every layer and the flags
} LLMap;

static const LLCart *cart;

// --- loading ----------------------------------------------------------------

// Integer field of the table at 'idx', or 'def' when missing
static int int_field(lua_State *L, int idx, const char *key, int def, int lo,
                     int hi)
{
    int t = lua_getfield(L, idx, key);
    int v = def;
    if (t != LUA_TNIL)
    {
        if (!lua_isinteger(L, -1))
            luaL_error(L, "map: '%s' must be an integer", key);
        lua_Integer n = lua_tointeger(L, -1);
        if (n < lo || n > hi)
            luaL_error(L, "map: '%s' must be %d..%d", key, lo, hi);
        v = (int)n;
    }
    lua_pop(L, 1);
    return v;
}

// Tile id from the legend table at 'legend' (0 when absent) for character c
static int legend_id(lua_State *L, int legend, int layer_legend, char c)
{
    char key[2] = { c, '\0' };
    for (int i = 0; i < 2; i++)
    {
        int t = i == 0 ? layer_legend : legend;
        if (t == 0)
            continue;
        if (lua_getfield(L, t, key) != LUA_TNIL)
        {
            if (!lua_isinteger(L, -1))
                luaL_error(L, "map: legend '%s' must be a tile number", key);
            int id = (int)lua_tointeger(L, -1);
            lua_pop(L, 1);
            return id;
        }
        lua_pop(L, 1);
    }
    if (c == '.' || c == ' ')
        return 0;
    return luaL_error(L, "map: character '%s' is not in the legend", key);
}

static void check_id(lua_State *L, lua_Integer id)
{
    if (id < 0 || id > MAX_TILE)
        luaL_error(L, "map: tile %d out of range (0..%d)", (int)id, MAX_TILE);
}

// Size of a layer given as rows (strings) or data (numbers); the map is as
// big as its biggest layer (unless w and h are given)
static void layer_size(lua_State *L, int layer, int *w, int *h)
{
    int lw = 0, lh = 0;
    if (lua_getfield(L, layer, "rows") == LUA_TTABLE)
    {
        lh = (int)lua_rawlen(L, -1);
        for (int y = 1; y <= lh; y++)
        {
            if (lua_rawgeti(L, -1, y) != LUA_TSTRING)
                luaL_error(L, "map: rows must be strings");
            int len = (int)lua_rawlen(L, -1);
            if (len > lw)
                lw = len;
            lua_pop(L, 1);
        }
    }
    else if (lua_getfield(L, layer, "data"), lua_type(L, -1) == LUA_TTABLE)
    {
        lua_remove(L, -2);
        lh = (int)lua_rawlen(L, -1);
        if (lh > 0 && lua_rawgeti(L, -1, 1) == LUA_TTABLE)
            lw = (int)lua_rawlen(L, -1); // A list of rows
        else
            lw = -1; // A flat list: needs w
        lua_pop(L, 1);
    }
    else
    {
        luaL_error(L, "map: a layer needs 'rows' or 'data'");
    }
    lua_pop(L, 1);
    if (lw == -1)
    {
        if (*w == 0)
            luaL_error(L, "map: 'data' as one list needs 'w' in the map (first)");
        lw = *w, lh = (lh + lw - 1) / lw;
    }
    if (lw > *w)
        *w = lw;
    if (lh > *h)
        *h = lh;
}

static void fill_layer(lua_State *L, int layer, int legend, uint16_t *cells,
                       int w, int h)
{
    int layer_legend = 0;
    if (lua_getfield(L, layer, "legend") == LUA_TTABLE)
        layer_legend = lua_gettop(L);
    else
        lua_pop(L, 1);

    if (lua_getfield(L, layer, "rows") == LUA_TTABLE)
    {
        int n = (int)lua_rawlen(L, -1);
        for (int y = 0; y < n && y < h; y++)
        {
            lua_rawgeti(L, -1, y + 1);
            size_t len;
            const char *s = lua_tolstring(L, -1, &len);
            for (int x = 0; x < (int)len && x < w; x++)
            {
                int id = legend_id(L, legend, layer_legend, s[x]);
                check_id(L, id);
                cells[y * w + x] = (uint16_t)id;
            }
            lua_pop(L, 1);
        }
        lua_pop(L, 1);
    }
    else
    {
        lua_pop(L, 1);
        lua_getfield(L, layer, "data");
        int n = (int)lua_rawlen(L, -1);
        bool nested = n > 0 && lua_rawgeti(L, -1, 1) == LUA_TTABLE;
        lua_pop(L, 1);
        if (nested)
        {
            for (int y = 0; y < n && y < h; y++)
            {
                lua_rawgeti(L, -1, y + 1);
                int rn = (int)lua_rawlen(L, -1);
                for (int x = 0; x < rn && x < w; x++)
                {
                    lua_rawgeti(L, -1, x + 1);
                    lua_Integer id = lua_tointeger(L, -1);
                    check_id(L, id);
                    cells[y * w + x] = (uint16_t)id;
                    lua_pop(L, 1);
                }
                lua_pop(L, 1);
            }
        }
        else
        {
            for (int i = 0; i < n && i < w * h; i++)
            {
                lua_rawgeti(L, -1, i + 1);
                lua_Integer id = lua_tointeger(L, -1);
                check_id(L, id);
                cells[i] = (uint16_t)id;
                lua_pop(L, 1);
            }
        }
        lua_pop(L, 1);
    }
    if (layer_legend)
        lua_remove(L, layer_legend);
}

// Highest tile id named in the flags table at 'idx'; ids are numbers or
// "a-b" ranges
static int flag_ids(lua_State *L, int list, int bit, uint8_t *flags, int max)
{
    int n = (int)lua_rawlen(L, list), top = 0;
    for (int i = 1; i <= n; i++)
    {
        int a, b;
        if (lua_rawgeti(L, list, i) == LUA_TSTRING)
        {
            if (sscanf(lua_tostring(L, -1), "%d-%d", &a, &b) != 2)
                luaL_error(L, "map: flag range '%s' (use \"1-16\")", lua_tostring(L, -1));
        }
        else if (lua_isinteger(L, -1))
        {
            a = b = (int)lua_tointeger(L, -1);
        }
        else
        {
            luaL_error(L, "map: flags are tile numbers or \"a-b\" ranges");
        }
        lua_pop(L, 1);
        if (a < 1 || b > MAX_TILE || a > b)
            luaL_error(L, "map: flag tiles %d-%d out of range (1..%d)", a, b, MAX_TILE);
        if (b > top)
            top = b;
        if (flags)
        {
            for (int id = a; id <= b && id <= max; id++)
                flags[id] |= (uint8_t)(1 << bit);
        }
    }
    return top;
}

// tilemap(name): upvalue 1 is image()
static int l_tilemap(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    if (cart == NULL)
        return luaL_error(L, "no cart files in the built-in demo");

    char rel[LL_PATH_MAX], path[LL_PATH_MAX];
    snprintf(path, sizeof(path), MAP_DIR "%s.lua", name);
    if (!ll_path_clean(path, rel, sizeof(rel)))
        return luaL_error(L, "bad map name '%s'", name);
    size_t len;
    char *src = ll_cart_read(cart, rel, &len);
    if (src == NULL)
        return luaL_error(L, "cannot read %s", rel);

    static const LLDataLimits limits = { 4 * 1024 * 1024, 8, 64 * 1024 };
    char err[200];
    const char *text = ll_skip_bom(src, &len);
    bool ok = ll_data_parse(L, text, len, rel, &limits, err, sizeof(err));
    free(src);
    if (!ok)
        return luaL_error(L, "%s", err);
    int def = lua_gettop(L);
    if (!lua_istable(L, def))
        return luaL_error(L, "%s must return a table", rel);

    // Header
    int format = int_field(L, def, "format", 1, 1, 1);
    (void)format;
    if (lua_getfield(L, def, "mode") != LUA_TNIL
        && strcmp(luaL_optstring(L, -1, ""), "platform") != 0)
        return luaL_error(L, "%s: mode '%s' is not supported (only \"platform\")",
                          rel, lua_tostring(L, -1));
    lua_pop(L, 1);
    int tile = int_field(L, def, "tile", 16, 1, 256);
    if (tile != 8 && tile != 16 && tile != 32)
        return luaL_error(L, "%s: tile must be 8, 16 or 32", rel);
    int fixed_w = int_field(L, def, "w", 0, 1, MAX_SIDE);
    int fixed_h = int_field(L, def, "h", 0, 1, MAX_SIDE);
    int w = fixed_w, h = fixed_h;

    if (lua_getfield(L, def, "layers") != LUA_TTABLE)
        return luaL_error(L, "%s: 'layers' (a list) is missing", rel);
    int layers = lua_gettop(L);
    int nlayers = (int)lua_rawlen(L, layers);
    if (nlayers < 1 || nlayers > MAX_LAYERS)
        return luaL_error(L, "%s: 1..%d layers", rel, MAX_LAYERS);
    for (int i = 1; i <= nlayers; i++)
    {
        if (lua_rawgeti(L, layers, i) != LUA_TTABLE)
            return luaL_error(L, "%s: layer %d is not a table", rel, i);
        layer_size(L, lua_gettop(L), &w, &h);
        lua_pop(L, 1);
    }
    if (fixed_w)
        w = fixed_w;
    if (fixed_h)
        h = fixed_h;
    if (w < 1 || h < 1 || w > MAX_SIDE || h > MAX_SIDE || (long)w * h > MAX_CELLS)
        return luaL_error(L, "%s: bad size %dx%d", rel, w, h);

    // Flags: names and the highest tile id
    int max_id = 0, nflags = 0;
    int flags_t = 0;
    if (lua_getfield(L, def, "flags") == LUA_TTABLE)
    {
        flags_t = lua_gettop(L);
        lua_pushnil(L);
        while (lua_next(L, flags_t))
        {
            if (lua_type(L, -2) != LUA_TSTRING || !lua_istable(L, -1))
                return luaL_error(L, "%s: flags = { name = { tiles } }", rel);
            if (++nflags > MAX_FLAGS)
                return luaL_error(L, "%s: at most %d flags", rel, MAX_FLAGS);
            int top = flag_ids(L, lua_gettop(L), 0, NULL, 0);
            if (top > max_id)
                max_id = top;
            lua_pop(L, 1);
        }
    }
    else
    {
        lua_pop(L, 1);
    }

    // One block: header, cells, flags
    size_t cells = (size_t)w * h;
    size_t size = sizeof(LLMap) + cells * sizeof(uint16_t) * nlayers + max_id + 1;
    LLMap *m = lua_newuserdatauv(L, size, 1);
    memset(m, 0, size);
    int mi = lua_gettop(L);
    m->w = w, m->h = h, m->tile = tile, m->nlayers = nlayers;
    uint16_t *data = (uint16_t *)(m + 1);
    m->flags = (uint8_t *)(data + cells * nlayers);
    m->max_id = max_id;

    if (flags_t)
    {
        lua_pushnil(L);
        while (lua_next(L, flags_t))
        {
            snprintf(m->flag_names[m->nflags], MAP_NAME_MAX, "%s", lua_tostring(L, -2));
            flag_ids(L, lua_gettop(L), m->nflags, m->flags, max_id);
            m->nflags++;
            lua_pop(L, 1);
        }
    }

    // Layers: cells and tilesets (images kept in the uservalue table)
    int legend = 0;
    if (lua_getfield(L, def, "legend") == LUA_TTABLE)
        legend = lua_gettop(L);
    lua_createtable(L, nlayers, 0); // Tilesets
    int sets = lua_gettop(L);
    for (int i = 0; i < nlayers; i++)
    {
        Layer *ly = &m->layers[i];
        ly->cells = data + cells * i;
        lua_rawgeti(L, layers, i + 1);
        int lt = lua_gettop(L);
        if (lua_getfield(L, lt, "name") == LUA_TSTRING)
            snprintf(ly->name, MAP_NAME_MAX, "%s", lua_tostring(L, -1));
        else
            snprintf(ly->name, MAP_NAME_MAX, "%d", i + 1);
        lua_pop(L, 1);
        fill_layer(L, lt, legend, ly->cells, w, h);

        if (lua_getfield(L, lt, "tileset") != LUA_TSTRING)
            return luaL_error(L, "%s: layer '%s' needs 'tileset' (an image name)",
                              rel, ly->name);
        lua_pushvalue(L, lua_upvalueindex(1)); // image(name, tile, tile)
        lua_insert(L, -2);
        lua_pushinteger(L, tile);
        lua_pushinteger(L, tile);
        lua_call(L, 3, 1);
        LLImage *img = ll_image_check(L, -1);
        // Every tile id of the layer must be a frame of the tileset
        for (size_t c = 0; c < cells; c++)
        {
            if (ly->cells[c] > img->frames)
                return luaL_error(L, "%s: layer '%s' uses tile %d, the tileset has %d",
                                  rel, ly->name, ly->cells[c], img->frames);
        }
        lua_rawseti(L, sets, i + 1);
        lua_pop(L, 1); // Layer table
    }
    lua_setiuservalue(L, mi, 1);
    lua_pushvalue(L, mi);
    luaL_setmetatable(L, MAP_MT);
    return 1;
}

// --- methods ----------------------------------------------------------------

static LLMap *check_map(lua_State *L)
{
    return luaL_checkudata(L, 1, MAP_MT);
}

// Layer argument: a name, a number (1-based) or none (the layer "main",
// otherwise the first one)
static int layer_arg(lua_State *L, LLMap *m, int idx)
{
    if (lua_isnoneornil(L, idx))
    {
        for (int i = 0; i < m->nlayers; i++)
        {
            if (strcmp(m->layers[i].name, "main") == 0)
                return i;
        }
        return 0;
    }
    if (lua_type(L, idx) == LUA_TNUMBER)
    {
        int n = (int)luaL_checkinteger(L, idx);
        luaL_argcheck(L, n >= 1 && n <= m->nlayers, idx, "no such layer");
        return n - 1;
    }
    const char *name = luaL_checkstring(L, idx);
    for (int i = 0; i < m->nlayers; i++)
    {
        if (strcmp(m->layers[i].name, name) == 0)
            return i;
    }
    return luaL_argerror(L, idx, lua_pushfstring(L, "no layer '%s'", name));
}

static LLImage *tileset(lua_State *L, int layer)
{
    lua_getiuservalue(L, 1, 1);
    lua_rawgeti(L, -1, layer + 1);
    LLImage *img = lua_touserdata(L, -1);
    lua_pop(L, 2); // The map keeps the image alive
    return img;
}

static void draw_layer(lua_State *L, LLMap *m, int i)
{
    ll_gfx_tiles(tileset(L, i), m->layers[i].cells, m->w, m->h, m->tile, m->tile);
}

static int m_draw(lua_State *L)
{
    LLMap *m = check_map(L);
    if (lua_isnoneornil(L, 2))
    {
        for (int i = 0; i < m->nlayers; i++)
            draw_layer(L, m, i);
    }
    else
    {
        draw_layer(L, m, layer_arg(L, m, 2));
    }
    return 0;
}

static int m_get(lua_State *L)
{
    LLMap *m = check_map(L);
    lua_Integer tx = luaL_checkinteger(L, 2), ty = luaL_checkinteger(L, 3);
    int layer = layer_arg(L, m, 4);
    int id = 0;
    if (tx >= 0 && ty >= 0 && tx < m->w && ty < m->h)
        id = m->layers[layer].cells[ty * m->w + tx];
    lua_pushinteger(L, id);
    return 1;
}

static int m_set(lua_State *L)
{
    LLMap *m = check_map(L);
    lua_Integer tx = luaL_checkinteger(L, 2), ty = luaL_checkinteger(L, 3);
    lua_Integer id = luaL_checkinteger(L, 4);
    int layer = layer_arg(L, m, 5);
    if (tx < 0 || ty < 0 || tx >= m->w || ty >= m->h)
        return 0; // Outside the map: nothing to change
    LLImage *img = tileset(L, layer);
    luaL_argcheck(L, id >= 0 && id <= img->frames, 4, "no such tile in the tileset");
    m->layers[layer].cells[ty * m->w + tx] = (uint16_t)id;
    return 0;
}

// Floor division for pixel -> tile (negative pixels give negative tiles)
static int tile_of(lua_Number p, int tile)
{
    lua_Integer i = (lua_Integer)p;
    if ((lua_Number)i > p)
        i--;
    return (int)(i >= 0 ? i / tile : -((-i + tile - 1) / tile));
}

static int m_cell(lua_State *L)
{
    LLMap *m = check_map(L);
    lua_pushinteger(L, tile_of(luaL_checknumber(L, 2), m->tile));
    lua_pushinteger(L, tile_of(luaL_checknumber(L, 3), m->tile));
    return 2;
}

// Bit of flag 'name', or -1
static int flag_bit(LLMap *m, const char *name)
{
    for (int i = 0; i < m->nflags; i++)
    {
        if (strcmp(m->flag_names[i], name) == 0)
            return i;
    }
    return -1;
}

static bool has_flag(LLMap *m, int id, int bit)
{
    return id > 0 && id <= m->max_id && (m->flags[id] & (1 << bit));
}

// m:hit(x, y, w, h, [flag], [layer]): the first tile with the flag that the
// rectangle (pixels) touches, as tx, ty; nil when none. Without flags in the
// map, any tile that is not 0 counts.
static int m_hit(lua_State *L)
{
    LLMap *m = check_map(L);
    lua_Number x = luaL_checknumber(L, 2), y = luaL_checknumber(L, 3);
    lua_Number w = luaL_checknumber(L, 4), h = luaL_checknumber(L, 5);
    const char *flag = luaL_optstring(L, 6, "solid");
    int layer = layer_arg(L, m, 7);
    int bit = flag_bit(m, flag);
    if (bit < 0 && m->nflags > 0)
        return luaL_argerror(L, 6, lua_pushfstring(L, "no flag '%s' in the map", flag));
    if (w <= 0 || h <= 0)
        return 0;

    int tx1 = tile_of(x, m->tile), ty1 = tile_of(y, m->tile);
    // The right/bottom edges are outside the rectangle
    int tx2 = tile_of(x + w - 1e-3, m->tile), ty2 = tile_of(y + h - 1e-3, m->tile);
    if (tx1 < 0) tx1 = 0;
    if (ty1 < 0) ty1 = 0;
    if (tx2 >= m->w) tx2 = m->w - 1;
    if (ty2 >= m->h) ty2 = m->h - 1;
    const uint16_t *cells = m->layers[layer].cells;
    for (int ty = ty1; ty <= ty2; ty++)
    {
        for (int tx = tx1; tx <= tx2; tx++)
        {
            int id = cells[ty * m->w + tx];
            if (bit < 0 ? id != 0 : has_flag(m, id, bit))
            {
                lua_pushinteger(L, tx);
                lua_pushinteger(L, ty);
                return 2;
            }
        }
    }
    lua_pushnil(L);
    return 1;
}

static int m_flag(lua_State *L)
{
    LLMap *m = check_map(L);
    lua_Integer id = luaL_checkinteger(L, 2);
    int bit = flag_bit(m, luaL_checkstring(L, 3));
    lua_pushboolean(L, bit >= 0 && id >= 0 && id <= MAX_TILE && has_flag(m, (int)id, bit));
    return 1;
}

static int m_find(lua_State *L)
{
    LLMap *m = check_map(L);
    lua_Integer want = luaL_checkinteger(L, 2);
    int layer = layer_arg(L, m, 3);
    const uint16_t *cells = m->layers[layer].cells;
    lua_newtable(L);
    int n = 0;
    for (int ty = 0; ty < m->h; ty++)
    {
        for (int tx = 0; tx < m->w; tx++)
        {
            if (cells[ty * m->w + tx] != want)
                continue;
            lua_createtable(L, 0, 2);
            lua_pushinteger(L, tx);
            lua_setfield(L, -2, "x");
            lua_pushinteger(L, ty);
            lua_setfield(L, -2, "y");
            lua_rawseti(L, -2, ++n);
        }
    }
    return 1;
}

static int m_index(lua_State *L)
{
    LLMap *m = check_map(L);
    const char *k = luaL_checkstring(L, 2);
    if (strcmp(k, "w") == 0)
        lua_pushinteger(L, m->w);
    else if (strcmp(k, "h") == 0)
        lua_pushinteger(L, m->h);
    else if (strcmp(k, "tile") == 0)
        lua_pushinteger(L, m->tile);
    else if (strcmp(k, "layers") == 0)
    {
        lua_createtable(L, m->nlayers, 0);
        for (int i = 0; i < m->nlayers; i++)
        {
            lua_pushstring(L, m->layers[i].name);
            lua_rawseti(L, -2, i + 1);
        }
    }
    else
    {
        // Methods
        luaL_getmetatable(L, MAP_MT);
        lua_getfield(L, -1, "methods");
        lua_getfield(L, -1, k);
    }
    return 1;
}

static int m_tostring(lua_State *L)
{
    LLMap *m = check_map(L);
    lua_pushfstring(L, "tilemap (%dx%d, tile %d, %d layers)", m->w, m->h, m->tile,
                    m->nlayers);
    return 1;
}

void ll_map_register(lua_State *L, const LLCart *c)
{
    static const luaL_Reg methods[] = {
        { "draw", m_draw }, { "get", m_get }, { "set", m_set },
        { "cell", m_cell }, { "hit", m_hit }, { "flag", m_flag },
        { "find", m_find }, { NULL, NULL },
    };
    cart = c;

    luaL_newmetatable(L, MAP_MT);
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "methods");
    lua_pushcfunction(L, m_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, m_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pop(L, 1);

    // tilemap() keeps image() as its upvalue (a game may replace the global)
    lua_getglobal(L, "image");
    lua_pushcclosure(L, l_tilemap, 1);
    lua_setglobal(L, "tilemap");
}
