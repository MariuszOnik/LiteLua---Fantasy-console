// SPDX-License-Identifier: Zlib
//
// LiteLua - graphics: 2D drawing with the 3D engine (D1, D22).
//
// Every primitive is a polygon of the 3D engine, drawn with an orthographic
// projection like gl2d. Vertex coordinates are quarter pixels (projection
// scaled by 4, like gl2d, but the modelview matrix is identity): rotated and
// zoomed sprites get sub-pixel positions. The camera offset and zoom are
// applied in C before the vertices are sent. The depth
// grows with every primitive, so later calls are drawn on top. Translucent
// polygons get changing polygon IDs (the DS only blends polygons with a
// different ID) and the frame is flushed with manual translucency sorting,
// so the drawing order is kept.
//
// The 3D image is rebuilt in every frame: what is not drawn in _draw is not
// on the screen. The draw state is rebuilt too (D30): every _draw starts with
// the default color, alpha, camera, clip, tint and background, whatever the
// previous _draw (other screen, last frame) has set.
//
// Both screens use the 3D engine (dual30, D5, D28), like the BlocksDS example
// video_capture/dual_screen_3d: the engine renders the top and the bottom
// screen in turns, one per VBlank, and every rendered image is captured to a
// VRAM bank: top -> bank C, bottom -> bank D. The screens always show
// captured images: the main engine shows the bank it is capturing into, the
// sub engine shows the other bank (bank C as a bitmap background, bank D as a
// grid of 12 bitmap sprites). If a frame is late, both screens keep showing
// their last image, without flicker. The configuration is switched in the
// VBlank interrupt right after the buffers of a flushed screen were swapped.

#include <math.h>
#include <string.h>

#include <gl2d.h>
#include <nds.h>

#include "lauxlib.h"

#include "ll_gfx.h"
#include "ll_image.h"
#include "ll_log.h"

#define SCREEN_W 256
#define SCREEN_H 192
#define SCALE_SHIFT 2  // Projection scale, the same as gl2d
#define MAX_DEPTH 4095 // Depth must stay inside the near/far planes
#define V16_LIMIT 32767 // Vertex coordinates are 16-bit (quarter pixels)
#define ZOOM_ONE 4096    // Zoom in 20.12 fixed point
#define WHITE 0x7fff

#define DEFAULT_COLOR 12 // Palette entry used when no color is given

// Built-in 6x8 font (tools/make_font.py): sheet of 16 x 8 cells
#include "ll_font6x8.inc"
#define FONT_W 6
#define FONT_H 8
#define FONT_COLS 16
#define FONT_UNKNOWN 113 // Glyph index of the box for unknown characters
#define TAB_COLS 4

static LLImage font;

// Sweetie 16 palette by GrafxKid (D22)
static const u32 palette_rgb[16] = {
    0x1a1c2c, 0x5d275d, 0xb13e53, 0xef7d57, 0xffcd75, 0xa7f070, 0x38b764, 0x257179,
    0x29366f, 0x3b5dc9, 0x41a6f6, 0x73eff7, 0xf4f4f4, 0x94b0c2, 0x566c86, 0x333c57,
};
static u16 palette[16];

static struct {
    bool active;       // Inside ll_gfx_begin/end
    int screen;        // Screen of the current frame (0 top, 1 bottom)
    int depth;
    int poly_id;       // Rotating ID for translucent polygons
    u16 color;
    int alpha;         // 0..31, 0 = invisible
    int cam_x, cam_y;
    int zoom;          // 20.12 fixed point
    int clip_x, clip_y, clip_w, clip_h;
    u16 clear_color[2]; // Background of each screen (cls)
    int bound;         // Texture bound in the 3D engine, -1 = unknown
    u16 tint[4];       // Sprite corner colors: top left, top right,
                       // bottom right, bottom left
    bool tint_corners; // The four tint colors differ
    int stroke;        // Width of lines and outlines in pixels (D31)
    bool warned;       // Draw state set outside _draw was logged (once per cart)
} gs;

static u16 rgb15(u32 rgb)
{
    unsigned r = (rgb >> 16) & 0xff, g = (rgb >> 8) & 0xff, b = rgb & 0xff;
    return RGB15((r * 31 + 127) / 255, (g * 31 + 127) / 255, (b * 31 + 127) / 255);
}

// --- Arguments --------------------------------------------------------------

// Number argument as a pixel coordinate (floats are rounded down)
// Coordinates are limited to +-COORD_MAX pixels, so world positions in
// quarter pixels (and their differences) fit in 32 bits.
#define COORD_MAX (1 << 20)

static int arg_int(lua_State *L, int i)
{
    int isint;
    lua_Integer v = lua_tointegerx(L, i, &isint);
    if (!isint)
    {
        lua_Number n = luaL_checknumber(L, i);
        v = n < -COORD_MAX ? -COORD_MAX : n > COORD_MAX ? COORD_MAX : (int)floorf(n);
    }
    return v < -COORD_MAX ? -COORD_MAX : v > COORD_MAX ? COORD_MAX : (int)v;
}

// Color argument: 0-15 = palette entry, otherwise 0xRRGGBB. None/nil = the
// current color.
static u16 arg_color(lua_State *L, int i)
{
    if (lua_isnoneornil(L, i))
        return gs.color;
    lua_Integer c = luaL_checkinteger(L, i);
    if (c >= 0 && c < 16)
        return palette[c];
    if (c < 0 || c > 0xffffff)
        luaL_argerror(L, i, "color must be 0-15 or 0xRRGGBB");
    return rgb15((u32)c);
}

static int clamp(int v, int lo, int hi)
{
    return v < lo ? lo : v > hi ? hi : v;
}

// --- Emitting polygons ------------------------------------------------------

// Prepares a polygon: returns false if nothing would be visible
static bool poly_begin(bool textured)
{
    // Outside _draw (e.g. in _update) drawing does nothing
    if (!gs.active || gs.alpha == 0 || gs.clip_w <= 0 || gs.clip_h <= 0)
        return false;

    int id = 0;
    if (gs.alpha < 31)
    {
        gs.poly_id = gs.poly_id % 62 + 1; // 1..62; 63 is the clear plane
        id = gs.poly_id;
    }
    glPolyFmt(POLY_ALPHA(gs.alpha) | POLY_CULL_NONE | POLY_ID(id));
    if (!textured && gs.bound != 0)
    {
        glBindTexture(0, 0);
        gs.bound = 0;
    }
    return true;
}

