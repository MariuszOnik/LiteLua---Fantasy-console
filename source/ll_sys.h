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
    LL_SYS_DEMO, // sys.system.demo(): run the built-in demo
} LLSysRequest;

// Registers the 'sys' table for 'cart' (NULL for the demo) and clears any
// pending request. System carts also get sys.system.
void ll_sys_register(lua_State *L, const LLCart *cart);

// Most items a game can add to the pause menu with sys.menu, and the
// longest label (bytes)
#define LL_MENU_ITEMS 3
#define LL_MENU_LABEL_MAX 20

// Labels of the game's pause menu items (sys.menu): fills 'labels' (each
// LL_MENU_LABEL_MAX + 1 bytes) and returns their number.
int ll_sys_menu_labels(lua_State *L, char labels[][LL_MENU_LABEL_MAX + 1]);

// Pushes the function of the game's pause menu item 'index' (0-based).
void ll_sys_menu_push(lua_State *L, int index);

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
