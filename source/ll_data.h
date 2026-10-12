// SPDX-License-Identifier: Zlib
//
// LiteLua - data files in a subset of Lua syntax (D38): cart.lua manifests,
// later .lsong songs (docs/LSONG.md section 8). The text is parsed, never
// run: no loops, functions, calls or expressions can be written, so a
// broken or malicious file can only fail to load, in bounded time.

#ifndef LL_DATA_H__
#define LL_DATA_H__

#include <stdbool.h>
#include <stddef.h>

#include "lua.h"

typedef struct {
    size_t max_size;   // Bytes of the whole text
    int max_depth;     // Nesting of tables
    size_t max_string; // Bytes of one string
} LLDataLimits;

// Parses "return <value>" and pushes the value onto L: tables, strings,
// numbers, true and false; comments; fields "name = v", ["key"] = v or list
// items (a table is a list or a map, not both). Memory comes from L's
// allocator, so its limit also applies. On failure returns false with
// "<name>:<line>: <message>" in 'err' and pushes nothing.
bool ll_data_parse(lua_State *L, const char *text, size_t len, const char *name,
                   const LLDataLimits *limits, char *err, size_t err_size);

#endif // LL_DATA_H__
