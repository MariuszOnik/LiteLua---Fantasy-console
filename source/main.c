// SPDX-License-Identifier: Zlib
//
// LiteLua - P0 smoke test: boots Lua 5.4 (LUA_32BITS), runs a micro benchmark
// and then main.lua from the default FAT drive if present.

#include <stdio.h>

#include <fat.h>
#include <nds.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

// Returns elapsed microseconds since cpuStartTiming()
static int l_micros(lua_State *L)
{
    u32 ticks = cpuGetTiming();
    lua_pushinteger(L, (lua_Integer)timerTicks2usec(ticks));
    return 1;
}

// Baseline (P0, melonDS 1.1): int 457 ms, float 499 ms
static const char *bench =
    "print(_VERSION, 'maxint=' .. math.maxinteger)\n"
    "local t0 = micros()\n"
    "local s = 0\n"
    "for i = 1, 200000 do s = s + i % 7 end\n"
    "local t1 = micros()\n"
    "local f = 0.0\n"
    "for i = 1, 200000 do f = f + i * 0.5 end\n"
    "local t2 = micros()\n"
    "print(('int   loop: %d ms'):format((t1 - t0) // 1000))\n"
    "print(('float loop: %d ms'):format((t2 - t1) // 1000))\n"
    "print(('mem: %d KB'):format(collectgarbage('count') // 1))\n";

int main(int argc, char **argv)
{
    consoleDemoInit();
    printf("LiteLua (P0)\n");

    bool fat_ok = fatInitDefault();
    printf("FAT: %s (%s)\n", fat_ok ? "ok" : "fail",
           fat_ok ? fatGetDefaultDrive() : "-");

    lua_State *L = luaL_newstate();
    luaL_openlibs(L);
    lua_register(L, "micros", l_micros);

    cpuStartTiming(0);

    if (luaL_dostring(L, bench) != LUA_OK)
        printf("Error: %s\n", lua_tostring(L, -1));

    if (fat_ok && luaL_dofile(L, "main.lua") != LUA_OK)
        printf("main.lua: %s\n", lua_tostring(L, -1));

    lua_close(L);

    printf("\nSTART: exit\n");
    while (1)
    {
        swiWaitForVBlank();
        scanKeys();
        if (keysDown() & KEY_START)
            break;
    }

    return 0;
}
