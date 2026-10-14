// SPDX-License-Identifier: Zlib
//
// LiteLua - graphics: 2D drawing with the 3D engine (D1, D22).

#ifndef LL_GFX_H__
#define LL_GFX_H__

#include <stdbool.h>
#include <stddef.h>

#include <nds/ndstypes.h>

#include "lua.h"

#include "ll_image.h"

// Sets up the 3D engine for both screens (dual30). Call once at boot, after
// the VBlank interrupt handler is installed (ll_log_init).
void ll_gfx_init(void);

// Called by the VBlank interrupt: shows the screen whose frame was flushed.
void ll_gfx_vblank(void);

// Resets the draw state (color, camera, clip, alpha, tint, backgrounds) for a
// new cart.
void ll_gfx_reset(void);

// Starts a frame of the given screen (0 = top, 1 = bottom) with the default
// draw state and background (D30). Frames of the two screens must alternate,
// one per VBlank.
void ll_gfx_begin(int screen);

// Ends the frame started by ll_gfx_begin and sends it to the 3D engine; the
// image is shown from the next VBlank. 'overlay' is the text of the
// statistics overlay, or NULL.
void ll_gfx_end(const char *overlay);

// Polygons and vertices the game sent in the last frame of a screen (the
// overlay not included).
void ll_gfx_counts(int screen, int *polys, int *verts);

// Uploads the built-in font. Call after the textures were reset (each cart).
void ll_gfx_font_reset(void);

// Must be called after any glBindTexture outside ll_gfx.c (texture uploads).
void ll_gfx_texture_changed(void);

// Drawing from C, for the screens of the engine (error screen, cart list).
// Colors: 0-15 = palette, otherwise 0xRRGGBB. Use between ll_gfx_begin/end,
// or inside the callback of ll_gfx_frame.
u16 ll_gfx_color(u32 color);
void ll_gfx_cls(u32 color);
void ll_gfx_rectfill(int x, int y, int w, int h, u32 color);
void ll_gfx_text(int x, int y, const char *s, size_t len, u32 color);
void ll_gfx_alpha(int alpha); // 0..31

// Draws one game frame of both screens: draw(0, ud), then draw(1, ud), each
// followed by its VBlank. Each screen starts with the default draw state.
void ll_gfx_frame(void (*draw)(int screen, void *ud), void *ud);

// Draws the visible cells of a tile layer (P8): 'cells' is map_w x map_h
// values, 0 = empty, n = frame n - 1 of 'img' (tile_w x tile_h frames).
// Uses the camera, zoom, clip, alpha and tint color of the current _draw.
void ll_gfx_tiles(const LLImage *img, const uint16_t *cells, int map_w,
                  int map_h, int tile_w, int tile_h);

// Registers the drawing functions as globals.
void ll_gfx_register(lua_State *L);

#endif // LL_GFX_H__
