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
#include <string.h>

#include <nds.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "ll_error.h"
#include "ll_input.h"
#include "ll_mem.h"
#include "ll_runtime.h"

#define SCREEN_TOP 0
#define SCREEN_BOTTOM 1

#define MSGH_INDEX 1 // Message handler is kept at the bottom of the stack

extern const char ll_demo_lua[];

static LLMem lua_mem;
static jmp_buf panic_jmp;

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
    ll_error_show(msg ? msg : "unprotected error", &lua_mem);
    longjmp(panic_jmp, 1);
    return 0;
}

static void show_error(lua_State *L)
{
    const char *msg = lua_tostring(L, -1);
    ll_error_show(msg ? msg : "(error object is not a string)", &lua_mem);
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
    return true;
}

static void register_api(lua_State *L)
{
    lua_register(L, "micros", l_micros);

    lua_pushinteger(L, SCREEN_TOP);
    lua_setglobal(L, "TOP");
    lua_pushinteger(L, SCREEN_BOTTOM);
    lua_setglobal(L, "BOTTOM");

    ll_input_register(L);
}

static bool load_main(lua_State *L, const char *path)
{
    int status;
    if (path)
        status = luaL_loadfile(L, path);
    else
        status = luaL_loadbuffer(L, ll_demo_lua, strlen(ll_demo_lua), "=demo");

    if (status == LUA_OK)
        status = lua_pcall(L, 0, 0, MSGH_INDEX);

    if (status != LUA_OK)
    {
        show_error(L);
        return false;
    }
    return true;
}

static void frame_loop(lua_State *L)
{
    while (1)
    {
        ll_input_update();
        if (!call_hook(L, "_update", -1))
            return;
        if (!call_hook(L, "_draw", SCREEN_TOP))
            return;
        swiWaitForVBlank();

        if (!call_hook(L, "_draw", SCREEN_BOTTOM))
            return;
        swiWaitForVBlank();
    }
}

void ll_run(const char *path)
{
    ll_mem_init(&lua_mem, LL_MEM_DEFAULT_LIMIT);

    lua_State *L = lua_newstate(ll_mem_alloc, &lua_mem);
    if (L == NULL)
    {
        ll_error_show("cannot create Lua state", &lua_mem);
        return;
    }

    if (setjmp(panic_jmp) != 0)
        return;
    lua_atpanic(L, panic_handler);

    lua_pushcfunction(L, msg_handler); // MSGH_INDEX
    luaL_openlibs(L);
    register_api(L);

    if (load_main(L, path) && call_hook(L, "_init", -1))
        frame_loop(L);

    lua_close(L);
}
