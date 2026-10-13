// SPDX-License-Identifier: Zlib
//
// LiteLua - sys module: switching carts (D14), console info (D33), the
// extra API of system carts (sys.system, D27, D42).
//
// sys.run and sys.exit only record the request. The runtime closes the Lua
// state after the current callback returns and then starts the next cart in
// a new state, so a cart never runs inside another one.
//
// A system cart (the code editor) starts a game with sys.system.run(name,
// data): when the game ends, the system cart is started again and finds the
// data in sys.system.start, so it can go back to where it was (D14 variant A).

#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"

#include "ll_log.h"
#include "ll_sys.h"

#define DATA_MAX (64 * 1024) // Data passed from a system cart to itself
#define CARTS_MAX 64

static LLSysRequest request;
static LLCart next_cart;
static const LLCart *current; // Cart of the state, NULL for the demo

// Return to a system cart after the game it started; 'pending' becomes
// 'ret' when the game really starts
typedef struct {
    bool active;
    char caller[LL_NAME_MAX];
    char *data;
} Return;
static Return ret, pending;

// sys.system.start of the next system cart
static struct {
    const char *reason; // "run", "edit", "exit" or "error"
    char cart[LL_NAME_MAX];
    char *data, *error;
} start = { "run" };

static void return_clear(Return *r)
{
    free(r->data);
    *r = (Return){ 0 };
}

static void set_start(const char *reason, const char *cart, char *data,
                      const char *error)
{
    free(start.data);
    free(start.error);
    start.reason = reason;
    snprintf(start.cart, sizeof(start.cart), "%s", cart ? cart : "");
    start.data = data; // Taken over
    start.error = error ? strdup(error) : NULL;
}

// Closes a cart opened by sys.run that will not be started
void ll_sys_discard(void)
{
    if (request == LL_SYS_RUN)
        ll_cart_close(&next_cart);
    return_clear(&pending);
    request = LL_SYS_NONE;
}

// Opens the cart for the run request; raises a Lua error on failure
static void open_next(lua_State *L, const char *name)
{
    ll_sys_discard(); // An earlier sys.run in the same callback
    char err[160];
    if (!ll_cart_open(&next_cart, name, err, sizeof(err)))
        luaL_error(L, "sys.run: %s", err);
    request = LL_SYS_RUN;
}

// sys.run(name): runs the cart litelua/carts/<name> (or system cart "@name")
// after this callback
static int l_run(lua_State *L)
{
    open_next(L, luaL_checkstring(L, 1));
    return 0;
}

// sys.exit(): back to the cart list after this callback
static int l_exit(lua_State *L)
{
    ll_sys_discard();
    request = LL_SYS_EXIT;
    return 0;
}

// sys.info(): the console the game runs on (D33)
static int l_info(lua_State *L)
{
    bool dsi = isDSiMode();
    lua_createtable(L, 0, 3);
    lua_pushstring(L, dsi ? "DSi" : "DS");
    lua_setfield(L, -2, "console");
    lua_pushinteger(L, dsi && (REG_SCFG_CLK & SCFG_CLK_ARM9_TWL) ? 134 : 67);
    lua_setfield(L, -2, "cpu_mhz");
    lua_pushinteger(L, dsi ? 16384 : 4096);
    lua_setfield(L, -2, "ram_kb");
    return 1;
}

// --- sys.system -------------------------------------------------------------

// Opens the files of cart 'name' (argument 1). Returns false with nil and a
// message pushed if it cannot be opened.
static bool open_files(lua_State *L, LLCart *cart)
{
    char err[160];
    if (ll_cart_open_files(cart, luaL_checkstring(L, 1), err, sizeof(err)))
        return true;
    luaL_pushfail(L);
    lua_pushstring(L, err);
    return false;
}

// Checks argument 'arg' as a path inside a cart; "" is the top folder when
// 'allow_top' is set
static void check_rel(lua_State *L, int arg, char *out, size_t size,
                      bool allow_top)
{
    const char *path = luaL_checkstring(L, arg);
    if (allow_top && (*path == '\0' || strcmp(path, ".") == 0))
    {
        *out = '\0';
        return;
    }
    if (!ll_path_clean(path, out, size))
        luaL_argerror(L, arg, lua_pushfstring(L, "bad path '%s'", path));
}

// Pushes the description of a cart (opened with its manifest when it can be)
static void push_cart_info(lua_State *L, const char *name)
{
    LLCart cart;
    char err[160], unused[1];
    bool ok = ll_cart_open(&cart, name, err, sizeof(err));
    // A broken manifest: the files can still be edited
    if (!ok && !ll_cart_open_files(&cart, name, unused, sizeof(unused)))
        memset(&cart, 0, sizeof(cart));

    lua_createtable(L, 0, 7);
    lua_pushstring(L, name);
    lua_setfield(L, -2, "name");
    if (ok)
    {
        lua_pushstring(L, cart.title);
        lua_setfield(L, -2, "title");
        lua_pushstring(L, cart.id);
        lua_setfield(L, -2, "id");
        lua_pushstring(L, cart.entry);
        lua_setfield(L, -2, "entry");
    }
    else
    {
        lua_pushstring(L, err);
        lua_setfield(L, -2, "error");
    }
    lua_pushboolean(L, cart.zip != NULL);
    lua_setfield(L, -2, "lcart");
    lua_pushboolean(L, cart.system);
    lua_setfield(L, -2, "system");
    lua_pushboolean(L, cart.root[0] && ll_cart_writable(&cart));
    lua_setfield(L, -2, "writable");
    ll_cart_close(&cart);
}

