// SPDX-License-Identifier: Zlib
//
// LiteLua - file sandbox of a cart (D6, D20).

#ifndef LL_SANDBOX_H__
#define LL_SANDBOX_H__

#include "lua.h"

#include "ll_cart.h"

// Replaces io.open, io.lines/input/output, os.remove/rename, load, loadfile,
// dofile and require with versions limited to the cart's files and its save
// folder, and removes the rest of io/os/package that reaches outside.
// 'cart' is NULL for the built-in demo (no file access). Call after
// luaL_openlibs; 'cart' must stay valid while the state is used.
void ll_sandbox_install(lua_State *L, const LLCart *cart);

#endif // LL_SANDBOX_H__
