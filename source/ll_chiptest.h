// SPDX-License-Identifier: Zlib
//
// LiteLua - S0 hardware test of live chiptune synthesis (D40). Experimental:
// a fixed song played by a sequencer in a timer interrupt on the DS sound
// channels. Replaced by the real sequencer in P18 S1.

#ifndef LL_CHIPTEST_H__
#define LL_CHIPTEST_H__

#include "lua.h"

// Registers the experimental table 'chiptest' (start, stop, stats).
void ll_chiptest_register(lua_State *L);

// Stops the test (cart end, error screen). Safe to repeat.
void ll_chiptest_stop(void);

#endif // LL_CHIPTEST_H__
