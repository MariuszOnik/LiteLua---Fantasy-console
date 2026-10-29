// SPDX-License-Identifier: Zlib
//
// LiteLua - 3D layer (D60, experimental): a perspective camera over a ground
// of tiles, with terrain (isogrid:draw3d) and billboards (sprites that always
// face the camera, e.g. soldiers drawn from 16 directions).
//
// Lua API:
//   camera3d(x, y, yaw, pitch, dist, [fov], [z])
//       looks at the point x, y (tiles) at height z (default 0) from 'dist'
//       tiles away; yaw in degrees (0 = the camera is south of the point and
//       looks north, 90 = it is west of it), pitch in degrees above the
//       ground (5..89), fov = vertical field of view (default 50)
//   g:draw3d([hscale], [tpt])      isogrid as terrain, see ll_3d_terrain
//   b = billboards(img, n, [opts])
//       opts.dirs = 9   directions stored in the image: 0 = facing south
//                       (the camera at yaw 0), then turning west; the other
//                       2 * (dirs - 1) - dirs are mirrored. 1 = no directions
//       opts.scale      tiles per texel (default 1/32)
//   b:anim(id, first, frames, [ms], [loop])   animation id 0..31: frame of
//       direction d, step f is first + d * frames + f; ms per step (100)
//   b:set(i, x, y, z, dir, anim, [t0])        billboard i (1..n) at x, y,
//       height z (tiles, the image anchor is the point), facing dir (0..15,
//       0 = south, 4 = west, 8 = north, 12 = east), animation (-1 = hidden)
//       started at time t0 (ms, default 0)
//   b:pos(i, x, y, [z])                       puts billboard i there (stops it)
//   b:move(i, vx, vy, t)                      from time t (ms) it walks vx, vy
//                                             tiles per second
//   b:get(i, t) -> x, y                       where it is at time t
//   b:ground(g, [hscale])                     z is above the ground of the
//                                             isogrid g (heights as draw3d)
//   b:draw3d(t)                               draws at time t (ms)
//   b.n
//
// The 3D layer shares the frame with 2D drawing: its depth range is behind
// all 2D primitives, so whatever 2D is drawn (before or after) covers it.
// Vertices are relative to the camera target in 1/512 tiles (v16), so only
// about 60 tiles around it can be drawn; the projection is set up in floats
// once per call, the vertices are integer.

#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include <nds.h>

#include "lauxlib.h"

#include "ll_3d.h"
#include "ll_iso.h"

#define BB_MT "LiteLua.billboards"
#define Q 512                 // Vertex units per tile
#define REACH (60 * Q)        // Farthest vertex from the target
#define MAX_ANIMS 32
#define MAX_BILLBOARDS 4096
#define PI 3.14159265f

static struct {
    float tx, ty, tz;         // Target, tiles
    float yaw, pitch, dist, fov;
} cam;

void ll_3d_reset(void)
{
    cam.tx = cam.ty = cam.tz = 0;
    cam.yaw = 0;
    cam.pitch = 45;
    cam.dist = 12;
    cam.fov = 50;
}

// --- View -------------------------------------------------------------------

// Everything one draw call needs, in GL coordinates: X = east, Y = up,
// Z = south (world x, z, y), relative to the target.
typedef struct {
    float s[3], u[3], f[3];   // Camera right, up, forward
    float e[3];               // Eye
    int32_t tx, ty, tz;       // Target in vertex units
    // Ground footprint of the view: half-planes a*x + b*z + c >= 0, with x, z
    // in 1/16 tiles relative to the target; and its bounding box in tiles
    int32_t ea[4], eb[4], ec[4];
    float x1, z1, x2, z2;
} View;

static void cross(const float *a, const float *b, float *out)
{
    out[0] = a[1] * b[2] - a[2] * b[1];
    out[1] = a[2] * b[0] - a[0] * b[2];
    out[2] = a[0] * b[1] - a[1] * b[0];
}

