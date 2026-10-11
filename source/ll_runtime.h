// SPDX-License-Identifier: Zlib
//
// LiteLua - cart runtime: Lua state, callbacks and the frame loop.

#ifndef LL_RUNTIME_H__
#define LL_RUNTIME_H__

#include "ll_cart.h"

typedef enum {
    LL_RUN_RESTART, // Run the same cart again (START on the error screen)
    LL_RUN_MENU,    // Back to the cart list
    LL_RUN_NEXT,    // Run ll_sys_next_cart() (sys.run)
} LLRunResult;

// Runs one session of 'cart' (the built-in demo when NULL) in a new Lua
// state: loads the entry file, calls _init and then the frame loop. Returns
// when the cart stops: after an error has been shown, on sys.run/sys.exit or
// when L+R+START+SELECT is held. The state is closed before returning (D14).
LLRunResult ll_run(const LLCart *cart);

#endif // LL_RUNTIME_H__
