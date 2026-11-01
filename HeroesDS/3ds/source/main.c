// HeroesDS 3D political map prototype for the 3DS (tools/make_m3.py): a flat map in 3D.
// The picture (fractal borders, coast, paper, waves) comes as tiles of 1024x1024 --
// only the tiles near the camera are kept, loaded by a worker thread from
// romfs:/tiles/ -- over one texture of the whole map (romfs:/overview.bin) for the rest.
// Owners' colours are put on while loading. Each region's exact shape (romfs:/map3d.bin)
// is drawn only to light up the selected one. Bottom screen: the map, tap a province to
// select it, drag to pan. Top screen: a closer stereo view and the info.
#include <3ds.h>
#include <citro3d.h>
#include <citro2d.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "miniz.h"
#include "map_shbin.h"
#include "maptex_shbin.h"

#define CLEAR_COLOR 0x96BEC8FF   // RGBA: the sea of the picture
#define TINT 0.62f               // as in make_m3.py: how strong the owners' colours are
#define SLOTS 6                  // tiles kept at once
#define LABEL_DIST 80.0f         // names further from the eye are not drawn

#define DISPLAY_TRANSFER_FLAGS \
	(GX_TRANSFER_FLIP_VERT(0) | GX_TRANSFER_OUT_TILED(0) | GX_TRANSFER_RAW_COPY(0) | \
	GX_TRANSFER_IN_FORMAT(GX_TRANSFER_FMT_RGBA8) | GX_TRANSFER_OUT_FORMAT(GX_TRANSFER_FMT_RGB8) | \
	GX_TRANSFER_SCALING(GX_TRANSFER_SCALE_NO))

enum { KIND_LAND, KIND_SEA, KIND_NEUTRAL };
enum { NO_REGION = 0xFFFF };

// map3d.bin and the tiles, see docs/FORMATS.md
typedef struct {
	char magic[4];
	u16 version, nregions, nland, nfactions;
	u32 nverts, nidx, tex;
	float world;               // the map's width (and depth) in world units
	u16 tiles, pad;            // tiles per side
} MapHeader;

typedef struct {
	u8 r, g, b, pad;
	char name[16];
} Faction;

typedef struct {
	s16 id;
	s8 kind, owner;
	u8 nneigh, pad[3];
	char name[24];
	float cx, cz, x0, z0, x1, z1;
	u32 vstart, vcount, istart, icount, itop, reserved;
} Region;

typedef struct { float x, y, z, shade; } Vertex;
typedef struct { float x, y, z, u, v; } TexVertex;

_Static_assert(sizeof(MapHeader) == 32, "header");
_Static_assert(sizeof(Faction) == 20, "faction");
_Static_assert(sizeof(Region) == 80, "region");

enum { SLOT_FREE, SLOT_LOADING, SLOT_READY, SLOT_FAILED };

// one texture of the map: a tile, or the overview (tx = -1)
typedef struct {
	C3D_Tex tex;
	u16* ids;                  // region index per pixel, level 0, texture order
	int tx, ty;
	volatile int state;
	u32 used;                  // frame it was last wanted
} Slot;

static MapHeader hdr;
static Faction factions[8];
static Region* regions;
static u8 (*tint)[3];        // per region: the colour the paper is multiplied by
static Vertex* verts;        // linear memory
static u16* indices;         // linear memory
static TexVertex* quad;      // linear memory: one map-sized quad, scaled per tile
static Slot overview, slots[SLOTS];
static u32 texPixels;        // pixels of a texture, all mipmap levels
static u8* fileBuf;          // a tile file
static size_t fileBufSize;
static u16* idsBuf;          // a tile's region indices, all levels

// worker thread: loads one slot at a time
static Thread worker;
static LightEvent wake;
static Slot* volatile job;
static volatile bool quitting;
static volatile float lastLoadMs;
static volatile int loadedCount;

typedef struct {
	shaderProgram_s program;
	DVLB_s* dvlb;
	int uProj, uModelView, uTint;
} Shader;

static Shader overlay, textured;
static C3D_AttrInfo attrOverlay, attrTex;
static C3D_BufInfo bufQuad;

typedef struct {
	float tx, tz;            // looked-at point on the ground
	float yaw, pitch, dist;
	float fovy, aspect;
	C3D_FVec eye, f, r, u;   // derived
} Camera;

