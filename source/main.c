// SPDX-License-Identifier: Zlib
//
// LiteLua - entry point. Runs main.lua from the default FAT drive if present,
// otherwise the built-in demo, and restarts it after every error.

#include <stdio.h>

#include <fat.h>
#include <nds.h>

#include "ll_log.h"
#include "ll_runtime.h"

static bool file_exists(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (f == NULL)
        return false;
    fclose(f);
    return true;
}

int main(int argc, char **argv)
{
    consoleDemoInit();

    // Timers 0+1 as a 32-bit counter for micros()
    cpuStartTiming(0);

    bool fat_ok = fatInitDefault();
    ll_log_init(fat_ok);

    while (1)
    {
        const char *path = NULL;
        if (fat_ok && file_exists("main.lua"))
            path = "main.lua";

        ll_run(path);
    }

    return 0;
}
