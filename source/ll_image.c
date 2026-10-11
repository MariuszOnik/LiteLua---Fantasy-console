// SPDX-License-Identifier: Zlib
//
// LiteLua - images: PNG files as DS textures (D10), Lua image objects.
//
// Texture format by PNG type (D10):
// - palette with up to 16 colors  -> 16-color texture (4 bits per pixel)
// - palette with up to 256 colors -> 256-color texture (8 bits per pixel)
// - gray, RGB, RGBA               -> direct color (15 bits + 1 bit alpha)
// Transparent: palette entries or pixels with alpha below 128; a palette
// image without transparency information uses index 0 as transparent.
// Texture sides are padded to powers of two (8..1024).
//
// Textures live in VRAM banks A and B (256 KB), palettes in bank E (64 KB).
// An image object owns its texture and frees it when collected; views made
// by sub() or frame grids share it and keep the owner alive. All textures
// belong to the cart's Lua state (D14).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <nds.h>

#include "lauxlib.h"

#include "ll_gfx.h"
#include "ll_image.h"
#include "ll_log.h"
#include "ll_png.h"

#define IMAGE_MT "LiteLua.image"
#define CACHE_KEY "LiteLua.images" // Registry: name -> image (weak values)

static const LLCart *cart;
static unsigned vram_used;
static const void *image_mt; // Metatable of images in the current state

void ll_image_init(void)
{
    vramSetBankA(VRAM_A_TEXTURE_SLOT0);
    vramSetBankB(VRAM_B_TEXTURE_SLOT1);
    vramSetBankE(VRAM_E_TEX_PALETTE);
}

void ll_image_reset(const LLCart *c)
{
    cart = c;
    glResetTextures();
    vram_used = 0;
    ll_gfx_texture_changed();
}

unsigned ll_image_vram_used(void)
{
    return vram_used;
}

static int pow2_side(int n)
{
    int s = 8;
    while (s < n)
        s <<= 1;
    return s;
}

static u16 rgb15(uint32_t c)
{
    unsigned r = (c >> 16) & 0xff, g = (c >> 8) & 0xff, b = c & 0xff;
    return RGB15((r * 31 + 127) / 255, (g * 31 + 127) / 255, (b * 31 + 127) / 255);
}

int ll_image_upload(const LLPng *png, unsigned *vram, char *err, size_t err_size)
{
    int tw = pow2_side(png->w), th = pow2_side(png->h);
    GL_TEXTURE_TYPE_ENUM type;
    int bits, pal_size = 0;
    u16 pal[256];
    int param = TEXGEN_OFF;
    uint8_t remap[256];

    if (png->indexed)
    {
        // Transparent entries must become index 0 for the DS
        int transparent = -1;
        for (int i = 0; i < png->num_colors; i++)
            remap[i] = (uint8_t)i;
        if (png->has_trns)
        {
            for (int i = 0; i < png->num_colors; i++)
            {
                if ((png->palette[i] >> 24) < 128)
                {
                    if (transparent < 0)
                        transparent = i;
                    remap[i] = 0;
                }
            }
            if (transparent > 0)
                remap[0] = (uint8_t)transparent; // Swap with the old index 0
        }
        else
        {
            transparent = 0; // D10: index 0 is transparent
        }

        for (int i = 0; i < png->num_colors; i++)
            pal[remap[i]] = rgb15(png->palette[i]);
        if (transparent >= 0)
            param |= GL_TEXTURE_COLOR0_TRANSPARENT;

        if (png->num_colors <= 16)
            type = GL_RGB16, bits = 4, pal_size = 16;
        else
            type = GL_RGB256, bits = 8, pal_size = 256;
        for (int i = png->num_colors; i < pal_size; i++)
            pal[i] = 0;
    }
    else
    {
        type = GL_RGBA;
        bits = 16;
    }

    size_t tex_bytes = (size_t)tw * th * bits / 8;
    uint8_t *data = calloc(1, tex_bytes);
    if (data == NULL)
    {
        snprintf(err, err_size, "not enough memory to convert the image");
        return 0;
    }

    for (int y = 0; y < png->h; y++)
    {
        for (int x = 0; x < png->w; x++)
        {
            size_t i = (size_t)y * png->w + x;
            size_t t = (size_t)y * tw + x;
            if (bits == 16)
            {
                const uint8_t *p = png->pixels + i * 4;
                u16 c = 0;
                if (p[3] >= 128)
                    c = rgb15((uint32_t)p[0] << 16 | p[1] << 8 | p[2]) | BIT(15);
                ((u16 *)data)[t] = c;
            }
            else
            {
                int index = png->pixels[i];
                index = index < png->num_colors ? remap[index] : 0;
                if (bits == 8)
                    data[t] = (uint8_t)index;
                else
                    data[t >> 1] |= (uint8_t)(index << ((t & 1) * 4));
            }
        }
    }

    int name = 0;
    bool ok = glGenTextures(1, &name) && glBindTexture(0, name)
              && glTexImage2D(0, 0, type, tw, th, 0, param, data)
              && (pal_size == 0 || glColorTableEXT(0, 0, pal_size, 0, 0, pal));
    free(data);
    ll_gfx_texture_changed();

    if (!ok)
    {
        if (name)
            glDeleteTextures(1, &name);
        snprintf(err, err_size, "out of video memory: %ux%u image needs %u KB, "
                 "%u KB of %u KB in use", (unsigned)png->w, (unsigned)png->h,
                 (unsigned)((tex_bytes + pal_size * 2 + 1023) / 1024),
                 vram_used / 1024, (128 + 128 + 64));
        return 0;
    }

    *vram = (unsigned)(tex_bytes + pal_size * 2);
    vram_used += *vram;
    return name;
}

