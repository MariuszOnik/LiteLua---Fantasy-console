// SPDX-License-Identifier: Zlib
//
// LiteLua - path search on a grid (D57): Dijkstra in C for units that stand on a
// size x size footprint, with step costs, other units in the way, zones of
// control, slow and miry cells, and flying. Lua does the same about 50 times
// slower on a DS (HeroesDS measured ~1 s for one search).
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
// Returns cost[key] of every place the mover can stop at and parent[key] of the
// cheapest steps. Ties go the same way on every machine (a binary heap without
// key order, steps in the given order).

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"

#include "ll_path.h"

#define GRID_MT "LiteLua.pathgrid"
#define MAX_SIDE 512
#define MAX_STEPS 16
#define MAX_RECTS 64

#define F_CLOSED 1
#define F_SLOW 2
#define F_MIRE 4

typedef struct {
    int w, h;
    uint8_t cells[]; // y * w + x
} Grid;

// Work memory of a search, kept between calls (grown when needed)
static int32_t *dist;     // cost, -1 = not reached
static int32_t *parent;
static uint8_t *mark;     // 1 popped, 2 occupied, 4 fits known, 8 fits, 16 touches a zone
static int32_t *sums;     // (w+1)(h+1) counts of closed cells
static int32_t *msums;    // the same for mire cells
static int32_t *heap_c, *heap_k;
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
    lua_pushinteger(L, (x >= 0 && y >= 0 && x < g->w && y < g->h) ? g->cells[y * g->w + x] : F_CLOSED);
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
            if (g->cells[(y + j) * g->w + x + i] & F_CLOSED)
            {
                ok = false;
                break;
            }
    lua_pushboolean(L, ok);
    return 1;
}

// ---------------------------------------------------------------------------
// Search

static bool grow(lua_State *L, int cells)
{
    if (cells <= cap_cells)
        return true;
    int s = (cells / 1024 + 1) * 1024;
    int ss = s + 2 * MAX_SIDE + 1;  // (w+1)(h+1) <= cells + w + h + 1
    int32_t *d = realloc(dist, sizeof(int32_t) * s);
    if (d) dist = d;
    int32_t *p = realloc(parent, sizeof(int32_t) * s);
    if (p) parent = p;
    uint8_t *m = realloc(mark, s);
    if (m) mark = m;
    int32_t *a = realloc(sums, sizeof(int32_t) * ss);
    if (a) sums = a;
    int32_t *b = realloc(msums, sizeof(int32_t) * ss);
    if (b) msums = b;
    if (!d || !p || !m || !a || !b)
        return luaL_error(L, "pathgrid: out of memory"), false;
    cap_cells = s;
    return true;
}

static void heap_grow(lua_State *L, int n)
{
    if (n <= cap_heap)
        return;
    int s = cap_heap ? cap_heap * 2 : 4096;
    while (s < n)
        s *= 2;
    int32_t *c = realloc(heap_c, sizeof(int32_t) * s);
    if (c) heap_c = c;
    int32_t *k = realloc(heap_k, sizeof(int32_t) * s);
    if (k) heap_k = k;
    if (!c || !k)
        luaL_error(L, "pathgrid: out of memory");
    cap_heap = s;
}

// The same binary heap as HeroesDS's grid.lua (1-based, ties by position only)
static void heap_push(int n, int32_t c, int32_t k)
{
    heap_c[n] = c;
    heap_k[n] = k;
    while (n > 1)
    {
        int p = n / 2;
        if (heap_c[p] <= heap_c[n])
            break;
        int32_t t = heap_c[p]; heap_c[p] = heap_c[n]; heap_c[n] = t;
        t = heap_k[p]; heap_k[p] = heap_k[n]; heap_k[n] = t;
        n = p;
    }
}

