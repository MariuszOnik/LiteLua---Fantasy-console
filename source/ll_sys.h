// SPDX-License-Identifier: Zlib
//
// LiteLua - sys module: switching carts (D14), system carts (D27, D42).

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

// Registers the 'sys' table for 'cart' (NULL for the demo) and clears any
// pending request. System carts also get sys.system.
void ll_sys_register(lua_State *L, const LLCart *cart);

// Request made by the cart; checked by the runtime after every callback.
LLSysRequest ll_sys_request(void);

// Cart requested by sys.run (valid when the request is LL_SYS_RUN). The
// caller takes over the open cart and must close it; the request is cleared.
LLCart ll_sys_take_next_cart(void);

// Drops the request; a cart opened by sys.run is closed.
void ll_sys_discard(void);

// The code editor opened from the cart list for cart 'name' (Y): it gets
// sys.system.start = { reason = "edit", cart = name }. Forgets any return.
void ll_sys_start_edit(const char *name);

// A cart was chosen on the list: forgets any return to a system cart.
void ll_sys_forget(void);

// Game 'game' has ended: back to the list (error NULL) or with the error
// message for the editor (Y on the error screen). Returns true with the
// system cart to open in 'caller' when one started the game with
// sys.system.run (or always for an error: the code editor), and prepares
// its sys.system.start.
bool ll_sys_back(const char *game, const char *error, char *caller,
                 size_t size);

// True when L+R+START has been held for a second (D32). Call once per frame
// with keysHeld(), in the game, the cart list and the error screen.
bool ll_sys_quit_poll(u32 held);

// Quits LiteLua (D32): back to the loader if it supports it, otherwise the
// console turns off. A running cart gets _quit() first (in the runtime).
void ll_sys_quit(void) __attribute__((noreturn));

#endif // LL_SYS_H__
