// SPDX-License-Identifier: Zlib
//
// LiteLua - images: PNG files as DS textures (D10), Lua image objects.

#ifndef LL_IMAGE_H__
#define LL_IMAGE_H__

#include <stdbool.h>

#include "lua.h"

#include "ll_cart.h"

typedef struct {
    int tex;          // GL texture name, shared by views; 0 when freed
    int x, y, w, h;   // Part of the texture this image shows (texels)
    int fw, fh;       // Frame size; 0 = the image is one frame
    int cols, frames; // Frame grid
    bool owner;       // Frees the texture when collected (views do not)
    unsigned vram;    // Bytes of texture + palette memory (owner only)
} LLImage;

// Sets up the texture VRAM banks. Call once after the 3D engine is set up.
void ll_image_init(void);

// Frees all textures (also any leaked by an abandoned state) before a cart
// starts. 'cart' is used to load files (NULL: images cannot be loaded).
void ll_image_reset(const LLCart *cart);

// Registers image() and sub().
void ll_image_register(lua_State *L);

// Checks that argument 'idx' is an image.
LLImage *ll_image_check(lua_State *L, int idx);

// Region of frame 'frame' (0-based) of an image; raises a Lua error if the
// frame does not exist.
void ll_image_frame(lua_State *L, const LLImage *img, int frame,
                    int *x, int *y, int *w, int *h);

// Texture and palette memory in use, in bytes.
unsigned ll_image_vram_used(void);

#endif // LL_IMAGE_H__
