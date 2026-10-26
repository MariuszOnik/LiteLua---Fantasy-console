// SPDX-License-Identifier: Zlib
//
// LiteLua - path search on a grid (D57): Dijkstra in C for units that stand on a
// size x size footprint, with step costs, other units in the way, zones of
// control, slow and miry cells, and flying. Lua does the same about 50 times
// slower on a DS (HeroesDS measured ~1 s for one search). The search itself is
// in ll_path_core.itcm.arm.c.
//
// Lua API:
//   g = pathgrid(w, h)               all cells open
//   g:set(x, y, flags) / g:get(x, y) flags: 1 closed, 2 slow, 4 mire
//   g:fits(x, y, [size]) -> boolean  footprint inside and on no closed cell
//   g:clone() -> a new grid with the same cells
//   cost, parent = g:flood(opts)
//   g.w, g.h
//
// opts (all costs are integers; scale them up for fractions):
//   x, y, size = 1      start: top-left cell of the footprint
//   budget              the highest cost to reach
//   steps               { dx, dy, cost, ... } (default: 4 straight 2, 4 diagonal 3)
//   corners = true      a diagonal step needs one of its two straight neighbours
//   blockers            { x, y, size, ... } footprints the mover may not overlap
//   zones, zone_costs   { x, y, size, ... } zones of control: leaving a place whose
//                       footprint touches a zone costs zone_costs[i] more for step i,
//                       unless the step goes straight to or away from the zone's
//                       centre (8 directions)
//   slow, mire          a step onto a slow cell costs at least `slow`, one with the
//                       footprint on a mire cell at least `mire` (mire wins)
//   fly = false         passes over closed cells and blockers, lands only where free
//   columns = false     keys x * h + y instead of y * w + x
//   div                 return costs / div as numbers (0 stays the integer 0)
// cost[key] is the cost of every place the mover can stop at, parent[key] the
// place it came from (nil at the start). Both are read-only objects that work
// like tables for [key] and pairs() (in key order): on a DS, filling real
// tables took as long as the search.

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"

#include "ll_path.h"
#include "ll_path_core.h"

#define GRID_MT "LiteLua.pathgrid"
#define RESULT_MT "LiteLua.pathresult"
#define MAX_SIDE 512
#define MAX_STEPS 16
#define MAX_RECTS 64

typedef struct {
    int w, h;
    uint8_t cells[]; // y * w + x
} Grid;

// The costs or the parents of a search, by key; -1 = none
typedef struct {
    int n;
    bool parent;    // values are keys
    bool has_div;
    lua_Number div;
    int32_t v[];
} Result;

// Work memory of a search, kept between calls (grown when needed)
static int32_t *dist, *sums, *msums, *heap_c;
static uint32_t *heap_xy;
static uint8_t *mark;
static int cap_cells, cap_heap;

static Grid *check_grid(lua_State *L)
{
    return (Grid *)luaL_checkudata(L, 1, GRID_MT);
}

static int l_pathgrid(lua_State *L)
{
    int w = (int)luaL_checkinteger(L, 1);
    int h = (int)luaL_checkinteger(L, 2);
    luaL_argcheck(L, w > 0 && w <= MAX_SIDE, 1, "width out of range");
    luaL_argcheck(L, h > 0 && h <= MAX_SIDE, 2, "height out of range");
    Grid *g = (Grid *)lua_newuserdatauv(L, sizeof(Grid) + (size_t)w * h, 0);
    g->w = w;
    g->h = h;
    memset(g->cells, 0, (size_t)w * h);
    luaL_setmetatable(L, GRID_MT);
    return 1;
}

static int g_set(lua_State *L)
{
    Grid *g = check_grid(L);
    int x = (int)luaL_checkinteger(L, 2), y = (int)luaL_checkinteger(L, 3);
    int f = (int)luaL_checkinteger(L, 4);
    if (x >= 0 && y >= 0 && x < g->w && y < g->h)
        g->cells[y * g->w + x] = (uint8_t)f;
    return 0;
}

static int g_get(lua_State *L)
{
    Grid *g = check_grid(L);
    int x = (int)luaL_checkinteger(L, 2), y = (int)luaL_checkinteger(L, 3);
    lua_pushinteger(L, (x >= 0 && y >= 0 && x < g->w && y < g->h) ? g->cells[y * g->w + x]
                                                                  : LL_PATH_CLOSED);
    return 1;
}

static int g_clone(lua_State *L)
{
    Grid *g = check_grid(L);
    size_t n = (size_t)g->w * g->h;
    Grid *c = (Grid *)lua_newuserdatauv(L, sizeof(Grid) + n, 0);
    c->w = g->w;
    c->h = g->h;
    memcpy(c->cells, g->cells, n);
    luaL_setmetatable(L, GRID_MT);
    return 1;
}

