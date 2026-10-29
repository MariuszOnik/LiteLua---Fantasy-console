// SPDX-License-Identifier: Zlib
//
// LiteLua - isometric height grid (D58): ground made of diamonds whose corners
// are raised, drawn by the 3D engine in one call. In Lua a quad() per cell
// took ~40 ms per screen on a DS (HeroesDS M1); here the loop is in C.
//
// Lua API:
//   g = isogrid(img, cols, rows, [opts])
//   g:draw(x, y, [scale])             top corner of cell (0, 0) at world x, y;
//                                     heights times scale (default 1, 0..8) pixels up
//   g:draw3d([hscale], [tpt], [lod]) the grid as 3D terrain (D60, ll_3d.c)
//   g:frame(x, y, [f]) -> f           cell x, y (0-based): frame of img, -1 = none
//   g:height(x, y, [h]) -> h          corner x, y (0..cols, 0..rows): 0..32767
//   g:color(x, y, [col]) -> col       corner color (shading), 0xRRGGBB
//   g.cols, g.rows, g.w, g.h
//
// opts:
//   w = 32, h = w / 2     diamond size in pixels (even)
//   frames                cols * rows frames, row by row (default 0; -1 = none)
//   heights               (cols + 1) * (rows + 1) corner heights (default 0)
//   colors                the same corners: colors multiplied with the frame
//                         (shading); without them the tint color is used
//
// A frame is stretched onto its diamond: its top left corner goes on the top
// corner of the cell, top right on the right, bottom right on the bottom and
// bottom left on the left one. So frames are squares "straightened" from the
// diamond: x runs along the columns, y along the rows.

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"

#include "ll_3d.h"
#include "ll_gfx.h"
#include "ll_image.h"
#include "ll_iso.h"

#define ISO_MT "LiteLua.isogrid"
#define MAX_SIDE 1024
#define MAX_HEIGHT 32767

typedef struct {
    LLIsoGrid g;
    bool colored;
    int16_t *frames, *heights;
    u16 *colors;
} Iso;

static Iso *check_iso(lua_State *L)
{
    return luaL_checkudata(L, 1, ISO_MT);
}

const LLIsoGrid *ll_iso_check(lua_State *L, int idx)
{
    return &((Iso *)luaL_checkudata(L, idx, ISO_MT))->g;
}

static LLImage *iso_image(lua_State *L)
{
    lua_getiuservalue(L, 1, 1);
    LLImage *img = ll_image_check(L, -1);
    lua_pop(L, 1);
    return img;
}

// Fills n values from the array opts[key]; false if there is none
static bool fill(lua_State *L, int opts, const char *key, int n, int lo, int hi,
                 int16_t *out)
{
    if (lua_getfield(L, opts, key) == LUA_TNIL)
    {
        lua_pop(L, 1);
        return false;
    }
    luaL_argexpected(L, lua_istable(L, -1), 4, "table of numbers");
    if ((int)lua_rawlen(L, -1) != n)
        luaL_error(L, "isogrid: %s needs %d values, has %d", key, n, (int)lua_rawlen(L, -1));
    for (int i = 0; i < n; i++)
    {
        lua_rawgeti(L, -1, i + 1);
        int isint;
        lua_Integer v = lua_tointegerx(L, -1, &isint);
        if (!isint || v < lo || v > hi)
            luaL_error(L, "isogrid: %s[%d] must be an integer %d..%d", key, i + 1, lo, hi);
        out[i] = (int16_t)v;
        lua_pop(L, 1);
    }
    lua_pop(L, 1);
    return true;
}

static void update_maxh(Iso *iso)
{
    int n = (iso->g.cols + 1) * (iso->g.rows + 1), m = 0;
    for (int i = 0; i < n; i++)
        if (iso->heights[i] > m)
            m = iso->heights[i];
    iso->g.maxh = m;
}

