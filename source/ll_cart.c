// SPDX-License-Identifier: Zlib
//
// LiteLua - carts: manifest, paths inside a cart and reading cart files.
//
// A cart is a folder in litelua/carts (D6); .lcart files come later (P3).
// Cart files are read only. Paths starting with "save/" go to the cart's
// save folder litelua/saves/<id>, which is the only writable place (D20).

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include <fat.h>

#include "lauxlib.h"
#include "lua.h"

#include "ll_cart.h"
#include "ll_mem.h"

#define MANIFEST "cart.lua"
#define MANIFEST_MEM_LIMIT (64 * 1024)
#define SAVE_PREFIX "save/"

char ll_base[LL_BASE_MAX];

void ll_cart_init(bool fat_ok)
{
    ll_base[0] = '\0';
    if (!fat_ok)
        return;

    snprintf(ll_base, sizeof(ll_base), "%slitelua", fatGetDefaultDrive());

    static const char *const dirs[] = { "", "/carts", "/lib", "/saves" };
    for (size_t i = 0; i < sizeof(dirs) / sizeof(dirs[0]); i++)
    {
        char path[LL_PATH_MAX];
        snprintf(path, sizeof(path), "%s%s", ll_base, dirs[i]);
        mkdir(path, 0777); // Fails harmlessly if it exists
    }
}

bool ll_path_clean(const char *path, char *out, size_t out_size)
{
    size_t n = 0;
    const char *p = path;

    if (*p == '/' || strchr(p, ':') || strchr(p, '\\'))
        return false;

    while (*p)
    {
        const char *end = strchr(p, '/');
        size_t len = end ? (size_t)(end - p) : strlen(p);

        if (len == 2 && p[0] == '.' && p[1] == '.')
            return false;
        if (len > 0 && !(len == 1 && p[0] == '.'))
        {
            if (n + (n > 0) + len + 1 > out_size)
                return false;
            if (n > 0)
                out[n++] = '/';
            memcpy(out + n, p, len);
            n += len;
        }

        p += len;
        if (*p == '/')
            p++;
    }

    out[n] = '\0';
    return n > 0;
}

bool ll_path_is_save(const char *rel)
{
    return strncmp(rel, SAVE_PREFIX, sizeof(SAVE_PREFIX) - 1) == 0;
}

bool ll_cart_file(const LLCart *cart, const char *rel, char *out, size_t out_size)
{
    int n;
    if (ll_path_is_save(rel))
        n = snprintf(out, out_size, "%s/saves/%s/%s", ll_base, cart->id,
                     rel + sizeof(SAVE_PREFIX) - 1);
    else
        n = snprintf(out, out_size, "%s/%s", cart->root, rel);
    return n >= 0 && (size_t)n < out_size;
}

void ll_cart_make_save_dir(const LLCart *cart)
{
    char path[LL_PATH_MAX];
    snprintf(path, sizeof(path), "%s/saves/%s", ll_base, cart->id);
    mkdir(path, 0777);
}

char *ll_file_read(const char *abs_path, size_t *size)
{
    FILE *f = fopen(abs_path, "rb");
    if (f == NULL)
        return NULL;

    char *buf = NULL;
    long len;
    if (fseek(f, 0, SEEK_END) == 0 && (len = ftell(f)) >= 0
        && fseek(f, 0, SEEK_SET) == 0)
    {
        buf = malloc((size_t)len + 1);
        if (buf && fread(buf, 1, (size_t)len, f) == (size_t)len)
        {
            buf[len] = '\0';
            *size = (size_t)len;
        }
        else
        {
            free(buf);
            buf = NULL;
        }
    }

    fclose(f);
    return buf;
}

char *ll_cart_read(const LLCart *cart, const char *rel, size_t *size)
{
    char path[LL_PATH_MAX];
    if (!ll_cart_file(cart, rel, path, sizeof(path)))
        return NULL;
    return ll_file_read(path, size);
}

FILE *ll_cart_fopen(const LLCart *cart, const char *rel)
{
    char path[LL_PATH_MAX];
    if (!ll_cart_file(cart, rel, path, sizeof(path)))
        return NULL;
    return fopen(path, "rb");
}

// Copies string field 'key' of the table at the top of the stack into 'out'.
// Missing fields keep 'out'. Returns false (with 'err') for a wrong type.
static bool get_string(lua_State *L, const char *key, char *out, size_t size,
                       char *err, size_t err_size)
{
    int t = lua_getfield(L, -1, key);
    bool ok = true;
    if (t == LUA_TSTRING)
        snprintf(out, size, "%s", lua_tostring(L, -1));
    else if (t != LUA_TNIL)
    {
        snprintf(err, err_size, MANIFEST ": '%s' must be a string", key);
        ok = false;
    }
    lua_pop(L, 1);
    return ok;
}

