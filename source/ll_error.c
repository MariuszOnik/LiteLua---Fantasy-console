// SPDX-License-Identifier: Zlib
//
// LiteLua - error screen.
//
// Uses the text console (32x24). The message gets the top rows, the stack
// traceback fills the rest and the bottom rows show memory use and the
// restart hint. Text that does not fit is cut, never scrolled.

#include <stdio.h>
#include <string.h>

#include <nds.h>

#include "ll_error.h"

#define COLS 32
#define MSG_MAX_ROWS 9
#define TRACE_LAST_ROW 20 // Rows 21-23 are the footer

#define RED "\x1b[31;1m"
#define WHITE "\x1b[39m"
#define GRAY "\x1b[37;0m"

// Prints 'len' bytes of 's' starting at 'row', wrapping at COLS and never
// past 'last_row'. Tabs become a space. Returns the next free row.
static int print_wrapped(const char *s, size_t len, int row, int last_row)
{
    int col = 0;

    if (row > last_row)
        return row;
    printf("\x1b[%d;0H", row);

    for (size_t i = 0; i < len; i++)
    {
        char c = s[i];
        if (c == '\n' || col == COLS)
        {
            if (++row > last_row)
                return row;
            printf("\x1b[%d;0H", row);
            col = 0;
            if (c == '\n')
                continue;
        }
        putchar(c == '\t' ? ' ' : c);
        col++;
    }

    return row + 1;
}

void ll_error_show(const char *err, const LLMem *mem)
{
    static const char trace_tag[] = "\nstack traceback:";

    const char *trace = strstr(err, trace_tag);
    size_t msg_len = trace ? (size_t)(trace - err) : strlen(err);

    consoleClear();
    printf(RED "\x1b[0;0HLua error" WHITE);

    int row = print_wrapped(err, msg_len, 1, MSG_MAX_ROWS);

    if (trace)
    {
        trace++; // Skip the newline
        printf(GRAY);
        print_wrapped(trace, strlen(trace), row + 1, TRACE_LAST_ROW);
    }

    printf(WHITE);
    if (mem)
    {
        printf("\x1b[22;0HLua mem: %u/%u KB (peak %u)",
               (unsigned)(mem->used / 1024), (unsigned)(mem->limit / 1024),
               (unsigned)(mem->peak / 1024));
    }
    printf("\x1b[23;0HSTART: restart");

    while (1)
    {
        swiWaitForVBlank();
        scanKeys();
        if (keysDown() & KEY_START)
            break;
    }

    consoleClear();
}
