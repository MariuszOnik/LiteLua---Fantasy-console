// SPDX-License-Identifier: Zlib
//
// LiteLua - file sandbox of a cart (D6, D20).
//
// Carts see their own files through relative paths ("data/level1.txt") and
// may only read them. Paths starting with "save/" go to litelua/saves/<id>,
// which is also writable. require looks in src/, lib/ of the cart, then in
// the shared litelua/lib on the SD card and last in nitro:/lib (built in). Code is only loaded from source text: binary
// chunks are rejected because a broken one can crash the VM.

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#include "ll_cart.h"
#include "ll_sandbox.h"

static const LLCart *cart; // Cart of the current state, NULL for the demo

// Checks argument 'arg' as a cart path and returns it cleaned in 'out'.
static void check_path(lua_State *L, int arg, char *out, size_t size)
{
    const char *path = luaL_checkstring(L, arg);
    if (cart == NULL)
        luaL_error(L, "no cart files in the built-in demo");
    if (!ll_path_clean(path, out, size))
        luaL_argerror(L, arg, lua_pushfstring(L, "bad path '%s' (use relative "
                      "paths like \"data/map.txt\", no \"..\")", path));
}

// --- io ---------------------------------------------------------------------

static int stream_close(lua_State *L)
{
    luaL_Stream *p = luaL_checkudata(L, 1, LUA_FILEHANDLE);
    errno = 0;
    return luaL_fileresult(L, fclose(p->f) == 0, NULL);
}

static bool valid_mode(const char *mode)
{
    if (*mode == '\0' || strchr("rwa", *mode++) == NULL)
        return false;
    if (*mode == '+')
        mode++;
    return strspn(mode, "b") == strlen(mode);
}

// io.open(path [, mode])
static int l_io_open(lua_State *L)
{
    char rel[LL_PATH_MAX], abs[LL_PATH_MAX];
    check_path(L, 1, rel, sizeof(rel));
    const char *mode = luaL_optstring(L, 2, "r");
    luaL_argcheck(L, valid_mode(mode), 2, "invalid mode");

    bool writing = mode[0] != 'r' || strchr(mode, '+') != NULL;
    bool save = ll_path_is_save(rel);
    if (writing && !save)
        return luaL_error(L, "cart files are read only; write to \"save/...\"");

    luaL_Stream *p = lua_newuserdatauv(L, sizeof(luaL_Stream), 0);
    p->closef = NULL; // Marked as closed until the file is open
    luaL_setmetatable(L, LUA_FILEHANDLE);

    errno = 0;
    if (save)
    {
        if (writing)
            ll_cart_make_save_dir(cart);
        p->f = ll_cart_save_path(cart, rel, abs, sizeof(abs)) ? fopen(abs, mode) : NULL;
    }
    else
    {
        p->f = ll_cart_fopen(cart, rel);
    }

    if (p->f == NULL)
        return luaL_fileresult(L, 0, rel);
    p->closef = stream_close;
    return 1;
}

// --- os ---------------------------------------------------------------------

static void check_save_path(lua_State *L, int arg, char *abs, size_t size)
{
    char rel[LL_PATH_MAX];
    check_path(L, arg, rel, sizeof(rel));
    if (!ll_path_is_save(rel))
        luaL_error(L, "only files in \"save/...\" can be changed");
    if (!ll_cart_save_path(cart, rel, abs, size))
        luaL_error(L, "path too long");
}

static int l_os_remove(lua_State *L)
{
    char abs[LL_PATH_MAX];
    check_save_path(L, 1, abs, sizeof(abs));
    errno = 0;
    return luaL_fileresult(L, remove(abs) == 0, luaL_checkstring(L, 1));
}

static int l_os_rename(lua_State *L)
{
    char from[LL_PATH_MAX], to[LL_PATH_MAX];
    check_save_path(L, 1, from, sizeof(from));
    check_save_path(L, 2, to, sizeof(to));
    errno = 0;
    return luaL_fileresult(L, rename(from, to) == 0, NULL);
}

