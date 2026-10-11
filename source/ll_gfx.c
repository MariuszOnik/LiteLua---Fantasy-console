// SPDX-License-Identifier: Zlib
//
// LiteLua - graphics: 2D drawing with the 3D engine (D1, D22).
//
// Every primitive is a polygon of the 3D engine, drawn with an orthographic
// projection like gl2d (coordinates scaled by 4 for precision). The depth
// grows with every primitive, so later calls are drawn on top. Translucent
// polygons get changing polygon IDs (the DS only blends polygons with a
// different ID) and the frame is flushed with manual translucency sorting,
// so the drawing order is kept.
//
// The 3D image is rebuilt in every frame: what is not drawn in _draw is not
// on the screen. Until P6 (dual30) only the top screen is drawn.

#include <math.h>

#include <gl2d.h>
#include <nds.h>

#include "lauxlib.h"

#include "ll_gfx.h"
#include "ll_log.h"

#define SCREEN_W 256
#define SCREEN_H 192
#define SCALE_SHIFT 2  // Projection scale, the same as gl2d
#define MAX_DEPTH 4095 // Depth must stay inside the near/far planes
#define COORD_LIMIT 8191 // Vertex coordinates are 16-bit, scaled by 4 later

#define DEFAULT_COLOR 12 // Palette entry used when no color is given

// Sweetie 16 palette by GrafxKid (D22)
static const u32 palette_rgb[16] = {
    0x1a1c2c, 0x5d275d, 0xb13e53, 0xef7d57, 0xffcd75, 0xa7f070, 0x38b764, 0x257179,
    0x29366f, 0x3b5dc9, 0x41a6f6, 0x73eff7, 0xf4f4f4, 0x94b0c2, 0x566c86, 0x333c57,
};
static u16 palette[16];

static struct {
    bool active;       // Inside ll_gfx_begin/end of the top screen
    bool warned;       // Bottom screen warning already logged
    int depth;
    int poly_id;       // Rotating ID for translucent polygons
    u16 color;
    int alpha;         // 0..31, 0 = invisible
    int cam_x, cam_y;
    int clip_x, clip_y, clip_w, clip_h;
    u16 clear_color;
} gs;

static u16 rgb15(u32 rgb)
{
    unsigned r = (rgb >> 16) & 0xff, g = (rgb >> 8) & 0xff, b = rgb & 0xff;
    return RGB15((r * 31 + 127) / 255, (g * 31 + 127) / 255, (b * 31 + 127) / 255);
}

// --- Arguments --------------------------------------------------------------