static int g_fits(lua_State *L)
{
    Grid *g = check_grid(L);
    int x = (int)luaL_checkinteger(L, 2), y = (int)luaL_checkinteger(L, 3);
    int s = (int)luaL_optinteger(L, 4, 1);
    bool ok = x >= 0 && y >= 0 && x + s <= g->w && y + s <= g->h;
    for (int j = 0; ok && j < s; j++)
        for (int i = 0; i < s; i++)
            if (g->cells[(y + j) * g->w + x + i] & LL_PATH_CLOSED)
            {
                ok = false;
                break;
            }
    lua_pushboolean(L, ok);
    return 1;
}

// ---------------------------------------------------------------------------
// Search

static void *grow_array(lua_State *L, void *p, size_t bytes)
{
    void *n = realloc(p, bytes);
    if (!n)
        luaL_error(L, "pathgrid: out of memory");
    return n;
}

static void grow_work(lua_State *L, int cells)
{
    if (cells <= cap_cells)
        return;
    int s = (cells / 1024 + 1) * 1024;
    int ss = s + 2 * MAX_SIDE + 1; // (w + 1)(h + 1) = cells + w + h + 1
    dist = grow_array(L, dist, sizeof(int32_t) * s);
    mark = grow_array(L, mark, s);
    sums = grow_array(L, sums, sizeof(int32_t) * ss);
    msums = grow_array(L, msums, sizeof(int32_t) * ss);
    cap_cells = s;
}

static void grow_heap(lua_State *L, int n)
{
    if (n <= cap_heap)
        return;
    heap_c = grow_array(L, heap_c, sizeof(int32_t) * n);
    heap_xy = grow_array(L, heap_xy, sizeof(uint32_t) * n);
    cap_heap = n;
}