static Camera cam;
static int selected = -1;
static float pulse;
static u32 frame;

static C2D_TextBuf nameBuf, infoBuf;
static C2D_Text* names;

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
	void* p = linearAlloc(size ? size : 4);
	memcpy(p, src, size);
	return p;
}

static void regionTint(int i, u8* rgb)
{
	const Region* g = &regions[i];
	if (g->kind == KIND_SEA) {
		rgb[0] = rgb[1] = rgb[2] = 255;
	} else if (g->kind == KIND_NEUTRAL || g->owner < 0) {
		rgb[0] = 190; rgb[1] = 180; rgb[2] = 160;
	} else {
		const Faction* f = &factions[g->owner];
		rgb[0] = TINT * f->r + (1 - TINT) * 255;
		rgb[1] = TINT * f->g + (1 - TINT) * 255;
		rgb[2] = TINT * f->b + (1 - TINT) * 255;
	}
}

static bool loadMap(void)
{
	size_t size;
	u8* buf = readFile("romfs:/map3d.bin", &size);
	if (!buf) return false;
	u8* p = buf;
	memcpy(&hdr, p, sizeof hdr); p += sizeof hdr;
	if (memcmp(hdr.magic, "HM3D", 4) || hdr.version != 4 || hdr.nregions >= NO_REGION
		|| hdr.nfactions > 8 || hdr.tex != 1024 || hdr.tiles < 1) {
		free(buf);
		return false;
	}
	memcpy(factions, p, hdr.nfactions * sizeof(Faction)); p += hdr.nfactions * sizeof(Faction);
	regions = malloc(hdr.nregions * sizeof(Region));
	memcpy(regions, p, hdr.nregions * sizeof(Region)); p += hdr.nregions * sizeof(Region);
	u32 nn = 0;
	for (int i = 0; i < hdr.nregions; i++) nn += regions[i].nneigh;
	p += (nn * sizeof(s16) + 3) & ~3;   // neighbour lists: not used yet
	verts = linearCopy(p, hdr.nverts * sizeof(Vertex)); p += hdr.nverts * sizeof(Vertex);
	indices = linearCopy(p, hdr.nidx * sizeof(u16));
	free(buf);

	tint = malloc(hdr.nregions * sizeof *tint);
	for (int i = 0; i < hdr.nregions; i++) regionTint(i, tint[i]);
	return true;
}

// index of pixel (column x, row y from the top) in the texture: 8x8 tiles from the
// bottom row up, Morton order inside a tile (tile_order in make_m3.py)
static u32 texIndex(u32 x, u32 y, u32 size)
{
	u32 yf = size - 1 - y;
	u32 tile = (yf >> 3) * (size >> 3) + (x >> 3);
	u32 xs = x & 7, ys = yf & 7;
	u32 m = (xs & 1) | ((ys & 1) << 1) | ((xs & 2) << 1) | ((ys & 2) << 2) | ((xs & 4) << 2) | ((ys & 4) << 3);
	return tile * 64 + m;
}

static bool unpack(const u8** p, const u8* end, void* out, u32 outSize)
{
	if (*p + 8 > end) return false;
	u32 raw, packed;
	memcpy(&raw, *p, 4);
	memcpy(&packed, *p + 4, 4);
	*p += 8;
	if (raw != outSize || *p + packed > end) return false;
	size_t n = tinfl_decompress_mem_to_mem(out, outSize, *p, packed, TINFL_FLAG_PARSE_ZLIB_HEADER);
	*p += (packed + 3) & ~3;
	return n == outSize;
}

// a texture file into a slot: the paper straight into the texture, times the owners'
// colours of its pixels; the region indices of level 0 kept for taps
static bool loadSlot(Slot* s)
{
	char path[64];
	if (s->tx < 0) snprintf(path, sizeof path, "romfs:/overview.bin");
	else snprintf(path, sizeof path, "romfs:/tiles/%d_%d.bin", s->tx, s->ty);
	FILE* f = fopen(path, "rb");
	if (!f) return false;
	size_t n = fread(fileBuf, 1, fileBufSize, f);
	fclose(f);
	const u8* p = fileBuf + 4;
	const u8* end = fileBuf + n;
	if (n < 4 || memcmp(fileBuf, "HT01", 4)
		|| !unpack(&p, end, s->tex.data, texPixels * 2) || !unpack(&p, end, idsBuf, texPixels * 2))
		return false;
	u16* out = s->tex.data;
	for (u32 k = 0; k < texPixels; k++) {
		u16 id = idsBuf[k];
		if (id >= hdr.nregions) continue;
		const u8* t = tint[id];
		u32 c = out[k];
		u32 r = ((c >> 11) << 3) * t[0] >> 8, g = (((c >> 5) & 63) << 2) * t[1] >> 8, b = ((c & 31) << 3) * t[2] >> 8;
		out[k] = (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3);
	}
	memcpy(s->ids, idsBuf, hdr.tex * hdr.tex * sizeof(u16));
	C3D_TexFlush(&s->tex);
	return true;
}

