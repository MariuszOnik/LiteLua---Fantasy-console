// SPDX-License-Identifier: Zlib
//
// LiteLua - cart runtime: Lua state, callbacks and the frame loop.
//
// Callbacks (all optional): _init(), _update(), _draw(screen), _quit().
// The game runs at 30 FPS: every game frame takes two VBlanks, one per
// screen (dual30, D28): _draw(TOP) in the first, _draw(BOTTOM) and the
// next _update() in the second.

#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nds.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "ll_cart.h"
#include "ll_console.h"
#include "ll_error.h"
#include "ll_gfx.h"
#include "ll_image.h"
#include "ll_input.h"
#include "ll_log.h"
#include "ll_map.h"
#include "ll_mem.h"
#include "ll_runtime.h"
#include "ll_sandbox.h"
#include "ll_sound.h"
#include "ll_stats.h"
#include "ll_sys.h"

#define SCREEN_TOP 0
#define SCREEN_BOTTOM 1

#define MSGH_INDEX 1 // Message handler is kept at the bottom of the stack

extern const char ll_demo_lua[];

// Hold all of these to leave the cart (until the pause menu of P10)
#define KEYS_LEAVE (KEY_L | KEY_R | KEY_B)
// L+R held, then Y: statistics overlay on/off, X: console overlay on/off
#define KEYS_OVERLAY (KEY_L | KEY_R)

static unsigned elapsed_us(u32 start_ticks)
{
    return timerTicks2usec(cpuGetTiming() - start_ticks);
}

static LLMem lua_mem;
static jmp_buf panic_jmp;
static LLRunResult result;
static bool failed; // The cart stopped with an error: no _quit
static const LLCart *run_cart; // NULL for the demo
static char last_error[2048];

const char *ll_run_error(void)
{
    return last_error;
}

// Shows the error screen and sets 'result' from the choice. Errors of the
// demo and of system carts (the editor itself) cannot be edited.
static void error_screen(const char *msg)
{
    snprintf(last_error, sizeof(last_error), "%s", msg);
    bool can_edit = run_cart != NULL && !run_cart->system;
    switch (ll_error_show(msg, &lua_mem, can_edit))
    {
        case LL_ERROR_RESTART:
            result = LL_RUN_RESTART;
            break;
        case LL_ERROR_BACK:
            result = LL_RUN_MENU;
            break;
        case LL_ERROR_EDIT:
            result = LL_RUN_EDIT;
            break;
    }
}

#define QUIT_TIME_US 1000000 // Time limit of _quit
static u32 quit_start;

// Watchdog (D38): a callback that runs for over a second while L+R+B is held
// (an endless loop, for example) is stopped. The VBlank interrupt checks it
// and only then sets a Lua hook (lua_sethook may be called asynchronously,
// like lua.c does for Ctrl+C), so normal code runs without any hook cost: a
// permanent count hook would slow down every Lua instruction.
#define WATCHDOG_US 1000000
static lua_State *volatile watch_L; // Running a callback, or NULL
static volatile u32 watch_start;    // cpuGetTiming at the callback start
static volatile bool watch_stopped;

static void watchdog_hook(lua_State *L, lua_Debug *ar)
{
    (void)ar;
    luaL_error(L, "stopped with L+R+B: the game did not return for over a second");
}

void ll_runtime_vblank(void)
{
    lua_State *L = watch_L;
    if (L == NULL || watch_stopped
        || timerTicks2usec(cpuGetTiming() - watch_start) < WATCHDOG_US)
        return;
    u32 keys = ~REG_KEYINPUT;
    if ((keys & (KEY_L | KEY_R | KEY_B)) != (KEY_L | KEY_R | KEY_B))
        return;
    watch_stopped = true;
    // Every instruction from now on raises the error, so a pcall in the game
    // cannot keep it running
    lua_sethook(L, watchdog_hook, LUA_MASKCOUNT, 1);
}

// Runs a protected call of the function below 'nargs' arguments, watched
static int watched_pcall(lua_State *L, int nargs, int nresults)
{
    watch_start = cpuGetTiming();
    watch_L = L;
    int status = lua_pcall(L, nargs, nresults, MSGH_INDEX);
    watch_L = NULL;
    return status;
}

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
    failed = true;
    ll_sound_stop_all();
    ll_log("PANIC: %s", msg);
    ll_log_flush();
    error_screen(msg);
    longjmp(panic_jmp, 1);
    return 0;
}

