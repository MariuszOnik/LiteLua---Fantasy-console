// SPDX-License-Identifier: Zlib
//
// LiteLua - input module: buttons and touch screen.

#ifndef LL_INPUT_H__
#define LL_INPUT_H__

#include "lua.h"

// Samples keys and touch; call once per game frame, before _update. Presses
// and releases seen by ll_input_sample since the last frame are included.
void ll_input_update(void);

// Samples the keys between game frames (every VBlank, D51), so a press
// shorter than a game frame is not lost: btnp/btnr see it in the next frame.
void ll_input_sample(void);

// Registers btn, btnp, btnr and touch as globals.
void ll_input_register(lua_State *L);

#endif // LL_INPUT_H__