static void workerMain(void* arg)
{
	while (true) {
		LightEvent_Wait(&wake);
		if (quitting) break;
		Slot* s = job;
		if (!s) continue;
		u64 t0 = svcGetSystemTick();
		bool ok = loadSlot(s);
		lastLoadMs = (svcGetSystemTick() - t0) / (float)(SYSCLOCK_ARM11 / 1000);
		if (ok) loadedCount++;
		s->state = ok ? SLOT_READY : SLOT_FAILED;
		job = NULL;
	}
}

static bool slotInit(Slot* s)
{
	if (!C3D_TexInitMipmap(&s->tex, hdr.tex, hdr.tex, GPU_RGB565)) return false;
	C3D_TexSetFilter(&s->tex, GPU_LINEAR, GPU_LINEAR);
	C3D_TexSetFilterMipmap(&s->tex, GPU_LINEAR);
	C3D_TexSetWrap(&s->tex, GPU_CLAMP_TO_EDGE, GPU_CLAMP_TO_EDGE);
	s->ids = malloc(hdr.tex * hdr.tex * sizeof(u16));
	s->state = SLOT_FREE;
	s->tx = s->ty = -2;
	return s->ids != NULL;
}

static bool texturesInit(void)
{
	texPixels = C3D_TexCalcTotalSize(hdr.tex * hdr.tex, C3D_TexCalcMaxLevel(hdr.tex, hdr.tex));
	fileBufSize = texPixels * 4 + 64;   // more than both packed parts can take
	fileBuf = malloc(fileBufSize);
	idsBuf = malloc(texPixels * 2);
	if (!fileBuf || !idsBuf || !slotInit(&overview)) return false;
	overview.tx = overview.ty = -1;
	if (!loadSlot(&overview)) return false;
	overview.state = SLOT_READY;
	for (int i = 0; i < SLOTS && hdr.tiles > 1; i++)
		if (!slotInit(&slots[i])) return false;
	LightEvent_Init(&wake, RESET_ONESHOT);
	if (hdr.tiles > 1) {
		s32 prio = 0x30;
		svcGetThreadPriority(&prio, CUR_THREAD_HANDLE);
		worker = threadCreate(workerMain, NULL, 32 * 1024, prio + 1, -2, false);
	}
	return true;
}

static void texturesExit(void)
{
	if (worker) {
		quitting = true;
		LightEvent_Signal(&wake);
		threadJoin(worker, U64_MAX);
		threadFree(worker);
	}
	C3D_TexDelete(&overview.tex);
	free(overview.ids);
	for (int i = 0; i < SLOTS && hdr.tiles > 1; i++) {
		C3D_TexDelete(&slots[i].tex);
		free(slots[i].ids);
	}
	free(fileBuf);
	free(idsBuf);
}

static Slot* slotFor(int tx, int ty)
{
	for (int i = 0; i < SLOTS; i++)
		if (slots[i].tx == tx && slots[i].ty == ty && slots[i].state != SLOT_FREE) return &slots[i];
	return NULL;
}

static void cameraUpdate(Camera* c)
{
	float cp = cosf(c->pitch), sp = sinf(c->pitch);
	C3D_FVec target = FVec3_New(c->tx, 0, c->tz);
	c->eye = FVec3_New(c->tx + sinf(c->yaw) * cp * c->dist, sp * c->dist, c->tz + cosf(c->yaw) * cp * c->dist);
	c->f = FVec3_Normalize(FVec3_Subtract(target, c->eye));
	c->r = FVec3_Normalize(FVec3_Cross(c->f, FVec3_New(0, 1, 0)));
	c->u = FVec3_Cross(c->r, c->f);
}

