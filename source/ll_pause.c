// SPDX-License-Identifier: Zlib
//
// LiteLua - pause menu of games (D27, P10): the game's title and help on
// the top screen, the choices as large buttons on the bottom (touch) screen.
// The game is stopped meanwhile: no _update or _draw is called.

#include <string.h>

#include <nds.h>

#include "ll_gfx.h"
#include "ll_pause.h"
#include "ll_sound.h"
#include "ll_sys.h"

#define ITEM_X 32
#define ITEM_W 192
#define ITEM_H 30
#define MAX_ITEMS 7

typedef struct {
    const char *title;
    const char *labels[MAX_ITEMS];
    LLPauseChoice choices[MAX_ITEMS];
    int items[MAX_ITEMS]; // Index of a game's item
    int count, cursor, step;
} Menu;

static void text(int x, int y, const char *s, u32 color)
{
    ll_gfx_text(x, y, s, strlen(s), color);
}

static void text_centered(int y, const char *s, u32 color)
{
    // The built-in font is 6 pixels wide (ASCII; a longer UTF-8 title is
    // only a little off center)
    int w = (int)strlen(s) * 6;
    text(w < 256 ? (256 - w) / 2 : 0, y, s, color);
}

static int item_y(const Menu *m, int i)
{
    int top = (192 - (m->count - 1) * m->step - ITEM_H) / 2;
    return top + i * m->step;
}

static void draw(int screen, void *ud)
{
    const Menu *m = ud;
    ll_gfx_cls(0);
    if (screen == 0)
    {
        ll_gfx_rectfill(0, 0, 256, 12, 8);
        text(4, 2, "Paused", 4);
        text_centered(70, m->title, 12);
        text(4, 150, "Up/Down and A, or touch: choose", 13);
        text(4, 160, "START or B: back to the game", 13);
        text(4, 176, "Hold L+R+START: quit LiteLua", 14);
    }
    else
    {
        for (int i = 0; i < m->count; i++)
        {
            int y = item_y(m, i);
            bool sel = i == m->cursor;
            ll_gfx_rectfill(ITEM_X, y, ITEM_W, ITEM_H, sel ? 9 : 15);
            int w = (int)strlen(m->labels[i]) * 6;
            text(ITEM_X + (ITEM_W - w) / 2, y + 11, m->labels[i], sel ? 12 : 13);
        }
    }
}

// Item under the stylus, or -1
static int touched_item(const Menu *m)
{
    touchPosition t;
    touchRead(&t);
    for (int i = 0; i < m->count; i++)
    {
        int y = item_y(m, i);
        if (t.px >= ITEM_X && t.px < ITEM_X + ITEM_W && t.py >= y
            && t.py < y + ITEM_H)
            return i;
    }
    return -1;
}

static void add(Menu *m, const char *label, LLPauseChoice choice, int item)
{
    m->labels[m->count] = label;
    m->items[m->count] = item;
    m->choices[m->count++] = choice;
}

static void frame(Menu *m)
{
    ll_gfx_frame(draw, m);
    ll_sound_update();
    scanKeys();
    if (ll_sys_quit_poll(keysHeld()))
        ll_sys_quit();
}

LLPauseChoice ll_pause_show(const char *title, bool can_edit,
                            const char *const labels[], int count, int *item)
{
    static Menu m;
    m = (Menu){ .title = title };
    add(&m, "Resume", LL_PAUSE_RESUME, 0);
    for (int i = 0; i < count && m.count < MAX_ITEMS - 3; i++)
        add(&m, labels[i], LL_PAUSE_ITEM, i);
    add(&m, "Restart", LL_PAUSE_RESTART, 0);
    if (can_edit)
        add(&m, "Edit code", LL_PAUSE_EDIT, 0);
    add(&m, "Quit game", LL_PAUSE_QUIT, 0);
    // Up to 4 items fit with large gaps; more are closer together
    m.step = m.count <= 4 ? 38 : (192 - 8 - ITEM_H) / (m.count - 1);

    // The frame the game sent last is shown at the next VBlank; the menu's
    // frames then alternate screens from the top one
    swiWaitForVBlank();

    // START opened the menu: it counts again only after it is released
    bool start_armed = false;
    int touch_item = -1; // A touch on an item chooses it when released there
    LLPauseChoice choice;
    while (1)
    {
        frame(&m);
        u32 down = keysDown(), held = keysHeld(), rep = keysDownRepeat();
        if (!(held & KEY_START))
            start_armed = true;
        bool lr = (held & (KEY_L | KEY_R)) == (KEY_L | KEY_R); // L+R+START: quit

        if ((rep & KEY_UP) && m.cursor > 0)
            m.cursor--;
        if ((rep & KEY_DOWN) && m.cursor < m.count - 1)
            m.cursor++;
        if (down & KEY_A)
        {
            choice = m.choices[m.cursor];
            *item = m.items[m.cursor];
            break;
        }
        if ((down & KEY_B) || (start_armed && !lr && (down & KEY_START)))
        {
            choice = LL_PAUSE_RESUME;
            break;
        }

        if (held & KEY_TOUCH)
        {
            int i = touched_item(&m);
            if (down & KEY_TOUCH)
                touch_item = i;
            if (touch_item >= 0)
                m.cursor = touch_item;
            if (i != touch_item)
                touch_item = -1; // Slid off the item: cancelled
        }
        else if (touch_item >= 0)
        {
            choice = m.choices[touch_item];
            *item = m.items[touch_item];
            break;
        }
    }

    // Back to the game only with nothing held, so it does not see the menu's
    // buttons or stylus as its own presses
    if (choice == LL_PAUSE_RESUME || choice == LL_PAUSE_ITEM)
        while (keysHeld() & ~KEY_LID)
            frame(&m);
    return choice;
}
