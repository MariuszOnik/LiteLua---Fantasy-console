// SPDX-License-Identifier: Zlib
//
// LiteLua - tile maps (P8, D50).

#ifndef LL_MAP_H__
#define LL_MAP_H__

#include "lua.h"

#include "ll_cart.h"

// Registers tilemap() for 'cart' (NULL for the demo). Call after image() is
// registered: tilemap() loads its tilesets through it.
void ll_map_register(lua_State *L, const LLCart *cart);

#endif // LL_MAP_H__