// screen pixel -> ray direction, matching Mtx_PerspTilt(fovy, aspect)
static C3D_FVec cameraRay(const Camera* c, float px, float py, float w, float h)
{
	float t = tanf(c->fovy / 2);
	float nx = px / (w / 2) - 1, ny = 1 - py / (h / 2);
	return FVec3_Normalize(FVec3_Add(c->f, FVec3_Add(FVec3_Scale(c->r, nx * t * c->aspect),
		FVec3_Scale(c->u, ny * t))));
}

static bool cameraProject(const Camera* c, float x, float y, float z, float w, float h, float* px, float* py)
{
	C3D_FVec v = FVec3_Subtract(FVec3_New(x, y, z), c->eye);
	float d = FVec3_Dot(v, c->f);
	if (d < 0.1f) return false;
	float t = tanf(c->fovy / 2);
	*px = (FVec3_Dot(v, c->r) / (d * t * c->aspect) + 1) * w / 2;
	*py = (1 - FVec3_Dot(v, c->u) / (d * t)) * h / 2;
	return *px > -40 && *px < w + 40 && *py > -10 && *py < h + 10;
}

// where the ray from a screen pixel meets the ground (rays over the horizon: far away)
static void groundAt(const Camera* c, float px, float py, float w, float h, float* x, float* z)
{
	C3D_FVec d = cameraRay(c, px, py, w, h);
	float s = d.y < -1e-3f ? -c->eye.y / d.y : 1e6f;
	float far = c->dist * 4;
	if (s > far) s = far;
	*x = c->eye.x + d.x * s;
	*z = c->eye.z + d.z * s;
}

// the part of the map a camera sees, as a box (x0, z0, x1, z1) in world units
static void viewBox(const Camera* c, float w, float h, float* box)
{
	static const float at[8][2] = { {0,0}, {0.5f,0}, {1,0}, {1,0.5f}, {1,1}, {0.5f,1}, {0,1}, {0,0.5f} };
	box[0] = box[1] = 1e9f;
	box[2] = box[3] = -1e9f;
	for (int i = 0; i < 8; i++) {
		float x, z;
		groundAt(c, at[i][0] * w, at[i][1] * h, w, h, &x, &z);
		if (x < box[0]) box[0] = x;
		if (z < box[1]) box[1] = z;
		if (x > box[2]) box[2] = x;
		if (z > box[3]) box[3] = z;
	}
}

// the tiles seen by both cameras, nearest the looked-at point first: keep them, load the
// first missing one (one at a time), free the ones no longer seen when a slot is needed
static void streamTiles(const Camera* cams[2], const float sizes[2][2])
{
	if (hdr.tiles < 2) return;
	float span = hdr.world / hdr.tiles, half = hdr.world / 2;
	int want[64][2], n = 0;
	float dist[64];
	for (int c = 0; c < 2; c++) {
		float b[4];
		viewBox(cams[c], sizes[c][0], sizes[c][1], b);
		int x0 = floorf((b[0] + half) / span), z0 = floorf((b[1] + half) / span);
		int x1 = floorf((b[2] + half) / span), z1 = floorf((b[3] + half) / span);
		if (x0 < 0) x0 = 0;
		if (z0 < 0) z0 = 0;
		if (x1 >= hdr.tiles) x1 = hdr.tiles - 1;
		if (z1 >= hdr.tiles) z1 = hdr.tiles - 1;
		for (int tz = z0; tz <= z1; tz++)
			for (int tx = x0; tx <= x1; tx++) {
				bool dup = false;
				for (int i = 0; i < n; i++) dup |= want[i][0] == tx && want[i][1] == tz;
				if (dup || n == 64) continue;
				float dx = (tx + 0.5f) * span - half - cams[c]->tx, dz = (tz + 0.5f) * span - half - cams[c]->tz;
				want[n][0] = tx;
				want[n][1] = tz;
				dist[n++] = dx * dx + dz * dz;
			}
	}
	// nearest first (few, insertion sort)
	for (int i = 1; i < n; i++)
		for (int j = i; j > 0 && dist[j] < dist[j - 1]; j--) {
			float d = dist[j]; dist[j] = dist[j - 1]; dist[j - 1] = d;
			int a = want[j][0], b = want[j][1];
			want[j][0] = want[j - 1][0]; want[j][1] = want[j - 1][1];
			want[j - 1][0] = a; want[j - 1][1] = b;
		}
	if (n > SLOTS) n = SLOTS;
	for (int i = 0; i < n; i++) {
		Slot* s = slotFor(want[i][0], want[i][1]);
		if (s) s->used = frame;
	}
	if (job) return;
	for (int i = 0; i < n; i++) {
		if (slotFor(want[i][0], want[i][1])) continue;
		// a free slot, else the one not wanted for longest
		Slot* best = NULL;
		for (int k = 0; k < SLOTS; k++) {
			Slot* s = &slots[k];
			if (s->state == SLOT_LOADING || (s->state != SLOT_FREE && s->used == frame)) continue;
			if (!best || s->state == SLOT_FREE || (best->state != SLOT_FREE && s->used < best->used)) best = s;
		}
		if (!best) return;
		best->state = SLOT_LOADING;
		best->tx = want[i][0];
		best->ty = want[i][1];
		best->used = frame;
		job = best;
		LightEvent_Signal(&wake);
		return;
	}
}

