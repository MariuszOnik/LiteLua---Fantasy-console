// SPDX-License-Identifier: Zlib
//
// LiteLua - performance statistics: sys.stats() and the overlay (L+R+Y).
//
// The runtime measures every game frame (times of the callbacks, polygons and
// vertices of the top screen). Memory is read when asked: Lua memory from the
// allocator, free RAM from the C heap (free blocks + not yet used heap), video
// memory from the image module's counter.

#include <malloc.h>
#include <stdio.h>

#include <nds.h>

#include "lauxlib.h"

#include "ll_image.h"
#include "ll_log.h"
#include "ll_stats.h"

#define FRAME_US 33333  // A game frame at 30 FPS
#define VRAM_TOTAL ((256 + 64) * 1024) // Texture banks A+B and palette bank E

static const LLMem *lua_mem;
static LLFrameStats last;
static bool overlay;
static int fps;
static int fps_frames;
static unsigned long fps_start;

void ll_stats_reset(const LLMem *mem)
{
    lua_mem = mem;
    last = (LLFrameStats){ 0 };
    fps = 0;
    fps_frames = 0;
    fps_start = ll_vblanks();
}

void ll_stats_frame(const LLFrameStats *f)
{
    last = *f;

    // Frames per second over about one second (60 VBlanks)
    fps_frames++;
    unsigned long now = ll_vblanks(), elapsed = now - fps_start;
    if (elapsed >= 60)
    {
        fps = (int)((fps_frames * 60 + elapsed / 2) / elapsed);
        fps_frames = 0;
        fps_start = now;
    }
}

bool ll_stats_overlay(void)
{
    return overlay;
}

void ll_stats_toggle_overlay(void)
{
    overlay = !overlay;
}

static size_t ram_free(void)
{
    struct mallinfo mi = mallinfo();
    return (size_t)(getHeapLimit() - getHeapEnd()) + mi.fordblks;
}

static unsigned frame_us(void)
{
    return last.update_us + last.draw_top_us + last.draw_bottom_us;
}

void ll_stats_overlay_text(char *buf, size_t size)
{
    unsigned draw = last.draw_top_us + last.draw_bottom_us;
    snprintf(buf, size,
             "FPS %d  CPU %u%%\n"
             "upd %u.%u ms\n"
             "drw %u.%u ms\n"
             "Lua %u/%u KB\n"
             "RAM %u KB free\n"
             "VRAM %u/%u KB\n"
             "poly %d vtx %d",
             fps, frame_us() * 100 / FRAME_US,
             last.update_us / 1000, last.update_us / 100 % 10,
             draw / 1000, draw / 100 % 10,
             lua_mem ? (unsigned)(lua_mem->used / 1024) : 0,
             lua_mem ? (unsigned)(lua_mem->limit / 1024) : 0,
             (unsigned)(ram_free() / 1024),
             ll_image_vram_used() / 1024, VRAM_TOTAL / 1024,
             last.polys, last.verts);
}

static void set_int(lua_State *L, const char *key, lua_Integer v)
{
    lua_pushinteger(L, v);
    lua_setfield(L, -2, key);
}

// sys.stats() -> table with the numbers of the last frame and memory use
static int l_stats(lua_State *L)
{
    lua_createtable(L, 0, 16);
    set_int(L, "fps", fps);
    set_int(L, "cpu", frame_us() * 100 / FRAME_US);
    set_int(L, "update_us", last.update_us);
    set_int(L, "draw_us", last.draw_top_us + last.draw_bottom_us);
    set_int(L, "draw_top_us", last.draw_top_us);
    set_int(L, "draw_bottom_us", last.draw_bottom_us);
    set_int(L, "mem", lua_mem ? (lua_Integer)lua_mem->used : 0);
    set_int(L, "mem_peak", lua_mem ? (lua_Integer)lua_mem->peak : 0);
    set_int(L, "mem_limit", lua_mem ? (lua_Integer)lua_mem->limit : 0);
    set_int(L, "ram_free", (lua_Integer)ram_free());
    set_int(L, "vram", ll_image_vram_used());
    set_int(L, "vram_total", VRAM_TOTAL);
    set_int(L, "polys", last.polys);
    set_int(L, "verts", last.verts);
    return 1;
}

void ll_stats_register(lua_State *L)
{
    lua_getglobal(L, "sys");
    lua_pushcfunction(L, l_stats);
    lua_setfield(L, -2, "stats");
    lua_pop(L, 1);
}
