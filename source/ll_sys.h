// SPDX-License-Identifier: Zlib
//
// LiteLua - sys module: switching carts (D14).

#ifndef LL_SYS_H__
#define LL_SYS_H__

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

#endif // LL_SYS_H__