// the region under a screen pixel: the ray meets the map, the pixel there says which
static int pick(const Camera* c, float px, float py)
{
	C3D_FVec d = cameraRay(c, px, py, 320, 240);
	if (d.y > -1e-4f) return -1;
	float s = -c->eye.y / d.y;
	float u = (c->eye.x + d.x * s) / hdr.world + 0.5f, v = (c->eye.z + d.z * s) / hdr.world + 0.5f;
	if (u < 0 || v < 0 || u >= 1 || v >= 1) return -1;
	int tx = u * hdr.tiles, ty = v * hdr.tiles;
	Slot* sl = hdr.tiles > 1 ? slotFor(tx, ty) : NULL;
	int id;
	if (sl && sl->state == SLOT_READY) {
		float fu = u * hdr.tiles - tx, fv = v * hdr.tiles - ty;
		id = sl->ids[texIndex(fu * hdr.tex, fv * hdr.tex, hdr.tex)];
	} else {
		id = overview.ids[texIndex(u * hdr.tex, v * hdr.tex, hdr.tex)];
	}
	if (id >= hdr.nregions || regions[id].kind == KIND_NEUTRAL) return -1;
	return id;
}

static void shaderInit(Shader* s, u32* bin, u32 size)
{
	s->dvlb = DVLB_ParseFile(bin, size);
	shaderProgramInit(&s->program);
	shaderProgramSetVsh(&s->program, &s->dvlb->DVLE[0]);
	s->uProj = shaderInstanceGetUniformLocation(s->program.vertexShader, "projection");
	s->uModelView = shaderInstanceGetUniformLocation(s->program.vertexShader, "modelView");
	s->uTint = shaderInstanceGetUniformLocation(s->program.vertexShader, "tint");
}

static void shaderFree(Shader* s)
{
	shaderProgramFree(&s->program);
	DVLB_Free(s->dvlb);
}

static void sceneInit(void)
{
	shaderInit(&overlay, (u32*)map_shbin, map_shbin_size);
	shaderInit(&textured, (u32*)maptex_shbin, maptex_shbin_size);

	AttrInfo_Init(&attrOverlay);
	AttrInfo_AddLoader(&attrOverlay, 0, GPU_FLOAT, 3);   // v0 = position
	AttrInfo_AddLoader(&attrOverlay, 1, GPU_FLOAT, 1);   // v1 = shade
	AttrInfo_Init(&attrTex);
	AttrInfo_AddLoader(&attrTex, 0, GPU_FLOAT, 3);       // v0 = position
	AttrInfo_AddLoader(&attrTex, 1, GPU_FLOAT, 2);       // v1 = texcoord

	// a unit quad (0..1 on x and z): picture row 0 (north, -z) is at t = 0
	TexVertex q[6] = {
		{ 0, 0, 0, 0, 0 }, { 1, 0, 0, 1, 0 }, { 1, 0, 1, 1, 1 },
		{ 0, 0, 0, 0, 0 }, { 1, 0, 1, 1, 1 }, { 0, 0, 1, 0, 1 },
	};
	quad = linearCopy(q, sizeof q);
	BufInfo_Init(&bufQuad);
	BufInfo_Add(&bufQuad, quad, sizeof(TexVertex), 2, 0x10);

	u32 chars = 0;
	for (int i = 0; i < hdr.nregions; i++) chars += strlen(regions[i].name) + 1;
	nameBuf = C2D_TextBufNew(chars + 16);
	infoBuf = C2D_TextBufNew(512);
	names = calloc(hdr.nregions, sizeof(C2D_Text));
	for (int i = 0; i < hdr.nregions; i++) {
		C2D_TextParse(&names[i], nameBuf, regions[i].name);
		C2D_TextOptimize(&names[i]);
	}
}