static void normalize(float *v)
{
    float l = sqrtf(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (l > 0)
        v[0] /= l, v[1] /= l, v[2] /= l;
}

static int32_t f32(float v)
{
    return (int32_t)lrintf(v * 4096);
}

// Loads the projection and modelview matrices; 'margin' (tiles) widens the
// footprint for things above the ground. False outside _draw.
static bool view_begin(View *v, float margin)
{
    int cx, cy, cw, ch;
    if (!ll_gfx_3d_begin(&cx, &cy, &cw, &ch))
        return false;

    float yaw = cam.yaw * PI / 180, pitch = cam.pitch * PI / 180;
    float cp = cosf(pitch), sp = sinf(pitch);
    v->e[0] = -sinf(yaw) * cp * cam.dist;
    v->e[1] = sp * cam.dist;
    v->e[2] = cosf(yaw) * cp * cam.dist;
    for (int i = 0; i < 3; i++)
        v->f[i] = -v->e[i] / cam.dist;
    const float up[3] = { 0, 1, 0 };
    cross(v->f, up, v->s);
    normalize(v->s);
    cross(v->s, v->f, v->u);
    v->tx = (int32_t)lrintf(cam.tx * Q);
    v->ty = (int32_t)lrintf(cam.ty * Q);
    v->tz = (int32_t)lrintf(cam.tz * Q);

    float n = cam.dist / 16, far = cam.dist * 4 + 32;
    if (n < 0.1f)
        n = 0.1f;
    if (far > 200)
        far = 200;
    float ty = tanf(cam.fov * PI / 360), aspect = (float)cw / ch, tx = ty * aspect;

    // Projection; z is moved to the far half of the depth range (the 2D
    // layer uses the near half): z' = (z + w) / 2
    float a = 1 / ty;
    float A = 0.5f * (far + n) / (n - far) - 0.5f, B = far * n / (n - far);
    m4x4 p = { {
        f32(a / aspect), 0, 0, 0,
        0, f32(a), 0, 0,
        0, 0, f32(A), f32(-1),
        0, 0, f32(B), 0,
    } };
    glMatrixMode(GL_PROJECTION);
    glLoadMatrix4x4(&p);

    // Modelview: the view matrix times 8 (a vertex unit is 1/512 tile and
    // v16 1.0 is 4096 units, so 8 tiles)
    float t0 = -(v->s[0] * v->e[0] + v->s[1] * v->e[1] + v->s[2] * v->e[2]);
    float t1 = -(v->u[0] * v->e[0] + v->u[1] * v->e[1] + v->u[2] * v->e[2]);
    float t2 = v->f[0] * v->e[0] + v->f[1] * v->e[1] + v->f[2] * v->e[2];
    m4x4 m = { {
        f32(8 * v->s[0]), f32(8 * v->u[0]), f32(-8 * v->f[0]), 0,
        f32(8 * v->s[1]), f32(8 * v->u[1]), f32(-8 * v->f[1]), 0,
        f32(8 * v->s[2]), f32(8 * v->u[2]), f32(-8 * v->f[2]), 0,
        f32(t0), f32(t1), f32(t2), f32(1),
    } };
    glMatrixMode(GL_MODELVIEW);
    glLoadMatrix4x4(&m);

    // Footprint: where the rays through the corners of the view hit the
    // ground (or 'far' away, if they miss it)
    float px[4], pz[4];
    static const float cxs[4] = { -1, 1, 1, -1 }, cys[4] = { -1, -1, 1, 1 };
    for (int k = 0; k < 4; k++)
    {
        float d[3];
        for (int i = 0; i < 3; i++)
            d[i] = v->f[i] + v->s[i] * cxs[k] * tx + v->u[i] * cys[k] * ty;
        float len = sqrtf(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
        float t = far / len;
        if (d[1] < -1e-4f && -v->e[1] / d[1] < t)
            t = -v->e[1] / d[1];
        px[k] = v->e[0] + d[0] * t;
        pz[k] = v->e[2] + d[2] * t;
    }
    v->x1 = v->x2 = px[0];
    v->z1 = v->z2 = pz[0];
    for (int k = 1; k < 4; k++)
    {
        v->x1 = fminf(v->x1, px[k]), v->x2 = fmaxf(v->x2, px[k]);
        v->z1 = fminf(v->z1, pz[k]), v->z2 = fmaxf(v->z2, pz[k]);
    }
    v->x1 -= margin, v->z1 -= margin, v->x2 += margin, v->z2 += margin;
    float mx = (px[0] + px[1] + px[2] + px[3]) / 4, mz = (pz[0] + pz[1] + pz[2] + pz[3]) / 4;
    for (int k = 0; k < 4; k++)
    {
        int j = (k + 1) & 3;
        float nx = -(pz[j] - pz[k]), nz = px[j] - px[k];
        float l = sqrtf(nx * nx + nz * nz);
        if (l < 1e-4f)
        {
            v->ea[k] = v->eb[k] = 0, v->ec[k] = 1; // Degenerate edge: no limit
            continue;
        }
        nx /= l, nz /= l;
        if (nx * (mx - px[k]) + nz * (mz - pz[k]) < 0)
            nx = -nx, nz = -nz;   // Inward
        v->ea[k] = (int32_t)lrintf(nx * 1024);
        v->eb[k] = (int32_t)lrintf(nz * 1024);
        v->ec[k] = (int32_t)lrintf((-(nx * px[k] + nz * pz[k]) + margin) * 16 * 1024);
    }

    glPolyFmt(POLY_ALPHA(31) | POLY_CULL_NONE | POLY_ID(0));
    return true;
}

// Whether the point x, z (vertex units, relative to the target) lies in the
// footprint
static inline bool in_view(const View *v, int32_t x, int32_t z)
{
    x >>= 5, z >>= 5; // 1/16 tiles
    for (int k = 0; k < 4; k++)
        if (v->ea[k] * x + v->eb[k] * z + v->ec[k] < 0)
            return false;
    return true;
}

static inline v16 clamp16(int32_t v)
{
    return (v16)(v < -32767 ? -32767 : v > 32767 ? 32767 : v);
}

// camera3d(x, y, yaw, pitch, dist, [fov], [z])
static int l_camera3d(lua_State *L)
{
    float x = (float)luaL_checknumber(L, 1), y = (float)luaL_checknumber(L, 2);
    float yaw = (float)luaL_checknumber(L, 3), pitch = (float)luaL_checknumber(L, 4);
    float dist = (float)luaL_checknumber(L, 5);
    float fov = (float)luaL_optnumber(L, 6, 50), z = (float)luaL_optnumber(L, 7, 0);
    luaL_argcheck(L, pitch >= 5 && pitch <= 89, 4, "pitch must be 5..89");
    luaL_argcheck(L, dist >= 0.5f && dist <= 200, 5, "dist must be 0.5..200");
    luaL_argcheck(L, fov >= 10 && fov <= 120, 6, "fov must be 10..120");
    cam.tx = x, cam.ty = y, cam.tz = z;
    cam.yaw = fmodf(yaw, 360);
    if (cam.yaw < 0)
        cam.yaw += 360;
    cam.pitch = pitch, cam.dist = dist, cam.fov = fov;
    return 0;
}

// --- Terrain ----------------------------------------------------------------

// Heights in vertex units: h * hscale * 512, hscale in 20.12
static inline v16 corner_y(const LLIsoGrid *g, int i, int64_t hs, int32_t tz)
{
    return clamp16((int32_t)((g->heights[i] * hs) >> 12) - tz);
}

// One texture repeated over the ground, 'tpt' texels per tile: every row of
// cells is one strip, so a cell costs ~2 vertices instead of 4.
static void terrain_strips(const LLImage *img, const LLIsoGrid *g, const View *v,
                           int64_t hs, int tpt, int c1, int c2, int r1, int r2)
{
    // Repeat the whole texture
    u32 param = glGetTexParameter();
    if ((param & (GL_TEXTURE_WRAP_S | GL_TEXTURE_WRAP_T)) != (GL_TEXTURE_WRAP_S | GL_TEXTURE_WRAP_T))
        glTexParameter(0, (int)((param & 0xE00F0000) | GL_TEXTURE_WRAP_S | GL_TEXTURE_WRAP_T));

    // Texture coordinates are 12.4 (+-2048 texels): count them from a
    // multiple of the texture size near the target
    int tw = 8, th = 8;
    while (tw < img->w)
        tw <<= 1;
    while (th < img->h)
        th <<= 1;
    int32_t u0 = (int32_t)floorf(cam.tx * tpt / tw) * tw;
    int32_t w0 = (int32_t)floorf(cam.ty * tpt / th) * th;
    const int W1 = g->cols + 1;
    const u16 *col = g->colors;
    if (!col)
        glColor(0x7fff);
    for (int r = r1; r <= r2; r++)
    {
        int32_t z0 = r * Q - v->ty, z1 = z0 + Q;
        if (z0 < -REACH || z1 > REACH)
            continue;
        // The visible cells of the row, as one run
        int a = -1, b = -1;
        for (int c = c1; c <= c2; c++)
        {
            int32_t x0 = c * Q - v->tx;
            if (x0 >= -REACH && x0 + Q <= REACH && in_view(v, x0 + Q / 2, z0 + Q / 2))
            {
                if (a < 0)
                    a = c;
                b = c;
            }
        }
        if (a < 0)
            continue;
        int wt = (r * tpt - w0) * 16, wb = wt + tpt * 16;
        glBegin(GL_QUAD_STRIP);
        for (int c = a; c <= b + 1; c++)
        {
            int32_t x = c * Q - v->tx;
            int u = (c * tpt - u0) * 16;
            int i = r * W1 + c;
            if (col)
                glColor(col[i]);
            glTexCoord2t16(u, wt);
            glVertex3v16(x, corner_y(g, i, hs, v->tz), z0);
            if (col)
                glColor(col[i + W1]);
            glTexCoord2t16(u, wb);
            glVertex3v16(x, corner_y(g, i + W1, hs, v->tz), z1);
        }
        glEnd();
    }
}

void ll_3d_terrain(const LLImage *img, const LLIsoGrid *g, int32_t hscale, int tpt)
{
    if (img->tex == 0 || (tpt == 0 && img->frames == 0))
        return;
    const int64_t hs = (int64_t)hscale * Q;
    float lift = (float)(((int64_t)g->maxh * hs) >> 12) / Q;
    View v;
    if (!view_begin(&v, 1 + lift))
        return;

    int c1 = (int)floorf(cam.tx + v.x1), c2 = (int)floorf(cam.tx + v.x2);
    int r1 = (int)floorf(cam.ty + v.z1), r2 = (int)floorf(cam.ty + v.z2);
    if (c1 < 0)
        c1 = 0;
    if (r1 < 0)
        r1 = 0;
    if (c2 > g->cols - 1)
        c2 = g->cols - 1;
    if (r2 > g->rows - 1)
        r2 = g->rows - 1;

    ll_gfx_bind(img->tex);
    if (tpt > 0)
    {
        terrain_strips(img, g, &v, hs, tpt, c1, c2, r1, r2);
        ll_gfx_3d_end();
        return;
    }

    const int W1 = g->cols + 1;
    const u16 *col = g->colors;
    const int fw = img->fw ? img->fw : img->w, fh = img->fh ? img->fh : img->h;
    const int fcols = img->cols > 0 ? img->cols : 1;
    glBegin(GL_QUADS);
    if (!col)
        glColor(0x7fff);
    for (int r = r1; r <= r2; r++)
    {
        int32_t z0 = r * Q - v.ty, z1 = z0 + Q;
        if (z0 < -REACH || z1 > REACH)
            continue;
        for (int c = c1; c <= c2; c++)
        {
            int32_t x0 = c * Q - v.tx, x1 = x0 + Q;
            if (x0 < -REACH || x1 > REACH || !in_view(&v, x0 + Q / 2, z0 + Q / 2))
                continue;
            int f = g->frames[r * g->cols + c];
            if (f < 0 || f >= img->frames)
                continue;
            int i = r * W1 + c; // Corners: T = i, R = i + 1, B = i + W1 + 1, L = i + W1
            int u = (img->x + (f % fcols) * fw) * 16;
            int w = (img->y + (f / fcols) * fh) * 16;
            int u2 = u + fw * 16, w2 = w + fh * 16;

            if (col)
                glColor(col[i]);
            glTexCoord2t16(u, w);
            glVertex3v16(x0, corner_y(g, i, hs, v.tz), z0);
            if (col)
                glColor(col[i + 1]);
            glTexCoord2t16(u2, w);
            glVertex3v16(x1, corner_y(g, i + 1, hs, v.tz), z0);
            if (col)
                glColor(col[i + W1 + 1]);
            glTexCoord2t16(u2, w2);
            glVertex3v16(x1, corner_y(g, i + W1 + 1, hs, v.tz), z1);
            if (col)
                glColor(col[i + W1]);
            glTexCoord2t16(u, w2);
            glVertex3v16(x0, corner_y(g, i + W1, hs, v.tz), z1);
        }
    }
    glEnd();
    ll_gfx_3d_end();
}

// --- Billboards -------------------------------------------------------------

typedef struct {
    int16_t first, frames, ms;
    bool loop;
    uint32_t inv_ms, inv_frames; // 2^32 / ms, 2^32 / frames, rounded up
} Anim;

typedef struct {
    int32_t x, y, z;          // Vertex units (1/512 tiles); z above the ground
    int32_t t0;               // Animation start, ms
    int32_t tm;               // Walking from x, y since this time, ms
    int16_t vx, vy;           // Vertex units per second
    uint8_t dir;              // 0..15
    int8_t anim;              // -1 = hidden
} Inst;

typedef struct {
    int n, dirs, frames;
    float scale;              // Tiles per texel
    Anim anims[MAX_ANIMS];
    Inst *inst;
    int16_t *uv;              // Top left texture coordinate of each frame (t16)
    const LLIsoGrid *ground;  // Heights under the billboards, or NULL
    int64_t hs;               // Its height scale: vertex units per height, 20.12
} Bill;

// Position at time t (ms)
static inline void inst_xy(const Inst *p, int32_t t, int32_t *x, int32_t *y)
{
    *x = p->x, *y = p->y;
    if (p->vx | p->vy)
    {
        int64_t el = t - p->tm;
        if (el < 0)
            el = 0;
        // / 1000 as * 4194.3 / 2^22: a 64-bit division is slow on the ARM9
        *x += (int32_t)((p->vx * el * 4194) >> 22);
        *y += (int32_t)((p->vy * el * 4194) >> 22);
    }
}

// Ground height under x, y (vertex units), between the four corners
static int32_t ground_at(const Bill *b, int32_t x, int32_t y)
{
    const LLIsoGrid *g = b->ground;
    int c = x >> 9, r = y >> 9;
    if (c < 0 || r < 0 || c >= g->cols || r >= g->rows)
        return 0;
    int32_t fx = x & (Q - 1), fy = y & (Q - 1);
    int W1 = g->cols + 1, i = r * W1 + c;
    int32_t top = (g->heights[i] * (Q - fx) + g->heights[i + 1] * fx) >> 9;
    int32_t bot = (g->heights[i + W1] * (Q - fx) + g->heights[i + W1 + 1] * fx) >> 9;
    int32_t h = (top * (Q - fy) + bot * fy) >> 9;
    return (int32_t)((h * b->hs) >> 12);
}

static Bill *check_bb(lua_State *L)
{
    return luaL_checkudata(L, 1, BB_MT);
}

static LLImage *bb_image(lua_State *L)
{
    lua_getiuservalue(L, 1, 1);
    LLImage *img = ll_image_check(L, -1);
    lua_pop(L, 1);
    return img;
}

static int32_t tiles(lua_State *L, int i)
{
    lua_Number t = luaL_checknumber(L, i);
    luaL_argcheck(L, t > -4000 && t < 4000, i, "position out of range");
    return (int32_t)lrintf((float)t * Q);
}

// billboards(img, n, [opts])
static int l_billboards(lua_State *L)
{
    lua_Integer n = luaL_checkinteger(L, 2);
    luaL_argcheck(L, n >= 1 && n <= MAX_BILLBOARDS, 2, "n must be 1..4096");
    int dirs = 9;
    float scale = 1.0f / 32;
    if (!lua_isnoneornil(L, 3))
    {
        luaL_checktype(L, 3, LUA_TTABLE);
        lua_getfield(L, 3, "dirs");
        dirs = (int)luaL_optinteger(L, -1, 9);
        lua_getfield(L, 3, "scale");
        scale = (float)luaL_optnumber(L, -1, 1.0 / 32);
        lua_pop(L, 2);
    }
    luaL_argcheck(L, dirs >= 1 && dirs <= 9, 3, "dirs must be 1..9");
    luaL_argcheck(L, scale > 0 && scale <= 4, 3, "scale must be 0..4");

    LLImage *img = ll_image_check(L, 1);
    int frames = img->frames;
    size_t size = sizeof(Bill) + (size_t)n * sizeof(Inst) + (size_t)frames * 2 * sizeof(int16_t);
    Bill *b = lua_newuserdatauv(L, size, 2);
    memset(b, 0, size);
    b->n = (int)n;
    b->dirs = dirs;
    b->scale = scale;
    b->frames = frames;
    b->inst = (Inst *)(b + 1);
    b->uv = (int16_t *)(b->inst + n);
    const int fw = img->fw ? img->fw : img->w, fh = img->fh ? img->fh : img->h;
    const int fcols = img->cols > 0 ? img->cols : 1;
    for (int f = 0; f < frames; f++)
    {
        b->uv[2 * f] = (int16_t)((img->x + (f % fcols) * fw) * 16);
        b->uv[2 * f + 1] = (int16_t)((img->y + (f / fcols) * fh) * 16);
    }
    for (int i = 0; i < n; i++)
        b->inst[i].anim = -1;
    lua_pushvalue(L, 1);
    lua_setiuservalue(L, -2, 1);
    luaL_setmetatable(L, BB_MT);
    return 1;
}

// b:anim(id, first, frames, [ms], [loop])
static int m_anim(lua_State *L)
{
    Bill *b = check_bb(L);
    lua_Integer id = luaL_checkinteger(L, 2);
    lua_Integer first = luaL_checkinteger(L, 3), frames = luaL_checkinteger(L, 4);
    lua_Integer ms = luaL_optinteger(L, 5, 100);
    luaL_argcheck(L, id >= 0 && id < MAX_ANIMS, 2, "id must be 0..31");
    luaL_argcheck(L, first >= 0 && first < 32768, 3, "first must be 0..32767");
    luaL_argcheck(L, frames >= 1 && frames < 32768, 4, "frames must be 1..32767");
    luaL_argcheck(L, ms >= 1 && ms < 32768, 5, "ms must be 1..32767");
    int last = (int)(first + frames * b->dirs - 1), count = bb_image(L)->frames;
    if (last >= count)
        return luaL_error(L, "billboards: animation needs frames up to %d, the image has %d",
                          last, count);
    b->anims[id] = (Anim){ (int16_t)first, (int16_t)frames, (int16_t)ms,
                           lua_isnoneornil(L, 6) || lua_toboolean(L, 6),
                           (uint32_t)((0xffffffffu / ms) + 1), (uint32_t)((0xffffffffu / frames) + 1) };
    return 0;
}

static Inst *arg_inst(lua_State *L, Bill *b)
{
    lua_Integer i = luaL_checkinteger(L, 2);
    luaL_argcheck(L, i >= 1 && i <= b->n, 2, "no such billboard");
    return &b->inst[i - 1];
}

// b:set(i, x, y, z, dir, anim, [t0])
static int m_set(lua_State *L)
{
    Bill *b = check_bb(L);
    Inst *p = arg_inst(L, b);
    p->x = tiles(L, 3), p->y = tiles(L, 4), p->z = tiles(L, 5);
    p->vx = p->vy = 0;
    p->dir = (uint8_t)(luaL_checkinteger(L, 6) & 15);
    lua_Integer a = luaL_checkinteger(L, 7);
    luaL_argcheck(L, a >= -1 && a < MAX_ANIMS, 7, "anim must be -1..31");
    p->anim = (int8_t)a;
    p->t0 = (int32_t)luaL_optinteger(L, 8, 0);
    return 0;
}

// b:pos(i, x, y, [z])
static int m_pos(lua_State *L)
{
    Bill *b = check_bb(L);
    Inst *p = arg_inst(L, b);
    p->x = tiles(L, 3), p->y = tiles(L, 4);
    p->vx = p->vy = 0;
    if (!lua_isnoneornil(L, 5))
        p->z = tiles(L, 5);
    return 0;
}

// b:move(i, vx, vy, t)
static int m_move(lua_State *L)
{
    Bill *b = check_bb(L);
    Inst *p = arg_inst(L, b);
    lua_Number vx = luaL_checknumber(L, 3), vy = luaL_checknumber(L, 4);
    luaL_argcheck(L, vx > -60 && vx < 60, 3, "speed must be -60..60 tiles per second");
    luaL_argcheck(L, vy > -60 && vy < 60, 4, "speed must be -60..60 tiles per second");
    int32_t t = (int32_t)luaL_checkinteger(L, 5);
    inst_xy(p, t, &p->x, &p->y);
    p->tm = t;
    p->vx = (int16_t)lrintf((float)vx * Q);
    p->vy = (int16_t)lrintf((float)vy * Q);
    return 0;
}

// b:get(i, t) -> x, y
static int m_get(lua_State *L)
{
    Bill *b = check_bb(L);
    Inst *p = arg_inst(L, b);
    int32_t x, y;
    inst_xy(p, (int32_t)luaL_checkinteger(L, 3), &x, &y);
    lua_pushnumber(L, (lua_Number)x / Q);
    lua_pushnumber(L, (lua_Number)y / Q);
    return 2;
}

// b:ground(g, [hscale])
static int m_ground(lua_State *L)
{
    Bill *b = check_bb(L);
    if (lua_isnoneornil(L, 2))
    {
        b->ground = NULL;
        lua_pushnil(L);
        lua_setiuservalue(L, 1, 2);
        return 0;
    }
    const LLIsoGrid *g = ll_iso_check(L, 2);
    lua_Number hscale = luaL_optnumber(L, 3, 1.0 / 16);
    luaL_argcheck(L, hscale >= 0 && hscale <= 8, 3, "hscale must be 0..8");
    b->ground = g;
    b->hs = (int64_t)(hscale * 4096 + 0.5f) * Q;
    lua_pushvalue(L, 2);
    lua_setiuservalue(L, 1, 2); // Keeps the grid alive
    return 0;
}

// b:draw3d(t)
static int m_draw3d(lua_State *L)
{
    Bill *b = check_bb(L);
    LLImage *img = bb_image(L);
    int32_t t = (int32_t)luaL_checkinteger(L, 2);
    if (img->tex == 0 || img->frames == 0)
        return 0;
    const int fw = img->fw ? img->fw : img->w, fh = img->fh ? img->fh : img->h;
    const float ax = img->anchored ? img->ax * fw / 4096.0f : fw / 2.0f;
    const float ay = img->anchored ? img->ay * fh / 4096.0f : (float)fh;
    View v;
    if (!view_begin(&v, 1 + fh * b->scale))
        return 0;

    // Corner offsets (top left, top right, bottom right, bottom left) facing
    // the camera, plain and mirrored around the anchor; pulled half a frame
    // towards the camera, so the feet do not sink into the ground behind
    int32_t off[2][4][3];
    const float q = b->scale * Q, pull = fh * q / 2;
    for (int m = 0; m < 2; m++)
    {
        float left = m ? ax - fw : -ax, right = left + fw;
        const float xs[4] = { left, right, right, left };
        const float ys[4] = { ay, ay, ay - fh, ay - fh };
        for (int k = 0; k < 4; k++)
            for (int i = 0; i < 3; i++)
                off[m][k][i] = (int32_t)lrintf((v.s[i] * xs[k] + v.u[i] * ys[k]) * q
                                               - v.f[i] * pull);
    }

    // Directions: 'total' around, the camera's yaw in the same steps
    const int total = b->dirs > 1 ? 2 * (b->dirs - 1) : 1;
    const int yawt = (int)lrintf(cam.yaw * total / 360) % total;
    int8_t dir_frame[16];     // Stored direction for each dir, < 0 = mirrored
    for (int k = 0; k < 16; k++)
    {
        int rel = ((k * total + 8) / 16 - yawt + total) % total;
        dir_frame[k] = (int8_t)(rel >= b->dirs ? -(total - rel) - 1 : rel);
    }
    const int du = fw * 16, dw = fh * 16;

    ll_gfx_bind(img->tex);
    glBegin(GL_QUADS);
    glColor(0x7fff);
    for (int i = 0; i < b->n; i++)
    {
        const Inst *p = &b->inst[i];
        if (p->anim < 0)
            continue;
        const Anim *a = &b->anims[p->anim];
        if (a->frames == 0)
            continue;
        int32_t wx, wy;
        inst_xy(p, t, &wx, &wy);
        int32_t x = wx - v.tx, z = wy - v.ty;
        if (x < -REACH || x > REACH || z < -REACH || z > REACH || !in_view(&v, x, z))
            continue;
        int32_t y = p->z - v.tz + (b->ground ? ground_at(b, wx, wy) : 0);
        if (y < -REACH || y > REACH)
            continue;

        int d = dir_frame[p->dir];
        bool mirror = d < 0;
        if (mirror)
            d = -d - 1;
        // Divisions by multiplying with 2^32 / x (rounded up: exact for
        // the small numbers here)
        int32_t el = t - p->t0;
        uint32_t step = el < 0 ? 0 : (uint32_t)(((uint64_t)(uint32_t)el * a->inv_ms) >> 32);
        if (step >= (uint32_t)a->frames)
        {
            if (a->loop)
            {
                // The quotient may be one off for large times
                int32_t m = (int32_t)(step - (uint32_t)(((uint64_t)step * a->inv_frames) >> 32)
                                                 * a->frames);
                if (m < 0)
                    m += a->frames;
                else if (m >= a->frames)
                    m -= a->frames;
                step = (uint32_t)m;
            }
            else
                step = a->frames - 1;
        }
        int f = a->first + d * a->frames + (int)step;
        if (f >= b->frames)
            continue;

        int u = b->uv[2 * f], w = b->uv[2 * f + 1];
        int u2 = u + du, w2 = w + dw;
        if (mirror)
        {
            int tmp = u;
            u = u2, u2 = tmp;
        }
        const int32_t(*o)[3] = off[mirror];
        glTexCoord2t16(u, w);
        glVertex3v16(clamp16(x + o[0][0]), clamp16(y + o[0][1]), clamp16(z + o[0][2]));
        glTexCoord2t16(u2, w);
        glVertex3v16(clamp16(x + o[1][0]), clamp16(y + o[1][1]), clamp16(z + o[1][2]));
        glTexCoord2t16(u2, w2);
        glVertex3v16(clamp16(x + o[2][0]), clamp16(y + o[2][1]), clamp16(z + o[2][2]));
        glTexCoord2t16(u, w2);
        glVertex3v16(clamp16(x + o[3][0]), clamp16(y + o[3][1]), clamp16(z + o[3][2]));
    }
    glEnd();
    ll_gfx_3d_end();
    return 0;
}

static int m_index(lua_State *L)
{
    Bill *b = check_bb(L);
    const char *k = luaL_checkstring(L, 2);
    if (strcmp(k, "n") == 0)
        lua_pushinteger(L, b->n);
    else
    {
        luaL_getmetatable(L, BB_MT);
        lua_getfield(L, -1, "methods");
        lua_getfield(L, -1, k);
    }
    return 1;
}

static int m_tostring(lua_State *L)
{
    Bill *b = check_bb(L);
    lua_pushfstring(L, "billboards (%d)", b->n);
    return 1;
}

void ll_3d_register(lua_State *L)
{
    static const luaL_Reg methods[] = {
        { "anim", m_anim }, { "set", m_set }, { "pos", m_pos }, { "move", m_move },
        { "get", m_get }, { "ground", m_ground },
        { "draw3d", m_draw3d }, { NULL, NULL },
    };
    luaL_newmetatable(L, BB_MT);
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "methods");
    lua_pushcfunction(L, m_index);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, m_tostring);
    lua_setfield(L, -2, "__tostring");
    lua_pop(L, 1);
    lua_register(L, "camera3d", l_camera3d);
    lua_register(L, "billboards", l_billboards);
}