// Prepares an untextured primitive of one color
static bool prim_begin(u16 color)
{
    if (!poly_begin(false))
        return false;
    glColor(color);
    return true;
}

void ll_gfx_texture_changed(void)
{
    gs.bound = -1;
}

static void prim_end(void)
{
    if (gs.depth < MAX_DEPTH)
        gs.depth++;
}

// World position in quarter pixels -> vertex coordinate (quarter pixels on
// the screen) with the camera offset and zoom applied
static inline v16 to_vertex(int32_t world_q, int cam)
{
    int32_t v = world_q - cam * 4;
    if (gs.zoom != ZOOM_ONE) // 64-bit multiplication only when zoomed
        v = (int32_t)(((int64_t)v * gs.zoom) >> 12);
    return (v16)(v < -V16_LIMIT ? -V16_LIMIT : v > V16_LIMIT ? V16_LIMIT : v);
}

#define VX(x) to_vertex((x) * 4, gs.cam_x)
#define VY(y) to_vertex((y) * 4, gs.cam_y)
#define VXQ(q) to_vertex(q, gs.cam_x)
#define VYQ(q) to_vertex(q, gs.cam_y)

// A quad of a GL_QUADS batch, corners in pixels
static void quad_px(int x1, int y1, int x2, int y2)
{
    glVertex3v16(VX(x1), VY(y1), gs.depth);
    glVertex2v16(VX(x1), VY(y2));
    glVertex2v16(VX(x2), VY(y2));
    glVertex2v16(VX(x2), VY(y1));
}

static void emit_quad(int x1, int y1, int x2, int y2)
{
    glBegin(GL_QUADS);
    quad_px(x1, y1, x2, y2);
    glEnd();
}

// Thick line (stroke > 1, D31), a quad of a GL_QUADS batch: a rectangle
// around the segment between the pixel centers, with square caps (extended
// by half the width at both ends, which also closes the corners of
// outlines). Even widths are shifted by half a pixel, so horizontal and
// vertical lines cover whole pixels.
static void quad_thick_line(int x1, int y1, int x2, int y2, int w)
{
    float o = (w & 1) ? 0.5f : 1.0f;
    float ax = x1 + o, ay = y1 + o, bx = x2 + o, by = y2 + o;
    float dx = bx - ax, dy = by - ay;
    float len = sqrtf(dx * dx + dy * dy);
    float h = w * 0.5f;
    // u: half width along the line, n = (-uy, ux): half width across it
    float ux = h, uy = 0; // A point is a w x w square
    if (len > 0.001f)
        ux = dx * h / len, uy = dy * h / len;
    glVertex3v16(VXQ(lroundf((ax - ux - uy) * 4)), VYQ(lroundf((ay - uy + ux) * 4)),
                 gs.depth);
    glVertex2v16(VXQ(lroundf((ax - ux + uy) * 4)), VYQ(lroundf((ay - uy - ux) * 4)));
    glVertex2v16(VXQ(lroundf((bx + ux + uy) * 4)), VYQ(lroundf((by + uy - ux) * 4)));
    glVertex2v16(VXQ(lroundf((bx + ux - uy) * 4)), VYQ(lroundf((by + uy + ux) * 4)));
}

// A line is a degenerate triangle, which the DS draws as a line (like gl2d)
static void emit_line(int x1, int y1, int x2, int y2)
{
    glBegin(GL_TRIANGLES);
    glVertex3v16(VX(x1), VY(y1), gs.depth);
    glVertex2v16(VX(x2), VY(y2));
    glVertex2v16(VX(x2), VY(y2));
    glEnd();
}

static void draw_line(int x1, int y1, int x2, int y2, u16 color)
{
    if (!prim_begin(color))
        return;
    if (gs.stroke > 1)
    {
        glBegin(GL_QUADS);
        quad_thick_line(x1, y1, x2, y2, gs.stroke);
        glEnd();
        prim_end();
        return;
    }
    // Include the last pixel: extend the end point by one pixel along the
    // longer axis (extending both would tilt horizontal/vertical lines)
    int dx = x2 - x1, dy = y2 - y1;
    if ((dx < 0 ? -dx : dx) >= (dy < 0 ? -dy : dy))
        x2 += dx >= 0 ? 1 : -1;
    else
        y2 += dy >= 0 ? 1 : -1;
    emit_line(x1, y1, x2, y2);
    prim_end();
}

static void draw_box(int x, int y, int w, int h, u16 color)
{
    if (w <= 0 || h <= 0 || !prim_begin(color))
        return;
    emit_quad(x, y, x + w, y + h);
    prim_end();
}

// Circles up to this radius are drawn pixel by pixel from horizontal spans,
// larger ones as polygons (D31)
#define CIRCLE_SPAN_R 16

// Number of segments of a polygon circle: a multiple of 8, so the polygon is
// symmetric
static int circle_segments(int r)
{
    int n = (8 + r / 2 + 7) & ~7;
    return n > 64 ? 64 : n;
}

// Half widths of the rows of a filled circle of radius r <= CIRCLE_SPAN_R:
// half[dy] is the largest dx with dx^2 + dy^2 <= r^2 + r (pixel centers
// inside radius r + 0.5), -1 outside (dy > r). Integers only: the ARM9 has no
// FPU, so a sqrtf per row would cost more than drawing the circle.
static void disc_halves(int r, int half[CIRCLE_SPAN_R + 2])
{
    for (int dy = 0; dy <= CIRCLE_SPAN_R + 1; dy++)
        half[dy] = -1;
    int t = r * r + r, x = 0;
    for (int dy = r; dy >= 0; dy--)
    {
        while ((x + 1) * (x + 1) + dy * dy <= t)
            x++;
        half[dy] = x;
    }
}

// Rows y1..y2-1 of a span circle: the right half covers dx = lo..hi and the
// left half mirrors it; lo = 0 is one span over the whole row
static void quad_rows(int cx, int y1, int y2, int lo, int hi)
{
    if (lo == 0)
    {
        quad_px(cx - hi, y1, cx + hi + 1, y2);
        return;
    }
    quad_px(cx + lo, y1, cx + hi + 1, y2);
    quad_px(cx - hi, y1, cx - lo + 1, y2);
}