static void drawQuad(const C3D_Mtx* view, C3D_Tex* tex, float x0, float z0, float size)
{
	C3D_Mtx mv = *view;
	Mtx_Translate(&mv, x0, 0, z0, true);
	Mtx_Scale(&mv, size, 1, size);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, textured.uModelView, &mv);
	C3D_TexBind(0, tex);
	C3D_DrawArrays(GPU_TRIANGLES, 0, 6);
}

static void drawMap(const C3D_Mtx* proj, const C3D_Mtx* view)
{
	// the map is flat: no depth test, later layers simply cover earlier ones
	C3D_DepthTest(false, GPU_ALWAYS, GPU_WRITE_COLOR);
	C3D_CullFace(GPU_CULL_NONE);
	for (int k = 1; k < 6; k++) C3D_TexEnvInit(C3D_GetTexEnv(k));

	C3D_BindProgram(&textured.program);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, textured.uProj, proj);
	C3D_SetAttrInfo(&attrTex);
	C3D_SetBufInfo(&bufQuad);
	C3D_TexEnv* env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_TEXTURE0, 0, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_REPLACE);
	float half = hdr.world / 2, span = hdr.world / hdr.tiles;
	drawQuad(view, &overview.tex, -half, -half, hdr.world);
	for (int i = 0; i < SLOTS && hdr.tiles > 1; i++)
		if (slots[i].state == SLOT_READY)
			drawQuad(view, &slots[i].tex, slots[i].tx * span - half, slots[i].ty * span - half, span);

	if (selected < 0) return;

	// the selected region: a pulsing light over its exact shape and an outline inside it
	const Region* g = &regions[selected];
	C3D_BindProgram(&overlay.program);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, overlay.uProj, proj);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, overlay.uModelView, view);
	C3D_SetAttrInfo(&attrOverlay);
	C3D_BufInfo buf;
	BufInfo_Init(&buf);
	BufInfo_Add(&buf, verts + g->vstart, sizeof(Vertex), 2, 0x10);
	C3D_SetBufInfo(&buf);
	env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_PRIMARY_COLOR, 0, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_REPLACE);
	C3D_AlphaBlend(GPU_BLEND_ADD, GPU_BLEND_ADD, GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA,
		GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA);
	float a = 0.18f + 0.1f * sinf(pulse);
	C3D_FVUnifSet(GPU_VERTEX_SHADER, overlay.uTint, 1, 1, 0.9f, a);
	C3D_DrawElements(GPU_TRIANGLES, g->itop, C3D_UNSIGNED_SHORT, indices + g->istart);
	C3D_FVUnifSet(GPU_VERTEX_SHADER, overlay.uTint, 1, 0.95f, 0.6f, 0.75f + 0.2f * sinf(pulse));
	C3D_DrawElements(GPU_TRIANGLES, g->icount - g->itop, C3D_UNSIGNED_SHORT, indices + g->istart + g->itop);
}

static void viewMatrix(const Camera* c, C3D_Mtx* view)
{
	Mtx_LookAt(view, c->eye, FVec3_New(c->tx, 0, c->tz), FVec3_New(0, 1, 0), false);
}

static void drawLabels(const Camera* c, float w, float h)
{
	for (int i = 0; i < hdr.nregions; i++) {
		const Region* g = &regions[i];
		if (g->kind != KIND_LAND) continue;
		float dx = g->cx - c->eye.x, dz = g->cz - c->eye.z, dy = c->eye.y;
		if (i != selected && dx * dx + dy * dy + dz * dz > LABEL_DIST * LABEL_DIST) continue;
		float px, py;
		if (!cameraProject(c, g->cx, 0, g->cz, w, h, &px, &py)) continue;
		u32 col = i == selected ? C2D_Color32(255, 255, 255, 255) : C2D_Color32(20, 12, 4, 255);
		C2D_DrawText(&names[i], C2D_AlignCenter | C2D_WithColor, px, py - 5, 0.5f, 0.36f, 0.36f, col);
	}
}

