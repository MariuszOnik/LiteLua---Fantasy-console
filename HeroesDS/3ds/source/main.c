// HeroesDS 3D political map prototype for the 3DS (tools/make_m3.py): a flat map in 3D --
// one quad with the picture of romfs:/map_tex.bin (all the detail: fractal borders,
// coast, paper, waves), owners' colours put on here -- and each region's exact shape from
// romfs:/map3d.bin, drawn only to light up the selected one. Bottom screen: the map, tap
// a province to select it, drag to pan. Top screen: a closer stereo view and the info.
#include <3ds.h>
#include <citro3d.h>
#include <citro2d.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "map_shbin.h"
#include "maptex_shbin.h"

#define CLEAR_COLOR 0x96BEC8FF   // RGBA: the sea of the picture
#define TINT 0.62f               // as in make_m3.py: how strong the owners' colours are

#define DISPLAY_TRANSFER_FLAGS \
	(GX_TRANSFER_FLIP_VERT(0) | GX_TRANSFER_OUT_TILED(0) | GX_TRANSFER_RAW_COPY(0) | \
	GX_TRANSFER_IN_FORMAT(GX_TRANSFER_FMT_RGBA8) | GX_TRANSFER_OUT_FORMAT(GX_TRANSFER_FMT_RGB8) | \
	GX_TRANSFER_SCALING(GX_TRANSFER_SCALE_NO))

enum { KIND_LAND, KIND_SEA, KIND_NEUTRAL };
enum { MAX_REGIONS = 255, NO_REGION = 255 };

// map3d.bin and map_tex.bin, see docs/FORMATS.md
typedef struct {
	char magic[4];
	u16 version, nregions, nland, nfactions;
	u32 nverts, nidx, tex;
	float world;               // the map's width (and depth) in world units
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

_Static_assert(sizeof(MapHeader) == 28, "header");
_Static_assert(sizeof(Faction) == 20, "faction");
_Static_assert(sizeof(Region) == 80, "region");

static MapHeader hdr;
static Faction factions[8];
static Region* regions;
static Vertex* verts;        // linear memory
static u16* indices;         // linear memory
static TexVertex* quad;      // linear memory
static u8* paper;            // the picture without owners' colours, RGB, texture order
static u8* ids;              // region index per pixel, texture order
static C3D_Tex mapTex;

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

static C2D_TextBuf nameBuf, infoBuf;
static C2D_Text names[MAX_REGIONS];

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

static bool loadMap(void)
{
	size_t size;
	u8* buf = readFile("romfs:/map3d.bin", &size);
	if (!buf) return false;
	u8* p = buf;
	memcpy(&hdr, p, sizeof hdr); p += sizeof hdr;
	if (memcmp(hdr.magic, "HM3D", 4) || hdr.version != 3 || hdr.nregions > MAX_REGIONS
		|| hdr.nfactions > 8 || hdr.tex != 1024) {
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

	// all mipmap levels: 1024 down to 8 pixels, as C3D_TexInitMipmap lays them out
	u32 pixels = C3D_TexCalcTotalSize(hdr.tex * hdr.tex, C3D_TexCalcMaxLevel(hdr.tex, hdr.tex));
	u8* tex = readFile("romfs:/map_tex.bin", &size);
	if (!tex || size != pixels * 4) return false;
	paper = tex;
	ids = tex + pixels * 3;
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

// the picture times every region's colour into the texture (after an owner changes)
static void paintMap(void)
{
	u8 tint[256][3];
	for (int i = 0; i < 256; i++) tint[i][0] = tint[i][1] = tint[i][2] = 255;
	for (int i = 0; i < hdr.nregions; i++) regionTint(i, tint[i]);
	u16* out = mapTex.data;
	u32 n = C3D_TexCalcTotalSize(mapTex.size, mapTex.maxLevel) / 2;   // every level
	for (u32 k = 0; k < n; k++) {
		const u8* c = paper + 3 * k;
		const u8* t = tint[ids[k]];
		u32 r = c[0] * t[0] >> 8, g = c[1] * t[1] >> 8, b = c[2] * t[2] >> 8;
		out[k] = (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3);
	}
	C3D_TexFlush(&mapTex);
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

// the region under a screen pixel: the ray meets the map, the pixel there says which
static int pick(const Camera* c, float px, float py)
{
	C3D_FVec d = cameraRay(c, px, py, 320, 240);
	if (d.y > -1e-4f) return -1;
	float s = -c->eye.y / d.y;
	float x = c->eye.x + d.x * s, z = c->eye.z + d.z * s;
	float tx = (x / hdr.world + 0.5f) * hdr.tex, ty = (z / hdr.world + 0.5f) * hdr.tex;
	if (tx < 0 || ty < 0 || tx >= hdr.tex || ty >= hdr.tex) return -1;
	int i = ids[texIndex(tx, ty, hdr.tex)];
	if (i == NO_REGION || regions[i].kind == KIND_NEUTRAL) return -1;
	return i;
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

	// the map: picture row 0 (north, -z) is at t = 0
	float h = hdr.world / 2;
	TexVertex q[6] = {
		{ -h, 0, -h, 0, 0 }, { h, 0, -h, 1, 0 }, { h, 0, h, 1, 1 },
		{ -h, 0, -h, 0, 0 }, { h, 0, h, 1, 1 }, { -h, 0, h, 0, 1 },
	};
	quad = linearCopy(q, sizeof q);
	BufInfo_Init(&bufQuad);
	BufInfo_Add(&bufQuad, quad, sizeof(TexVertex), 2, 0x10);

	C3D_TexInitMipmap(&mapTex, hdr.tex, hdr.tex, GPU_RGB565);
	C3D_TexSetFilter(&mapTex, GPU_LINEAR, GPU_LINEAR);
	C3D_TexSetFilterMipmap(&mapTex, GPU_LINEAR);
	C3D_TexSetWrap(&mapTex, GPU_CLAMP_TO_EDGE, GPU_CLAMP_TO_EDGE);
	paintMap();

	nameBuf = C2D_TextBufNew(4096);
	infoBuf = C2D_TextBufNew(512);
	for (int i = 0; i < hdr.nregions; i++) {
		C2D_TextParse(&names[i], nameBuf, regions[i].name);
		C2D_TextOptimize(&names[i]);
	}
}

static void drawMap(const C3D_Mtx* proj, const C3D_Mtx* view)
{
	C3D_DepthTest(true, GPU_GREATER, GPU_WRITE_ALL);
	C3D_CullFace(GPU_CULL_NONE);
	for (int k = 1; k < 6; k++) C3D_TexEnvInit(C3D_GetTexEnv(k));

	// the map
	C3D_BindProgram(&textured.program);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, textured.uProj, proj);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, textured.uModelView, view);
	C3D_SetAttrInfo(&attrTex);
	C3D_SetBufInfo(&bufQuad);
	C3D_TexBind(0, &mapTex);
	C3D_TexEnv* env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_TEXTURE0, 0, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_REPLACE);
	C3D_DrawArrays(GPU_TRIANGLES, 0, 6);

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
	C3D_DepthTest(false, GPU_ALWAYS, GPU_WRITE_COLOR);
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
		float px, py;
		if (!cameraProject(c, g->cx, 0, g->cz, w, h, &px, &py)) continue;
		u32 col = i == selected ? C2D_Color32(255, 255, 255, 255) : C2D_Color32(20, 12, 4, 255);
		C2D_DrawText(&names[i], C2D_AlignCenter | C2D_WithColor, px, py - 5, 0.5f, 0.36f, 0.36f, col);
	}
}