// Pixel exact circle (r <= CIRCLE_SPAN_R): w = 0 is filled, otherwise an
// outline w pixels thick inside the radius. The thin outline (w = 1) is the
// edge of the filled circle (its pixels with an outer neighbor outside), so
// it matches circfill and stays 8-connected. Rows with the same spans are
// merged into one quad.
static void circle_spans(int cx, int cy, int r, int w, u16 color)
{
    if (!prim_begin(color))
        return;
    int outer[CIRCLE_SPAN_R + 2], inner[CIRCLE_SPAN_R + 2];
    disc_halves(r, outer);
    if (w > 1)
        disc_halves(r - w, inner); // r - w < 0: all -1, the circle is filled
    glBegin(GL_QUADS);
    int run_lo = 0, run_hi = 0, run_y = -r;
    for (int dy = -r; dy <= r + 1; dy++)
    {
        int lo = 0, hi = -2; // Past the last row: differs from every row
        if (dy <= r)
        {
            int ady = dy < 0 ? -dy : dy;
            hi = outer[ady];
            if (w == 1)
                lo = outer[ady + 1] + 1;
            else if (w > 1)
                lo = inner[ady] + 1;
            if (lo > hi)
                lo = hi;
        }
        if (dy == -r)
        {
            run_lo = lo, run_hi = hi;
            continue;
        }
        if (lo == run_lo && hi == run_hi)
            continue;
        quad_rows(cx, cy + run_y, cy + dy, run_lo, run_hi);
        run_lo = lo, run_hi = hi, run_y = dy;
    }
    glEnd();
    prim_end();
}

// --- Frame ------------------------------------------------------------------

static void apply_clip(void)
{
    if (gs.clip_w <= 0 || gs.clip_h <= 0)
        return;

    // The viewport limits drawing to the clip rectangle and the projection
    // maps the same rectangle to it, so coordinates stay screen pixels. The
    // DS viewport counts Y from the bottom.
    int x1 = gs.clip_x, y1 = gs.clip_y;
    int x2 = x1 + gs.clip_w, y2 = y1 + gs.clip_h;
    glViewport(x1, SCREEN_H - y2, x2 - 1, SCREEN_H - 1 - y1);

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    glOrthof32(x1 << SCALE_SHIFT, x2 << SCALE_SHIFT, y2 << SCALE_SHIFT,
               y1 << SCALE_SHIFT, -inttof32(1), inttof32(1));
    glMatrixMode(GL_MODELVIEW);
}

// --- Two screens (dual30) ---------------------------------------------------

static volatile int pending_screen = -1; // Flushed, waiting for the swap

// Sub engine sprites showing bank D: a 4x3 grid of 64x64 bitmap sprites
static void setup_sub_sprites(void)
{
    for (int i = 0; i < 128; i++)
        OAM_SUB[i * 4] = ATTR0_DISABLED;

    int i = 0;
    for (int y = 0; y < 3; y++)
    {
        for (int x = 0; x < 4; x++)
        {
            OAM_SUB[i * 4 + 0] = ATTR0_BMP | ATTR0_SQUARE | (64 * y);
            OAM_SUB[i * 4 + 1] = ATTR1_SIZE_64 | (64 * x);
            OAM_SUB[i * 4 + 2] = ATTR2_ALPHA(1) | (8 * 32 * y) | (8 * x);
            i++;
        }
    }
}

// Shows the screens for a frame in which the 3D engine renders 'screen'
static void show(int screen)
{
    u32 capture = DCAP_SIZE(DCAP_SIZE_256x192) | DCAP_MODE(DCAP_MODE_A)
                | DCAP_SRC_A(DCAP_SRC_A_3DONLY) | DCAP_ENABLE;
    if (screen == 0)
    {
        lcdMainOnTop();
        videoSetMode(MODE_VRAM_C);
        videoSetModeSub(MODE_0_2D | DISPLAY_SPR_ACTIVE | DISPLAY_SPR_2D_BMP_256);
        vramSetBankC(VRAM_C_LCD);
        vramSetBankD(VRAM_D_SUB_SPRITE_0x06600000);
        REG_DISPCAPCNT = capture | DCAP_BANK(DCAP_BANK_VRAM_C);
    }
    else
    {
        lcdMainOnBottom();
        videoSetMode(MODE_VRAM_D);
        videoSetModeSub(MODE_5_2D | DISPLAY_BG2_ACTIVE);
        vramSetBankC(VRAM_C_SUB_BG_0x06200000);
        vramSetBankD(VRAM_D_LCD);
        REG_DISPCAPCNT = capture | DCAP_BANK(DCAP_BANK_VRAM_D);
    }
}

void ll_gfx_vblank(void)
{
    int screen = pending_screen;
    if (screen < 0)
        return;
    pending_screen = -1;
    show(screen);
}

void ll_gfx_init(void)
{
    for (int i = 0; i < 16; i++)
        palette[i] = rgb15(palette_rgb[i]);

    // Both capture banks start black (bit 15 = opaque pixel)
    vramSetBankC(VRAM_C_LCD);
    vramSetBankD(VRAM_D_LCD);
    dmaFillHalfWords(0x8000, VRAM_C, 128 * 1024);
    dmaFillHalfWords(0x8000, VRAM_D, 128 * 1024);

    videoSetModeSub(MODE_5_2D | DISPLAY_BG2_ACTIVE);
    bgInitSub(2, BgType_Bmp16, BgSize_B16_256x256, 0, 0);
    setup_sub_sprites();

    glScreen2D();
    ll_image_init();
    show(0);
    ll_gfx_reset();
    ll_gfx_font_reset(); // Also for the cart list before any cart runs
}

// The draw state every _draw starts with (D30); the background is reset
// separately, it is read only when the frame ends
static void reset_draw_state(void)
{
    gs.color = palette[DEFAULT_COLOR];
    gs.alpha = 31;
    gs.cam_x = gs.cam_y = 0;
    gs.zoom = ZOOM_ONE;
    gs.clip_x = gs.clip_y = 0;
    gs.clip_w = SCREEN_W;
    gs.clip_h = SCREEN_H;
    for (int i = 0; i < 4; i++)
        gs.tint[i] = WHITE;
    gs.tint_corners = false;
    gs.stroke = 1;
}