static void drawInfo(void)
{
	char text[256];
	int ready = 0;
	for (int i = 0; i < SLOTS && hdr.tiles > 1; i++) ready += slots[i].state == SLOT_READY;
	char stats[96];
	snprintf(stats, sizeof stats, "%d reg | tiles %dx%d: %d kept, %d loads, %.0f ms | free %lu KB",
		hdr.nregions, hdr.tiles, hdr.tiles, ready, loadedCount, lastLoadMs, (unsigned long)(linearSpaceFree() / 1024));
	if (selected < 0) {
		snprintf(text, sizeof text, "Tap a province or a sea zone.\nDrag: pan  L/R: turn  Up/Down: zoom\n%s", stats);
	} else {
		const Region* g = &regions[selected];
		const char* owner = g->kind == KIND_SEA ? "sea zone" : g->owner >= 0 ? factions[g->owner].name : "-";
		snprintf(text, sizeof text, "%s\n%s, %d neighbours\n%s", g->name, owner, g->nneigh, stats);
	}
	C2D_TextBufClear(infoBuf);
	C2D_Text t;
	C2D_TextParse(&t, infoBuf, text);
	C2D_TextOptimize(&t);
	C2D_DrawRectSolid(0, 0, 0.5f, 400, 58, C2D_Color32(0, 0, 0, 140));
	C2D_DrawText(&t, C2D_WithColor, 8, 4, 0.5f, 0.55f, 0.55f, C2D_Color32(255, 240, 200, 255));
}

static void render2D(C3D_RenderTarget* target)
{
	C2D_Prepare();
	C2D_SceneTarget(target);
	C3D_DepthTest(false, GPU_ALWAYS, GPU_WRITE_COLOR);
	C3D_AlphaBlend(GPU_BLEND_ADD, GPU_BLEND_ADD, GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA,
		GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA);
}

