// SPDX-License-Identifier: Zlib
//
// LiteLua - entry point. Shows the cart list (or runs the built-in demo when
// there is no SD card) and runs the chosen cart, again after every error.

#include <stdio.h>

#include <fat.h>
#include <nds.h>

#include "ll_cart.h"
#include "ll_error.h"
#include "ll_log.h"
#include "ll_menu.h"
#include "ll_runtime.h"
#include "ll_sys.h"

int main(int argc, char **argv)
{
    consoleDemoInit();

    // Timers 0+1 as a 32-bit counter for micros()
    cpuStartTiming(0);

    bool fat_ok = fatInitDefault();
    ll_log_init(fat_ok);
    ll_cart_init(fat_ok);

    static LLCart cart;
    bool choose = fat_ok; // Without an SD card only the demo can run
    bool is_cart = false;

    while (1)
    {
        if (choose)
        {
            char name[LL_NAME_MAX], err[160];
            is_cart = ll_menu_choose(name, sizeof(name));
            if (is_cart && !ll_cart_open(&cart, name, err, sizeof(err)))
            {
                ll_log("cannot open cart %s: %s", name, err);
                ll_log_flush();
                ll_error_show(err, NULL);
                continue;
            }
        }

        switch (ll_run(is_cart ? &cart : NULL))
        {
            case LL_RUN_RESTART:
                choose = false;
                break;
            case LL_RUN_MENU:
                choose = fat_ok;
                break;
            case LL_RUN_NEXT:
                cart = *ll_sys_next_cart();
                is_cart = true;
                choose = false;
                break;
        }
    }

    return 0;
}