// --- Lua objects ------------------------------------------------------------

// Faster than luaL_checkudata, which looks the metatable up by name in the
// registry: compares the metatable pointer saved at registration
LLImage *ll_image_check(lua_State *L, int idx)
{
    LLImage *img = lua_touserdata(L, idx);
    bool ok = false;
    if (img && lua_getmetatable(L, idx))
    {
        ok = lua_topointer(L, -1) == image_mt;
        lua_pop(L, 1);
    }
    if (!ok)
        luaL_typeerror(L, idx, "image");
    if (img->tex == 0)
        luaL_argerror(L, idx, "image has been freed");
    return img;
}

void ll_image_frame(lua_State *L, const LLImage *img, int frame,
                    int *x, int *y, int *w, int *h)
{
    if (img->frames == 0)
    {
        if (frame != 0)
            luaL_error(L, "frame %d: the image has no frames (use image(name, w, h))",
                       frame);
        *x = img->x, *y = img->y, *w = img->w, *h = img->h;
        return;
    }
    if (frame < 0 || frame >= img->frames)
        luaL_error(L, "frame %d does not exist (0..%d)", frame, img->frames - 1);
    *x = img->x + (frame % img->cols) * img->fw;
    *y = img->y + (frame / img->cols) * img->fh;
    *w = img->fw;
    *h = img->fh;
}

static LLImage *push_image(lua_State *L)
{
    LLImage *img = lua_newuserdatauv(L, sizeof(LLImage), 1);
    memset(img, 0, sizeof(*img));
    luaL_setmetatable(L, IMAGE_MT);
    return img;
}

// Makes a view of the image at 'parent' (shares its texture)
static LLImage *push_view(lua_State *L, int parent, const LLImage *src)
{
    LLImage *view = push_image(L);
    *view = *src;
    view->owner = false;
    view->vram = 0;
    view->fw = view->fh = view->cols = view->frames = 0;
    lua_pushvalue(L, parent);
    lua_setiuservalue(L, -2, 1); // Keeps the owner (and texture) alive
    return view;
}

static void set_frames(lua_State *L, LLImage *img, int fw, int fh)
{
    if (fw <= 0 || fh <= 0 || fw > img->w || fh > img->h)
        luaL_error(L, "frame size %dx%d does not fit the %dx%d image",
                   fw, fh, img->w, img->h);
    img->fw = fw;
    img->fh = fh;
    img->cols = img->w / fw;
    img->frames = img->cols * (img->h / fh);
}

// Loads gfx/<name>.png, or returns the image already loaded
static int load_image(lua_State *L, const char *name)
{
    lua_getfield(L, LUA_REGISTRYINDEX, CACHE_KEY);
    if (lua_getfield(L, -1, name) == LUA_TUSERDATA)
    {
        lua_remove(L, -2);
        return 1;
    }
    lua_pop(L, 1);

    if (cart == NULL)
        luaL_error(L, "images can only be loaded by a cart");

    // "hero" -> gfx/hero.png; a name with .png is used as it is (D4)
    char path[LL_PATH_MAX], rel[LL_PATH_MAX];
    size_t len = strlen(name);
    bool has_ext = len > 4 && strcasecmp(name + len - 4, ".png") == 0;
    snprintf(path, sizeof(path), "gfx/%s%s", name, has_ext ? "" : ".png");
    if (!ll_path_clean(path, rel, sizeof(rel)))
        luaL_error(L, "bad image name '%s'", name);

    size_t size;
    char *file = ll_cart_read(cart, rel, &size);
    if (file == NULL)
        luaL_error(L, "cannot read %s", rel);

    char err[160];
    LLPng png;
    bool ok = ll_png_decode((const uint8_t *)file, size, &png, err, sizeof(err));
    free(file);
    if (!ok)
        luaL_error(L, "%s: %s", rel, err);

    unsigned vram;
    int tex = ll_image_upload(&png, &vram, err, sizeof(err));
    if (tex == 0)
    {
        // Unused images may still hold textures: collect them and retry
        lua_gc(L, LUA_GCCOLLECT);
        tex = ll_image_upload(&png, &vram, err, sizeof(err));
    }
    int w = png.w, h = png.h;
    ll_png_free(&png);
    if (tex == 0)
        luaL_error(L, "%s: %s", rel, err);

    LLImage *img = push_image(L);
    img->tex = tex;
    img->w = w;
    img->h = h;
    img->owner = true;
    img->vram = vram;

    lua_pushvalue(L, -1);
    lua_setfield(L, -3, name); // Cache
    lua_remove(L, -2);
    return 1;
}