int main(void)
{
	gfxInitDefault();
	gfxSet3D(true);
	romfsInit();
	C3D_Init(C3D_DEFAULT_CMDBUF_SIZE);
	C2D_Init(C2D_DEFAULT_MAX_OBJECTS);

	if (!loadMap() || !texturesInit()) {
		consoleInit(GFX_BOTTOM, NULL);
		printf("Cannot read the map from romfs:/\nRun tools/make_m3.py, then rebuild.\nSTART: exit\n");
		while (aptMainLoop()) {
			hidScanInput();
			if (hidKeysDown() & KEY_START) break;
			gspWaitForVBlank();
		}
		gfxExit();
		return 0;
	}

	C3D_RenderTarget* topL = C3D_RenderTargetCreate(240, 400, GPU_RB_RGBA8, GPU_RB_DEPTH24_STENCIL8);
	C3D_RenderTarget* topR = C3D_RenderTargetCreate(240, 400, GPU_RB_RGBA8, GPU_RB_DEPTH24_STENCIL8);
	C3D_RenderTarget* bot = C3D_RenderTargetCreate(240, 320, GPU_RB_RGBA8, GPU_RB_DEPTH24_STENCIL8);
	C3D_RenderTargetSetOutput(topL, GFX_TOP, GFX_LEFT, DISPLAY_TRANSFER_FLAGS);
	C3D_RenderTargetSetOutput(topR, GFX_TOP, GFX_RIGHT, DISPLAY_TRANSFER_FLAGS);
	C3D_RenderTargetSetOutput(bot, GFX_BOTTOM, GFX_LEFT, DISPLAY_TRANSFER_FLAGS);
	sceneInit();

	cam = (Camera){ .tx = 0, .tz = 4, .yaw = 0, .pitch = C3D_AngleFromDegrees(55), .dist = 60,
		.fovy = C3D_AngleFromDegrees(50), .aspect = C3D_AspectRatioBot };

	bool touching = false, dragged = false;
	touchPosition t0 = { 0 }, tl = { 0 };
	float lim = hdr.world / 2, farPlane = hdr.world * 3;

	while (aptMainLoop()) {
		hidScanInput();
		u32 down = hidKeysDown(), held = hidKeysHeld(), up = hidKeysUp();
		if (down & KEY_START) break;
		frame++;

		// camera
		float step = cam.dist * 0.012f;
		circlePosition cp;
		hidCircleRead(&cp);
		float mx = cp.dx / 156.0f, my = cp.dy / 156.0f;
		// on the ground: right = (cos yaw, -sin yaw), forward (away from the eye) = (-sin yaw, -cos yaw)
		float rx = cosf(cam.yaw), rz = -sinf(cam.yaw), fx = -sinf(cam.yaw), fz = -cosf(cam.yaw);
		if (held & (KEY_DLEFT | KEY_L)) cam.yaw += 0.03f;
		if (held & (KEY_DRIGHT | KEY_R)) cam.yaw -= 0.03f;
		if (held & KEY_DUP) cam.dist *= 0.98f;
		if (held & KEY_DDOWN) cam.dist *= 1.02f;
		if (cam.dist < 8) cam.dist = 8;
		if (cam.dist > hdr.world * 1.3f) cam.dist = hdr.world * 1.3f;
		cam.tx += (rx * mx + fx * my) * step;
		cam.tz += (rz * mx + fz * my) * step;

		// touch: tap selects, drag pans
		touchPosition tp;
		hidTouchRead(&tp);
		if (down & KEY_TOUCH) {
			touching = true;
			dragged = false;
			t0 = tl = tp;
		} else if (touching && (held & KEY_TOUCH)) {
			if (abs(tp.px - t0.px) + abs(tp.py - t0.py) > 5) dragged = true;
			if (dragged) {
				// the map follows the stylus
				float k = cam.dist * 0.0035f;
				float dr = -(tp.px - tl.px) * k, df = (tp.py - tl.py) * k / sinf(cam.pitch);
				cam.tx += rx * dr + fx * df;
				cam.tz += rz * dr + fz * df;
			}
			tl = tp;
		} else if (touching && (up & KEY_TOUCH)) {
			touching = false;
			if (!dragged) {
				int i = pick(&cam, t0.px, t0.py);
				selected = i == selected ? -1 : i;
			}
		}
		if (cam.tx < -lim) cam.tx = -lim;
		if (cam.tx > lim) cam.tx = lim;
		if (cam.tz < -lim) cam.tz = -lim;
		if (cam.tz > lim) cam.tz = lim;
		cameraUpdate(&cam);
		pulse += 0.12f;

		// top: closer, lower view of the same spot
		Camera top = cam;
		top.dist = cam.dist * 0.55f;
		top.pitch = C3D_AngleFromDegrees(35);
		top.aspect = C3D_AspectRatioTop;
		if (selected >= 0) {
			top.tx = regions[selected].cx;
			top.tz = regions[selected].cz;
		}
		cameraUpdate(&top);
		float iod = osGet3DSliderState() / 3;

		const Camera* seen[2] = { &cam, &top };
		const float sizes[2][2] = { { 320, 240 }, { 400, 240 } };
		streamTiles(seen, sizes);

		C3D_Mtx proj, view;
		C3D_FrameBegin(C3D_FRAME_SYNCDRAW);

		viewMatrix(&top, &view);
		for (int eye = 0; eye < (iod > 0 ? 2 : 1); eye++) {
			C3D_RenderTarget* tgt = eye ? topR : topL;
			C3D_RenderTargetClear(tgt, C3D_CLEAR_ALL, CLEAR_COLOR, 0);
			C3D_FrameDrawOn(tgt);
			Mtx_PerspStereoTilt(&proj, top.fovy, top.aspect, 0.5f, farPlane, eye ? iod : -iod, top.dist, false);
			drawMap(&proj, &view);
			render2D(tgt);
			drawInfo();
			C2D_Flush();
		}

		C3D_RenderTargetClear(bot, C3D_CLEAR_ALL, CLEAR_COLOR, 0);
		C3D_FrameDrawOn(bot);
		Mtx_PerspTilt(&proj, cam.fovy, cam.aspect, 0.5f, farPlane, false);
		viewMatrix(&cam, &view);
		drawMap(&proj, &view);
		render2D(bot);
		drawLabels(&cam, 320, 240);
		C2D_Flush();

		C3D_FrameEnd(0);
	}

	texturesExit();
	C2D_TextBufDelete(nameBuf);
	C2D_TextBufDelete(infoBuf);
	shaderFree(&overlay);
	shaderFree(&textured);
	linearFree(verts);
	linearFree(indices);
	linearFree(quad);
	free(names);
	free(tint);
	C2D_Fini();
	C3D_Fini();
	romfsExit();
	gfxExit();
	return 0;
}
