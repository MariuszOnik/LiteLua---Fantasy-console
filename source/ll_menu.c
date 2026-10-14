// SPDX-License-Identifier: Zlib
//
// LiteLua - the simple cart list in C (D20): the fallback of the launcher
// (P10) in safe mode (SELECT held at start) or when the launcher fails.
// Lists the folders and .lcart files in litelua/carts: the list is on the
// bottom (touch) screen, the chosen cart and the help on the top one.

#include <dirent.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nds.h>

#include "ll_cart.h"
#include "ll_gfx.h"
#include "ll_menu.h"
#include "ll_sys.h"

#define MAX_CARTS 64
#define ROW_H 10
#define LIST_Y 2
#define VISIBLE_ROWS 19

static int cursor; // Kept between calls (return to the same position, D14)

typedef struct {
    char **names;
    int count, top;
} List;

static const char *label(const List *l, int item)
{
    return item == 0 ? "(built-in demo)" : l->names[item - 1];
}

static void text(int x, int y, const char *s, u32 color)
{
    ll_gfx_text(x, y, s, strlen(s), color);
}

static void draw(int screen, void *ud)
{
    const List *l = ud;
    ll_gfx_cls(0);
    if (screen == 0)
    {
        ll_gfx_rectfill(0, 0, 256, 12, 8);
        text(4, 2, "LiteLua", 4);
        text(52, 2, "carts", 13);

        text(4, 40, label(l, cursor), 12);
        text(4, 52, cursor == 0 ? "built into LiteLua" : "litelua/carts", 14);
        text(4, 100, "Safe mode: the built-in cart list", 3);

        text(4, 130, "Hold L+R+START: quit LiteLua", 14);
        text(4, 140, "Up/Down or touch: choose", 13);
        text(4, 150, "A or touch again: run", 13);
        text(4, 160, "Y: edit the code", 13);
        text(4, 170, "In a game: L+R+B back here", 14);
        text(4, 180, "L+R+Y stats, L+R+X console", 14);
        if (ll_base[0] == '\0')
            text(4, 80, "No SD card: only the demo", 2);
    }
    else
    {
        for (int i = 0; i < VISIBLE_ROWS && l->top + i <= l->count; i++)
        {
            int item = l->top + i, y = LIST_Y + i * ROW_H;
            if (item == cursor)
                ll_gfx_rectfill(0, y, 256, ROW_H, 9);
            text(6, y + 1, label(l, item), item == cursor ? 12 : 13);
        }
    }
}

LLMenuChoice ll_menu_choose(char *name, size_t size)
{
    char *names[MAX_CARTS];
    int count = ll_cart_list_names(names, MAX_CARTS);
    int items = count + 1; // Demo first

    if (cursor >= items)
        cursor = items - 1;

    List list = { names, count, -1 };
    LLMenuChoice choice = LL_MENU_RUN;
    ll_gfx_reset();
    while (1)
    {
        if (cursor < list.top || list.top < 0)
            list.top = cursor;
        if (cursor >= list.top + VISIBLE_ROWS)
            list.top = cursor - VISIBLE_ROWS + 1;

        ll_gfx_frame(draw, &list);
        scanKeys();
        if (ll_sys_quit_poll(keysHeld()))
            ll_sys_quit();
        u32 keys = keysDownRepeat();
        if ((keys & KEY_UP) && cursor > 0)
            cursor--;
        if ((keys & KEY_DOWN) && cursor < items - 1)
            cursor++;
        if (keysDown() & KEY_A)
            break;
        if ((keysDown() & KEY_Y) && cursor > 0) // The demo has no files
        {
            choice = LL_MENU_EDIT;
            break;
        }

        // Touch a row to choose it, touch the chosen row again to run it
        if (keysDown() & KEY_TOUCH)
        {
            touchPosition t;
            touchRead(&t);
            int row = (t.py - LIST_Y) / ROW_H;
            int item = list.top + row;
            if (t.py >= LIST_Y && row < VISIBLE_ROWS && item < items)
            {
                if (item == cursor)
                    break;
                cursor = item;
            }
        }
    }

    if (cursor > 0)
        snprintf(name, size, "%s", names[cursor - 1]);
    else
        choice = LL_MENU_DEMO;

    for (int i = 0; i < count; i++)
        free(names[i]);
    return choice;
}