static void heap_pop(int n, int32_t *c, int32_t *k)
{
    *c = heap_c[1];
    *k = heap_k[1];
    int32_t lc = heap_c[n], lk = heap_k[n];
    n--;
    if (n > 0)
    {
        heap_c[1] = lc;
        heap_k[1] = lk;
        int i = 1;
        for (;;)
        {
            int l = 2 * i, r = l + 1, m = i;
            if (l <= n && heap_c[l] < heap_c[m]) m = l;
            if (r <= n && heap_c[r] < heap_c[m]) m = r;
            if (m == i)
                break;
            int32_t t = heap_c[i]; heap_c[i] = heap_c[m]; heap_c[m] = t;
            t = heap_k[i]; heap_k[i] = heap_k[m]; heap_k[m] = t;
            i = m;
        }
    }
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

static inline int sgn(int v) { return (v > 0) - (v < 0); }

// The nearest of 8 directions (HeroesDS grid.dir8): borders at 22.5 degrees exact
static void dir8(int dx, int dy, int *ox, int *oy)
{
    int ax = abs(dx), ay = abs(dy);
    if (ax == 0 && ay == 0) { *ox = 1; *oy = 0; return; }
    int s2 = (ax + ay) * (ax + ay);
    if (s2 < 2 * ax * ax) { *ox = sgn(dx); *oy = 0; return; }
    if (s2 < 2 * ay * ay) { *ox = 0; *oy = sgn(dy); return; }
    *ox = sgn(dx);
    *oy = sgn(dy);
}

static int g_flood(lua_State *L)
{
    Grid *g = check_grid(L);
    luaL_checktype(L, 2, LUA_TTABLE);
    const int W = g->w, H = g->h, M = W + 1;
    int sx = opt_int(L, 2, "x", 0), sy = opt_int(L, 2, "y", 0);
    int size = opt_int(L, 2, "size", 1);
    int budget = opt_int(L, 2, "budget", 0);
    bool corners = opt_bool(L, 2, "corners", true);
    bool fly = opt_bool(L, 2, "fly", false);
    bool columns = opt_bool(L, 2, "columns", false);
    lua_getfield(L, 2, "slow");
    bool has_slow = !lua_isnil(L, -1);
    int slow = has_slow ? (int)luaL_checkinteger(L, -1) : 0;
    lua_getfield(L, 2, "mire");
    bool has_mire = !lua_isnil(L, -1);
    int mire = has_mire ? (int)luaL_checkinteger(L, -1) : 0;
    lua_getfield(L, 2, "div");
    bool has_div = !lua_isnil(L, -1);
    lua_Number div = has_div ? luaL_checknumber(L, -1) : 1;
    lua_pop(L, 3);
    luaL_argcheck(L, size >= 1 && size <= W && size <= H, 2, "size out of range");
    luaL_argcheck(L, sx >= 0 && sy >= 0 && sx < W && sy < H, 2, "start outside the grid");

    int32_t steps[MAX_STEPS * 3], blockers[MAX_RECTS * 3], zones[MAX_RECTS * 3];
    int32_t zone_costs[MAX_STEPS];
    int ns = read_ints(L, 2, "steps", steps, MAX_STEPS * 3) / 3;
    if (ns == 0)
    {
        static const int32_t def[] = { 1, 0, 2, -1, 0, 2, 0, 1, 2, 0, -1, 2,
                                       1, 1, 3, -1, -1, 3, 1, -1, 3, -1, 1, 3 };
        memcpy(steps, def, sizeof(def));
        ns = 8;
    }
    int nb = read_ints(L, 2, "blockers", blockers, MAX_RECTS * 3) / 3;
    int nz = read_ints(L, 2, "zones", zones, MAX_RECTS * 3) / 3;
    int nzc = read_ints(L, 2, "zone_costs", zone_costs, MAX_STEPS);
    for (int i = nzc; i < ns; i++)
        zone_costs[i] = 0;
    // the cheapest straight step: costlier ones are diagonal
    int straight = steps[2];
    for (int i = 1; i < ns; i++)
        if (steps[i * 3 + 2] < straight) straight = steps[i * 3 + 2];

    const int cells = W * H;
    if (!grow(L, cells))
        return 0;
    heap_grow(L, 4096);

    // prefix sums of closed and mire cells: S[(y) * M + x] over cells < x, < y
    for (int i = 0; i < M; i++)
        sums[i] = msums[i] = 0;
    for (int y = 0; y < H; y++)
    {
        int row = 0, mrow = 0;
        sums[(y + 1) * M] = msums[(y + 1) * M] = 0;
        for (int x = 0; x < W; x++)
        {
            uint8_t f = g->cells[y * W + x];
            row += f & F_CLOSED;
            mrow += (f & F_MIRE) != 0;
            sums[(y + 1) * M + x + 1] = sums[y * M + x + 1] + row;
            msums[(y + 1) * M + x + 1] = msums[y * M + x + 1] + mrow;
        }
    }
#define BOX(S, x, y, s) (S[((y) + (s)) * M + (x) + (s)] - S[(y) * M + (x) + (s)] \
                         - S[((y) + (s)) * M + (x)] + S[(y) * M + (x)])
#define FITS(x, y) ((x) >= 0 && (y) >= 0 && (x) + size <= W && (y) + size <= H \
                    && BOX(sums, x, y, size) == 0)

    for (int i = 0; i < cells; i++)
        dist[i] = -1;
    memset(mark, 0, cells);
    // places overlapping a blocker / touching a zone
    for (int b = 0; b < nb; b++)
    {
        int bx = blockers[b * 3], by = blockers[b * 3 + 1], bs = blockers[b * 3 + 2];
        for (int y = by - size + 1 > 0 ? by - size + 1 : 0; y <= by + bs - 1 && y < H; y++)
            for (int x = bx - size + 1 > 0 ? bx - size + 1 : 0; x <= bx + bs - 1 && x < W; x++)
                mark[y * W + x] |= 2;
    }
    for (int z = 0; z < nz; z++)
    {
        int zx = zones[z * 3], zy = zones[z * 3 + 1], zs = zones[z * 3 + 2];
        for (int y = zy - size > 0 ? zy - size : 0; y <= zy + zs && y < H; y++)
            for (int x = zx - size > 0 ? zx - size : 0; x <= zx + zs && x < W; x++)
                mark[y * W + x] |= 16;
    }

    int start = sy * W + sx;
    dist[start] = 0;
    int hn = 1;
    heap_c[1] = 0;
    heap_k[1] = start;
    int popped = 0;
    while (hn > 0)
    {
        int32_t c, k;
        heap_pop(hn, &c, &k);
        hn--;
        if (c > dist[k])
            continue;
        if (!(mark[k] & 1))
        {
            mark[k] |= 1;
            popped++;
        }
        int x = k % W, y = k / W;
        // steps that leave a zone freely: straight to or away from each zone touched
        uint32_t free_mask = ~0u;
        if (mark[k] & 16)
        {
            bool any = false;
            uint32_t ok = 0;
            for (int z = 0; z < nz; z++)
            {
                int zx = zones[z * 3], zy = zones[z * 3 + 1], zs = zones[z * 3 + 2];
                if (x <= zx + zs && zx <= x + size && y <= zy + zs && zy <= y + size)
                {
                    int fx, fy;
                    dir8((2 * zx + zs) - (2 * x + size), (2 * zy + zs) - (2 * y + size), &fx, &fy);
                    for (int s = 0; s < ns; s++)
                    {
                        int dx = steps[s * 3], dy = steps[s * 3 + 1];
                        if ((dx == fx && dy == fy) || (dx == -fx && dy == -fy))
                            ok |= 1u << s;
                    }
                    any = true;
                }
            }
            if (any)
                free_mask = ok;
        }
        for (int s = 0; s < ns; s++)
        {
            int dx = steps[s * 3], dy = steps[s * 3 + 1], cost = steps[s * 3 + 2];
            int nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= W || ny >= H)
                continue;
            int nk = ny * W + nx;
            int32_t nc = c + cost;
            if (has_slow && (g->cells[nk] & F_SLOW))
                nc = c + (cost > slow ? cost : slow);
            if (has_mire && nx + size <= W && ny + size <= H && BOX(msums, nx, ny, size) > 0)
                nc = c + (cost > mire ? cost : mire);
            if (!(free_mask & (1u << s)))
                nc += zone_costs[s];
            if (nc > budget || (dist[nk] >= 0 && nc >= dist[nk]))
                continue;
            bool pass;
            if (fly)
                pass = nx + size <= W && ny + size <= H;
            else
            {
                pass = !(mark[nk] & 2) && FITS(nx, ny);
                if (pass && corners && cost > straight)
                    pass = FITS(nx, y) || FITS(x, ny);
            }
            if (!pass)
                continue;
            dist[nk] = nc;
            parent[nk] = k;
            heap_grow(L, hn + 2);
            heap_push(++hn, nc, nk);
        }
    }

    // results
    lua_createtable(L, 0, popped);
    int nparent = 0;
    for (int k = 0; k < cells; k++)
        if (dist[k] >= 0) nparent++;
    lua_createtable(L, 0, nparent);
    for (int k = 0; k < cells; k++)
    {
        if (dist[k] < 0)
            continue;
        int x = k % W, y = k / W;
        lua_Integer key = columns ? (lua_Integer)x * H + y : k;
        if (k != start)
        {
            int p = parent[k];
            lua_pushinteger(L, columns ? (lua_Integer)(p % W) * H + p / W : p);
            lua_rawseti(L, -2, key);
        }
        if (!(mark[k] & 1))
            continue;
        if (fly && ((mark[k] & 2) || !FITS(x, y)))
            continue;
        if (has_div && dist[k] != 0)
            lua_pushnumber(L, (lua_Number)dist[k] / div);
        else
            lua_pushinteger(L, dist[k]);
        lua_rawseti(L, -3, key);
    }
    return 2;
#undef FITS
#undef BOX
}

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
        { "clone", g_clone },
        { NULL, NULL },
    };
    luaL_newmetatable(L, GRID_MT);
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "methods");
    lua_pushcfunction(L, g_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, g_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pop(L, 1);
    lua_register(L, "pathgrid", l_pathgrid);
}
