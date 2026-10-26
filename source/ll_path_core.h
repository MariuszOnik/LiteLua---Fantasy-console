// SPDX-License-Identifier: Zlib
//
// LiteLua - the path search itself (D57), without Lua: ll_path_core.itcm.arm.c
// runs it as ARM code in ITCM; ll_path.c reads the options and makes the results.

#ifndef LL_PATH_CORE_H__
#define LL_PATH_CORE_H__

#include <stdbool.h>
#include <stdint.h>

#define LL_PATH_CLOSED 1
#define LL_PATH_SLOW 2
#define LL_PATH_MIRE 4

typedef struct {
    // the grid: cells[y * w + x]; result keys are x * kx + y * ky
    int w, h, kx, ky;
    const uint8_t *cells;
    // the mover and the rules
    int x, y, size, budget;
    int nsteps;
    const int32_t *steps;       // dx, dy, cost
    const int32_t *zone_costs;  // one per step
    int nblockers, nzones;
    const int32_t *blockers, *zones; // x, y, size
    bool corners, fly, has_slow, has_mire;
    int slow, mire;
    // work memory, w * h each (sums: (w + 1) * (h + 1)), heap: heap_cap entries
    int32_t *dist, *sums, *msums;
    uint8_t *mark;
    int32_t *heap_c;
    uint32_t *heap_xy;
    int heap_cap;
    // results by key, w * h each: cost (-1 = cannot stop there), parent key (-1 = none)
    int32_t *cost, *parent;
} LLPathJob;

// Runs the search. Returns the number of places in cost, or -1 when the heap
// was too small (grow heap_cap and run again).
int ll_path_search(LLPathJob *j);

#endif // LL_PATH_CORE_H__
