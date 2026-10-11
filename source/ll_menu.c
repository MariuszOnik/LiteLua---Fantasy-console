// SPDX-License-Identifier: Zlib
//
// LiteLua - temporary cart list (D20), replaced by the cart selection cart
// in P10. Lists the folders in litelua/carts on the text console.

#include <dirent.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nds.h>

#include "ll_cart.h"
#include "ll_menu.h"

#define MAX_CARTS 64
#define FIRST_ROW 2
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
        if (e->d_type != DT_DIR || e->d_name[0] == '.')
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

static void draw(char *names[], int count, int top)
{
    printf("\x1b[2J\x1b[0;0HLiteLua - carts");
    for (int i = 0; i < VISIBLE_ROWS && top + i <= count; i++)
    {
        int item = top + i;
        const char *label = item == 0 ? "(built-in demo)" : names[item - 1];
        printf("\x1b[%d;0H%c %.29s", FIRST_ROW + i, item == cursor ? '>' : ' ',
               label);
    }
    printf("\x1b[22;0HUp/Down: choose  A: run");
    printf("\x1b[23;0Hcarts: %.24s", ll_base[0] ? "litelua/carts" : "no SD card");
}

bool ll_menu_choose(char *name, size_t size)
{
    char *names[MAX_CARTS];
    int count = list_carts(names, MAX_CARTS);
    int items = count + 1; // Demo first

    if (cursor >= items)
        cursor = items - 1;

    int top = -1;
    bool redraw = true;
    while (1)
    {
        if (cursor < top || top < 0)
            top = cursor, redraw = true;
        if (cursor >= top + VISIBLE_ROWS)
            top = cursor - VISIBLE_ROWS + 1, redraw = true;
        if (redraw)
            draw(names, count, top);
        redraw = false;

        swiWaitForVBlank();
        scanKeys();
        u32 keys = keysDownRepeat();
        if ((keys & KEY_UP) && cursor > 0)
            cursor--, redraw = true;
        if ((keys & KEY_DOWN) && cursor < items - 1)
            cursor++, redraw = true;
        if (keysDown() & KEY_A)
            break;
    }

    bool is_cart = cursor > 0;
    if (is_cart)
        snprintf(name, size, "%s", names[cursor - 1]);

    for (int i = 0; i < count; i++)
        free(names[i]);
    consoleClear();
    return is_cart;
}
