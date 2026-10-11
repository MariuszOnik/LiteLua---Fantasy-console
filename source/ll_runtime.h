// SPDX-License-Identifier: Zlib
//
// LiteLua - cart runtime: Lua state, callbacks and the frame loop.

#ifndef LL_RUNTIME_H__
#define LL_RUNTIME_H__

// Runs one session: creates a Lua state, loads 'path' (or the built-in demo
// when NULL), calls _init and then the frame loop. Returns after an error has
// been shown on the error screen, so the caller can restart.
void ll_run(const char *path);

#endif // LL_RUNTIME_H__
