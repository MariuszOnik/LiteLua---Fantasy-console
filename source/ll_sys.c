// SPDX-License-Identifier: Zlib
//
// LiteLua - sys module: switching carts (D14).
//
// sys.run and sys.exit only record the request. The runtime closes the Lua
// state after the current callback returns and then starts the next cart in
// a new state, so a cart never runs inside another one.

#include <string.h>

#include "lauxlib.h"

#include "ll_sys.h"

static LLSysRequest request;
static LLCart next_cart;

// sys.run(name): runs the cart litelua/carts/<name> after this callback
static int l_run(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    luaL_argcheck(L, *name && strchr(name, '/') == NULL
                  && strchr(name, '\\') == NULL && strchr(name, ':') == NULL
                  && strcmp(name, ".") != 0 && strcmp(name, "..") != 0,
                  1, "cart name expected (a folder in litelua/carts)");

    char err[160];
    if (!ll_cart_open(&next_cart, name, err, sizeof(err)))
        return luaL_error(L, "sys.run: %s", err);

    request = LL_SYS_RUN;
    return 0;
}

// sys.exit(): back to the cart list after this callback
static int l_exit(lua_State *L)
{
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

    request = LL_SYS_NONE;
    luaL_newlib(L, funcs);
    lua_setglobal(L, "sys");
}

LLSysRequest ll_sys_request(void)
{
    return request;
}

const LLCart *ll_sys_next_cart(void)
{
    return &next_cart;
}
