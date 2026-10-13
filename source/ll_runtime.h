// SPDX-License-Identifier: Zlib
//
// LiteLua - cart runtime: Lua state, callbacks and the frame loop.

#ifndef LL_RUNTIME_H__
#define LL_RUNTIME_H__

#include "ll_cart.h"

typedef enum {
    LL_RUN_RESTART, // Run the same cart again (START on the error screen)
    LL_RUN_MENU,    // Back to the cart list
    LL_RUN_NEXT,    // Run ll_sys_take_next_cart() (sys.run)
    LL_RUN_QUIT,    // Quit LiteLua (L+R+START, D32)
    LL_RUN_EDIT,    // Open the code editor at the error (Y on the error screen)
} LLRunResult;

// Runs one session of 'cart' (the built-in demo when NULL) in a new Lua
// state: loads the entry file, calls _init and then the frame loop. Returns
// when the cart stops: after an error has been shown, on sys.run/sys.exit or
// when L+R+B is held. The state is closed before returning (D14).
LLRunResult ll_run(const LLCart *cart);

// Message (with the stack traceback) of the error that ended the last
// session, "" if it ended without one. Valid until the next ll_run.
const char *ll_run_error(void);

// Watchdog (D38), called by the VBlank interrupt: when a callback has been
// running for over a second and L+R+B is held, stops the cart.
void ll_runtime_vblank(void);

#endif // LL_RUNTIME_H__