// sys.system.carts() -> array of cart descriptions (litelua/carts)
static int l_carts(lua_State *L)
{
    char *names[CARTS_MAX];
    int n = ll_cart_list_names(names, CARTS_MAX);
    lua_createtable(L, n, 0);
    for (int i = 0; i < n; i++)
    {
        push_cart_info(L, names[i]);
        lua_rawseti(L, -2, i + 1);
        free(names[i]);
    }
    return 1;
}

// sys.system.cart(name) -> description, or nil and a message
static int l_cart(lua_State *L)
{
    LLCart cart;
    if (!open_files(L, &cart))
        return 2;
    ll_cart_close(&cart);
    push_cart_info(L, lua_tostring(L, 1));
    return 1;
}

// sys.system.files(cart, [dir]) -> { {name=, dir=}, ... } or nil, message
static int l_files(lua_State *L)
{
    char dir[LL_PATH_MAX];
    if (lua_isnoneornil(L, 2))
        dir[0] = '\0';
    else
        check_rel(L, 2, dir, sizeof(dir), true);
    LLCart cart;
    if (!open_files(L, &cart))
        return 2;
    bool ok = ll_cart_push_list(L, &cart, dir);
    ll_cart_close(&cart);
    if (ok)
        return 1;
    luaL_pushfail(L);
    lua_pushfstring(L, "cannot read folder '%s'", dir);
    return 2;
}

// sys.system.read(cart, path) -> string, or nil and a message
static int l_read(lua_State *L)
{
    char rel[LL_PATH_MAX];
    check_rel(L, 2, rel, sizeof(rel), false);
    LLCart cart;
    if (!open_files(L, &cart))
        return 2;
    size_t len;
    char *data = ll_cart_read(&cart, rel, &len);
    ll_cart_close(&cart);
    if (data == NULL)
    {
        luaL_pushfail(L);
        lua_pushfstring(L, "cannot read %s", rel);
        return 2;
    }
    lua_pushlstring(L, data, len);
    free(data);
    return 1;
}

// sys.system.write(cart, path, data) -> true, or nil and a message
static int l_write(lua_State *L)
{
    char rel[LL_PATH_MAX], err[160];
    check_rel(L, 2, rel, sizeof(rel), false);
    size_t len;
    const char *data = luaL_checklstring(L, 3, &len);
    LLCart cart;
    if (!open_files(L, &cart))
        return 2;
    bool ok = ll_cart_write(&cart, rel, data, len, err, sizeof(err));
    ll_cart_close(&cart);
    if (ok)
    {
        ll_log("sys.system.write: %s/%s (%u bytes)", cart.name, rel,
               (unsigned)len);
        lua_pushboolean(L, 1);
        return 1;
    }
    ll_log("sys.system.write: %s", err);
    luaL_pushfail(L);
    lua_pushstring(L, err);
    return 2;
}

// sys.system.mkdir(cart, path) -> true, or nil and a message
static int l_mkdir(lua_State *L)
{
    char rel[LL_PATH_MAX], err[160];
    check_rel(L, 2, rel, sizeof(rel), false);
    LLCart cart;
    if (!open_files(L, &cart))
        return 2;
    bool ok = ll_cart_mkdir(&cart, rel, err, sizeof(err));
    ll_cart_close(&cart);
    if (ok)
    {
        lua_pushboolean(L, 1);
        return 1;
    }
    luaL_pushfail(L);
    lua_pushstring(L, err);
    return 2;
}

// sys.system.remove(cart, path) -> true, or nil and a message
static int l_remove(lua_State *L)
{
    char rel[LL_PATH_MAX], err[160];
    check_rel(L, 2, rel, sizeof(rel), false);
    LLCart cart;
    if (!open_files(L, &cart))
        return 2;
    bool ok = ll_cart_remove(&cart, rel, err, sizeof(err));
    ll_cart_close(&cart);
    ll_log("sys.system.remove: %s/%s%s%s", cart.name, rel, ok ? "" : ": ",
           ok ? "" : err);
    if (ok)
    {
        lua_pushboolean(L, 1);
        return 1;
    }
    luaL_pushfail(L);
    lua_pushstring(L, err);
    return 2;
}

