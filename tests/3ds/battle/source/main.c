// Hex battle prototype for the 3DS: a map of hexes over gentle hills, trees and rocks, and
// units of knights standing on the hexes (romfs:/knight_lo.bin, polish_lo.bin from
// tests/3ds/army/make_knight.py, format "LLM2": several morph animations in one file).
// The terrain is one mesh: every hex a fan of 24 triangles, heights from a smooth function,
// so hexes meet without seams; a second texture darkens the hex borders (texcoord 1 is the
// distance from the hex centre). Trees and rocks are made here, flat shaded by vertex
// colour, all in one mesh. Knights idle (sometimes the horse moves its head); A: the Polish
// units advance one hex, B: the Teutonic ones; they gallop over the hills, then stand.
// Circle pad: turn and tilt the camera, D-pad: move it, L/R: zoom, START: exit.
#include <3ds.h>
#include <citro3d.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "soldier_shbin.h"
#include "terrain_shbin.h"

#define COLS 14                // hexes across (x)
#define ROWS 12                // hexes down (z)
#define HEX 6.0f               // hex radius (centre to corner), metres
#define SQ3 1.7320508f
#define PER_HEX 8              // knights on a hex (4 x 2)
#define MAX_UNITS 16
#define MAX_KNIGHTS (MAX_UNITS * PER_HEX)
#define GROUND_TEX 64
#define BORDER_TEX 64

#define DISPLAY_TRANSFER_FLAGS \
	(GX_TRANSFER_FLIP_VERT(0) | GX_TRANSFER_OUT_TILED(0) | GX_TRANSFER_RAW_COPY(0) | \
	GX_TRANSFER_IN_FORMAT(GX_TRANSFER_FMT_RGBA8) | GX_TRANSFER_OUT_FORMAT(GX_TRANSFER_FMT_RGB8) | \
	GX_TRANSFER_SCALING(GX_TRANSFER_SCALE_NO))

// --- models (LLM2) ---------------------------------------------------------------------

typedef struct {
	char name[8];
	u16 first, frames;
	float seconds, speed;
} Anim;

typedef struct {
	u16 verts, tris, nframes, texSize, nanims;
	Anim anims[8];
	float* uvs;                // linear memory
	u16* indices;
	float* frames;             // frames * verts * 3
	C3D_Tex tex;
} Model;

enum { A_IDLE, A_FIDGET, A_RUN, A_CHARGE };

typedef struct {
	int model;
	float x, z, yaw;           // hex centre now
	float tx, tz;              // where it goes (== x, z when standing)
} Unit;

typedef struct {
	int unit;
	float dx, dz;              // place in the formation (unit space)
	int anim;
	float t0;                  // when the animation started, s
} Knight;

static Model models[2];
static Unit units[MAX_UNITS];
static int nunits;
static Knight knights[MAX_KNIGHTS];
static int nknights;

typedef struct { float x, y, z, u0, v0, u1, v1, r, g, b; } TVert;   // terrain / decoration vertex

static TVert* terrain;         // linear memory
static int terrainCount;       // vertices (triangles * 3)
static TVert* decor;
static int decorCount;
static C3D_Tex groundTex, borderTex;
static bool forest[ROWS][COLS];

// tree sprites (romfs:/trees.bin from make_trees.py), drawn as billboards turned to the camera
typedef struct { float u0, v0, u1, v1, w, h; } Sprite;
typedef struct { float x, y, z, s, tint; int sprite; } Tree;
#define MAX_TREES 1200
static Sprite sprites[8];
static int nsprites;
static C3D_Tex treeTex;
static Tree trees[MAX_TREES];
static int ntrees;
static TVert* treeVerts;       // linear memory: 6 per tree, refilled every frame

static shaderProgram_s soldierProg, terrainProg;
static DVLB_s *soldierDvlb, *terrainDvlb;
static int uSProj, uSModelView, uSBlend, uTProj, uTModelView;
static C3D_AttrInfo soldierAttr, terrainAttr;

static void* readFile(const char* path, size_t* size)
{
	FILE* f = fopen(path, "rb");
	if (!f) return NULL;
	fseek(f, 0, SEEK_END);
	*size = ftell(f);
	fseek(f, 0, SEEK_SET);
	void* buf = malloc(*size);
	if (buf && fread(buf, 1, *size, f) != *size) { free(buf); buf = NULL; }
	fclose(f);
	return buf;
}

static void* linearCopy(const void* src, size_t size)
{
	void* p = linearAlloc(size);
	if (p) memcpy(p, src, size);
	return p;
}