void ll_gfx_reset(void)
{
    gs.active = false;
    reset_draw_state();
    gs.clear_color[0] = gs.clear_color[1] = palette[0];
    gs.bound = -1;
    gs.warned = false;
}

void ll_gfx_begin(int screen)
{
    gs.screen = screen ? 1 : 0;
    glBegin2D();
    // glBegin2D scales the modelview matrix by 4; our vertices are already
    // quarter pixels
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    gs.active = true;
    gs.depth = 0;
    gs.bound = -1;
    reset_draw_state();
    gs.clear_color[gs.screen] = palette[0];
    apply_clip();
}

static void draw_text(const unsigned char *s, size_t len, int x0, int y, u16 color);

// Statistics overlay: a translucent box in the top left corner, drawn in
// screen space whatever the game's camera, zoom, clip and alpha are. Nothing
// is drawn after it and the next _draw resets the state, so the game's state
// is not restored.
static void draw_overlay(const char *text)
{
    reset_draw_state();
    apply_clip();

    int cols = 0, max_cols = 0, lines = 1;
    for (const char *p = text; *p; p++)
    {
        if (*p == '\n')
            lines++, cols = 0;
        else if (++cols > max_cols)
            max_cols = cols;
    }

    gs.alpha = 22;
    draw_box(0, 0, max_cols * FONT_W + 4, lines * FONT_H + 4, palette[0]);
    gs.alpha = 31;
    draw_text((const unsigned char *)text, strlen(text), 2, 2, palette[5]);
}

static int count_polys[2], count_verts[2];

void ll_gfx_counts(int screen, int *polys, int *verts)
{
    *polys = count_polys[screen ? 1 : 0];
    *verts = count_verts[screen ? 1 : 0];
}

void ll_gfx_end(const char *overlay)
{
    if (!gs.active)
        return;

    // What the game sent, before the overlay adds its own polygons (waits
    // until the geometry engine has processed the commands)
    glGetInt(GL_GET_POLYGON_RAM_COUNT, &count_polys[gs.screen]);
    glGetInt(GL_GET_VERTEX_RAM_COUNT, &count_verts[gs.screen]);
    if (overlay)
        draw_overlay(overlay);

    u16 clear = gs.clear_color[gs.screen];
    glClearColor(clear & 31, (clear >> 5) & 31, (clear >> 10) & 31, 31);
    glClearPolyID(63);

    // Back to the full screen for the next frame's glBegin2D
    glViewport(0, 0, SCREEN_W - 1, SCREEN_H - 1);
    glEnd2D();
    glFlush(GL_TRANS_MANUALSORT);
    gs.active = false;

    // The buffers are swapped at the next VBlank; the interrupt then shows
    // this screen
    pending_screen = gs.screen;
}

// --- Lua API ----------------------------------------------------------------

// The draw state only lives inside _draw (D30): set in _init or _update it
// would be reset before the next _draw. Logged once per cart.
static void check_in_draw(const char *name)
{
    if (!gs.active && !gs.warned)
    {
        ll_log("%s() outside _draw has no effect", name);
        gs.warned = true;
    }
}

// cls([col]): clears the screen. Everything drawn before in this frame is
// covered too.
static int l_cls(lua_State *L)
{
    check_in_draw("cls");
    u16 color = lua_isnoneornil(L, 1) ? palette[0] : arg_color(L, 1);
    if (gs.active)
        gs.clear_color[gs.screen] = color;
    if (gs.active && gs.depth > 0)
    {
        int alpha = gs.alpha;
        gs.alpha = 31;
        if (prim_begin(color))
        {
            // Screen space: no camera or zoom
            glBegin(GL_QUADS);
            glVertex3v16(0, 0, gs.depth);
            glVertex2v16(0, SCREEN_H * 4);
            glVertex2v16(SCREEN_W * 4, SCREEN_H * 4);
            glVertex2v16(SCREEN_W * 4, 0);
            glEnd();
            prim_end();
        }
        gs.alpha = alpha;
    }
    return 0;
}

// color([col]): sets the color used when a function gets none
static int l_color(lua_State *L)
{
    check_in_draw("color");
    gs.color = lua_isnoneornil(L, 1) ? palette[DEFAULT_COLOR] : arg_color(L, 1);
    return 0;
}

// alpha([a]): opacity 0..1 of what is drawn next (1 = opaque)
static int l_alpha(lua_State *L)
{
    check_in_draw("alpha");
    lua_Number a = luaL_optnumber(L, 1, 1);
    int v = (int)(a * 31 + 0.5f);
    gs.alpha = clamp(v, 0, 31);
    return 0;
}

// camera([x, y [, zoom]]): screen = (world - camera) * zoom
static int l_camera(lua_State *L)
{
    check_in_draw("camera");
    gs.cam_x = lua_isnoneornil(L, 1) ? 0 : arg_int(L, 1);
    gs.cam_y = lua_isnoneornil(L, 2) ? 0 : arg_int(L, 2);
    lua_Number zoom = luaL_optnumber(L, 3, 1);
    luaL_argcheck(L, zoom >= 1.0f / 16 && zoom <= 16, 3, "zoom must be 1/16 .. 16");
    gs.zoom = (int)(zoom * ZOOM_ONE + 0.5f);
    return 0;
}

// clip([x, y, w, h]): limits drawing to a screen rectangle (no camera)
static int l_clip(lua_State *L)
{
    check_in_draw("clip");
    if (lua_isnoneornil(L, 1))
    {
        gs.clip_x = gs.clip_y = 0;
        gs.clip_w = SCREEN_W;
        gs.clip_h = SCREEN_H;
    }
    else
    {
        int x = arg_int(L, 1), y = arg_int(L, 2);
        int x2 = x + arg_int(L, 3), y2 = y + arg_int(L, 4);
        x = clamp(x, 0, SCREEN_W);
        y = clamp(y, 0, SCREEN_H);
        gs.clip_x = x;
        gs.clip_y = y;
        gs.clip_w = clamp(x2, 0, SCREEN_W) - x;
        gs.clip_h = clamp(y2, 0, SCREEN_H) - y;
    }
    if (gs.active)
    {
        if (gs.clip_w > 0 && gs.clip_h > 0)
            apply_clip();
    }
    return 0;
}

