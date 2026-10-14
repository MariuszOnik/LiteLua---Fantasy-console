// SPDX-License-Identifier: Zlib
//
// LiteLua - entry point. Runs the launcher (system cart "@launcher", P10),
// which chooses the next cart, and goes back to it when a cart ends. A game
// started by a system cart (the code editor) goes back to it (D42).
//
// The simple cart list in C (ll_menu.c) is the fallback: in safe mode
// (SELECT held at start), without NitroFS, or when the launcher fails.

#include <stdio.h>
#include <string.h>

#include <fat.h>
#include <filesystem.h>
#include <nds.h>

#include "ll_cart.h"
#include "ll_error.h"
#include "ll_gfx.h"
#include "ll_log.h"
#include "ll_menu.h"
#include "ll_runtime.h"
#include "ll_sound.h"
#include "ll_sys.h"

#define CODE_EDITOR "@code"
#define LAUNCHER "@launcher"

static LLCart cart;
static bool use_launcher;

// Opens cart 'name' into 'cart'; shows the error on failure
static bool open_cart(const char *name)
{
    char err[160];
    ll_cart_close(&cart);
    if (ll_cart_open(&cart, name, err, sizeof(err)))
        return true;
    ll_log("cannot open cart %s: %s", name, err);
    ll_log_flush();
    ll_error_show(err, NULL, false);
    return false;
}

int main(int argc, char **argv)
{
    // Timers 0+1 as a 32-bit counter for micros()
    cpuStartTiming(0);

    bool fat_ok = fatInitDefault();
    ll_log_init(fat_ok); // Also installs the VBlank interrupt handler
    ll_gfx_init();       // 3D on both screens (dual30)
    ll_cart_init(fat_ok);
    ll_sound_init();     // Maxmod without a soundbank (P7)

    // Built-in files (nitro:/), e.g. libraries in nitro:/lib for require
    bool nitro_ok = nitroFSInit(NULL);
    ll_log("NitroFS: %s", nitro_ok ? "ok" : "not available");

    // Safe mode: SELECT held at start, the cart list in C instead of the
    // launcher
    bool safe = (~REG_KEYINPUT) & KEY_SELECT;
    use_launcher = nitro_ok && !safe;
    if (safe)
        ll_log("SELECT held: safe mode, the built-in cart list");

    bool choose = true;
    bool is_cart = false;

    while (1)
    {
        if (choose)
        {
            char name[LL_NAME_MAX], err[160];
            ll_cart_close(&cart);
            ll_sys_forget();
            if (use_launcher)
            {
                if (ll_cart_open(&cart, LAUNCHER, err, sizeof(err)))
                {
                    is_cart = true;
                    goto run;
                }
                ll_log("cannot open %s: %s", LAUNCHER, err);
                use_launcher = false;
            }
            if (!fat_ok) // Without an SD card only the demo can run
            {
                is_cart = false;
                goto run;
            }

            LLMenuChoice choice = ll_menu_choose(name, sizeof(name));
            is_cart = choice != LL_MENU_DEMO;
            if (choice == LL_MENU_EDIT)
            {
                ll_sys_start_edit(name);
                is_cart = open_cart(CODE_EDITOR);
            }
            else
            {
                ll_sys_forget();
                if (is_cart && !open_cart(name))
                    continue;
            }
            if (choice == LL_MENU_EDIT && !is_cart)
                continue;
        }

    run:;
        LLRunResult r = ll_run(is_cart ? &cart : NULL);
        char caller[LL_NAME_MAX], game[LL_NAME_MAX];
        snprintf(game, sizeof(game), "%s", is_cart ? cart.name : "");
        bool from_game = is_cart && !cart.system;

        // A launcher that stops with an error is not used again (until the
        // next start): the cart list in C takes over
        if (is_cart && strcmp(cart.name, LAUNCHER) == 0 && ll_run_error()[0]
            && r != LL_RUN_RESTART)
        {
            ll_log("the launcher failed: the built-in cart list from now on");
            use_launcher = false;
        }

        switch (r)
        {
            case LL_RUN_RESTART:
                choose = false;
                break;
            case LL_RUN_MENU:
                // Back to the system cart that started the game, if any
                choose = !(from_game && ll_sys_back(game, NULL, caller, sizeof(caller))
                           && open_cart(caller));
                break;
            case LL_RUN_EDIT:
                ll_sys_back(game, ll_run_error(), caller, sizeof(caller));
                choose = !open_cart(caller);
                break;
            case LL_RUN_EDIT_GAME:
                // A game started by the editor goes back to it (with its
                // data); otherwise the editor opens the game's files
                if (!(ll_sys_back(game, NULL, caller, sizeof(caller))
                      && strcmp(caller, CODE_EDITOR) == 0))
                    ll_sys_start_edit(game);
                choose = !open_cart(CODE_EDITOR);
                break;
            case LL_RUN_DEMO:
                ll_cart_close(&cart);
                ll_sys_forget();
                is_cart = false;
                choose = false;
                break;
            case LL_RUN_NEXT:
                ll_cart_close(&cart);
                cart = ll_sys_take_next_cart(); // Takes over the open archive
                is_cart = true;
                choose = false;
                break;
            case LL_RUN_QUIT:
                ll_cart_close(&cart);
                ll_sys_quit();
        }
    }

    return 0;
}