// pixel (x, y from the top) in a 3DS texture: 8x8 tiles from the bottom row up, Morton inside
static u32 texIndex(u32 x, u32 y, u32 size)
{
	u32 yf = size - 1 - y;
	u32 tile = (yf >> 3) * (size >> 3) + (x >> 3);
	u32 xs = x & 7, ys = yf & 7;
	u32 m = (xs & 1) | ((ys & 1) << 1) | ((xs & 2) << 1) | ((ys & 2) << 2) | ((xs & 4) << 2) | ((ys & 4) << 3);
	return tile * 64 + m;
}

static bool loadModel(Model* m, const char* path)
{
	size_t size;
	u8* buf = readFile(path, &size);
	if (!buf) return false;
	if (memcmp(buf, "LLM2", 4)) { free(buf); return false; }
	u16 h[6];
	memcpy(h, buf + 4, sizeof h);
	m->verts = h[0]; m->tris = h[1]; m->nframes = h[2]; m->texSize = h[3]; m->nanims = h[4];
	if (m->nanims > 8) { free(buf); return false; }
	u8* p = buf + 16;
	for (int i = 0; i < m->nanims; i++, p += 20) memcpy(&m->anims[i], p, 20);
	size_t uvSize = m->verts * 8, idxSize = m->tris * 6, idxPad = (idxSize + 3) & ~3u;
	size_t frameSize = (size_t)m->nframes * m->verts * 12, texSize = (size_t)m->texSize * m->texSize * 2;
	if ((size_t)(p - buf) + uvSize + idxPad + frameSize + texSize != size) { free(buf); return false; }
	m->uvs = linearCopy(p, uvSize);
	p += uvSize;
	m->indices = linearCopy(p, idxSize);
	p += idxPad;
	m->frames = linearCopy(p, frameSize);
	p += frameSize;
	C3D_TexInit(&m->tex, m->texSize, m->texSize, GPU_RGB565);
	C3D_TexUpload(&m->tex, p);
	C3D_TexSetFilter(&m->tex, GPU_LINEAR, GPU_LINEAR);
	free(buf);
	return true;
}

// --- terrain -----------------------------------------------------------------------------

// gentle hills: a few long waves, a couple of metres high
static float height(float x, float z)
{
	return 2.2f * sinf(x * 0.055f + 0.4f) * cosf(z * 0.048f - 0.3f)
		+ 1.1f * sinf(x * 0.11f + z * 0.07f + 1.0f)
		+ 0.5f * cosf(x * 0.19f - z * 0.15f) + 2.5f;
}

static void hexCentre(int c, int r, float* x, float* z)
{
	*x = c * 1.5f * HEX;
	*z = r * SQ3 * HEX + ((c & 1) ? SQ3 * HEX / 2 : 0);
}

// light from the slope: normal from the height's differences
static float shade(float x, float z)
{
	float e = 0.5f;
	float nx = height(x - e, z) - height(x + e, z), nz = height(x, z - e) - height(x, z + e), ny = 2 * e;
	float len = sqrtf(nx * nx + ny * ny + nz * nz);
	float l = (nx * -0.45f + ny * 0.8f + nz * 0.4f) / len;   // sun from the left, a bit behind
	return 0.55f + 0.5f * (l > 0 ? l : 0);
}

static TVert tvert(float x, float z, float radial, float tint)
{
	float s = shade(x, z) * tint;
	return (TVert){ x, height(x, z), z, x / 8, z / 8, radial, 0.5f, s, s, s };
}

static void buildTerrain(void)
{
	terrainCount = ROWS * COLS * 24 * 3;
	terrain = linearAlloc(terrainCount * sizeof(TVert));
	TVert* v = terrain;
	for (int r = 0; r < ROWS; r++)
		for (int c = 0; c < COLS; c++) {
			float cx, cz;
			hexCentre(c, r, &cx, &cz);
			float tint = forest[r][c] ? 0.78f : 1.0f;
			TVert centre = tvert(cx, cz, 0, tint);
			TVert in[6], corner[6], mid[6];
			for (int k = 0; k < 6; k++) {        // flat-top hex: corners at 0, 60, ... degrees
				float a = k * (float)M_PI / 3, b = (k + 1) * (float)M_PI / 3;
				in[k] = tvert(cx + HEX * 0.5f * cosf(a), cz + HEX * 0.5f * sinf(a), 0.5f, tint);
				corner[k] = tvert(cx + HEX * cosf(a), cz + HEX * sinf(a), 1, tint);
				float mx = (cosf(a) + cosf(b)) / 2, mz = (sinf(a) + sinf(b)) / 2;
				mid[k] = tvert(cx + HEX * mx, cz + HEX * mz, 1, tint);
			}
			for (int k = 0; k < 6; k++) {
				int n = (k + 1) % 6;
				TVert tris[4][3] = {
					{ centre, in[n], in[k] },
					{ in[k], mid[k], corner[k] },
					{ in[k], in[n], mid[k] },
					{ in[n], corner[n], mid[k] },
				};
				memcpy(v, tris, sizeof tris);
				v += 12;
			}
		}
}