// image(name [, fw, fh]) -> image
static int l_image(lua_State *L)
{
    const char *name = luaL_checkstring(L, 1);
    bool frames = !lua_isnoneornil(L, 2);
    int fw = frames ? (int)luaL_checkinteger(L, 2) : 0;
    int fh = frames ? (int)luaL_optinteger(L, 3, fw) : 0;
    lua_settop(L, 1);
    load_image(L, name);
    if (!frames)
        return 1;

    int owner = lua_gettop(L);
    LLImage *view = push_view(L, owner, lua_touserdata(L, owner));
    set_frames(L, view, fw, fh);
    return 1;
}

// sub(img, x, y, w, h [, fw, fh]) -> image showing a part of img
static int l_sub(lua_State *L)
{
    LLImage *src = ll_image_check(L, 1);
    int x = (int)luaL_checkinteger(L, 2), y = (int)luaL_checkinteger(L, 3);
    int w = (int)luaL_checkinteger(L, 4), h = (int)luaL_checkinteger(L, 5);
    if (x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > src->w || y + h > src->h)
        return luaL_error(L, "sub(%d, %d, %d, %d) is outside the %dx%d image",
                          x, y, w, h, src->w, src->h);

    bool frames = !lua_isnoneornil(L, 6);
    int fw = frames ? (int)luaL_checkinteger(L, 6) : 0;
    int fh = frames ? (int)luaL_optinteger(L, 7, fw) : 0;

    LLImage *view = push_view(L, 1, src);
    view->x = src->x + x;
    view->y = src->y + y;
    view->w = w;
    view->h = h;
    if (frames)
        set_frames(L, view, fw, fh);
    return 1;
}

static int image_gc(lua_State *L)
{
    LLImage *img = luaL_checkudata(L, 1, IMAGE_MT);
    if (img->owner && img->tex)
    {
        glDeleteTextures(1, &img->tex);
        vram_used -= img->vram;
        ll_gfx_texture_changed();
    }
    img->tex = 0;
    return 0;
}

// img.w, img.h, img.frames
static int image_index(lua_State *L)
{
    LLImage *img = luaL_checkudata(L, 1, IMAGE_MT);
    const char *key = luaL_checkstring(L, 2);
    if (strcmp(key, "w") == 0)
        lua_pushinteger(L, img->fw ? img->fw : img->w);
    else if (strcmp(key, "h") == 0)
        lua_pushinteger(L, img->fh ? img->fh : img->h);
    else if (strcmp(key, "frames") == 0)
        lua_pushinteger(L, img->frames ? img->frames : 1);
    else
        lua_pushnil(L);
    return 1;
}

static int image_tostring(lua_State *L)
{
    LLImage *img = luaL_checkudata(L, 1, IMAGE_MT);
    lua_pushfstring(L, "image %dx%d", img->w, img->h);
    return 1;
}

void ll_image_register(lua_State *L)
{
    static const luaL_Reg meta[] = {
        { "__gc", image_gc },
        { "__index", image_index },
        { "__tostring", image_tostring },
        { NULL, NULL },
    };
    luaL_newmetatable(L, IMAGE_MT);
    luaL_setfuncs(L, meta, 0);
    image_mt = lua_topointer(L, -1);
    lua_pop(L, 1);

    // Loaded images by name; weak values so unused images can be collected
    lua_newtable(L);
    lua_newtable(L);
    lua_pushliteral(L, "v");
    lua_setfield(L, -2, "__mode");
    lua_setmetatable(L, -2);
    lua_setfield(L, LUA_REGISTRYINDEX, CACHE_KEY);

    lua_register(L, "image", l_image);
    lua_register(L, "sub", l_sub);
}
