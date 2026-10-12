// SPDX-License-Identifier: Zlib
//
// LiteLua - sys module: switching carts (D14).

#ifndef LL_SYS_H__
#define LL_SYS_H__

#include <nds.h>

#include "lua.h"

#include "ll_cart.h"

typedef enum {
    LL_SYS_NONE, // Keep running
    LL_SYS_RUN,  // sys.run(name): start another cart
    LL_SYS_EXIT, // sys.exit(): back to the cart list
} LLSysRequest;

// Registers the 'sys' table and clears any pending request.
void ll_sys_register(lua_State *L);

// Request made by the cart; checked by the runtime after every callback.
LLSysRequest ll_sys_request(void);

// Cart requested by sys.run (valid when the request is LL_SYS_RUN). The
// caller takes over the open cart and must close it; the request is cleared.
LLCart ll_sys_take_next_cart(void);

// Drops the request; a cart opened by sys.run is closed.
void ll_sys_discard(void);

// Quits LiteLua when L+R+START has been held for a second (D32): back to the
// loader if it supports it, otherwise the console turns off. Call once per
// frame with keysHeld(), in the game, the cart list and the error screen.
void ll_sys_quit_poll(u32 held);

#endif // LL_SYS_H__