static u32 rnd = 12345;
static float frand(void)
{
	rnd = rnd * 1103515245u + 12345u;
	return ((rnd >> 8) & 0xFFFF) / 65535.0f;
}

// one flat-shaded triangle of a decoration (colour by the face's light)
static TVert* decoTri(TVert* v, const float* a, const float* b, const float* c, float r, float g, float bl)
{
	float ux = b[0] - a[0], uy = b[1] - a[1], uz = b[2] - a[2];
	float wx = c[0] - a[0], wy = c[1] - a[1], wz = c[2] - a[2];
	float nx = uy * wz - uz * wy, ny = uz * wx - ux * wz, nz = ux * wy - uy * wx;
	float len = sqrtf(nx * nx + ny * ny + nz * nz) + 1e-6f;
	float l = (nx * -0.45f + ny * 0.8f + nz * 0.4f) / len;
	if (l < 0) l = -l * 0.3f;
	float s = 0.5f + 0.6f * l;
	const float* p[3] = { a, b, c };
	for (int k = 0; k < 3; k++)
		*v++ = (TVert){ p[k][0], p[k][1], p[k][2], 0, 0, 0, 0.5f, r * s, g * s, bl * s };
	return v;
}

// a cone (or a cylinder when top > 0) of n sides
static TVert* cone(TVert* v, float x, float y, float z, float rad, float top, float h, int n,
	float r, float g, float b)
{
	for (int k = 0; k < n; k++) {
		float a0 = k * 2 * (float)M_PI / n, a1 = (k + 1) * 2 * (float)M_PI / n;
		float p0[3] = { x + rad * cosf(a0), y, z + rad * sinf(a0) }, p1[3] = { x + rad * cosf(a1), y, z + rad * sinf(a1) };
		float q0[3] = { x + top * cosf(a0), y + h, z + top * sinf(a0) }, q1[3] = { x + top * cosf(a1), y + h, z + top * sinf(a1) };
		v = decoTri(v, p0, q0, p1, r, g, b);
		if (top > 0) v = decoTri(v, p1, q0, q1, r, g, b);
	}
	return v;
}

// a rough ball: an octahedron, its corners pushed a little at random
static TVert* blob(TVert* v, float x, float y, float z, float rx, float ry, float r, float g, float b)
{
	float d[6][3] = { {1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1} };
	float p[6][3];
	for (int i = 0; i < 6; i++) {
		float j = 0.8f + 0.4f * frand();
		p[i][0] = x + d[i][0] * rx * j; p[i][1] = y + d[i][1] * ry * j; p[i][2] = z + d[i][2] * rx * j;
	}
	int f[8][3] = { {2, 4, 0}, {2, 1, 4}, {2, 5, 1}, {2, 0, 5}, {3, 0, 4}, {3, 4, 1}, {3, 1, 5}, {3, 5, 0} };
	for (int i = 0; i < 8; i++) v = decoTri(v, p[f[i][0]], p[f[i][1]], p[f[i][2]], r, g, b);
	return v;
}

