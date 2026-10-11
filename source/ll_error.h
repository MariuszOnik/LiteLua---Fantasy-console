// SPDX-License-Identifier: Zlib
//
// LiteLua - error screen.

#ifndef LL_ERROR_H__
#define LL_ERROR_H__

#include "ll_mem.h"

// Shows the error message and stack traceback (as produced by
// luaL_traceback) and waits for START. 'mem' may be NULL.
void ll_error_show(const char *err, const LLMem *mem);

#endif // LL_ERROR_H__
