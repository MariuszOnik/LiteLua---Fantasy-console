// SPDX-License-Identifier: Zlib
//
// LiteLua - temporary cart list (D20), replaced by the cart selection cart
// in P10.

#ifndef LL_MENU_H__
#define LL_MENU_H__

#include <stdbool.h>
#include <stddef.h>

typedef enum {
    LL_MENU_DEMO, // Run the built-in demo
    LL_MENU_RUN,  // Run the cart in 'name' (A)
    LL_MENU_EDIT, // Open the cart in 'name' in the code editor (Y, D42)
} LLMenuChoice;

// Shows the carts in litelua/carts (folders and .lcart files) and the
// built-in demo, and waits for a choice; the cart's name goes to 'name'.
// The cursor position is kept between calls.
LLMenuChoice ll_menu_choose(char *name, size_t size);

#endif // LL_MENU_H__