static void buildDecor(void)
{
	// forests: a few clumps of hexes
	int seeds[][2] = { {2, 2}, {11, 3}, {6, 9}, {1, 9}, {12, 10} };
	for (int s = 0; s < 5; s++)
		for (int r = 0; r < ROWS; r++)
			for (int c = 0; c < COLS; c++) {
				int dc = c - seeds[s][0], dr = r - seeds[s][1];
				if (dc * dc + dr * dr <= 2 + s % 2) forest[r][c] = true;
			}
	int maxVerts = 120000;
	TVert* buf = malloc(maxVerts * sizeof(TVert));
	TVert* v = buf;
	for (int r = 0; r < ROWS; r++)
		for (int c = 0; c < COLS; c++) {
			float cx, cz;
			hexCentre(c, r, &cx, &cz);
			int count = forest[r][c] ? (nsprites ? 14 : 9) : (frand() < 0.2f ? 1 : 0);
			for (int t = 0; t < count && v - buf < maxVerts - 400; t++) {
				float a = frand() * 6.283f, d = sqrtf(frand()) * HEX * 0.85f;
				float x = cx + d * cosf(a), z = cz + d * sinf(a), y = height(x, z) - 0.2f;
				float s = 0.8f + 0.5f * frand();
				if (nsprites && ntrees < MAX_TREES) {   // a sprite: crowns and conifers, bushes at the edge
					int k = frand() < 0.45f ? 2 : (frand() < 0.5f ? 0 : 1);
					if (d > HEX * 0.7f && frand() < 0.5f) k = 3 + (frand() < 0.5f);
					if (k >= nsprites) k = 0;
					trees[ntrees++] = (Tree){ x, y + 0.2f, z, s, 0.85f + 0.3f * frand(), k };
					continue;
				}
				if (frand() < 0.6f) {   // pine: trunk and three cones
					v = cone(v, x, y, z, 0.25f * s, 0.18f * s, 1.5f * s, 6, 0.45f, 0.30f, 0.18f);
					for (int k = 0; k < 3; k++)
						v = cone(v, x, y + (1.2f + k * 1.5f) * s, z, (2.0f - k * 0.5f) * s, 0, 2.4f * s, 8,
							0.16f, 0.36f + 0.05f * k, 0.18f);
				} else {                // broadleaf: trunk and a crown
					v = cone(v, x, y, z, 0.3f * s, 0.22f * s, 2.6f * s, 6, 0.42f, 0.30f, 0.20f);
					v = blob(v, x, y + 4.2f * s, z, 2.4f * s, 2.0f * s, 0.30f, 0.52f, 0.20f);
					v = blob(v, x + 0.8f * s, y + 3.4f * s, z + 0.5f * s, 1.6f * s, 1.3f * s, 0.26f, 0.48f, 0.18f);
				}
			}
			if (frand() < 0.25f) {      // rocks
				float a = frand() * 6.283f, d = frand() * HEX * 0.7f;
				float x = cx + d * cosf(a), z = cz + d * sinf(a);
				v = blob(v, x, height(x, z) + 0.2f, z, 0.9f, 0.5f, 0.55f, 0.54f, 0.50f);
			}
		}
	decorCount = v - buf;
	decor = linearCopy(buf, decorCount * sizeof(TVert));
	free(buf);
}

static void loadTrees(void)
{
	size_t size;
	u8* buf = readFile("romfs:/trees.bin", &size);
	if (!buf) return;
	u16 h[2];
	memcpy(h, buf + 4, 4);
	size_t tex = (size_t)h[0] * h[0] * 2;
	if (memcmp(buf, "LLTR", 4) || h[1] > 8 || 8 + h[1] * sizeof(Sprite) + tex != size) { free(buf); return; }
	nsprites = h[1];
	memcpy(sprites, buf + 8, nsprites * sizeof(Sprite));
	C3D_TexInit(&treeTex, h[0], h[0], GPU_RGBA5551);
	C3D_TexUpload(&treeTex, buf + 8 + nsprites * sizeof(Sprite));
	C3D_TexSetFilter(&treeTex, GPU_LINEAR, GPU_LINEAR);
	C3D_TexSetWrap(&treeTex, GPU_CLAMP_TO_EDGE, GPU_CLAMP_TO_EDGE);
	free(buf);
	treeVerts = linearAlloc(MAX_TREES * 6 * sizeof(TVert));
}

