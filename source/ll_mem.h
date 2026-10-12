// SPDX-License-Identifier: Zlib
//
// LiteLua - Lua allocator with byte accounting and a hard limit.

#ifndef LL_MEM_H__
#define LL_MEM_H__

#include <stdbool.h>
#include <stddef.h>

// Default Lua heap limit. The same on DS and DSi so carts stay portable;
// a cart may ask for more in its manifest (P3).
#define LL_MEM_DEFAULT_LIMIT (2 * 1024 * 1024)

typedef struct {
    size_t used;  // Bytes currently allocated by Lua
    size_t peak;  // Highest value of 'used'
    size_t limit; // Allocations that would exceed this fail (0 = no limit)
} LLMem;

void ll_mem_init(LLMem *m, size_t limit);

// lua_Alloc implementation; 'ud' must point to an LLMem.
void *ll_mem_alloc(void *ud, void *ptr, size_t osize, size_t nsize);

// Memory of the cart allocated outside Lua (sound data, P7) is counted in the
// same limit. Returns false if 'size' more bytes would exceed it.
bool ll_mem_charge(LLMem *m, size_t size);
void ll_mem_release(LLMem *m, size_t size);

#endif // LL_MEM_H__