// stroke([w]): width in pixels of lines and outlines drawn next (D31)
static int l_stroke(lua_State *L)
{
    check_in_draw("stroke");
    lua_Number w = luaL_optnumber(L, 1, 1);
    luaL_argcheck(L, w >= 1 && w <= 64, 1, "width must be 1 .. 64");
    gs.stroke = (int)w;
    return 0;
}

// pset(x, y, [col])
static int l_pset(lua_State *L)
{
    int x = arg_int(L, 1), y = arg_int(L, 2);
    draw_box(x, y, 1, 1, arg_color(L, 3));
    return 0;
}

// line(x1, y1, x2, y2, [col])
static int l_line(lua_State *L)
{
    draw_line(arg_int(L, 1), arg_int(L, 2), arg_int(L, 3), arg_int(L, 4),
              arg_color(L, 5));
    return 0;
}

// Reads x, y, w, h; a negative width or height extends to the left/up
static void arg_rect(lua_State *L, int *x, int *y, int *w, int *h)
{
    *x = arg_int(L, 1);
    *y = arg_int(L, 2);
    *w = arg_int(L, 3);
    *h = arg_int(L, 4);
    if (*w < 0)
        *x += *w, *w = -*w;
    if (*h < 0)
        *y += *h, *h = -*h;
}

// rectfill(x, y, w, h, [col])
static int l_rectfill(lua_State *L)
{
    int x, y, w, h;
    arg_rect(L, &x, &y, &w, &h);
    draw_box(x, y, w, h, arg_color(L, 5));
    return 0;
}

// rect(x, y, w, h, [col]): outline, stroke() pixels wide, inside the
// rectangle
static int l_rect(lua_State *L)
{
    int x, y, w, h;
    arg_rect(L, &x, &y, &w, &h);
    u16 color = arg_color(L, 5);
    int t = gs.stroke;
    if (2 * t >= w || 2 * t >= h)
    {
        draw_box(x, y, w, h, color);
        return 0;
    }
    if (!prim_begin(color))
        return 0;
    glBegin(GL_QUADS);
    quad_px(x, y, x + w, y + t);
    quad_px(x, y + h - t, x + w, y + h);
    quad_px(x, y + t, x + t, y + h - t);
    quad_px(x + w - t, y + t, x + w, y + h - t);
    glEnd();
    prim_end();
    return 0;
}

// Vertex i of n of a polygon circle: center (qx, qy) and radius qr in
// quarter pixels. Fixed point sine table (no FPU on the ARM9).
static void circle_vertex(int qx, int qy, int qr, int i, int n, bool first)
{
    s16 a = (s16)((i % n) * DEGREES_IN_CIRCLE / n);
    v16 x = VXQ(qx + (int)(((int64_t)qr * cosLerp(a) + 2048) >> 12));
    v16 y = VYQ(qy + (int)(((int64_t)qr * sinLerp(a) + 2048) >> 12));
    if (first)
        glVertex3v16(x, y, gs.depth);
    else
        glVertex2v16(x, y);
}

// circfill(x, y, r, [col])
static int l_circfill(lua_State *L)
{
    int cx = arg_int(L, 1), cy = arg_int(L, 2), r = arg_int(L, 3);
    u16 color = arg_color(L, 4);
    if (r < 0)
        return 0;
    if (r <= CIRCLE_SPAN_R)
    {
        circle_spans(cx, cy, r, 0, color);
        return 0;
    }
    if (!prim_begin(color))
        return 0;

    // Triangle strip over a convex polygon: v0, v1, vn-1, v2, vn-2, ...
    // Pixel centers: the circle covers cx-r .. cx+r inclusive.
    int n = circle_segments(r);
    int qx = cx * 4 + 2, qy = cy * 4 + 2, qr = r * 4 + 2;
    glBegin(GL_TRIANGLE_STRIP);
    for (int k = 0; k < n; k++)
    {
        int i = k == 0 ? 0 : (k & 1) ? (k + 1) / 2 : n - k / 2;
        circle_vertex(qx, qy, qr, i, n, k == 0);
    }
    glEnd();
    prim_end();
    return 0;
}

// circ(x, y, r, [col]): outline, stroke() pixels thick inside the radius
static int l_circ(lua_State *L)
{
    int cx = arg_int(L, 1), cy = arg_int(L, 2), r = arg_int(L, 3);
    u16 color = arg_color(L, 4);
    int w = gs.stroke;
    if (r < 0)
        return 0;
    if (r <= CIRCLE_SPAN_R)
    {
        circle_spans(cx, cy, r, w, color);
        return 0;
    }
    if (!prim_begin(color))
        return 0;

    int n = circle_segments(r);
    int qx = cx * 4 + 2, qy = cy * 4 + 2;
    if (w == 1)
    {
        // Lines through the pixel centers at distance r, as degenerate
        // triangles of one primitive
        int qr = r * 4;
        glBegin(GL_TRIANGLES);
        for (int i = 0; i < n; i++)
        {
            circle_vertex(qx, qy, qr, i, n, true);
            circle_vertex(qx, qy, qr, i + 1, n, false);
            circle_vertex(qx, qy, qr, i + 1, n, false);
        }
        glEnd();
    }
    else
    {
        // Ring: a strip between the outer edge and w pixels inside
        int qr = r * 4 + 2, qi = qr - w * 4;
        if (qi < 0)
            qi = 0;
        glBegin(GL_TRIANGLE_STRIP);
        for (int i = 0; i <= n; i++)
        {
            circle_vertex(qx, qy, qr, i, n, i == 0);
            circle_vertex(qx, qy, qi, i, n, false);
        }
        glEnd();
    }
    prim_end();
    return 0;
}

// trifill(x1, y1, x2, y2, x3, y3, [col])
static int l_trifill(lua_State *L)
{
    int x1 = arg_int(L, 1), y1 = arg_int(L, 2), x2 = arg_int(L, 3);
    int y2 = arg_int(L, 4), x3 = arg_int(L, 5), y3 = arg_int(L, 6);
    if (!prim_begin(arg_color(L, 7)))
        return 0;
    glBegin(GL_TRIANGLES);
    glVertex3v16(VX(x1), VY(y1), gs.depth);
    glVertex2v16(VX(x2), VY(y2));
    glVertex2v16(VX(x3), VY(y3));
    glEnd();
    prim_end();
    return 0;
}