static void show_error(lua_State *L)
{
    const char *msg = lua_tostring(L, -1);
    if (msg == NULL)
        msg = "(error object is not a string)";
    failed = true;
    ll_sound_stop_all();

    if (watch_stopped)
    {
        // Not an error of the game's logic: back to the list, no error screen
        ll_log("watchdog: %s", msg);
        ll_log_flush();
        result = LL_RUN_MENU;
        return;
    }

    ll_log("ERROR (Lua mem %u/%u KB, peak %u KB):",
           (unsigned)(lua_mem.used / 1024), (unsigned)(lua_mem.limit / 1024),
           (unsigned)(lua_mem.peak / 1024));
    ll_log_text(msg, strlen(msg));
    ll_log_flush();

    error_screen(msg);
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

    if (watched_pcall(L, nargs, 0) != LUA_OK)
    {
        show_error(L);
        return false;
    }
    return !stop_requested();
}

// Stops a _quit that runs too long, so it cannot block leaving the cart
static void quit_time_hook(lua_State *L, lua_Debug *ar)
{
    (void)ar;
    if (elapsed_us(quit_start) > QUIT_TIME_US)
        luaL_error(L, "_quit took longer than 1 s");
}

// _quit(): the cart is closed without an error (L+R+B, L+R+START, sys.exit,
// sys.run), e.g. to save the game (D33). Errors only go to the log; the cart
// is closed anyway.
static void call_quit(lua_State *L)
{
    if (lua_getglobal(L, "_quit") == LUA_TNIL)
    {
        lua_pop(L, 1);
        return;
    }
    // The cart is already leaving: sys.run and sys.exit cannot change that
    if (lua_getglobal(L, "sys") == LUA_TTABLE)
    {
        lua_pushnil(L);
        lua_setfield(L, -2, "run");
        lua_pushnil(L);
        lua_setfield(L, -2, "exit");
    }
    lua_pop(L, 1);

    quit_start = cpuGetTiming();
    lua_sethook(L, quit_time_hook, LUA_MASKCOUNT, 1000);
    if (lua_pcall(L, 0, 0, MSGH_INDEX) != LUA_OK)
    {
        const char *msg = lua_tostring(L, -1);
        ll_log("_quit failed:");
        ll_log_text(msg ? msg : "?", msg ? strlen(msg) : 1);
        lua_pop(L, 1);
    }
    lua_sethook(L, NULL, 0, 0);
}

static void register_api(lua_State *L, const LLCart *cart)
{
    lua_register(L, "micros", l_micros);

    lua_pushinteger(L, SCREEN_TOP);
    lua_setglobal(L, "TOP");
    lua_pushinteger(L, SCREEN_BOTTOM);
    lua_setglobal(L, "BOTTOM");

    ll_input_register(L);
    ll_log_register(L);
    ll_sys_register(L, cart);
    ll_stats_register(L);
    ll_gfx_register(L);
    ll_image_register(L);
    ll_map_register(L, cart);
    ll_sound_register(L);
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
            const char *code = ll_skip_bom(src, &len);
            status = luaL_loadbufferx(L, code, len, chunkname, "t");
            free(src);
        }
    }
    else
    {
        status = luaL_loadbuffer(L, ll_demo_lua, strlen(ll_demo_lua), "=demo");
    }

    if (status == LUA_OK)
        status = watched_pcall(L, 0, 0);

    if (status != LUA_OK)
    {
        show_error(L);
        return false;
    }
    return !stop_requested();
}

// Reads the buttons and handles the system combinations. Returns false if
// the cart must stop (L+R+B).
static bool read_input(void)
{
    ll_input_update();
    u32 held = keysHeld(), down = keysDown();
    if (ll_sys_quit_poll(held))
    {
        result = LL_RUN_QUIT;
        return false;
    }
    if ((held & KEYS_LEAVE) == KEYS_LEAVE)
    {
        ll_log("L+R+B: back to the cart list");
        result = LL_RUN_MENU;
        return false;
    }
    if ((held & KEYS_OVERLAY) == KEYS_OVERLAY && (down & KEY_Y))
        ll_stats_toggle_overlay();
    if ((held & KEYS_OVERLAY) == KEYS_OVERLAY && (down & KEY_X))
        ll_console_toggle_overlay();
    return true;
}

