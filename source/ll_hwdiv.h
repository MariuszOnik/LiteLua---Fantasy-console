// SPDX-License-Identifier: Zlib
//
// LiteLua - 32-bit integer division with the DS hardware divider.
//
// Used by the Lua VM for integer '//' and '%' (D19). One division gives both
// the quotient and the remainder (~18 cycles instead of a libgcc call).
// The divider is not saved by interrupt handlers, so IRQ code must not use it.

#ifndef LL_HWDIV_H__
#define LL_HWDIV_H__

#include <stdint.h>

#include <nds/arm9/math.h>

// Returns num / den (truncated, like C) and stores num % den in *rem.
// den must not be 0, and num / den must not overflow (INT32_MIN / -1).
static inline int32_t ll_hwdiv(int32_t num, int32_t den, int32_t *rem)
{
    REG_DIVCNT = DIV_32_32;
    REG_DIV_NUMER_L = num;
    REG_DIV_DENOM_L = den;

    while (REG_DIVCNT & DIV_BUSY)
        ;

    *rem = REG_DIVREM_RESULT_L;
    return REG_DIV_RESULT_L;
}

#endif // LL_HWDIV_H__