// --- loading code -----------------------------------------------------------

// Compiles source text read by ll_cart_read/ll_file_read (and frees it),
// naming the chunk '@' + 'name'. Returns a Lua status; on error the message
// is on the stack.
static int load_source(lua_State *L, char *src, size_t len, const char *name)
{
    char chunkname[LL_PATH_MAX + 1];
    snprintf(chunkname, sizeof(chunkname), "@%s", name);
    const char *code = ll_skip_bom(src, &len);
    int status = luaL_loadbufferx(L, code, len, chunkname, "t");
    free(src);
    return status;
}

// Loads a cart file given by a clean relative path; the chunk is named after
// the path ("@src/player.lua", D13).
static int load_cart_file(lua_State *L, const char *rel)
{
    size_t len;
    char *src = ll_cart_read(cart, rel, &len);
    if (src == NULL)
    {
        lua_pushfstring(L, "cannot read %s", rel);
        return LUA_ERRFILE;
    }
    return load_source(L, src, len, rel);
}

// loadfile(path [, mode [, env]]); mode is ignored, only text is accepted
static int l_loadfile(lua_State *L)
{
    char rel[LL_PATH_MAX];
    check_path(L, 1, rel, sizeof(rel));
    bool has_env = !lua_isnone(L, 3);

    if (load_cart_file(L, rel) != LUA_OK)
    {
        luaL_pushfail(L);
        lua_insert(L, -2);
        return 2;
    }
    if (has_env)
    {
        lua_pushvalue(L, 3);
        if (!lua_setupvalue(L, -2, 1)) // _ENV
            lua_pop(L, 1);
    }
    return 1;
}

// dofile(path)
static int l_dofile(lua_State *L)
{
    char rel[LL_PATH_MAX];
    check_path(L, 1, rel, sizeof(rel));
    lua_settop(L, 1);
    if (load_cart_file(L, rel) != LUA_OK)
        return lua_error(L);
    lua_call(L, 0, LUA_MULTRET);
    return lua_gettop(L) - 1;
}

// load(chunk [, chunkname [, mode [, env]]]) with mode forced to "t".
// Upvalue 1 is the original load.
static int l_load(lua_State *L)
{
    lua_settop(L, 4);
    lua_pushliteral(L, "t");
    lua_replace(L, 3);
    lua_pushvalue(L, lua_upvalueindex(1));
    lua_insert(L, 1);
    lua_call(L, 4, LUA_MULTRET);
    return lua_gettop(L);
}

// package.searchers entry: "a.b" -> src/a/b.lua, lib/a/b.lua (cart), then
// litelua/lib/a/b.lua (shared, chunk named "@litelua/lib/a/b.lua") and
// nitro:/lib/a/b.lua (built in, chunk named "@rom/lib/a/b.lua").
static int l_searcher(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    char mod[LL_PATH_MAX], rel[LL_PATH_MAX / 2]; // Module names are short

    snprintf(mod, sizeof(mod), "%s", name);
    for (char *c = mod; *c; c++)
    {
        if (*c == '.')
            *c = '/';
    }

    if (cart == NULL || !ll_path_clean(mod, rel, sizeof(rel)))
    {
        lua_pushfstring(L, "\n\tbad module name '%s'", name);
        return 1;
    }

    static const char *const dirs[] = { "src", "lib" };
    luaL_Buffer tried;
    luaL_buffinit(L, &tried);

    for (int i = 0; i < 4; i++)
    {
        char path[LL_PATH_MAX], abs[LL_PATH_MAX];
        char *src;
        size_t len;

        if (i < 2)
        {
            snprintf(path, sizeof(path), "%s/%s.lua", dirs[i], rel);
            src = ll_cart_read(cart, path, &len);
        }
        else if (i == 2)
        {
            snprintf(path, sizeof(path), "litelua/lib/%s.lua", rel);
            snprintf(abs, sizeof(abs), "%s/lib/%s.lua", ll_base, rel);
            src = ll_file_read(abs, &len);
        }
        else
        {
            snprintf(path, sizeof(path), "rom/lib/%s.lua", rel);
            snprintf(abs, sizeof(abs), "nitro:/lib/%s.lua", rel);
            src = ll_file_read(abs, &len);
        }

        if (src == NULL)
        {
            lua_pushfstring(L, "\n\tno file '%s'", path);
            luaL_addvalue(&tried);
            continue;
        }

        if (load_source(L, src, len, path) != LUA_OK)
            return luaL_error(L, "error loading module '%s':\n\t%s", name,
                              lua_tostring(L, -1));
        lua_pushstring(L, path); // Second argument of the loader
        return 2;
    }

    luaL_pushresult(&tried);
    return 1;
}

