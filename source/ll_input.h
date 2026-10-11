// SPDX-License-Identifier: Zlib
//
// LiteLua - input module: buttons and touch screen.

#ifndef LL_INPUT_H__
#define LL_INPUT_H__

#include "lua.h"

// Samples keys and touch; call once per game frame, before _update.
void ll_input_update(void);

// Registers btn, btnp, btnr and touch as globals.
void ll_input_register(lua_State *L);

#endif // LL_INPUT_H__
