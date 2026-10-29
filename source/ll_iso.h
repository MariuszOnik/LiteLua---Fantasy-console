// SPDX-License-Identifier: Zlib
//
// LiteLua - isometric height grid (D58): isogrid(img, cols, rows, [opts]).

#ifndef LL_ISO_H__
#define LL_ISO_H__

#include "lua.h"

#include "ll_gfx.h"

void ll_iso_register(lua_State *L);

// Checks that argument 'idx' is an isogrid; its grid stays valid while the
// isogrid is alive.
const LLIsoGrid *ll_iso_check(lua_State *L, int idx);

#endif // LL_ISO_H__
