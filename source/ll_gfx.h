// SPDX-License-Identifier: Zlib
//
// LiteLua - graphics: 2D drawing with the 3D engine (D1, D22).

#ifndef LL_GFX_H__
#define LL_GFX_H__

#include <stdbool.h>

#include "lua.h"

// Sets up the 3D engine on the top screen. Call once at boot.
void ll_gfx_init(void);

// Resets the draw state (color, camera, clip, alpha) for a new cart and
// shows an empty frame.
void ll_gfx_reset(void);

// Starts a frame of the given screen (0 = top, 1 = bottom). Until P6 only the
// top screen is drawn; draw calls for the bottom screen are ignored.
void ll_gfx_begin(int screen);

// Ends the frame started by ll_gfx_begin and sends it to the 3D engine; the
// image is shown from the next VBlank. 'overlay' is the text of the
// statistics overlay, or NULL.
void ll_gfx_end(const char *overlay);

// Polygons and vertices the game sent in the last top screen frame (the
// overlay not included).
void ll_gfx_counts(int *polys, int *verts);

// Uploads the built-in font. Call after the textures were reset (each cart).
void ll_gfx_font_reset(void);

// Must be called after any glBindTexture outside ll_gfx.c (texture uploads).
void ll_gfx_texture_changed(void);

// Registers the drawing functions as globals.
void ll_gfx_register(lua_State *L);

#endif // LL_GFX_H__
