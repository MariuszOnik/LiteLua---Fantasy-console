// SPDX-License-Identifier: Zlib
//
// LiteLua - input module: buttons and touch screen.
//
// Lua API:
//   btn(name)  -> true while the button is held
//   btnp(name) -> true in the frame the button was pressed
//   btnr(name) -> true in the frame the button was released
//   touch()    -> x, y while the screen is touched, otherwise nil
//   touchp()   -> x, y where the stylus came down, in the frame btnp("touch") is true
//   touchr()   -> x, y where the stylus last was, in the frame btnr("touch") is true
//
// Button names: a b x y l r start select up down left right touch

#include <nds.h>

#include "lauxlib.h"

#include "ll_input.h"

static u32 keys_held, keys_down, keys_up;
static u32 pending_down, pending_up; // From ll_input_sample since the last frame
static touchPosition touch_pos;
// Touch positions from every sample (D59): a tap shorter than a game frame still has
// its place, and touchp/touchr give the press / release point, not the jittery current one
static bool pending_down_ok, down_ok, up_ok;
static touchPosition pending_down_pos, down_pos, last_pos, up_pos;

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

// Reads the stylus if it is down; remembers the press point of a new touch
static void sample_touch(bool down, touchPosition *press, bool *press_ok)
{
    if ((keysHeld() & KEY_TOUCH) == 0)
        return;
    touchRead(&last_pos);
    if (down)
    {
        *press = last_pos;
        *press_ok = true;
    }
}

void ll_input_sample(void)
{
    scanKeys();
    u32 down = keysDown();
    if (keysUp() & KEY_TOUCH)
        up_pos = last_pos;
    // Only the first press since the last frame keeps its point
    sample_touch((down & KEY_TOUCH) && !(pending_down & KEY_TOUCH), &pending_down_pos,
                 &pending_down_ok);
    pending_down |= down;
    pending_up |= keysUp();
}

void ll_input_update(void)
{
    scanKeys();
    bool new_down = (keysDown() & KEY_TOUCH) && !(pending_down & KEY_TOUCH);
    if (keysUp() & KEY_TOUCH)
        up_pos = last_pos;
    keys_held = keysHeld();
    keys_down = keysDown() | pending_down;
    keys_up = keysUp() | pending_up;
    down_ok = false;
    if (pending_down & KEY_TOUCH)
    {
        down_pos = pending_down_pos;
        down_ok = pending_down_ok;
    }
    sample_touch(new_down, &down_pos, &down_ok);
    touch_pos = last_pos;
    up_ok = (keys_up & KEY_TOUCH) != 0;
    pending_down = pending_up = 0;
    pending_down_ok = false;
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

static int push_pos(lua_State *L, bool ok, const touchPosition *pos)
{
    if (!ok)
    {
        lua_pushnil(L);
        return 1;
    }
    lua_pushinteger(L, pos->px);
    lua_pushinteger(L, pos->py);
    return 2;
}

static int l_touchp(lua_State *L)
{
    return push_pos(L, down_ok, &down_pos);
}

static int l_touchr(lua_State *L)
{
    return push_pos(L, up_ok, &up_pos);
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
    lua_pushcfunction(L, l_touchp);
    lua_setfield(L, -2, "touchp");
    lua_pushcfunction(L, l_touchr);
    lua_setfield(L, -2, "touchr");

    lua_pop(L, 1);
}