// io.lines/input/output with file names go through the sandboxed io.open
static const char prelude[] =
    "local io, open, lines0, input0, output0 = io, io.open, io.lines, io.input, io.output\n"
    "function io.lines(name, ...)\n"
    "  if name == nil then return lines0(nil, ...) end\n"
    "  local f = assert(open(name))\n"
    "  local it = f:lines(...)\n"
    "  local function check(...)\n"
    "    if (...) == nil then f:close() end\n"
    "    return ...\n"
    "  end\n"
    "  return function() return check(it()) end, nil, nil, f\n"
    "end\n"
    "function io.input(f)\n"
    "  if type(f) == 'string' then f = assert(open(f, 'r')) end\n"
    "  return input0(f)\n"
    "end\n"
    "function io.output(f)\n"
    "  if type(f) == 'string' then f = assert(open(f, 'w')) end\n"
    "  return output0(f)\n"
    "end\n";

static void set_nil(lua_State *L, const char *field)
{
    lua_pushnil(L);
    lua_setfield(L, -2, field);
}

void ll_sandbox_install(lua_State *L, const LLCart *c)
{
    cart = c;

    // io
    lua_getglobal(L, "io");
    lua_pushcfunction(L, l_io_open);
    lua_setfield(L, -2, "open");
    set_nil(L, "popen");
    set_nil(L, "tmpfile");
    lua_pop(L, 1);

    // os: only time functions, and remove/rename inside save/
    lua_getglobal(L, "os");
    lua_pushcfunction(L, l_os_remove);
    lua_setfield(L, -2, "remove");
    lua_pushcfunction(L, l_os_rename);
    lua_setfield(L, -2, "rename");
    set_nil(L, "execute");
    set_nil(L, "exit");
    set_nil(L, "getenv");
    set_nil(L, "tmpname");
    set_nil(L, "setlocale");
    lua_pop(L, 1);

    // Loading code
    lua_getglobal(L, "load");
    lua_pushcclosure(L, l_load, 1);
    lua_setglobal(L, "load");
    lua_register(L, "loadfile", l_loadfile);
    lua_register(L, "dofile", l_dofile);

    // require: keep the preload searcher, then the cart searcher
    lua_getglobal(L, "package");
    lua_createtable(L, 2, 0);
    lua_getfield(L, -2, "searchers");
    lua_rawgeti(L, -1, 1);
    lua_rawseti(L, -3, 1);
    lua_pop(L, 1);
    lua_pushcfunction(L, l_searcher);
    lua_rawseti(L, -2, 2);
    lua_setfield(L, -2, "searchers");
    lua_pushliteral(L, "");
    lua_setfield(L, -2, "path");
    lua_pushliteral(L, "");
    lua_setfield(L, -2, "cpath");
    set_nil(L, "loadlib");
    set_nil(L, "searchpath");
    lua_pop(L, 1);

    // Must not fail: the state was just created
    if (luaL_loadbuffer(L, prelude, sizeof(prelude) - 1, "=sandbox") == LUA_OK)
        lua_call(L, 0, 0);
}