// tri(x1, y1, x2, y2, x3, y3, [col]): outline
static int l_tri(lua_State *L)
{
    int x1 = arg_int(L, 1), y1 = arg_int(L, 2), x2 = arg_int(L, 3);
    int y2 = arg_int(L, 4), x3 = arg_int(L, 5), y3 = arg_int(L, 6);
    u16 color = arg_color(L, 7);
    if (gs.stroke > 1)
    {
        // One primitive: the overlapping corners are not blended twice
        if (!prim_begin(color))
            return 0;
        glBegin(GL_QUADS);
        quad_thick_line(x1, y1, x2, y2, gs.stroke);
        quad_thick_line(x2, y2, x3, y3, gs.stroke);
        quad_thick_line(x3, y3, x1, y1, gs.stroke);
        glEnd();
        prim_end();
        return 0;
    }
    draw_line(x1, y1, x2, y2, color);
    draw_line(x2, y2, x3, y3, color);
    draw_line(x3, y3, x1, y1, color);
    return 0;
}

// --- Sprites ----------------------------------------------------------------

// Flip argument: nil, "x", "y" or "xy"
static void arg_flip(lua_State *L, int i, bool *fx, bool *fy)
{
    const char *s = luaL_optstring(L, i, "");
    *fx = strchr(s, 'x') != NULL;
    *fy = strchr(s, 'y') != NULL;
    if (strspn(s, "xy") != strlen(s))
        luaL_argerror(L, i, "flip must be \"x\", \"y\" or \"xy\"");
}

// Draws texels (u, v, w, h) of an image on a quad with corners in quarter
// pixels of the world: top left, top right, bottom right, bottom left.
static void draw_textured(const LLImage *img, int u, int v, int w, int h,
                          const int32_t cx[4], const int32_t cy[4],
                          bool flip_x, bool flip_y)
{
    if (!poly_begin(true))
        return;
    if (gs.bound != img->tex)
    {
        glBindTexture(0, img->tex);
        gs.bound = img->tex;
    }

    // Texture coordinates are 1/16 texel. The DS samples at the left/top edge
    // of a pixel, so a flipped side starts just inside the last texel.
    int u1 = u * 16, u2 = (u + w) * 16;
    int v1 = v * 16, v2 = (v + h) * 16;
    if (flip_x)
        u1 = (u + w) * 16 - 1, u2 = u * 16 - 1;
    if (flip_y)
        v1 = (v + h) * 16 - 1, v2 = v * 16 - 1;

    // GL quad order: top left, bottom left, bottom right, top right. The
    // vertex color stays until changed, so one tint color is sent once.
    bool corners = gs.tint_corners;
    glBegin(GL_QUADS);
    glColor(gs.tint[0]);
    glTexCoord2t16(u1, v1);
    glVertex3v16(VXQ(cx[0]), VYQ(cy[0]), gs.depth);
    if (corners)
        glColor(gs.tint[3]);
    glTexCoord2t16(u1, v2);
    glVertex2v16(VXQ(cx[3]), VYQ(cy[3]));
    if (corners)
        glColor(gs.tint[2]);
    glTexCoord2t16(u2, v2);
    glVertex2v16(VXQ(cx[2]), VYQ(cy[2]));
    if (corners)
        glColor(gs.tint[1]);
    glTexCoord2t16(u2, v1);
    glVertex2v16(VXQ(cx[1]), VYQ(cy[1]));
    glEnd();
    prim_end();
}

// Tile layer of a map (P8): the cells inside the visible part of the world
// (camera, zoom and clip) are drawn as quads of one batch with one texture.
// Cell value 0 is empty; n is frame n - 1 of the tileset 'img'.
void ll_gfx_tiles(const LLImage *img, const uint16_t *cells, int map_w,
                  int map_h, int tile_w, int tile_h)
{
    if (img->tex == 0 || img->frames == 0 || !poly_begin(true))
        return;

    // Visible world rectangle: screen = (world - camera) * zoom
    int32_t x1 = gs.cam_x + (int32_t)(((int64_t)gs.clip_x << 12) / gs.zoom);
    int32_t y1 = gs.cam_y + (int32_t)(((int64_t)gs.clip_y << 12) / gs.zoom);
    int32_t x2 = gs.cam_x + (int32_t)(((int64_t)(gs.clip_x + gs.clip_w) << 12) / gs.zoom);
    int32_t y2 = gs.cam_y + (int32_t)(((int64_t)(gs.clip_y + gs.clip_h) << 12) / gs.zoom);
    int tx1 = x1 < 0 ? 0 : x1 / tile_w, ty1 = y1 < 0 ? 0 : y1 / tile_h;
    int tx2 = x2 < 0 ? -1 : x2 / tile_w, ty2 = y2 < 0 ? -1 : y2 / tile_h;
    if (tx2 >= map_w)
        tx2 = map_w - 1;
    if (ty2 >= map_h)
        ty2 = map_h - 1;
    if (tx1 > tx2 || ty1 > ty2)
        return;

    if (gs.bound != img->tex)
    {
        glBindTexture(0, img->tex);
        gs.bound = img->tex;
    }
    glBegin(GL_QUADS);
    glColor(gs.tint[0]);
    for (int ty = ty1; ty <= ty2; ty++)
    {
        const uint16_t *row = cells + ty * map_w;
        int32_t qy1 = ty * tile_h * 4, qy2 = qy1 + tile_h * 4;
        for (int tx = tx1; tx <= tx2; tx++)
        {
            int id = row[tx];
            if (id == 0 || id > img->frames)
                continue;
            int f = id - 1;
            int u = (img->x + (f % img->cols) * img->fw) * 16;
            int v = (img->y + (f / img->cols) * img->fh) * 16;
            int u2 = u + img->fw * 16, v2 = v + img->fh * 16;
            int32_t qx1 = tx * tile_w * 4, qx2 = qx1 + tile_w * 4;
            glTexCoord2t16(u, v);
            glVertex3v16(VXQ(qx1), VYQ(qy1), gs.depth);
            glTexCoord2t16(u, v2);
            glVertex2v16(VXQ(qx1), VYQ(qy2));
            glTexCoord2t16(u2, v2);
            glVertex2v16(VXQ(qx2), VYQ(qy2));
            glTexCoord2t16(u2, v);
            glVertex2v16(VXQ(qx2), VYQ(qy1));
        }
    }
    glEnd();
    prim_end();
}