// Number argument as a pixel coordinate (floats are rounded down)
static int arg_int(lua_State *L, int i)
{
    int isint;
    lua_Integer v = lua_tointegerx(L, i, &isint);
    if (isint)
        return (int)v;
    return (int)floorf(luaL_checknumber(L, i));
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

// Prepares a primitive: returns false if nothing would be visible
static bool prim_begin(u16 color)
{
    if (!gs.active || gs.alpha == 0 || gs.clip_w <= 0 || gs.clip_h <= 0)
    {
        if (!gs.active && !gs.warned)
        {
            ll_log("note: drawing on the bottom screen comes in P6, ignored");
            gs.warned = true;
        }
        return false;
    }

    int id = 0;
    if (gs.alpha < 31)
    {
        gs.poly_id = gs.poly_id % 62 + 1; // 1..62; 63 is the clear plane
        id = gs.poly_id;
    }
    glPolyFmt(POLY_ALPHA(gs.alpha) | POLY_CULL_NONE | POLY_ID(id));
    glColor(color);
    return true;
}

static void prim_end(void)
{
    if (gs.depth < MAX_DEPTH)
        gs.depth++;
}

// Screen-space vertex with the camera applied
#define VX(x) ((v16)clamp((x) - gs.cam_x, -COORD_LIMIT, COORD_LIMIT))
#define VY(y) ((v16)clamp((y) - gs.cam_y, -COORD_LIMIT, COORD_LIMIT))

static void emit_quad(int x1, int y1, int x2, int y2)
{
    glBegin(GL_QUADS);
    glVertex3v16(VX(x1), VY(y1), gs.depth);
    glVertex2v16(VX(x1), VY(y2));
    glVertex2v16(VX(x2), VY(y2));
    glVertex2v16(VX(x2), VY(y1));
    glEnd();
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
    // Include the last pixel: extend the end point away from the start
    x2 += x2 >= x1 ? 1 : -1;
    y2 += y2 >= y1 ? 1 : -1;
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

// Number of segments for a circle of radius r
static int circle_segments(int r)
{
    int n = 8 + r / 2;
    return n > 48 ? 48 : n;
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

void ll_gfx_init(void)
{
    for (int i = 0; i < 16; i++)
        palette[i] = rgb15(palette_rgb[i]);

    videoSetMode(MODE_0_3D);
    lcdMainOnTop();
    glScreen2D();
    ll_gfx_reset();
}

void ll_gfx_reset(void)
{
    gs.active = false;
    gs.warned = false;
    gs.color = palette[DEFAULT_COLOR];
    gs.alpha = 31;
    gs.cam_x = gs.cam_y = 0;
    gs.clip_x = gs.clip_y = 0;
    gs.clip_w = SCREEN_W;
    gs.clip_h = SCREEN_H;
    gs.clear_color = palette[0];

    // An empty frame, so the previous cart's image disappears
    ll_gfx_begin(0);
    ll_gfx_end();
}

void ll_gfx_begin(int screen)
{
    if (screen != 0)
    {
        gs.active = false;
        return;
    }

    glBegin2D();
    gs.active = true;
    gs.depth = 0;
    apply_clip();
}

void ll_gfx_end(void)
{
    if (!gs.active)
        return;

    glClearColor(gs.clear_color & 31, (gs.clear_color >> 5) & 31,
                 (gs.clear_color >> 10) & 31, 31);
    glClearPolyID(63);

    // Back to the full screen for the next frame's glBegin2D
    glViewport(0, 0, SCREEN_W - 1, SCREEN_H - 1);
    glEnd2D();
    glFlush(GL_TRANS_MANUALSORT);
    gs.active = false;
}

// --- Lua API ----------------------------------------------------------------

// cls([col]): clears the screen. Everything drawn before in this frame is
// covered too.
static int l_cls(lua_State *L)
{
    u16 color = lua_isnoneornil(L, 1) ? palette[0] : arg_color(L, 1);
    gs.clear_color = color;
    if (gs.active && gs.depth > 0)
    {
        int alpha = gs.alpha;
        gs.alpha = 31;
        if (prim_begin(color))
        {
            emit_quad(gs.cam_x, gs.cam_y, gs.cam_x + SCREEN_W, gs.cam_y + SCREEN_H);
            prim_end();
        }
        gs.alpha = alpha;
    }
    return 0;
}

// color([col]): sets the color used when a function gets none
static int l_color(lua_State *L)
{
    gs.color = lua_isnoneornil(L, 1) ? palette[DEFAULT_COLOR] : arg_color(L, 1);
    return 0;
}

// alpha([a]): opacity 0..1 of what is drawn next (1 = opaque)
static int l_alpha(lua_State *L)
{
    lua_Number a = luaL_optnumber(L, 1, 1);
    int v = (int)(a * 31 + 0.5f);
    gs.alpha = clamp(v, 0, 31);
    return 0;
}

// camera([x, y]): offset subtracted from all coordinates
static int l_camera(lua_State *L)
{
    gs.cam_x = lua_isnoneornil(L, 1) ? 0 : arg_int(L, 1);
    gs.cam_y = lua_isnoneornil(L, 2) ? 0 : arg_int(L, 2);
    return 0;
}

// clip([x, y, w, h]): limits drawing to a screen rectangle (no camera)
static int l_clip(lua_State *L)
{
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

// rect(x, y, w, h, [col]): outline, 1 pixel wide, inside the rectangle
static int l_rect(lua_State *L)
{
    int x, y, w, h;
    arg_rect(L, &x, &y, &w, &h);
    u16 color = arg_color(L, 5);
    if (w <= 2 || h <= 2)
    {
        draw_box(x, y, w, h, color);
        return 0;
    }
    draw_box(x, y, w, 1, color);
    draw_box(x, y + h - 1, w, 1, color);
    draw_box(x, y + 1, 1, h - 2, color);
    draw_box(x + w - 1, y + 1, 1, h - 2, color);
    return 0;
}

// circfill(x, y, r, [col])
static int l_circfill(lua_State *L)
{
    int cx = arg_int(L, 1), cy = arg_int(L, 2), r = arg_int(L, 3);
    u16 color = arg_color(L, 4);
    if (r < 0)
        return 0;
    if (r == 0)
    {
        draw_box(cx, cy, 1, 1, color);
        return 0;
    }
    if (!prim_begin(color))
        return 0;

    // Triangle strip over a convex polygon: v0, v1, vn-1, v2, vn-2, ...
    // Pixel centers: the circle covers cx-r .. cx+r inclusive.
    int n = circle_segments(r);
    float fr = r + 0.5f, fx = cx + 0.5f, fy = cy + 0.5f;
    glBegin(GL_TRIANGLE_STRIP);
    for (int k = 0; k < n; k++)
    {
        int i = k == 0 ? 0 : (k & 1) ? (k + 1) / 2 : n - k / 2;
        float a = i * (2 * (float)M_PI) / n;
        int vx = (int)floorf(fx + fr * cosf(a));
        int vy = (int)floorf(fy + fr * sinf(a));
        if (k == 0)
            glVertex3v16(VX(vx), VY(vy), gs.depth);
        else
            glVertex2v16(VX(vx), VY(vy));
    }
    glEnd();
    prim_end();
    return 0;
}

// circ(x, y, r, [col]): outline made of lines
static int l_circ(lua_State *L)
{
    int cx = arg_int(L, 1), cy = arg_int(L, 2), r = arg_int(L, 3);
    u16 color = arg_color(L, 4);
    if (r < 0)
        return 0;
    if (r == 0)
    {
        draw_box(cx, cy, 1, 1, color);
        return 0;
    }

    int n = circle_segments(r);
    float fr = r + 0.5f, fx = cx + 0.5f, fy = cy + 0.5f;
    int px = (int)floorf(fx + fr), py = (int)floorf(fy);
    for (int i = 1; i <= n; i++)
    {
        float a = i * (2 * (float)M_PI) / n;
        int x = (int)floorf(fx + fr * cosf(a));
        int y = (int)floorf(fy + fr * sinf(a));
        if (!prim_begin(color))
            return 0;
        emit_line(px, py, x, y);
        prim_end();
        px = x;
        py = y;
    }
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
    draw_line(x1, y1, x2, y2, color);
    draw_line(x2, y2, x3, y3, color);
    draw_line(x3, y3, x1, y1, color);
    return 0;
}

void ll_gfx_register(lua_State *L)
{
    static const luaL_Reg funcs[] = {
        { "cls", l_cls },
        { "color", l_color },
        { "alpha", l_alpha },
        { "camera", l_camera },
        { "clip", l_clip },
        { "pset", l_pset },
        { "line", l_line },
        { "rect", l_rect },
        { "rectfill", l_rectfill },
        { "circ", l_circ },
        { "circfill", l_circfill },
        { "tri", l_tri },
        { "trifill", l_trifill },
        { NULL, NULL },
    };

    lua_pushglobaltable(L);
    luaL_setfuncs(L, funcs, 0);
    lua_pop(L, 1);
}