static void drawInfo(void)
{
	char text[256];
	if (selected < 0) {
		snprintf(text, sizeof text, "Tap a province or a sea zone.\nDrag: pan  L/R: turn  Up/Down: zoom");
	} else {
		const Region* g = &regions[selected];
		const char* owner = g->kind == KIND_SEA ? "sea zone" : g->owner >= 0 ? factions[g->owner].name : "-";
		snprintf(text, sizeof text, "%s\n%s, %d neighbours", g->name, owner, g->nneigh);
	}
	C2D_TextBufClear(infoBuf);
	C2D_Text t;
	C2D_TextParse(&t, infoBuf, text);
	C2D_TextOptimize(&t);
	C2D_DrawRectSolid(0, 0, 0.5f, 400, 44, C2D_Color32(0, 0, 0, 140));
	C2D_DrawText(&t, C2D_WithColor, 8, 4, 0.5f, 0.6f, 0.6f, C2D_Color32(255, 240, 200, 255));
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

	if (!loadMap()) {
		consoleInit(GFX_BOTTOM, NULL);
		printf("Cannot read romfs:/map3d.bin or map_tex.bin\nRun tools/make_m3.py, then rebuild.\nSTART: exit\n");
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
	float lim = hdr.world / 2;

	while (aptMainLoop()) {
		hidScanInput();
		u32 down = hidKeysDown(), held = hidKeysHeld(), up = hidKeysUp();
		if (down & KEY_START) break;

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
		if (cam.dist > 110) cam.dist = 110;
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

		C3D_Mtx proj, view;
		C3D_FrameBegin(C3D_FRAME_SYNCDRAW);

		viewMatrix(&top, &view);
		for (int eye = 0; eye < (iod > 0 ? 2 : 1); eye++) {
			C3D_RenderTarget* tgt = eye ? topR : topL;
			C3D_RenderTargetClear(tgt, C3D_CLEAR_ALL, CLEAR_COLOR, 0);
			C3D_FrameDrawOn(tgt);
			Mtx_PerspStereoTilt(&proj, top.fovy, top.aspect, 0.5f, 300, eye ? iod : -iod, top.dist, false);
			drawMap(&proj, &view);
			render2D(tgt);
			drawInfo();
			C2D_Flush();
		}

		C3D_RenderTargetClear(bot, C3D_CLEAR_ALL, CLEAR_COLOR, 0);
		C3D_FrameDrawOn(bot);
		Mtx_PerspTilt(&proj, cam.fovy, cam.aspect, 0.5f, 300, false);
		viewMatrix(&cam, &view);
		drawMap(&proj, &view);
		render2D(bot);
		drawLabels(&cam, 320, 240);
		C2D_Flush();

		C3D_FrameEnd(0);
	}

	C2D_TextBufDelete(nameBuf);
	C2D_TextBufDelete(infoBuf);
	C3D_TexDelete(&mapTex);
	shaderFree(&overlay);
	shaderFree(&textured);
	linearFree(verts);
	linearFree(indices);
	linearFree(quad);
	free(paper);
	C2D_Fini();
	C3D_Fini();
	romfsExit();
	gfxExit();
	return 0;
}