// isogrid(img, cols, rows, [opts])
static int l_isogrid(lua_State *L)
{
    LLImage *img = ll_image_check(L, 1);
    lua_Integer cols = luaL_checkinteger(L, 2), rows = luaL_checkinteger(L, 3);
    luaL_argcheck(L, cols >= 1 && cols <= MAX_SIDE, 2, "cols must be 1..1024");
    luaL_argcheck(L, rows >= 1 && rows <= MAX_SIDE, 3, "rows must be 1..1024");
    int opts = 0;
    if (!lua_isnoneornil(L, 4))
    {
        luaL_checktype(L, 4, LUA_TTABLE);
        opts = 4;
    }
    int w = 32, h = 16;
    if (opts)
    {
        lua_getfield(L, opts, "w");
        w = (int)luaL_optinteger(L, -1, 32);
        lua_getfield(L, opts, "h");
        h = (int)luaL_optinteger(L, -1, w / 2);
        lua_pop(L, 2);
    }
    if (w < 2 || h < 2 || w > 512 || h > 512 || (w & 1) || (h & 1))
        return luaL_error(L, "isogrid: w and h must be even, 2..512");

    size_t cells = (size_t)cols * rows, corners = (size_t)(cols + 1) * (rows + 1);
    size_t size = sizeof(Iso) + cells * sizeof(int16_t) + corners * (sizeof(int16_t) + sizeof(u16));
    Iso *iso = lua_newuserdatauv(L, size, 1);
    memset(iso, 0, size);
    int ui = lua_gettop(L);
    iso->frames = (int16_t *)(iso + 1);
    iso->heights = iso->frames + cells;
    iso->colors = (u16 *)(iso->heights + corners);
    iso->g = (LLIsoGrid){ .cols = (int)cols, .rows = (int)rows, .cw = w, .ch = h,
                          .frames = iso->frames, .heights = iso->heights };
    if (opts)
    {
        fill(L, opts, "frames", (int)cells, -1, img->frames - 1, iso->frames);
        fill(L, opts, "heights", (int)corners, 0, MAX_HEIGHT, iso->heights);
        if (lua_getfield(L, opts, "colors") != LUA_TNIL)
        {
            luaL_argexpected(L, lua_istable(L, -1), 4, "table of colors");
            if (lua_rawlen(L, -1) != corners)
                return luaL_error(L, "isogrid: colors needs %d values, has %d", (int)corners,
                                  (int)lua_rawlen(L, -1));
            for (size_t i = 0; i < corners; i++)
            {
                lua_rawgeti(L, -1, (lua_Integer)i + 1);
                lua_Integer c = luaL_checkinteger(L, -1);
                if (c < 0 || c > 0xffffff)
                    return luaL_error(L, "isogrid: colors[%d] must be 0-15 or 0xRRGGBB", (int)i + 1);
                iso->colors[i] = ll_gfx_color((u32)c);
                lua_pop(L, 1);
            }
            iso->colored = true;
            iso->g.colors = iso->colors;
        }
        lua_pop(L, 1);
    }
    update_maxh(iso);
    lua_pushvalue(L, 1);
    lua_setiuservalue(L, ui, 1);
    luaL_setmetatable(L, ISO_MT);
    return 1;
}

// g:draw(x, y, [scale])
static int m_draw(lua_State *L)
{
    Iso *iso = check_iso(L);
    int x = (int)luaL_checknumber(L, 2), y = (int)luaL_checknumber(L, 3);
    lua_Number scale = luaL_optnumber(L, 4, 1);
    luaL_argcheck(L, scale >= 0 && scale <= 8, 4, "scale must be 0..8");
    ll_gfx_isogrid(iso_image(L), &iso->g, x, y, (int32_t)(scale * 4096 + 0.5f));
    return 0;
}

// g:draw3d([hscale], [tpt], [lod]): terrain in the view of camera3d (D60)
static int m_draw3d(lua_State *L)
{
    Iso *iso = check_iso(L);
    lua_Number hscale = luaL_optnumber(L, 2, 1.0 / 16);
    lua_Integer tpt = luaL_optinteger(L, 3, 0);
    lua_Number lod = luaL_optnumber(L, 4, 0);
    luaL_argcheck(L, hscale >= 0 && hscale <= 8, 2, "hscale must be 0..8");
    luaL_argcheck(L, tpt >= 0 && tpt <= 32, 3, "tpt must be 0..32");
    luaL_argcheck(L, lod >= 0 && lod <= 1000, 4, "lod must be 0..1000");
    ll_3d_terrain(iso_image(L), &iso->g, (int32_t)(hscale * 4096 + 0.5f), (int)tpt,
                  (float)lod);
    return 0;
}

static int arg_index(lua_State *L, int w, int h, const char *what)
{
    lua_Integer x = luaL_checkinteger(L, 2), y = luaL_checkinteger(L, 3);
    if (x < 0 || x >= w || y < 0 || y >= h)
        luaL_error(L, "isogrid: %s %d, %d is outside 0..%d, 0..%d", what, (int)x, (int)y,
                   w - 1, h - 1);
    return (int)(y * w + x);
}