// every tree a quad standing on its foot, turned about the vertical to face the camera
static void drawTrees(float yaw)
{
	if (!ntrees) return;
	float rx = cosf(yaw), rz = -sinf(yaw);        // the camera's right on the ground
	TVert* v = treeVerts;
	for (int i = 0; i < ntrees; i++) {
		Tree* t = &trees[i];
		Sprite* s = &sprites[t->sprite];
		float hw = s->w * t->s / 2, h = s->h * t->s;
		float r = 0.62f * t->tint, g = 0.80f * t->tint, b = 0.45f * t->tint;   // greener than the source
		// v from the top, as for the knights (the tile order already flips the rows)
		TVert a = { t->x - rx * hw, t->y, t->z - rz * hw, s->u0, s->v1, 0, 0.5f, r, g, b };
		TVert c = { t->x + rx * hw, t->y, t->z + rz * hw, s->u1, s->v1, 0, 0.5f, r, g, b };
		TVert d = { t->x + rx * hw, t->y + h, t->z + rz * hw, s->u1, s->v0, 0, 0.5f, r, g, b };
		TVert e = { t->x - rx * hw, t->y + h, t->z - rz * hw, s->u0, s->v0, 0, 0.5f, r, g, b };
		*v++ = a; *v++ = c; *v++ = d;
		*v++ = a; *v++ = d; *v++ = e;
	}
	GSPGPU_FlushDataCache(treeVerts, ntrees * 6 * sizeof(TVert));
	C3D_TexBind(0, &treeTex);
	C3D_TexEnv* env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_RGB, GPU_TEXTURE0, GPU_PRIMARY_COLOR, 0);
	C3D_TexEnvFunc(env, C3D_RGB, GPU_MODULATE);
	C3D_TexEnvScale(env, C3D_RGB, GPU_TEVSCALE_2);
	C3D_TexEnvSrc(env, C3D_Alpha, GPU_TEXTURE0, 0, 0);
	C3D_TexEnvFunc(env, C3D_Alpha, GPU_REPLACE);
	C3D_TexEnvInit(C3D_GetTexEnv(1));
	C3D_AlphaTest(true, GPU_GREATER, 0x80);
	C3D_CullFace(GPU_CULL_NONE);
	C3D_BufInfo* buf = C3D_GetBufInfo();
	BufInfo_Init(buf);
	BufInfo_Add(buf, treeVerts, sizeof(TVert), 4, 0x3210);
	C3D_DrawArrays(GPU_TRIANGLES, 0, ntrees * 6);
	C3D_AlphaTest(false, GPU_ALWAYS, 0);
}

static void texturesInit(void)
{
	u16* px = malloc(GROUND_TEX * GROUND_TEX * 2);
	for (u32 y = 0; y < GROUND_TEX; y++)
		for (u32 x = 0; x < GROUND_TEX; x++) {   // grass: greens with tufts
			u32 n = (x * 37 + y * 101 + (x * y * 7) % 13 + ((x ^ y) * 5) % 7) % 9;
			u32 r = 9 + n / 2, g = 30 + n, b = 5 + n / 3;
			px[texIndex(x, y, GROUND_TEX)] = r << 11 | g << 5 | b;
		}
	C3D_TexInit(&groundTex, GROUND_TEX, GROUND_TEX, GPU_RGB565);
	C3D_TexUpload(&groundTex, px);
	C3D_TexSetFilter(&groundTex, GPU_LINEAR, GPU_LINEAR);
	C3D_TexSetWrap(&groundTex, GPU_REPEAT, GPU_REPEAT);
	for (u32 y = 0; y < BORDER_TEX; y++)
		for (u32 x = 0; x < BORDER_TEX; x++) {   // u = distance from the hex centre: dark at the edge
			float t = x / (float)(BORDER_TEX - 1), k = t < 0.86f ? 1 : 1 - (t - 0.86f) / 0.14f * 0.45f;
			u32 r = (u32)(31 * k), g = (u32)(63 * k), b = (u32)(31 * k);
			px[texIndex(x, y, BORDER_TEX)] = r << 11 | g << 5 | b;
		}
	C3D_TexInit(&borderTex, BORDER_TEX, BORDER_TEX, GPU_RGB565);
	C3D_TexUpload(&borderTex, px);
	C3D_TexSetFilter(&borderTex, GPU_LINEAR, GPU_LINEAR);
	C3D_TexSetWrap(&borderTex, GPU_CLAMP_TO_EDGE, GPU_CLAMP_TO_EDGE);
	free(px);
}

// --- units -------------------------------------------------------------------------------

static void addUnit(int model, int c, int r, float yaw)
{
	if (nunits >= MAX_UNITS) return;
	Unit* u = &units[nunits];
	hexCentre(c, r, &u->x, &u->z);
	u->tx = u->x; u->tz = u->z;
	u->model = model;
	u->yaw = yaw;
	for (int i = 0; i < PER_HEX; i++) {
		Knight* k = &knights[nknights++];
		k->unit = nunits;
		k->dx = ((i % 4) - 1.5f) * 1.5f + (frand() - 0.5f) * 0.3f;
		k->dz = ((i / 4) - 0.5f) * 3.8f + (frand() - 0.5f) * 0.4f;
		k->anim = A_IDLE;
		k->t0 = -frand() * 2;
	}
	nunits++;
}