// sys.system.rename(cart, from, to) -> true, or nil and a message
static int l_rename(lua_State *L)
{
    char from[LL_PATH_MAX], to[LL_PATH_MAX], err[160];
    check_rel(L, 2, from, sizeof(from), false);
    check_rel(L, 3, to, sizeof(to), false);
    LLCart cart;
    if (!open_files(L, &cart))
        return 2;
    bool ok = ll_cart_rename(&cart, from, to, err, sizeof(err));
    ll_cart_close(&cart);
    ll_log("sys.system.rename: %s/%s -> %s%s%s", cart.name, from, to,
           ok ? "" : ": ", ok ? "" : err);
    if (ok)
    {
        lua_pushboolean(L, 1);
        return 1;
    }
    luaL_pushfail(L);
    lua_pushstring(L, err);
    return 2;
}

// sys.system.run(name, [data]): runs a game after this callback; when it
// ends, this system cart starts again with the data in sys.system.start
static int l_system_run(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    size_t len = 0;
    const char *data = luaL_optlstring(L, 2, NULL, &len);
    luaL_argcheck(L, len <= DATA_MAX, 2, "data longer than 64 KB");
    luaL_argcheck(L, name[0] != LL_SYSTEM_PREFIX, 1,
                  "a game expected (use sys.run for system carts)");

    open_next(L, name);
    pending.active = true;
    snprintf(pending.caller, sizeof(pending.caller), "%s", current->name);
    if (data)
    {
        pending.data = malloc(len + 1);
        if (pending.data == NULL)
        {
            ll_sys_discard();
            return luaL_error(L, "sys.system.run: out of memory");
        }
        memcpy(pending.data, data, len);
        pending.data[len] = '\0';
    }
    return 0;
}

static void push_start(lua_State *L)
{
    lua_createtable(L, 0, 4);
    lua_pushstring(L, start.reason);
    lua_setfield(L, -2, "reason");
    if (start.cart[0])
    {
        lua_pushstring(L, start.cart);
        lua_setfield(L, -2, "cart");
    }
    if (start.data)
    {
        lua_pushstring(L, start.data);
        lua_setfield(L, -2, "data");
    }
    if (start.error)
    {
        lua_pushstring(L, start.error);
        lua_setfield(L, -2, "error");
    }
}

static void register_system(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        { "carts", l_carts },
        { "cart", l_cart },
        { "files", l_files },
        { "read", l_read },
        { "write", l_write },
        { "mkdir", l_mkdir },
        { "remove", l_remove },
        { "rename", l_rename },
        { "run", l_system_run },
        { NULL, NULL },
    };
    luaL_newlib(L, funcs);
    push_start(L);
    lua_setfield(L, -2, "start");
    lua_setfield(L, -2, "system");
}

void ll_sys_register(lua_State *L, const LLCart *cart)
{
    static const luaL_Reg funcs[] = {
        { "run", l_run },
        { "exit", l_exit },
        { "info", l_info },
        { NULL, NULL },
    };

    current = cart;
    ll_sys_discard();
    luaL_newlib(L, funcs);
    if (cart && cart->system)
        register_system(L);
    lua_setglobal(L, "sys");
}

LLSysRequest ll_sys_request(void)
{
    return request;
}

LLCart ll_sys_take_next_cart(void)
{
    request = LL_SYS_NONE; // The caller owns the open cart now
    set_start("run", NULL, NULL, NULL);
    if (pending.active)
    {
        return_clear(&ret);
        ret = pending; // Takes over the data
        pending = (Return){ 0 };
    }
    return next_cart;
}

void ll_sys_start_edit(const char *name)
{
    return_clear(&ret);
    set_start("edit", name, NULL, NULL);
}

void ll_sys_forget(void)
{
    return_clear(&ret);
    set_start("run", NULL, NULL, NULL);
}

bool ll_sys_back(const char *game, const char *error, char *caller,
                 size_t size)
{
    if (error)
    {
        // Always the code editor; its own data only if it started the game
        bool own = ret.active && strcmp(ret.caller, "@code") == 0;
        snprintf(caller, size, "@code");
        set_start("error", game, own ? ret.data : NULL, error);
        if (own)
            ret.data = NULL; // Taken over
        return_clear(&ret);
        return true;
    }
    if (!ret.active)
        return false;
    snprintf(caller, size, "%s", ret.caller);
    set_start("exit", game, ret.data, NULL);
    ret.data = NULL;
    return_clear(&ret);
    return true;
}

#define KEYS_QUIT (KEY_L | KEY_R | KEY_START)
#define QUIT_HOLD_VBLANKS 60 // One second

bool ll_sys_quit_poll(u32 held)
{
    static bool holding;
    static unsigned long since;

    if ((held & KEYS_QUIT) != KEYS_QUIT)
    {
        holding = false;
        return false;
    }
    if (!holding)
    {
        holding = true;
        since = ll_vblanks();
    }
    return ll_vblanks() - since >= QUIT_HOLD_VBLANKS;
}

void ll_sys_quit(void)
{
    ll_log("L+R+START: quit LiteLua");
    ll_log_flush();
    // exit() closes the open files (log, cart archive) and returns to the
    // loader through its boot stub, or turns the console off
    exit(0);
}
