// SPDX-License-Identifier: Zlib
//
// LiteLua - text console buffer: the last lines of print() and io.write(),
// shown by the console overlay (L+R+X, D27).
//
// Since P6 the bottom screen is a game screen, so text output goes to this
// ring buffer (and print also to the log file).

#include <stdio.h>
#include <string.h>

#include "lauxlib.h"

#include "ll_console.h"

#define LINES 32
#define LINE_BYTES (LL_CONSOLE_COLS * 2 + 1) // UTF-8: Polish letters are 2 bytes

static char lines[LINES][LINE_BYTES];
static int first;      // Oldest line
static int count;      // Lines in use (the last one is being written)
static int cur_len;    // Bytes in the current line
static int cur_cols;   // Characters in the current line
static bool overlay;

static char *current(void)
{
    if (count == 0)
        count = 1;
    return lines[(first + count - 1) % LINES];
}

static void new_line(void)
{
    if (count == LINES)
        first = (first + 1) % LINES;
    else
        count++;
    lines[(first + count - 1) % LINES][0] = '\0';
    cur_len = cur_cols = 0;
}

void ll_console_write(const char *s, size_t len)
{
    current();
    for (size_t i = 0; i < len; i++)
    {
        unsigned char c = (unsigned char)s[i];

        // ESC [ ... letter: skip (old cursor/clear codes of the 2D console)
        if (c == 0x1b)
        {
            if (i + 1 < len && s[i + 1] == '[')
            {
                i += 2;
                while (i < len && !((s[i] >= 'A' && s[i] <= 'Z') || (s[i] >= 'a' && s[i] <= 'z')))
                    i++;
            }
            continue;
        }
        if (c == '\n')
        {
            new_line();
            continue;
        }
        if (c == '\r')
            continue;

        // A new character starts at a non-continuation byte
        bool starts = (c & 0xc0) != 0x80;
        if (starts && (cur_cols == LL_CONSOLE_COLS || cur_len + 4 >= LINE_BYTES))
            new_line();

        char *line = current();
        line[cur_len++] = (char)(c == '\t' ? ' ' : c);
        line[cur_len] = '\0';
        if (starts)
            cur_cols++;
    }
}

void ll_console_clear(void)
{
    first = count = cur_len = cur_cols = 0;
    lines[0][0] = '\0';
}

bool ll_console_overlay(void)
{
    return overlay;
}

void ll_console_toggle_overlay(void)
{
    overlay = !overlay;
}

void ll_console_text(char *buf, size_t size, int max_lines)
{
    int n = count < max_lines ? count : max_lines;
    size_t pos = 0;
    buf[0] = '\0';
    for (int i = count - n; i < count; i++)
    {
        const char *line = lines[(first + i) % LINES];
        int written = snprintf(buf + pos, size - pos, "%s%s", i > count - n ? "\n" : "", line);
        if (written < 0 || (size_t)written >= size - pos)
            break;
        pos += (size_t)written;
    }
}

// io.write(...): strings and numbers to the console
static int l_io_write(lua_State *L)
{
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++)
    {
        size_t len;
        const char *s = luaL_checklstring(L, i, &len);
        ll_console_write(s, len);
    }
    return 0;
}

void ll_console_register(lua_State *L)
{
    lua_getglobal(L, "io");
    lua_pushcfunction(L, l_io_write);
    lua_setfield(L, -2, "write");
    lua_pop(L, 1);
}
