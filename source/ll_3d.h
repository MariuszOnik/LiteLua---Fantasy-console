// SPDX-License-Identifier: Zlib
//
// LiteLua - 3D layer (D60, experimental): a perspective camera, height grid
// terrain and batches of billboards (camera3d, isogrid:draw3d, billboards).

#ifndef LL_3D_H__
#define LL_3D_H__

#include <stdint.h>

#include "lua.h"

#include "ll_gfx.h"
#include "ll_image.h"

// Back to the default camera; called at the start of every _draw (D30).
void ll_3d_reset(void);

// Draws the cells of 'g' as flat squares of one tile in the 3D view: cell
// (c, r) covers x c..c+1, y r..r+1, corner heights times 'hscale' (tiles per
// height unit, 20.12) up. With 'tpt' > 0 the frames are ignored: the whole
// image (power-of-two sides) repeats over the ground, 'tpt' texels per tile
// (1..32), and rows of cells are drawn as strips (half the vertices).
// Kept as display lists of 8x8 cells, rebuilt when the grid or the arguments
// change. With strips, chunks farther than 'lod' tiles from the eye (0 = off)
// use every second corner (a quarter of the polygons). 'under' >= 0 (RGB15)
// draws a flat quad of that color just under each chunk, which fills the
// cracks the DS leaves between polygons.
void ll_3d_terrain(const LLImage *img, LLIsoGrid *g, int32_t hscale, int tpt, float lod,
                   int under);

// Frees the display lists of a grid (when it is collected).
void ll_3d_free(LLIsoGrid *g);

// Registers camera3d() and billboards().
void ll_3d_register(lua_State *L);

#endif // LL_3D_H__
