// SPDX-License-Identifier: Zlib
//
// LiteLua - path search core (D57): Dijkstra for a size x size mover. ARM code
// in ITCM (D19 rule); no division in the loop (the ARM9 has no divide), the heap
// holds x, y and keys come from x * kx + y * ky.
//
// The heap is the same as HeroesDS's grid.lua (1-based binary heap, ties by
// position only) and the steps go in the given order, so ties end the same way
// as in the Lua search: both give the same costs and parents.

#include "ll_path_core.h"

#define PACK(x, y) (((uint32_t)(y) << 16) | (uint32_t)(x))

static inline int sgn(int v) { return (v > 0) - (v < 0); }

static inline int iabs(int v) { return v < 0 ? -v : v; }

// The nearest of 8 directions (HeroesDS grid.dir8): 22.5-degree borders, exact
static void dir8(int dx, int dy, int *ox, int *oy)
{
    int ax = iabs(dx), ay = iabs(dy);
    if (ax == 0 && ay == 0) { *ox = 1; *oy = 0; return; }
    int s2 = (ax + ay) * (ax + ay);
    if (s2 < 2 * ax * ax) { *ox = sgn(dx); *oy = 0; return; }
    if (s2 < 2 * ay * ay) { *ox = 0; *oy = sgn(dy); return; }
    *ox = sgn(dx);
    *oy = sgn(dy);
}

int ll_path_search(LLPathJob *j)
{
    const int W = j->w, H = j->h, M = W + 1, KX = j->kx, KY = j->ky;
    const int size = j->size, budget = j->budget, ns = j->nsteps;
    const int32_t *steps = j->steps;
    const uint8_t *cells = j->cells;
    int32_t *dist = j->dist, *sums = j->sums, *msums = j->msums;
    int32_t *cost = j->cost, *parent = j->parent;
    uint8_t *mark = j->mark;   // 1 popped, 2 overlaps a blocker, 16 touches a zone
    int32_t *hc = j->heap_c;
    uint32_t *hxy = j->heap_xy;
    const int cap = j->heap_cap;
    const int n = W * H;

    // prefix sums of closed and mire cells: S[y * M + x] = cells left of x, above y
    for (int i = 0; i < M; i++)
        sums[i] = msums[i] = 0;
    for (int y = 0; y < H; y++)
    {
        int row = 0, mrow = 0;
        int32_t *s0 = sums + y * M, *s1 = s0 + M, *m0 = msums + y * M, *m1 = m0 + M;
        const uint8_t *c = cells + y * W;
        s1[0] = m1[0] = 0;
        for (int x = 0; x < W; x++)
        {
            row += c[x] & LL_PATH_CLOSED;
            mrow += (c[x] & LL_PATH_MIRE) != 0;
            s1[x + 1] = s0[x + 1] + row;
            m1[x + 1] = m0[x + 1] + mrow;
        }
    }
#define BOX(S, x, y) (S[((y) + size) * M + (x) + size] - S[(y) * M + (x) + size] \
                      - S[((y) + size) * M + (x)] + S[(y) * M + (x)])
