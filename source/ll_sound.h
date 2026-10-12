// SPDX-License-Identifier: Zlib
//
// LiteLua - sound (P7): sound effects from WAV files, music from Maxmod
// modules (.mas) or WAV files streamed from the SD card.

#ifndef LL_SOUND_H__
#define LL_SOUND_H__

#include "lua.h"

#include "ll_cart.h"
#include "ll_mem.h"

// Starts Maxmod (without a soundbank). Call once at startup.
void ll_sound_init(void);

// A cart starts: its files and the memory its sounds are counted in.
void ll_sound_begin(const LLCart *cart, LLMem *mem);

// Registers the Lua functions (sound, sfx, sfx_stop, music, music_volume).
void ll_sound_register(lua_State *L);

// Keeps the music stream fed and frees sample data that is no longer
// played. Call every VBlank half of the frame loop.
void ll_sound_update(void);

// Stops the music and all sound effects (before an error screen and before
// the cart's Lua state is closed). Safe to repeat.
void ll_sound_stop_all(void);

// After the Lua state is closed: waits until all sound data is freed.
void ll_sound_end(void);

#endif // LL_SOUND_H__