static void advance(int model, float now)
{
	for (int i = 0; i < nunits; i++) {
		Unit* u = &units[i];
		if (u->model != model || u->tx != u->x || u->tz != u->z) continue;
		u->tx = u->x + sinf(u->yaw) * SQ3 * HEX;   // one hex forward
		u->tz = u->z + cosf(u->yaw) * SQ3 * HEX;
		for (int k = 0; k < nknights; k++)
			if (knights[k].unit == i) { knights[k].anim = A_RUN; knights[k].t0 = now - frand() * 0.3f; }
	}
}

static void stepUnits(float dt, float now)
{
	for (int i = 0; i < nunits; i++) {
		Unit* u = &units[i];
		float dx = u->tx - u->x, dz = u->tz - u->z, d = sqrtf(dx * dx + dz * dz);
		if (d == 0) continue;
		float s = models[u->model].anims[A_RUN].speed * dt;
		if (s >= d) {
			u->x = u->tx; u->z = u->tz;
			for (int k = 0; k < nknights; k++)
				if (knights[k].unit == i) { knights[k].anim = A_IDLE; knights[k].t0 = now - frand(); }
		} else {
			u->x += dx / d * s; u->z += dz / d * s;
		}
	}
}

// --- drawing -----------------------------------------------------------------------------

static void setSoldierBuffers(const float* a, const float* b, const float* uv)
{
	C3D_BufInfo* buf = C3D_GetBufInfo();
	BufInfo_Init(buf);
	BufInfo_Add(buf, a, 12, 1, 0x0);
	BufInfo_Add(buf, b, 12, 1, 0x1);
	BufInfo_Add(buf, uv, 8, 1, 0x2);
}

static void setTerrainBuffers(const TVert* v)
{
	C3D_BufInfo* buf = C3D_GetBufInfo();
	BufInfo_Init(buf);
	BufInfo_Add(buf, v, sizeof(TVert), 4, 0x3210);
}

static float camYaw;           // trees turn to it

static void drawWorld(const C3D_Mtx* proj, const C3D_Mtx* view, float now)
{
	// terrain: grass * shading * hex border
	C3D_BindProgram(&terrainProg);
	C3D_SetAttrInfo(&terrainAttr);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uTProj, proj);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uTModelView, view);
	C3D_CullFace(GPU_CULL_NONE);
	C3D_TexBind(0, &groundTex);
	C3D_TexBind(1, &borderTex);
	C3D_TexEnv* env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_TEXTURE0, GPU_PRIMARY_COLOR, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_MODULATE);
	env = C3D_GetTexEnv(1);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_PREVIOUS, GPU_TEXTURE1, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_MODULATE);
	setTerrainBuffers(terrain);
	C3D_DrawArrays(GPU_TRIANGLES, 0, terrainCount);

	// trees and rocks: vertex colour only
	env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_PRIMARY_COLOR, 0, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_REPLACE);
	C3D_TexEnvInit(C3D_GetTexEnv(1));
	setTerrainBuffers(decor);
	C3D_DrawArrays(GPU_TRIANGLES, 0, decorCount);
	drawTrees(camYaw);

	// knights
	C3D_BindProgram(&soldierProg);
	C3D_SetAttrInfo(&soldierAttr);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uSProj, proj);
	C3D_CullFace(GPU_CULL_BACK_CCW);
	env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_TEXTURE0, GPU_CONSTANT, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_MODULATE);
	C3D_TexEnvColor(env, 0xFFA0A0A0);
	C3D_TexEnvScale(env, C3D_RGB, GPU_TEVSCALE_2);
	C3D_Mtx model, mv;
	for (int m = 0; m < 2; m++) {
		Model* md = &models[m];
		C3D_TexBind(0, &md->tex);
		for (int i = 0; i < nknights; i++) {
			Knight* k = &knights[i];
			Unit* u = &units[k->unit];
			if (u->model != m) continue;
			Anim* a = &md->anims[k->anim];
			float t = (now - k->t0) / a->seconds;
			if (t >= 1 && (k->anim == A_IDLE || k->anim == A_FIDGET)) {   // next idle: now and then a fidget
				k->anim = frand() < 0.25f ? A_FIDGET : A_IDLE;
				k->t0 = now;
				a = &md->anims[k->anim];
				t = 0;
			}
			float f = (t - floorf(t)) * a->frames;
			int fa = (int)f, fb = (fa + 1) % a->frames;
			float cs = cosf(u->yaw), sn = sinf(u->yaw);
			float x = u->x + k->dx * cs + k->dz * sn, z = u->z - k->dx * sn + k->dz * cs;
			Mtx_Identity(&model);
			Mtx_Translate(&model, x, height(x, z), z, true);
			Mtx_RotateY(&model, u->yaw, true);
			Mtx_Multiply(&mv, view, &model);
			C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uSModelView, &mv);
			C3D_FVUnifSet(GPU_VERTEX_SHADER, uSBlend, f - fa, 0, 0, 0);
			const float* base = md->frames + (size_t)a->first * md->verts * 3;
			setSoldierBuffers(base + (size_t)fa * md->verts * 3, base + (size_t)fb * md->verts * 3, md->uvs);
			C3D_DrawElements(GPU_TRIANGLES, md->tris * 3, C3D_UNSIGNED_SHORT, md->indices);
		}
	}
}