#define FITS(x, y) ((x) >= 0 && (y) >= 0 && (x) + size <= W && (y) + size <= H \
                    && BOX(sums, x, y) == 0)

    for (int i = 0; i < n; i++)
    {
        dist[i] = -1;
        parent[i] = -1;
        mark[i] = 0;
    }
    for (int b = 0; b < j->nblockers; b++)
    {
        const int32_t *r = j->blockers + b * 3;
        int x0 = r[0] - size + 1, y0 = r[1] - size + 1;
        for (int y = y0 > 0 ? y0 : 0; y <= r[1] + r[2] - 1 && y < H; y++)
            for (int x = x0 > 0 ? x0 : 0; x <= r[0] + r[2] - 1 && x < W; x++)
                mark[x * KX + y * KY] |= 2;
    }
    for (int z = 0; z < j->nzones; z++)
    {
        const int32_t *r = j->zones + z * 3;
        int x0 = r[0] - size, y0 = r[1] - size;
        for (int y = y0 > 0 ? y0 : 0; y <= r[1] + r[2] && y < H; y++)
            for (int x = x0 > 0 ? x0 : 0; x <= r[0] + r[2] && x < W; x++)
                mark[x * KX + y * KY] |= 16;
    }
    int straight = steps[2];
    for (int s = 1; s < ns; s++)
        if (steps[s * 3 + 2] < straight) straight = steps[s * 3 + 2];

    int start = j->x * KX + j->y * KY;
    dist[start] = 0;
    int hn = 1;
    hc[1] = 0;
    hxy[1] = PACK(j->x, j->y);
    while (hn > 0)
    {
        // pop (the same steps as grid.lua's heap_pop)
        int32_t c = hc[1];
        uint32_t xy = hxy[1];
        int32_t lc = hc[hn];
        uint32_t lxy = hxy[hn];
        hn--;
        if (hn > 0)
        {
            hc[1] = lc;
            hxy[1] = lxy;
            int i = 1;
            for (;;)
            {
                int l = 2 * i, r = l + 1, m = i;
                if (l <= hn && hc[l] < hc[m]) m = l;
                if (r <= hn && hc[r] < hc[m]) m = r;
                if (m == i)
                    break;
                int32_t tc = hc[i]; hc[i] = hc[m]; hc[m] = tc;
                uint32_t txy = hxy[i]; hxy[i] = hxy[m]; hxy[m] = txy;
                i = m;
            }
        }
        int x = xy & 0xFFFF, y = xy >> 16;
        int k = x * KX + y * KY;
        if (c > dist[k])
            continue;
        mark[k] |= 1;

        // steps that leave a zone freely: straight to or away from each zone touched
        uint32_t free_mask = ~0u;
        if (mark[k] & 16)
        {
            bool any = false;
            uint32_t ok = 0;
            for (int z = 0; z < j->nzones; z++)
            {
                const int32_t *r = j->zones + z * 3;
                if (x <= r[0] + r[2] && r[0] <= x + size && y <= r[1] + r[2] && r[1] <= y + size)
                {
                    int fx, fy;
                    dir8((2 * r[0] + r[2]) - (2 * x + size), (2 * r[1] + r[2]) - (2 * y + size), &fx, &fy);
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
            int dx = steps[s * 3], dy = steps[s * 3 + 1], sc = steps[s * 3 + 2];
            int nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= W || ny >= H)
                continue;
            int nk = nx * KX + ny * KY;
            int32_t nc = c + sc;
            if (j->has_slow && (cells[ny * W + nx] & LL_PATH_SLOW))
                nc = c + (sc > j->slow ? sc : j->slow);
            if (j->has_mire && nx + size <= W && ny + size <= H && BOX(msums, nx, ny) > 0)
                nc = c + (sc > j->mire ? sc : j->mire);
            if (!(free_mask & (1u << s)))
                nc += j->zone_costs[s];
            if (nc > budget || (dist[nk] >= 0 && nc >= dist[nk]))
                continue;
            bool pass;
            if (j->fly)
                pass = nx + size <= W && ny + size <= H;
            else
            {
                pass = !(mark[nk] & 2) && FITS(nx, ny);
                if (pass && j->corners && sc > straight)
                    pass = FITS(nx, y) || FITS(x, ny);
            }
            if (!pass)
                continue;
            dist[nk] = nc;
            parent[nk] = k;
            // push (the same steps as grid.lua's heap_push)
            if (hn + 1 >= cap)
                return -1;
            int p = ++hn;
            hc[p] = nc;
            hxy[p] = PACK(nx, ny);
            while (p > 1)
            {
                int q = p >> 1;
                if (hc[q] <= hc[p])
                    break;
                int32_t tc = hc[q]; hc[q] = hc[p]; hc[p] = tc;
                uint32_t txy = hxy[q]; hxy[q] = hxy[p]; hxy[p] = txy;
                p = q;
            }
        }
    }

    // where it can stop: popped, and a flyer only where it may land
    int places = 0;
    for (int y = 0; y < H; y++)
        for (int x = 0; x < W; x++)
        {
            int k = x * KX + y * KY;
            int32_t v = -1;
            if ((mark[k] & 1) && !(j->fly && ((mark[k] & 2) || !FITS(x, y))))
            {
                v = dist[k];
                places++;
            }
            cost[k] = v;
        }
    return places;
#undef FITS
#undef BOX
}
