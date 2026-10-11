// SPDX-License-Identifier: Zlib
//
// LiteLua - temporary cart list (D20), replaced by the cart selection cart
// in P10.

#ifndef LL_MENU_H__
#define LL_MENU_H__

#include <stddef.h>

// Shows the carts in litelua/carts and the built-in demo, and waits for a
// choice. Returns false for the demo, true with the cart's folder name in
// 'name'. The cursor position is kept between calls.
bool ll_menu_choose(char *name, size_t size);

#endif // LL_MENU_H__
