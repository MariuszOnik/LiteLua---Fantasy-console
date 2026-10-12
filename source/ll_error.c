// SPDX-License-Identifier: Zlib
//
// LiteLua - error screen (D27): the message and memory use on the top screen,
// the stack traceback and the buttons on the bottom screen, drawn with the
// built-in font. Text that does not fit is cut, never scrolled.

#include <stdio.h>
#include <string.h>

#include <nds.h>

#include "ll_error.h"
#include "ll_gfx.h"
#include "ll_sys.h"

#define COLS 42
#define ROWS 24
#define MAX_LINES ROWS

typedef struct {
    const char *s;
    size_t len;
} Line;

typedef struct {
    Line msg[MAX_LINES], trace[MAX_LINES];
    int msg_lines, trace_lines;
    char mem[64];
} Screen;

// Splits text into lines at '\n' and at COLS characters (UTF-8 aware; a tab
// counts as up to the next multiple of 4 columns, like text())
static int wrap(const char *s, size_t len, Line *out, int max)
{
    int n = 0;
    size_t start = 0, i = 0;
    int cols = 0;
    while (i < len && n < max)
    {
        unsigned char c = (unsigned char)s[i];
        if (c == '\n')
        {
            out[n++] = (Line){ s + start, i - start };
            start = ++i;
            cols = 0;
            continue;
        }
        if ((c & 0xc0) != 0x80) // A character starts here
        {
            int w = c == '\t' ? 4 - cols % 4 : 1;
            if (cols + w > COLS)
            {
                out[n++] = (Line){ s + start, i - start };
                start = i;
                cols = 0;
                continue;
            }
            cols += w;
        }
        i++;
    }
    if (n < max && start < len)
        out[n++] = (Line){ s + start, len - start };
    return n;
}

static void draw(int screen, void *ud)
{
    Screen *sc = ud;
    ll_gfx_cls(0);
    if (screen == 0)
    {
        ll_gfx_rectfill(0, 0, 256, 10, 2);
        ll_gfx_text(2, 1, "Lua error", 9, 12);
        for (int i = 0; i < sc->msg_lines && i < ROWS - 4; i++)
            ll_gfx_text(0, 14 + i * 8, sc->msg[i].s, sc->msg[i].len, 12);
        ll_gfx_text(0, 184, sc->mem, strlen(sc->mem), 13);
    }
    else
    {
        for (int i = 0; i < sc->trace_lines && i < ROWS - 3; i++)
            ll_gfx_text(0, i * 8, sc->trace[i].s, sc->trace[i].len, 13);
        ll_gfx_rectfill(0, 176, 256, 16, 15);
        static const char help[] = "START: restart    SELECT: cart list";
        ll_gfx_text(2, 180, help, sizeof(help) - 1, 4);
    }
}

bool ll_error_show(const char *err, const LLMem *mem)
{
    static const char trace_tag[] = "\nstack traceback:";
    static Screen sc;

    const char *trace = strstr(err, trace_tag);
    size_t msg_len = trace ? (size_t)(trace - err) : strlen(err);
    sc.msg_lines = wrap(err, msg_len, sc.msg, MAX_LINES);
    sc.trace_lines = trace ? wrap(trace + 1, strlen(trace + 1), sc.trace, MAX_LINES) : 0;

    sc.mem[0] = '\0';
    if (mem)
    {
        snprintf(sc.mem, sizeof(sc.mem), "Lua mem: %u/%u KB (peak %u KB)",
                 (unsigned)(mem->used / 1024), (unsigned)(mem->limit / 1024),
                 (unsigned)(mem->peak / 1024));
    }

    ll_gfx_reset(); // Draw state of the cart (camera, clip...) is not wanted
    u32 keys;
    do
    {
        ll_gfx_frame(draw, &sc);
        scanKeys();
        ll_sys_quit_poll(keysHeld());
        keys = keysDown();
        // START with L+R held is the start of L+R+START (quit), not a restart
        if ((keysHeld() & (KEY_L | KEY_R)) == (KEY_L | KEY_R))
            keys &= ~KEY_START;
    } while (!(keys & (KEY_START | KEY_SELECT)));

    return (keys & KEY_START) != 0;
}
