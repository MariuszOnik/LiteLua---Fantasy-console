// SPDX-License-Identifier: Zlib
//
// LiteLua - Lua allocator with byte accounting and a hard limit.

#include <stdlib.h>

#include "ll_mem.h"

void ll_mem_init(LLMem *m, size_t limit)
{
    m->used = 0;
    m->peak = 0;
    m->limit = limit;
}

void *ll_mem_alloc(void *ud, void *ptr, size_t osize, size_t nsize)
{
    LLMem *m = ud;

    // When ptr is NULL, osize encodes the object type, not a size
    if (ptr == NULL)
        osize = 0;

    if (nsize == 0)
    {
        free(ptr);
        m->used -= osize;
        return NULL;
    }

    // Returning NULL makes Lua run an emergency full GC and retry, then
    // raise a "not enough memory" error.
    if (m->limit != 0 && nsize > osize && m->used - osize + nsize > m->limit)
        return NULL;

    void *p = realloc(ptr, nsize);
    if (p == NULL)
        return NULL;

    m->used = m->used - osize + nsize;
    if (m->used > m->peak)
        m->peak = m->used;
    return p;
}

bool ll_mem_charge(LLMem *m, size_t size)
{
    if (m->limit != 0 && m->used + size > m->limit)
        return false;
    m->used += size;
    if (m->used > m->peak)
        m->peak = m->used;
    return true;
}

void ll_mem_release(LLMem *m, size_t size)
{
    m->used -= size;
}
