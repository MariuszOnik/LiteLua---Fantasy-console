// SPDX-License-Identifier: Zlib
//
// LiteLua - sys module: switching carts (D14).
//
// sys.run and sys.exit only record the request. The runtime closes the Lua
// state after the current callback returns and then starts the next cart in
// a new state, so a cart never runs inside another one.

#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"

#include "ll_log.h"
#include "ll_sys.h"

static LLSysRequest request;
static LLCart next_cart;

// Closes a cart opened by sys.run that will not be started
void ll_sys_discard(void)
{
    if (request == LL_SYS_RUN)
        ll_cart_close(&next_cart);
    request = LL_SYS_NONE;
}

// sys.run(name): runs the cart litelua/carts/<name> after this callback
static int l_run(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    luaL_argcheck(L, *name && strchr(name, '/') == NULL
                  && strchr(name, '\\') == NULL && strchr(name, ':') == NULL
                  && strcmp(name, ".") != 0 && strcmp(name, "..") != 0,
                  1, "cart name expected (a folder or .lcart in litelua/carts)");

    ll_sys_discard(); // An earlier sys.run in the same callback
    char err[160];
    if (!ll_cart_open(&next_cart, name, err, sizeof(err)))
        return luaL_error(L, "sys.run: %s", err);

    request = LL_SYS_RUN;
    return 0;
}

// sys.exit(): back to the cart list after this callback
static int l_exit(lua_State *L)
{
    ll_sys_discard();
    request = LL_SYS_EXIT;
    return 0;
}

void ll_sys_register(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        { "run", l_run },
        { "exit", l_exit },
        { NULL, NULL },
    };

    ll_sys_discard();
    luaL_newlib(L, funcs);
    lua_setglobal(L, "sys");
}

LLSysRequest ll_sys_request(void)
{
    return request;
}

LLCart ll_sys_take_next_cart(void)
{
    request = LL_SYS_NONE; // The caller owns the open cart now
    return next_cart;
}

#define KEYS_QUIT (KEY_L | KEY_R | KEY_START)
#define QUIT_HOLD_VBLANKS 60 // One second

void ll_sys_quit_poll(u32 held)
{
    static bool holding;
    static unsigned long since;

    if ((held & KEYS_QUIT) != KEYS_QUIT)
    {
        holding = false;
        return;
    }
    if (!holding)
    {
        holding = true;
        since = ll_vblanks();
        return;
    }
    if (ll_vblanks() - since >= QUIT_HOLD_VBLANKS)
    {
        ll_log("L+R+START: quit LiteLua");
        ll_log_flush();
        // exit() closes the open files (log, cart archive) and returns to
        // the loader through its boot stub, or turns the console off
        exit(0);
    }
}
