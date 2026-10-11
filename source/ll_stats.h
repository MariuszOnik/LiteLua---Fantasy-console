// SPDX-License-Identifier: Zlib
//
// LiteLua - performance statistics: sys.stats() and the overlay (L+R+Y).

#ifndef LL_STATS_H__
#define LL_STATS_H__

#include <stdbool.h>
#include <stddef.h>

#include "lua.h"

#include "ll_mem.h"

typedef struct {
    unsigned update_us;      // _update()
    unsigned draw_top_us;    // _draw(TOP)
    unsigned draw_bottom_us; // _draw(BOTTOM)
    int polys_top, verts_top;       // Sent to the 3D engine, top screen
    int polys_bottom, verts_bottom; // and bottom screen
} LLFrameStats;

// Starts counting for a new cart; 'mem' is its Lua allocator.
void ll_stats_reset(const LLMem *mem);

// Records a finished game frame.
void ll_stats_frame(const LLFrameStats *f);

// The overlay stays on or off across carts until the console is turned off.
bool ll_stats_overlay(void);
void ll_stats_toggle_overlay(void);

// Text of the overlay (several lines).
void ll_stats_overlay_text(char *buf, size_t size);

// Adds stats() to the 'sys' table (call after ll_sys_register).
void ll_stats_register(lua_State *L);

#endif // LL_STATS_H__