// g:frame(x, y, [f]) -> f
static int m_frame(lua_State *L)
{
    Iso *iso = check_iso(L);
    int i = arg_index(L, iso->g.cols, iso->g.rows, "cell");
    if (!lua_isnoneornil(L, 4))
    {
        lua_Integer f = luaL_checkinteger(L, 4);
        int frames = iso_image(L)->frames;
        luaL_argcheck(L, f >= -1 && f < frames, 4, "not a frame of the image (or -1)");
        iso->frames[i] = (int16_t)f;
        iso->g.version++;
    }
    lua_pushinteger(L, iso->frames[i]);
    return 1;
}

// g:height(x, y, [h]) -> h
static int m_height(lua_State *L)
{
    Iso *iso = check_iso(L);
    int i = arg_index(L, iso->g.cols + 1, iso->g.rows + 1, "corner");
    if (!lua_isnoneornil(L, 4))
    {
        lua_Integer h = luaL_checkinteger(L, 4);
        luaL_argcheck(L, h >= 0 && h <= MAX_HEIGHT, 4, "height must be 0..32767");
        int old = iso->heights[i];
        iso->heights[i] = (int16_t)h;
        iso->g.version++;
        if (h > iso->g.maxh)
            iso->g.maxh = (int)h;
        else if (old == iso->g.maxh && h < old)
            update_maxh(iso);
    }
    lua_pushinteger(L, iso->heights[i]);
    return 1;
}

// g:color(x, y, [col]) -> col (0xRRGGBB, as stored: 5 bits per channel)
static int m_color(lua_State *L)
{
    Iso *iso = check_iso(L);
    int i = arg_index(L, iso->g.cols + 1, iso->g.rows + 1, "corner");
    if (!lua_isnoneornil(L, 4))
    {
        lua_Integer c = luaL_checkinteger(L, 4);
        luaL_argcheck(L, c >= 0 && c <= 0xffffff, 4, "color must be 0-15 or 0xRRGGBB");
        if (!iso->colored)
        {
            // From now on every corner has a color: white until set
            int n = (iso->g.cols + 1) * (iso->g.rows + 1);
            for (int k = 0; k < n; k++)
                iso->colors[k] = ll_gfx_color(0xffffff);
            iso->colored = true;
            iso->g.colors = iso->colors;
        }
        iso->colors[i] = ll_gfx_color((u32)c);
        iso->g.version++;
    }
    if (!iso->colored)
    {
        lua_pushinteger(L, 0xffffff);
        return 1;
    }
    u16 c = iso->colors[i];
    unsigned r = c & 31, g = (c >> 5) & 31, b = (c >> 10) & 31;
    lua_pushinteger(L, (lua_Integer)((r * 255 / 31) << 16 | (g * 255 / 31) << 8 | (b * 255 / 31)));
    return 1;
}

static int m_index(lua_State *L)
{
    Iso *iso = check_iso(L);
    const char *k = luaL_checkstring(L, 2);
    if (strcmp(k, "cols") == 0)
        lua_pushinteger(L, iso->g.cols);
    else if (strcmp(k, "rows") == 0)
        lua_pushinteger(L, iso->g.rows);
    else if (strcmp(k, "w") == 0)
        lua_pushinteger(L, iso->g.cw);
    else if (strcmp(k, "h") == 0)
        lua_pushinteger(L, iso->g.ch);
    else
    {
        luaL_getmetatable(L, ISO_MT);
        lua_getfield(L, -1, "methods");
        lua_getfield(L, -1, k);
    }
    return 1;
}

static int m_gc(lua_State *L)
{
    ll_3d_free(&check_iso(L)->g);
    return 0;
}

static int m_tostring(lua_State *L)
{
    Iso *iso = check_iso(L);
    lua_pushfstring(L, "isogrid (%dx%d, cell %dx%d)", iso->g.cols, iso->g.rows, iso->g.cw,
                    iso->g.ch);
    return 1;
}

void ll_iso_register(lua_State *L)
{
    static const luaL_Reg methods[] = {
        { "draw", m_draw }, { "draw3d", m_draw3d }, { "frame", m_frame }, { "height", m_height },
        { "color", m_color }, { NULL, NULL },
    };
    luaL_newmetatable(L, ISO_MT);
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "methods");
    lua_pushcfunction(L, m_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, m_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pushcfunction(L, m_gc);
    lua_setfield(L, -2, "__gc");
    lua_pop(L, 1);
    lua_register(L, "isogrid", l_isogrid);
}
