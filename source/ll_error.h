// SPDX-License-Identifier: Zlib
//
// LiteLua - error screen.

#ifndef LL_ERROR_H__
#define LL_ERROR_H__

#include <stdbool.h>

#include "ll_mem.h"

// Shows the error message and stack traceback (as produced by
// luaL_traceback) and waits for START (returns true: restart the cart) or
// SELECT (returns false: back to the cart list). 'mem' may be NULL.
bool ll_error_show(const char *err, const LLMem *mem);

#endif // LL_ERROR_H__