static void shaderInit(shaderProgram_s* prog, DVLB_s** dvlb, u32* bin, u32 size)
{
	*dvlb = DVLB_ParseFile(bin, size);
	shaderProgramInit(prog);
	shaderProgramSetVsh(prog, &(*dvlb)->DVLE[0]);
}

int main(void)
{
	gfxInitDefault();
	consoleInit(GFX_BOTTOM, NULL);
	romfsInit();
	C3D_Init(0x100000);

	bool ok = loadModel(&models[0], "romfs:/knight_lo.bin") && loadModel(&models[1], "romfs:/polish_lo.bin");
	if (!ok) {
		printf("Missing romfs:/knight_lo.bin or polish_lo.bin\n(LLM2). Run build.ps1.\nSTART: exit\n");
		while (aptMainLoop()) {
			hidScanInput();
			if (hidKeysDown() & KEY_START) break;
			gspWaitForVBlank();
		}
		C3D_Fini();
		romfsExit();
		gfxExit();
		return 0;
	}
	loadTrees();               // sprites if romfs:/trees.bin is there, else trees made of cones
	buildDecor();              // decides the forests first: the terrain darkens them
	buildTerrain();
	texturesInit();
	// two armies facing each other across the middle
	for (int i = 0; i < 4; i++) addUnit(0, 4 + i * 2, 8, (float)M_PI);   // Teutonic, facing -z
	for (int i = 0; i < 4; i++) addUnit(1, 4 + i * 2, 3, 0);             // Polish, facing +z
	addUnit(1, 6, 1, 0);
	addUnit(0, 8, 10, (float)M_PI);

	C3D_RenderTarget* top = C3D_RenderTargetCreate(240, 400, GPU_RB_RGBA8, GPU_RB_DEPTH24_STENCIL8);
	C3D_RenderTargetSetOutput(top, GFX_TOP, GFX_LEFT, DISPLAY_TRANSFER_FLAGS);

	shaderInit(&soldierProg, &soldierDvlb, (u32*)soldier_shbin, soldier_shbin_size);
	uSProj = shaderInstanceGetUniformLocation(soldierProg.vertexShader, "projection");
	uSModelView = shaderInstanceGetUniformLocation(soldierProg.vertexShader, "modelView");
	uSBlend = shaderInstanceGetUniformLocation(soldierProg.vertexShader, "blend");
	shaderInit(&terrainProg, &terrainDvlb, (u32*)terrain_shbin, terrain_shbin_size);
	uTProj = shaderInstanceGetUniformLocation(terrainProg.vertexShader, "projection");
	uTModelView = shaderInstanceGetUniformLocation(terrainProg.vertexShader, "modelView");
	AttrInfo_Init(&soldierAttr);
	AttrInfo_AddLoader(&soldierAttr, 0, GPU_FLOAT, 3);
	AttrInfo_AddLoader(&soldierAttr, 1, GPU_FLOAT, 3);
	AttrInfo_AddLoader(&soldierAttr, 2, GPU_FLOAT, 2);
	AttrInfo_Init(&terrainAttr);
	AttrInfo_AddLoader(&terrainAttr, 0, GPU_FLOAT, 3);
	AttrInfo_AddLoader(&terrainAttr, 1, GPU_FLOAT, 2);
	AttrInfo_AddLoader(&terrainAttr, 2, GPU_FLOAT, 2);
	AttrInfo_AddLoader(&terrainAttr, 3, GPU_FLOAT, 3);

	float camX, camZ;
	hexCentre(7, 5, &camX, &camZ);
	camZ += 3;
	float yaw = 0.6f, pitch = 0.55f, dist = 55;
	u64 start = osGetTime(), last = start;
	float fps = 0;
	int fpsFrames = 0;
	u64 fpsStart = start;

	while (aptMainLoop()) {
		hidScanInput();
		u32 down = hidKeysDown(), held = hidKeysHeld();
		if (down & KEY_START) break;
		u64 nowMs = osGetTime();
		float now = (nowMs - start) / 1000.0f, dt = (nowMs - last) / 1000.0f;
		last = nowMs;
		if (dt > 0.1f) dt = 0.1f;
		if (down & KEY_A) advance(1, now);
		if (down & KEY_B) advance(0, now);
		stepUnits(dt, now);

		circlePosition cp;
		hidCircleRead(&cp);
		if (abs(cp.dx) > 15) yaw += cp.dx / 156.0f * 0.04f;
		if (abs(cp.dy) > 15) pitch += cp.dy / 156.0f * 0.03f;
		if (pitch < 0.12f) pitch = 0.12f;
		if (pitch > 1.45f) pitch = 1.45f;
		if (held & KEY_L) dist *= 1.03f;
		if (held & KEY_R) dist /= 1.03f;
		if (dist < 6) dist = 6;
		if (dist > 160) dist = 160;
		float pan = dist * 0.02f, fx = -sinf(yaw), fz = -cosf(yaw);   // forward on the ground
		if (held & KEY_DUP) { camX += fx * pan; camZ += fz * pan; }
		if (held & KEY_DDOWN) { camX -= fx * pan; camZ -= fz * pan; }
		if (held & KEY_DLEFT) { camX += fz * pan; camZ -= fx * pan; }
		if (held & KEY_DRIGHT) { camX -= fz * pan; camZ += fx * pan; }
		if (++fpsFrames == 30) {
			fps = fpsFrames * 1000.0f / (nowMs - fpsStart);
			fpsStart = nowMs;
			fpsFrames = 0;
		}

		C3D_FVec target = FVec3_New(camX, height(camX, camZ), camZ);
		C3D_FVec eye = FVec3_New(camX + dist * cosf(pitch) * sinf(yaw), target.y + dist * sinf(pitch),
			camZ + dist * cosf(pitch) * cosf(yaw));
		C3D_Mtx proj, view;
		Mtx_PerspTilt(&proj, C3D_AngleFromDegrees(45), C3D_AspectRatioTop, 0.5f, 500, false);
		Mtx_LookAt(&view, eye, target, FVec3_New(0, 1, 0), false);

		C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
		C3D_RenderTargetClear(top, C3D_CLEAR_ALL, 0x9CC4E8FF, 0);
		C3D_FrameDrawOn(top);
		C3D_DepthTest(true, GPU_GREATER, GPU_WRITE_ALL);
		camYaw = yaw;
		drawWorld(&proj, &view, now);
		C3D_FrameEnd(0);

		int tris = terrainCount / 3 + decorCount / 3 + ntrees * 2;
		for (int m = 0; m < 2; m++) {
			int n = 0;
			for (int i = 0; i < nknights; i++) n += units[knights[i].unit].model == m;
			tris += n * models[m].tris;
		}
		printf("\x1b[1;1HHex battle prototype\n\n");
		printf("hexes     %d x %d, forests %s  \n", COLS, ROWS, "dark");
		printf("knights   %d (%d units of %d)   \n", nknights, nunits, PER_HEX);
		printf("triangles %6d                   \n", tris);
		printf("  terrain %6d, rocks %5d     \n", terrainCount / 3, decorCount / 3);
		printf("  trees   %6d sprites (%d tris) \n", ntrees, ntrees * 2);
		printf("fps       %5.1f                  \n", fps);
		printf("cpu ms    %5.2f  gpu ms %5.2f    \n", C3D_GetProcessingTime(), C3D_GetDrawingTime());
		printf("cmdbuf    %3d%%                  \n", (int)(C3D_GetCmdBufUsage() * 100));
		printf("\nA: Polish advance  B: Teutons advance\n");
		printf("pad: turn/tilt  D-pad: move\nL/R: zoom  START: exit\n");
	}

	for (int m = 0; m < 2; m++) {
		C3D_TexDelete(&models[m].tex);
		linearFree(models[m].uvs);
		linearFree(models[m].indices);
		linearFree(models[m].frames);
	}
	C3D_TexDelete(&groundTex);
	C3D_TexDelete(&borderTex);
	if (nsprites) {
		C3D_TexDelete(&treeTex);
		linearFree(treeVerts);
	}
	linearFree(terrain);
	linearFree(decor);
	shaderProgramFree(&soldierProg);
	shaderProgramFree(&terrainProg);
	DVLB_Free(soldierDvlb);
	DVLB_Free(terrainDvlb);
	C3D_Fini();
	romfsExit();
	gfxExit();
	return 0;
}
