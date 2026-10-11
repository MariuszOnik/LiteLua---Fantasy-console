// SPDX-License-Identifier: Zlib
//
// LiteLua - text console buffer: the last lines of print() and io.write(),
// shown by the console overlay (L+R+X, D27).

#ifndef LL_CONSOLE_H__
#define LL_CONSOLE_H__

#include <stdbool.h>
#include <stddef.h>

#include "lua.h"

#define LL_CONSOLE_COLS 42 // Characters per line (6x8 font, 256 pixels)

// Appends text: '\n' ends a line, long lines wrap, ANSI escape sequences
// (e.g. "\27[2J") are skipped.
void ll_console_write(const char *s, size_t len);

// Forgets all lines (a new cart starts).
void ll_console_clear(void);

// The overlay stays on or off across carts.
bool ll_console_overlay(void);
void ll_console_toggle_overlay(void);

// The last 'max_lines' lines joined with '\n' (UTF-8).
void ll_console_text(char *buf, size_t size, int max_lines);

// Replaces io.write with a version that writes to the console.
void ll_console_register(lua_State *L);

#endif // LL_CONSOLE_H__
