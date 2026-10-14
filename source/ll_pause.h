// SPDX-License-Identifier: Zlib
//
// LiteLua - pause menu of games (START held for half a second, D27, P10).

#ifndef LL_PAUSE_H__
#define LL_PAUSE_H__

#include <stdbool.h>

typedef enum {
    LL_PAUSE_RESUME,  // Back to the game
    LL_PAUSE_RESTART, // Run the game again
    LL_PAUSE_EDIT,    // Open the code editor with the game's files
    LL_PAUSE_QUIT,    // Leave the game (to the launcher, or the editor)
} LLPauseChoice;

// Shows the pause menu for game 'title' and waits for a choice. "Edit code"
// is offered only when 'can_edit' is set. Keeps the sound fed while it is
// shown (the caller pauses it). On "Resume" it returns only after all keys
// and the stylus are released, so the game does not get the menu's presses.
LLPauseChoice ll_pause_show(const char *title, bool can_edit);

#endif // LL_PAUSE_H__