// Axis-aligned sprite at x, y (pixels) with size dw x dh (pixels)
static void draw_rect_textured(const LLImage *img, int u, int v, int w, int h,
                               int x, int y, int dw, int dh, bool fx, bool fy)
{
    int32_t x1 = x * 4, y1 = y * 4, x2 = (x + dw) * 4, y2 = (y + dh) * 4;
    const int32_t cx[4] = { x1, x2, x2, x1 };
    const int32_t cy[4] = { y1, y1, y2, y2 };
    draw_textured(img, u, v, w, h, cx, cy, fx, fy);
}

// spr(img, x, y, [frame], [flip])
static int l_spr(lua_State *L)
{
    LLImage *img = ll_image_check(L, 1);
    int x = arg_int(L, 2), y = arg_int(L, 3);
    int frame = (int)luaL_optinteger(L, 4, 0);
    bool fx, fy;
    arg_flip(L, 5, &fx, &fy);

    int u, v, w, h;
    ll_image_frame(L, img, frame, &u, &v, &w, &h);
    draw_rect_textured(img, u, v, w, h, x, y, w, h, fx, fy);
    return 0;
}

// sprx(img, x, y, [frame], [angle], [sx], [sy], [flip]): x, y is the center;
// angle in degrees, clockwise; sx, sy scale (sy defaults to sx)
static int l_sprx(lua_State *L)
{
    LLImage *img = ll_image_check(L, 1);
    lua_Number x = luaL_checknumber(L, 2), y = luaL_checknumber(L, 3);
    int frame = (int)luaL_optinteger(L, 4, 0);
    lua_Number angle = luaL_optnumber(L, 5, 0);
    lua_Number sx = luaL_optnumber(L, 6, 1);
    lua_Number sy = luaL_optnumber(L, 7, sx);
    bool fx, fy;
    arg_flip(L, 8, &fx, &fy);

    int u, v, w, h;
    ll_image_frame(L, img, frame, &u, &v, &w, &h);

    // Corners around the center in quarter pixels, rotated with the DS
    // sine table (32768 per turn, 4.12 results)
    int hw = (int)(w * sx * 2), hh = (int)(h * sy * 2); // Half size * 4
    int a = (int)(angle * (32768.0f / 360.0f));
    int c = cosLerp(a), s = sinLerp(a);
    int32_t ox = (int32_t)(x * 4 + 0.5f), oy = (int32_t)(y * 4 + 0.5f);
    static const int8_t sxs[4] = { -1, 1, 1, -1 }, sys[4] = { -1, -1, 1, 1 };
    int32_t cx[4], cy[4];
    for (int i = 0; i < 4; i++)
    {
        int lx = sxs[i] * hw, ly = sys[i] * hh;
        cx[i] = ox + ((lx * c - ly * s) >> 12);
        cy[i] = oy + ((lx * s + ly * c) >> 12);
    }
    draw_textured(img, u, v, w, h, cx, cy, fx, fy);
    return 0;
}

// sspr(img, sx, sy, sw, sh, dx, dy, [dw], [dh], [flip]): part of an image,
// stretched to dw x dh (default: the same size)
static int l_sspr(lua_State *L)
{
    LLImage *img = ll_image_check(L, 1);
    int sx = arg_int(L, 2), sy = arg_int(L, 3);
    int sw = arg_int(L, 4), sh = arg_int(L, 5);
    int dx = arg_int(L, 6), dy = arg_int(L, 7);
    int dw = lua_isnoneornil(L, 8) ? sw : arg_int(L, 8);
    int dh = lua_isnoneornil(L, 9) ? sh : arg_int(L, 9);
    bool fx, fy;
    arg_flip(L, 10, &fx, &fy);

    if (sx < 0 || sy < 0 || sw <= 0 || sh <= 0 || sx + sw > img->w || sy + sh > img->h)
        return luaL_error(L, "sspr: part %d, %d, %d, %d is outside the %dx%d image",
                          sx, sy, sw, sh, img->w, img->h);
    if (dw == 0 || dh == 0)
        return 0;
    if (dw < 0)
        dx += dw, dw = -dw, fx = !fx;
    if (dh < 0)
        dy += dh, dh = -dh, fy = !fy;
    draw_rect_textured(img, img->x + sx, img->y + sy, sw, sh, dx, dy, dw, dh, fx, fy);
    return 0;
}

// --- Text -------------------------------------------------------------------

void ll_gfx_font_reset(void)
{
    static LLPng png;
    static bool decoded;
    char err[96];

    if (!decoded)
    {
        decoded = ll_png_decode(font6x8_png, sizeof(font6x8_png), &png, err,
                                sizeof(err));
        if (!decoded)
            ll_log("font: %s", err);
    }

    memset(&font, 0, sizeof(font));
    if (decoded)
    {
        font.tex = ll_image_upload(&png, &font.vram, err, sizeof(err));
        if (font.tex == 0)
            ll_log("font: %s", err);
        font.w = png.w;
        font.h = png.h;
    }
}

// Decodes one UTF-8 character; invalid bytes give 0xFFFD
static unsigned utf8_next(const unsigned char **p, const unsigned char *end)
{
    const unsigned char *s = *p;
    unsigned c = *s++;
    int extra = c >= 0xf0 ? 3 : c >= 0xe0 ? 2 : c >= 0xc0 ? 1 : 0;
    if (c >= 0x80 && extra == 0)
    {
        *p = s;
        return 0xfffd;
    }
    if (extra)
        c &= 0x3f >> extra;
    for (int i = 0; i < extra; i++)
    {
        if (s >= end || (*s & 0xc0) != 0x80)
        {
            *p = s;
            return 0xfffd;
        }
        c = (c << 6) | (*s++ & 0x3f);
    }
    *p = s;
    return c;
}

// Glyph index in the font sheet (order of tools/make_font.py)
static int glyph_index(unsigned c)
{
    // ąćęłńóśźż ĄĆĘŁŃÓŚŹŻ follow ASCII 32-126 (95 glyphs)
    static const unsigned short polish[18] = {
        0x105, 0x107, 0x119, 0x142, 0x144, 0xf3, 0x15b, 0x17a, 0x17c,
        0x104, 0x106, 0x118, 0x141, 0x143, 0xd3, 0x15a, 0x179, 0x17b,
    };
    if (c >= 32 && c < 127)
        return (int)c - 32;
    for (int i = 0; i < 18; i++)
    {
        if (polish[i] == c)
            return 95 + i;
    }
    return FONT_UNKNOWN;
}

