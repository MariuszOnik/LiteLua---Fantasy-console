// SPDX-License-Identifier: Zlib
//
// LiteLua - entry point. Shows the cart list (or runs the built-in demo when
// there is no SD card) and runs the chosen cart, again after every error.
// A game started by a system cart (the code editor) goes back to it (D42).

#include <stdio.h>

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

static LLCart cart;

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

    bool choose = fat_ok; // Without an SD card only the demo can run
    bool is_cart = false;

    while (1)
    {
        if (choose)
        {
            char name[LL_NAME_MAX];
            ll_cart_close(&cart);
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

        LLRunResult r = ll_run(is_cart ? &cart : NULL);
        char caller[LL_NAME_MAX], game[LL_NAME_MAX];
        snprintf(game, sizeof(game), "%s", is_cart ? cart.name : "");
        bool from_game = is_cart && !cart.system;

        switch (r)
        {
            case LL_RUN_RESTART:
                choose = false;
                break;
            case LL_RUN_MENU:
                // Back to the system cart that started the game, if any
                choose = !(from_game && ll_sys_back(game, NULL, caller, sizeof(caller))
                           && open_cart(caller));
                if (choose)
                    choose = fat_ok;
                break;
            case LL_RUN_EDIT:
                ll_sys_back(game, ll_run_error(), caller, sizeof(caller));
                choose = !open_cart(caller) && fat_ok;
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
