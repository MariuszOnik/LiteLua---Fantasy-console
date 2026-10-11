// SPDX-License-Identifier: Zlib
//
// LiteLua - temporary cart list (D20), replaced by the cart selection cart
// in P10. Lists the folders and .lcart files in litelua/carts: the list is on
// the bottom (touch) screen, the chosen cart and the help on the top one.

#include <dirent.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nds.h>

#include "ll_cart.h"
#include "ll_gfx.h"
#include "ll_menu.h"

#define MAX_CARTS 64
#define ROW_H 10
#define LIST_Y 2
#define VISIBLE_ROWS 19

static int cursor; // Kept between calls (return to the same position, D14)

static int compare_names(const void *a, const void *b)
{
    return strcasecmp(*(const char *const *)a, *(const char *const *)b);
}

// Fills 'names' with the cart folders, sorted. Returns their number.
static int list_carts(char *names[], int max)
{
    int n = 0;
    char path[LL_PATH_MAX];
    snprintf(path, sizeof(path), "%s/carts", ll_base);

    DIR *dir = ll_base[0] ? opendir(path) : NULL;
    if (dir == NULL)
        return 0;

    struct dirent *e;
    while (n < max && (e = readdir(dir)) != NULL)
    {
        if (e->d_name[0] == '.')
            continue;
        if (e->d_type != DT_DIR
            && !(e->d_type == DT_REG && ll_cart_is_file_name(e->d_name)))
            continue;
        if (strlen(e->d_name) >= LL_NAME_MAX)
            continue;
        names[n] = strdup(e->d_name);
        if (names[n])
            n++;
    }
    closedir(dir);

    qsort(names, n, sizeof(names[0]), compare_names);
    return n;
}

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

        text(4, 150, "Up/Down or touch: choose", 13);
        text(4, 160, "A or touch again: run", 13);
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

bool ll_menu_choose(char *name, size_t size)
{
    char *names[MAX_CARTS];
    int count = list_carts(names, MAX_CARTS);
    int items = count + 1; // Demo first

    if (cursor >= items)
        cursor = items - 1;

    List list = { names, count, -1 };
    ll_gfx_reset();
    while (1)
    {
        if (cursor < list.top || list.top < 0)
            list.top = cursor;
        if (cursor >= list.top + VISIBLE_ROWS)
            list.top = cursor - VISIBLE_ROWS + 1;

        ll_gfx_frame(draw, &list);
        scanKeys();
        u32 keys = keysDownRepeat();
        if ((keys & KEY_UP) && cursor > 0)
            cursor--;
        if ((keys & KEY_DOWN) && cursor < items - 1)
            cursor++;
        if (keysDown() & KEY_A)
            break;

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

    bool is_cart = cursor > 0;
    if (is_cart)
        snprintf(name, size, "%s", names[cursor - 1]);

    for (int i = 0; i < count; i++)
        free(names[i]);
    return is_cart;
}