// Calls _draw(screen) inside a 3D frame of that screen. The frame is ended
// (sent to the 3D engine) also after an error, so the 3D state stays valid.
static bool draw_screen(lua_State *L, int screen, unsigned *us)
{
    static char overlay[2048];
    const char *text = NULL;
    if (screen == SCREEN_TOP && ll_stats_overlay())
    {
        ll_stats_overlay_text(overlay, sizeof(overlay));
        text = overlay;
    }
    else if (screen == SCREEN_BOTTOM && ll_console_overlay())
    {
        ll_console_text(overlay, sizeof(overlay), 23);
        text = overlay;
    }

    u32 t0 = cpuGetTiming();
    ll_gfx_begin(screen);
    bool ok = call_hook(L, "_draw", screen);
    *us = elapsed_us(t0);
    ll_gfx_end(text);
    return ok;
}

// A game frame is two VBlanks, one per screen (dual30, D28): the 3D engine
// renders one screen per VBlank, so the frame of each screen has to be sent
// before its VBlank. The first half runs _draw(TOP); the second half
// _draw(BOTTOM) and then input and _update for the next frame, which spreads
// the work over both halves. A late half only delays the frame; the screens
// keep their last image.
static void frame_loop(lua_State *L)
{
    LLFrameStats fs = { 0 };
    u32 t0 = cpuGetTiming();
    if (!read_input() || !call_hook(L, "_update", -1))
        return;
    fs.update_us = elapsed_us(t0);

    while (1)
    {
        bool ok = draw_screen(L, SCREEN_TOP, &fs.draw_top_us);
        ll_gfx_counts(SCREEN_TOP, &fs.polys_top, &fs.verts_top);
        if (!ok)
            return;
        ll_sound_update();
        swiWaitForVBlank();

        ok = draw_screen(L, SCREEN_BOTTOM, &fs.draw_bottom_us);
        ll_gfx_counts(SCREEN_BOTTOM, &fs.polys_bottom, &fs.verts_bottom);
        if (!ok)
            return;
        ll_stats_frame(&fs);
        ll_log_flush();

        t0 = cpuGetTiming();
        if (!read_input() || !call_hook(L, "_update", -1))
            return;
        fs.update_us = elapsed_us(t0);
        ll_sound_update();
        swiWaitForVBlank();
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
    run_cart = cart;
    last_error[0] = '\0';
    failed = false;
    watch_stopped = false;
    ll_gfx_reset();
    ll_console_clear();
    ll_stats_reset(&lua_mem);
    ll_image_reset(cart);
    ll_gfx_font_reset();
    ll_sound_begin(cart, &lua_mem);
    lua_State *L = lua_newstate(ll_mem_alloc, &lua_mem);
    if (L == NULL)
    {
        ll_log("cannot create Lua state");
        error_screen("cannot create Lua state");
        return result;
    }

    if (setjmp(panic_jmp) != 0)
    {
        ll_log("Lua state abandoned after panic (%u KB leaked)",
               (unsigned)(lua_mem.used / 1024));
        ll_log_flush();
        ll_sound_end(); // Sounds of the abandoned state stay allocated too
        return result;
    }
    lua_atpanic(L, panic_handler);

    lua_pushcfunction(L, msg_handler); // MSGH_INDEX
    luaL_openlibs(L);
    ll_sandbox_install(L, cart);
    ll_console_register(L);
    register_api(L, cart);

    if (load_main(L, cart) && call_hook(L, "_init", -1))
        frame_loop(L);
    if (!failed)
        call_quit(L);

    ll_sound_stop_all();
    lua_close(L);
    ll_sound_end(); // Frees sounds collected by lua_close
    if (result != LL_RUN_NEXT)
        ll_sys_discard(); // sys.run followed by an error, or L+R+B

    // Everything must be freed by lua_close; anything left is an allocator bug
    ll_log("closed, peak Lua mem %u KB, left after close: %u bytes",
           (unsigned)(lua_mem.peak / 1024), (unsigned)lua_mem.used);
    ll_log_flush();
    return result;
}
