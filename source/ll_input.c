// SPDX-License-Identifier: Zlib
//
// LiteLua - input module: buttons and touch screen.
//
// Lua API:
//   btn(name)  -> true while the button is held
//   btnp(name) -> true in the frame the button was pressed
//   btnr(name) -> true in the frame the button was released
//   touch()    -> x, y while the screen is touched, otherwise nil
//
// Button names: a b x y l r start select up down left right touch

#include <nds.h>

#include "lauxlib.h"

#include "ll_input.h"

static u32 keys_held, keys_down, keys_up;
static u32 pending_down, pending_up; // From ll_input_sample since the last frame
static touchPosition touch_pos;

static const struct {
    const char *name;
    u32 mask;
} buttons[] = {
    { "a", KEY_A },         { "b", KEY_B },
    { "x", KEY_X },         { "y", KEY_Y },
    { "l", KEY_L },         { "r", KEY_R },
    { "start", KEY_START }, { "select", KEY_SELECT },
    { "up", KEY_UP },       { "down", KEY_DOWN },
    { "left", KEY_LEFT },   { "right", KEY_RIGHT },
    { "touch", KEY_TOUCH },
};

void ll_input_sample(void)
{
    scanKeys();
    pending_down |= keysDown();
    pending_up |= keysUp();
}

void ll_input_update(void)
{
    scanKeys();
    keys_held = keysHeld();
    keys_down = keysDown() | pending_down;
    keys_up = keysUp() | pending_up;
    pending_down = pending_up = 0;
    if (keys_held & KEY_TOUCH)
        touchRead(&touch_pos);
}

// Looks up the button mask in the name table stored as upvalue 1
static u32 check_button(lua_State *L)
{
    luaL_checktype(L, 1, LUA_TSTRING);
    lua_pushvalue(L, 1);
    if (lua_rawget(L, lua_upvalueindex(1)) != LUA_TNUMBER)
        luaL_error(L, "unknown button '%s'", lua_tostring(L, 1));
    u32 mask = (u32)lua_tointeger(L, -1);
    lua_pop(L, 1);
    return mask;
}

static int l_btn(lua_State *L)
{
    lua_pushboolean(L, (keys_held & check_button(L)) != 0);
    return 1;
}

static int l_btnp(lua_State *L)
{
    lua_pushboolean(L, (keys_down & check_button(L)) != 0);
    return 1;
}

static int l_btnr(lua_State *L)
{
    lua_pushboolean(L, (keys_up & check_button(L)) != 0);
    return 1;
}

static int l_touch(lua_State *L)
{
    if ((keys_held & KEY_TOUCH) == 0)
    {
        lua_pushnil(L);
        return 1;
    }
    lua_pushinteger(L, touch_pos.px);
    lua_pushinteger(L, touch_pos.py);
    return 2;
}

void ll_input_register(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        { "btn", l_btn },
        { "btnp", l_btnp },
        { "btnr", l_btnr },
        { NULL, NULL },
    };

    lua_pushglobaltable(L);

    lua_createtable(L, 0, sizeof(buttons) / sizeof(buttons[0]));
    for (size_t i = 0; i < sizeof(buttons) / sizeof(buttons[0]); i++)
    {
        lua_pushinteger(L, buttons[i].mask);
        lua_setfield(L, -2, buttons[i].name);
    }
    luaL_setfuncs(L, funcs, 1); // Name table shared as upvalue

    lua_pushcfunction(L, l_touch);
    lua_setfield(L, -2, "touch");

    lua_pop(L, 1);
}
