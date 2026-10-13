// SPDX-License-Identifier: Zlib
//
// LiteLua - error screen.

#ifndef LL_ERROR_H__
#define LL_ERROR_H__

#include <stdbool.h>

#include "ll_mem.h"

typedef enum {
    LL_ERROR_RESTART, // START: run the cart again
    LL_ERROR_BACK,    // SELECT: back to the cart list (or the editor)
    LL_ERROR_EDIT,    // Y: open the code editor at the error (D13, D42)
} LLErrorChoice;

// Shows the error message and stack traceback (as produced by
// luaL_traceback) and waits for a choice. Y (edit) is offered only when
// 'can_edit' is set. 'mem' may be NULL.
LLErrorChoice ll_error_show(const char *err, const LLMem *mem, bool can_edit);

#endif // LL_ERROR_H__