static int read_ints(lua_State *L, int opts, const char *name, int32_t *out, int max)
{
    int n = 0;
    if (lua_getfield(L, opts, name) == LUA_TTABLE)
    {
        n = (int)luaL_len(L, -1);
        if (n > max)
            luaL_error(L, "pathgrid: too many values in %s", name);
        for (int i = 0; i < n; i++)
        {
            lua_rawgeti(L, -1, i + 1);
            out[i] = (int32_t)luaL_checkinteger(L, -1);
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
    return n;
}

static int opt_int(lua_State *L, int opts, const char *name, int def)
{
    lua_getfield(L, opts, name);
    int v = lua_isnil(L, -1) ? def : (int)luaL_checkinteger(L, -1);
    lua_pop(L, 1);
    return v;
}

static bool opt_bool(lua_State *L, int opts, const char *name, bool def)
{
    lua_getfield(L, opts, name);
    bool v = lua_isnil(L, -1) ? def : lua_toboolean(L, -1);
    lua_pop(L, 1);
    return v;
}

static Result *new_result(lua_State *L, int n, bool parent)
{
    Result *r = (Result *)lua_newuserdatauv(L, sizeof(Result) + sizeof(int32_t) * n, 0);
    r->n = n;
    r->parent = parent;
    r->has_div = false;
    r->div = 1;
    luaL_setmetatable(L, RESULT_MT);
    return r;
}

static int g_flood(lua_State *L)
{
    Grid *g = check_grid(L);
    luaL_checktype(L, 2, LUA_TTABLE);
    LLPathJob j = { 0 };
    j.w = g->w;
    j.h = g->h;
    j.cells = g->cells;
    bool columns = opt_bool(L, 2, "columns", false);
    j.kx = columns ? g->h : 1;
    j.ky = columns ? 1 : g->w;
    j.x = opt_int(L, 2, "x", 0);
    j.y = opt_int(L, 2, "y", 0);
    j.size = opt_int(L, 2, "size", 1);
    j.budget = opt_int(L, 2, "budget", 0);
    j.corners = opt_bool(L, 2, "corners", true);
    j.fly = opt_bool(L, 2, "fly", false);
    lua_getfield(L, 2, "slow");
    j.has_slow = !lua_isnil(L, -1);
    j.slow = j.has_slow ? (int)luaL_checkinteger(L, -1) : 0;
    lua_getfield(L, 2, "mire");
    j.has_mire = !lua_isnil(L, -1);
    j.mire = j.has_mire ? (int)luaL_checkinteger(L, -1) : 0;
    lua_getfield(L, 2, "div");
    bool has_div = !lua_isnil(L, -1);
    lua_Number div = has_div ? luaL_checknumber(L, -1) : 1;
    lua_pop(L, 3);
    luaL_argcheck(L, j.size >= 1 && j.size <= j.w && j.size <= j.h, 2, "size out of range");
    luaL_argcheck(L, j.x >= 0 && j.y >= 0 && j.x < j.w && j.y < j.h, 2, "start outside the grid");

    int32_t steps[MAX_STEPS * 3], blockers[MAX_RECTS * 3], zones[MAX_RECTS * 3];
    int32_t zone_costs[MAX_STEPS];
    j.nsteps = read_ints(L, 2, "steps", steps, MAX_STEPS * 3) / 3;
    if (j.nsteps == 0)
    {
        static const int32_t def[] = { 1, 0, 2, -1, 0, 2, 0, 1, 2, 0, -1, 2,
                                       1, 1, 3, -1, -1, 3, 1, -1, 3, -1, 1, 3 };
        memcpy(steps, def, sizeof(def));
        j.nsteps = 8;
    }
    j.steps = steps;
    j.nblockers = read_ints(L, 2, "blockers", blockers, MAX_RECTS * 3) / 3;
    j.blockers = blockers;
    j.nzones = read_ints(L, 2, "zones", zones, MAX_RECTS * 3) / 3;
    j.zones = zones;
    int nzc = read_ints(L, 2, "zone_costs", zone_costs, MAX_STEPS);
    for (int i = nzc; i < j.nsteps; i++)
        zone_costs[i] = 0;
    j.zone_costs = zone_costs;

    const int cells = j.w * j.h;
    grow_work(L, cells);
    grow_heap(L, cells < 4096 ? 4096 : cells);
    Result *cost = new_result(L, cells, false);
    cost->has_div = has_div;
    cost->div = div;
    Result *parent = new_result(L, cells, true);
    j.dist = dist;
    j.sums = sums;
    j.msums = msums;
    j.mark = mark;
    j.cost = cost->v;
    j.parent = parent->v;
    for (;;)
    {
        j.heap_c = heap_c;
        j.heap_xy = heap_xy;
        j.heap_cap = cap_heap;
        if (ll_path_search(&j) >= 0)
            break;
        grow_heap(L, cap_heap * 2);
    }
    return 2;
}

// ---------------------------------------------------------------------------
// Results: read-only, [key] and pairs()

static void push_value(lua_State *L, const Result *r, int32_t v)
{
    if (r->parent || !r->has_div || v == 0)
        lua_pushinteger(L, v);
    else
        lua_pushnumber(L, (lua_Number)v / r->div);
}

static int r_index(lua_State *L)
{
    Result *r = (Result *)luaL_checkudata(L, 1, RESULT_MT);
    int isnum;
    lua_Integer k = lua_tointegerx(L, 2, &isnum);
    if (!isnum || k < 0 || k >= r->n || r->v[k] < 0)
        lua_pushnil(L);
    else
        push_value(L, r, r->v[k]);
    return 1;
}

static int r_newindex(lua_State *L)
{
    return luaL_error(L, "path search results are read-only");
}

// The key after `key` that has a value, in key order (the iterator of pairs)
static int r_next(lua_State *L)
{
    Result *r = (Result *)luaL_checkudata(L, 1, RESULT_MT);
    lua_Integer k = lua_isnil(L, 2) ? 0 : luaL_checkinteger(L, 2) + 1;
    for (; k < r->n; k++)
        if (r->v[k] >= 0)
        {
            lua_pushinteger(L, k);
            push_value(L, r, r->v[k]);
            return 2;
        }
    lua_pushnil(L);
    return 1;
}

static int r_pairs(lua_State *L)
{
    luaL_checkudata(L, 1, RESULT_MT);
    lua_pushcfunction(L, r_next);
    lua_pushvalue(L, 1);
    lua_pushnil(L);
    return 3;
}

static int r_tostring(lua_State *L)
{
    Result *r = (Result *)luaL_checkudata(L, 1, RESULT_MT);
    lua_pushstring(L, r->parent ? "path parents" : "path costs");
    return 1;
}

// ---------------------------------------------------------------------------

static int g_index(lua_State *L)
{
    Grid *g = check_grid(L);
    const char *k = luaL_checkstring(L, 2);
    if (strcmp(k, "w") == 0)
        lua_pushinteger(L, g->w);
    else if (strcmp(k, "h") == 0)
        lua_pushinteger(L, g->h);
    else
    {
        luaL_getmetatable(L, GRID_MT);
        lua_getfield(L, -1, "methods");
        lua_getfield(L, -1, k);
    }
    return 1;
}

static int g_tostring(lua_State *L)
{
    Grid *g = check_grid(L);
    lua_pushfstring(L, "pathgrid (%dx%d)", g->w, g->h);
    return 1;
}

void ll_path_register(lua_State *L)
{
    static const luaL_Reg methods[] = {
        { "set", g_set }, { "get", g_get }, { "fits", g_fits }, { "flood", g_flood },
        { "clone", g_clone }, { NULL, NULL },
    };
    luaL_newmetatable(L, GRID_MT);
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "methods");
    lua_pushcfunction(L, g_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, g_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pop(L, 1);

    luaL_newmetatable(L, RESULT_MT);
    lua_pushcfunction(L, r_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, r_newindex);
    lua_setfield(L, -2, "__newindex");
    lua_pushcfunction(L, r_pairs);
    lua_setfield(L, -2, "__pairs");
    lua_pushcfunction(L, r_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pop(L, 1);

    lua_register(L, "pathgrid", l_pathgrid);
}
