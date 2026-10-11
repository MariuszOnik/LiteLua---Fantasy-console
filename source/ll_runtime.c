// SPDX-License-Identifier: Zlib
//
// LiteLua - cart runtime: Lua state, callbacks and the frame loop.
//
// Callbacks (all optional): _init(), _update(), _draw(screen).
// The game runs at 30 FPS: every game frame takes two VBlanks. The first one
// runs _update() and _draw(TOP), the second one _draw(BOTTOM). In the dual30
// mode (P6) each VBlank renders one screen with the 3D engine.

#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nds.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "ll_cart.h"
#include "ll_error.h"
#include "ll_gfx.h"
#include "ll_input.h"
#include "ll_log.h"
#include "ll_mem.h"
#include "ll_runtime.h"
#include "ll_sandbox.h"
#include "ll_sys.h"

#define SCREEN_TOP 0
#define SCREEN_BOTTOM 1

#define MSGH_INDEX 1 // Message handler is kept at the bottom of the stack

extern const char ll_demo_lua[];

// Hold all of these to leave the cart (until the pause menu of P10)
#define KEYS_LEAVE (KEY_L | KEY_R | KEY_B)

static LLMem lua_mem;
static jmp_buf panic_jmp;
static LLRunResult result;

// Elapsed microseconds since boot (wraps after ~128 s)
static int l_micros(lua_State *L)
{
    lua_pushinteger(L, (lua_Integer)timerTicks2usec(cpuGetTiming()));
    return 1;
}

// Adds a stack traceback to the error message
static int msg_handler(lua_State *L)
{
    const char *msg = lua_tostring(L, 1);
    if (msg == NULL)
    {
        if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING)
            return 1;
        msg = lua_pushfstring(L, "(error object is a %s value)",
                              luaL_typename(L, 1));
    }
    luaL_traceback(L, L, msg, 1);
    return 1;
}

// Unprotected errors should not happen; if one does, the state cannot be used
// anymore. Show it and abandon the state (its memory is leaked).
static int panic_handler(lua_State *L)
{
    const char *msg = lua_tostring(L, -1);
    if (msg == NULL)
        msg = "unprotected error";
    ll_log("PANIC: %s", msg);
    ll_log_flush();
    result = ll_error_show(msg, &lua_mem) ? LL_RUN_RESTART : LL_RUN_MENU;
    longjmp(panic_jmp, 1);
    return 0;
}

static void show_error(lua_State *L)
{
    const char *msg = lua_tostring(L, -1);
    if (msg == NULL)
        msg = "(error object is not a string)";

    ll_log("ERROR (Lua mem %u/%u KB, peak %u KB):",
           (unsigned)(lua_mem.used / 1024), (unsigned)(lua_mem.limit / 1024),
           (unsigned)(lua_mem.peak / 1024));
    ll_log_text(msg, strlen(msg));
    ll_log_flush();

    result = ll_error_show(msg, &lua_mem) ? LL_RUN_RESTART : LL_RUN_MENU;
}

// True if the cart asked to stop (sys.run, sys.exit); sets 'result'.
static bool stop_requested(void)
{
    switch (ll_sys_request())
    {
        case LL_SYS_RUN:
            result = LL_RUN_NEXT;
            return true;
        case LL_SYS_EXIT:
            result = LL_RUN_MENU;
            return true;
        default:
            return false;
    }
}

// Calls global function 'name' if it exists. 'screen' < 0 means no argument.
static bool call_hook(lua_State *L, const char *name, int screen)
{
    if (lua_getglobal(L, name) == LUA_TNIL)
    {
        lua_pop(L, 1);
        return true;
    }

    int nargs = 0;
    if (screen >= 0)
    {
        lua_pushinteger(L, screen);
        nargs = 1;
    }

    if (lua_pcall(L, nargs, 0, MSGH_INDEX) != LUA_OK)
    {
        show_error(L);
        return false;
    }
    return !stop_requested();
}

static void register_api(lua_State *L)
{
    lua_register(L, "micros", l_micros);

    lua_pushinteger(L, SCREEN_TOP);
    lua_setglobal(L, "TOP");
    lua_pushinteger(L, SCREEN_BOTTOM);
    lua_setglobal(L, "BOTTOM");

    ll_input_register(L);
    ll_log_register(L);
    ll_sys_register(L);
    ll_gfx_register(L);
}