// Draws text with the built-in 6x8 font. '\n' starts a new line, tabs go to
// the next multiple of 4 columns.
static void draw_text(const unsigned char *s, size_t len, int x0, int y, u16 color)
{
    const unsigned char *end = s + len;
    if (font.tex == 0 || len == 0 || !poly_begin(true))
        return;
    if (gs.bound != font.tex)
    {
        glBindTexture(0, font.tex);
        gs.bound = font.tex;
    }

    // All glyphs are quads of one polygon list at the same depth
    glColor(color);
    glBegin(GL_QUADS);
    bool first = true;
    int col = 0;
    while (s < end)
    {
        unsigned c = utf8_next(&s, end);
        if (c == '\n')
        {
            y += FONT_H;
            col = 0;
            continue;
        }
        if (c == '\t')
        {
            col = (col / TAB_COLS + 1) * TAB_COLS;
            continue;
        }
        if (c == ' ')
        {
            col++;
            continue;
        }

        int g = glyph_index(c);
        int u = (g % FONT_COLS) * FONT_W * 16, v = (g / FONT_COLS) * FONT_H * 16;
        int x = x0 + col * FONT_W;
        int32_t qx1 = x * 4, qy1 = y * 4;
        int32_t qx2 = (x + FONT_W) * 4, qy2 = (y + FONT_H) * 4;

        glTexCoord2t16(u, v);
        if (first)
            glVertex3v16(VXQ(qx1), VYQ(qy1), gs.depth);
        else
            glVertex2v16(VXQ(qx1), VYQ(qy1));
        first = false;
        glTexCoord2t16(u, v + FONT_H * 16);
        glVertex2v16(VXQ(qx1), VYQ(qy2));
        glTexCoord2t16(u + FONT_W * 16, v + FONT_H * 16);
        glVertex2v16(VXQ(qx2), VYQ(qy2));
        glTexCoord2t16(u + FONT_W * 16, v);
        glVertex2v16(VXQ(qx2), VYQ(qy1));
        col++;
    }
    glEnd();
    prim_end();
}

// text(s, x, y, [col])
static int l_text(lua_State *L)
{
    size_t len;
    const unsigned char *s = (const unsigned char *)luaL_checklstring(L, 1, &len);
    int x = arg_int(L, 2), y = arg_int(L, 3);
    draw_text(s, len, x, y, arg_color(L, 4));
    return 0;
}

// textw(s) -> w, h: size of the text in pixels (widest line, all lines)
static int l_textw(lua_State *L)
{
    size_t len;
    const unsigned char *s = (const unsigned char *)luaL_checklstring(L, 1, &len);
    const unsigned char *end = s + len;
    int col = 0, max_col = 0, lines = len > 0 ? 1 : 0;
    while (s < end)
    {
        unsigned c = utf8_next(&s, end);
        if (c == '\n')
        {
            lines++;
            col = 0;
            continue;
        }
        col = c == '\t' ? (col / TAB_COLS + 1) * TAB_COLS : col + 1;
        if (col > max_col)
            max_col = col;
    }
    lua_pushinteger(L, max_col * FONT_W);
    lua_pushinteger(L, lines * FONT_H);
    return 2;
}

// tint([col]) or tint(c1, c2, c3, c4): colors multiplied with the sprites
// drawn next; four colors are the corners top left, top right, bottom right,
// bottom left. tint() removes the tint.
static int l_tint(lua_State *L)
{
    check_in_draw("tint");
    int n = lua_gettop(L);
    if (n == 0 || lua_isnil(L, 1))
    {
        for (int i = 0; i < 4; i++)
            gs.tint[i] = WHITE;
    }
    else if (n < 4)
    {
        u16 c = arg_color(L, 1);
        for (int i = 0; i < 4; i++)
            gs.tint[i] = c;
    }
    else
    {
        for (int i = 0; i < 4; i++)
            gs.tint[i] = arg_color(L, i + 1);
    }
    gs.tint_corners = gs.tint[1] != gs.tint[0] || gs.tint[2] != gs.tint[0]
                      || gs.tint[3] != gs.tint[0];
    return 0;
}

// --- Drawing from C (error screen, cart list) --------------------------------

u16 ll_gfx_color(u32 c)
{
    return c < 16 ? palette[c] : rgb15(c);
}

void ll_gfx_cls(u32 color)
{
    gs.clear_color[gs.screen] = ll_gfx_color(color);
}

void ll_gfx_rectfill(int x, int y, int w, int h, u32 color)
{
    draw_box(x, y, w, h, ll_gfx_color(color));
}

void ll_gfx_text(int x, int y, const char *s, size_t len, u32 color)
{
    draw_text((const unsigned char *)s, len, x, y, ll_gfx_color(color));
}

void ll_gfx_alpha(int alpha)
{
    gs.alpha = clamp(alpha, 0, 31);
}

void ll_gfx_frame(void (*draw)(int screen, void *ud), void *ud)
{
    for (int screen = 0; screen < 2; screen++)
    {
        ll_gfx_begin(screen);
        draw(screen, ud);
        ll_gfx_end(NULL);
        swiWaitForVBlank();
    }
}

void ll_gfx_register(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        { "cls", l_cls },
        { "color", l_color },
        { "alpha", l_alpha },
        { "camera", l_camera },
        { "clip", l_clip },
        { "stroke", l_stroke },
        { "pset", l_pset },
        { "line", l_line },
        { "rect", l_rect },
        { "rectfill", l_rectfill },
        { "circ", l_circ },
        { "circfill", l_circfill },
        { "tri", l_tri },
        { "trifill", l_trifill },
        { "spr", l_spr },
        { "sprx", l_sprx },
        { "sspr", l_sspr },
        { "tint", l_tint },
        { "text", l_text },
        { "textw", l_textw },
        { NULL, NULL },
    };

    lua_pushglobaltable(L);
    luaL_setfuncs(L, funcs, 0);
    lua_pop(L, 1);
}