// Reads an integer field; returns false (with 'err') for a wrong type.
static bool get_int(lua_State *L, const char *key, lua_Integer *out,
                    char *err, size_t err_size)
{
    int t = lua_getfield(L, -1, key);
    bool ok = true;
    if (lua_isinteger(L, -1))
        *out = lua_tointeger(L, -1);
    else if (t != LUA_TNIL)
    {
        snprintf(err, err_size, MANIFEST ": '%s' must be an integer", key);
        ok = false;
    }
    lua_pop(L, 1);
    return ok;
}

static bool valid_id(const char *id)
{
    if (*id == '\0')
        return false;
    for (; *id; id++)
    {
        if (!islower((unsigned char)*id) && !isdigit((unsigned char)*id)
            && *id != '_' && *id != '-' && *id != '.')
            return false;
    }
    return true;
}

// Evaluates the manifest in a small separate state with an empty
// environment: it may only build and return a table of literals.
static bool read_manifest(LLCart *cart, const char *src, size_t len,
                          char *err, size_t err_size)
{
    LLMem mem;
    ll_mem_init(&mem, MANIFEST_MEM_LIMIT);
    lua_State *L = lua_newstate(ll_mem_alloc, &mem);
    if (L == NULL)
    {
        snprintf(err, err_size, "out of memory");
        return false;
    }

    bool ok = false;
    lua_Integer api = 1, memory = LL_MEM_DEFAULT_LIMIT / 1024;
    char display[16] = "dual30";

    int status = luaL_loadbufferx(L, src, len, "@" MANIFEST, "t");
    if (status == LUA_OK)
    {
        lua_newtable(L);
        lua_setupvalue(L, -2, 1); // Empty _ENV
        status = lua_pcall(L, 0, 1, 0);
    }
    if (status != LUA_OK)
    {
        snprintf(err, err_size, "%s", lua_tostring(L, -1));
        goto done;
    }
    if (!lua_istable(L, -1))
    {
        snprintf(err, err_size, MANIFEST " must return a table");
        goto done;
    }

    if (!get_string(L, "id", cart->id, sizeof(cart->id), err, err_size)
        || !get_string(L, "title", cart->title, sizeof(cart->title), err, err_size)
        || !get_string(L, "entry", cart->entry, sizeof(cart->entry), err, err_size)
        || !get_string(L, "display", display, sizeof(display), err, err_size)
        || !get_int(L, "api", &api, err, err_size)
        || !get_int(L, "memory", &memory, err, err_size))
        goto done;

    if (!valid_id(cart->id))
    {
        snprintf(err, err_size, MANIFEST ": id '%s' may only use a-z 0-9 _ - .",
                 cart->id);
        goto done;
    }
    if (api > LL_API_VERSION)
    {
        snprintf(err, err_size, "cart needs API %d, this LiteLua has %d",
                 (int)api, LL_API_VERSION);
        goto done;
    }
    if (strcmp(display, "dual30") != 0)
    {
        snprintf(err, err_size, MANIFEST ": display '%s' is not supported",
                 display);
        goto done;
    }
    if (memory < 64 || memory > 64 * 1024)
    {
        snprintf(err, err_size, MANIFEST ": memory must be 64..65536 (KB)");
        goto done;
    }
    cart->mem_limit = (size_t)memory * 1024;

    char entry[LL_NAME_MAX];
    if (!ll_path_clean(cart->entry, entry, sizeof(entry))
        || ll_path_is_save(entry))
    {
        snprintf(err, err_size, MANIFEST ": bad entry '%s'", cart->entry);
        goto done;
    }
    strcpy(cart->entry, entry);
    ok = true;

done:
    lua_close(L);
    return ok;
}

bool ll_cart_open(LLCart *cart, const char *name, char *err, size_t err_size)
{
    memset(cart, 0, sizeof(*cart));
    snprintf(cart->name, sizeof(cart->name), "%s", name);
    snprintf(cart->root, sizeof(cart->root), "%s/carts/%s", ll_base, name);

    // Defaults; the id falls back to the folder name in lower case, with
    // characters that are not allowed in ids replaced by '_'
    for (size_t i = 0; name[i] && i < sizeof(cart->id) - 1; i++)
    {
        char c = (char)tolower((unsigned char)name[i]);
        cart->id[i] = valid_id((char[]){ c, '\0' }) ? c : '_';
    }
    strcpy(cart->entry, "main.lua");
    cart->mem_limit = LL_MEM_DEFAULT_LIMIT;

    if (ll_base[0] == '\0')
    {
        snprintf(err, err_size, "no SD card");
        return false;
    }

    size_t len;
    char *src = ll_cart_read(cart, MANIFEST, &len);
    if (src == NULL)
    {
        snprintf(err, err_size, "%s: no " MANIFEST, name);
        return false;
    }

    bool ok = read_manifest(cart, src, len, err, err_size);
    free(src);

    if (cart->title[0] == '\0')
        snprintf(cart->title, sizeof(cart->title), "%s", cart->id);
    return ok;
}