// Loads and runs the entry file; the chunk is named after its path in the
// cart ("@main.lua"), so errors show "main.lua:12:" (D13).
static bool load_main(lua_State *L, const LLCart *cart)
{
    int status;
    if (cart)
    {
        size_t len;
        char *src = ll_cart_read(cart, cart->entry, &len);
        if (src == NULL)
        {
            lua_pushfstring(L, "cannot read %s", cart->entry);
            status = LUA_ERRFILE;
        }
        else
        {
            char chunkname[LL_NAME_MAX + 1];
            snprintf(chunkname, sizeof(chunkname), "@%s", cart->entry);
            status = luaL_loadbufferx(L, src, len, chunkname, "t");
            free(src);
        }
    }
    else
    {
        status = luaL_loadbuffer(L, ll_demo_lua, strlen(ll_demo_lua), "=demo");
    }

    if (status == LUA_OK)
        status = lua_pcall(L, 0, 0, MSGH_INDEX);

    if (status != LUA_OK)
    {
        show_error(L);
        return false;
    }
    return !stop_requested();
}

// Waits until the VBlank counter reaches 'target' (no wait if it is past)
static void wait_vblank(unsigned long target)
{
    while ((long)(ll_vblanks() - target) < 0)
        swiWaitForVBlank();
}

// A game frame is two VBlanks. Waiting for VBlank numbers (instead of "the
// next VBlank") lets _update + _draw(TOP) take longer than one VBlank as
// long as the whole frame fits in two; a slower frame just takes three.
static void frame_loop(lua_State *L)
{
    while (1)
    {
        unsigned long start = ll_vblanks();
        ll_input_update();
        if ((keysHeld() & KEYS_LEAVE) == KEYS_LEAVE)
        {
            ll_log("L+R+B: back to the cart list");
            result = LL_RUN_MENU;
            return;
        }
        if (!call_hook(L, "_update", -1))
            return;

        // The frame must be ended (and sent to the 3D engine) also after an
        // error, so the 3D state stays consistent
        ll_gfx_begin(SCREEN_TOP);
        bool ok = call_hook(L, "_draw", SCREEN_TOP);
        ll_gfx_end();
        if (!ok)
            return;
        wait_vblank(start + 1);

        ll_gfx_begin(SCREEN_BOTTOM);
        ok = call_hook(L, "_draw", SCREEN_BOTTOM);
        ll_gfx_end();
        if (!ok)
            return;
        ll_log_flush();
        wait_vblank(start + 2);
    }
}

LLRunResult ll_run(const LLCart *cart)
{
    ll_mem_init(&lua_mem, cart ? cart->mem_limit : LL_MEM_DEFAULT_LIMIT);
    if (cart)
        ll_log("run: %s (carts/%s/%s, id %s, Lua mem limit %u KB)", cart->title,
               cart->name, cart->entry, cart->id,
               (unsigned)(lua_mem.limit / 1024));
    else
        ll_log("run: built-in demo (Lua mem limit %u KB)",
               (unsigned)(lua_mem.limit / 1024));

    result = LL_RUN_RESTART;
    ll_gfx_reset();
    lua_State *L = lua_newstate(ll_mem_alloc, &lua_mem);
    if (L == NULL)
    {
        ll_log("cannot create Lua state");
        return ll_error_show("cannot create Lua state", &lua_mem)
            ? LL_RUN_RESTART : LL_RUN_MENU;
    }

    if (setjmp(panic_jmp) != 0)
    {
        ll_log("Lua state abandoned after panic (%u KB leaked)",
               (unsigned)(lua_mem.used / 1024));
        ll_log_flush();
        return result;
    }
    lua_atpanic(L, panic_handler);

    lua_pushcfunction(L, msg_handler); // MSGH_INDEX
    luaL_openlibs(L);
    ll_sandbox_install(L, cart);
    register_api(L);

    if (load_main(L, cart) && call_hook(L, "_init", -1))
        frame_loop(L);

    lua_close(L);
    if (result != LL_RUN_NEXT)
        ll_sys_discard(); // sys.run followed by an error, or L+R+B

    // Everything must be freed by lua_close; anything left is an allocator bug
    ll_log("closed, peak Lua mem %u KB, left after close: %u bytes",
           (unsigned)(lua_mem.peak / 1024), (unsigned)lua_mem.used);
    ll_log_flush();
    return result;
}
