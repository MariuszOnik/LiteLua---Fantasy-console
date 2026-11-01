// HeroesDS 3D political map prototype for the 3DS: provinces and sea zones from
// romfs:/map3d.bin (tools/make_m3.py) as 3D meshes. Bottom screen: the map, tap a
// province to select it, drag to pan. Top screen: a closer stereo view and the info.
#include <3ds.h>
#include <citro3d.h>
#include <citro2d.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "map_shbin.h"

#define CLEAR_COLOR 0x14283AFF   // RGBA: deep sea

#define DISPLAY_TRANSFER_FLAGS \
	(GX_TRANSFER_FLIP_VERT(0) | GX_TRANSFER_OUT_TILED(0) | GX_TRANSFER_RAW_COPY(0) | \
	GX_TRANSFER_IN_FORMAT(GX_TRANSFER_FMT_RGBA8) | GX_TRANSFER_OUT_FORMAT(GX_TRANSFER_FMT_RGB8) | \
	GX_TRANSFER_SCALING(GX_TRANSFER_SCALE_NO))

enum { KIND_LAND, KIND_SEA, KIND_NEUTRAL };
enum { BORDER_CLASSES = 3, MAX_REGIONS = 256 };

// map3d.bin, see docs/FORMATS.md
typedef struct {
	char magic[4];
	u16 version, nregions, nland, nfactions;
	u32 nverts, nidx, nbverts;
	float land_h;
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
	u32 vstart, vcount, istart, icount, itop;
} Region;

typedef struct { float x, y, z, shade; } Vertex;
typedef struct { float x, y, z; } BVertex;

_Static_assert(sizeof(MapHeader) == 28, "header");
_Static_assert(sizeof(Faction) == 20, "faction");
_Static_assert(sizeof(Region) == 76, "region");

static MapHeader hdr;
static Faction factions[8];
static Region* regions;
static s16* neighbours;      // all lists one after another
static u16* neighStart;
static Vertex* verts;        // linear memory
static u16* indices;         // linear memory
static BVertex* bverts;      // linear memory
static u32 bcount[BORDER_CLASSES];

static DVLB_s* dvlb;
static shaderProgram_s program;
static int uProj, uModelView, uTint;
static C3D_AttrInfo attrMap, attrBorder;
static C3D_BufInfo bufBorder;

typedef struct {
	float tx, tz;            // looked-at point on the ground
	float yaw, pitch, dist;
	float fovy, aspect;
	C3D_FVec eye, f, r, u;   // derived
} Camera;

static Camera cam;
static int selected = -1;
static float lift;           // current extra height of the selected province
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
	if (memcmp(hdr.magic, "HM3D", 4) || hdr.version != 1 || hdr.nregions > MAX_REGIONS || hdr.nfactions > 8) {
		free(buf);
		return false;
	}
	memcpy(factions, p, hdr.nfactions * sizeof(Faction)); p += hdr.nfactions * sizeof(Faction);
	regions = malloc(hdr.nregions * sizeof(Region));
	memcpy(regions, p, hdr.nregions * sizeof(Region)); p += hdr.nregions * sizeof(Region);
	memcpy(bcount, p, sizeof bcount); p += sizeof bcount;
	u32 nn = 0;
	neighStart = malloc((hdr.nregions + 1) * sizeof(u16));
	for (int i = 0; i < hdr.nregions; i++) {
		neighStart[i] = nn;
		nn += regions[i].nneigh;
	}
	neighStart[hdr.nregions] = nn;
	neighbours = malloc(nn * sizeof(s16) + 2);
	memcpy(neighbours, p, nn * sizeof(s16)); p += (nn * sizeof(s16) + 3) & ~3;
	verts = linearCopy(p, hdr.nverts * sizeof(Vertex)); p += hdr.nverts * sizeof(Vertex);
	indices = linearCopy(p, hdr.nidx * sizeof(u16)); p += (hdr.nidx * sizeof(u16) + 3) & ~3;
	bverts = linearCopy(p, hdr.nbverts * sizeof(BVertex));
	free(buf);
	return true;
}

static void cameraUpdate(Camera* c)
{
	float cp = cosf(c->pitch), sp = sinf(c->pitch);
	C3D_FVec target = FVec3_New(c->tx, hdr.land_h, c->tz);
	c->eye = FVec3_New(c->tx + sinf(c->yaw) * cp * c->dist, hdr.land_h + sp * c->dist,
		c->tz + cosf(c->yaw) * cp * c->dist);
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

static bool inTriangle(float x, float z, const Vertex* a, const Vertex* b, const Vertex* c)
{
	float d1 = (x - b->x) * (a->z - b->z) - (a->x - b->x) * (z - b->z);
	float d2 = (x - c->x) * (b->z - c->z) - (b->x - c->x) * (z - c->z);
	float d3 = (x - a->x) * (c->z - a->z) - (c->x - a->x) * (z - a->z);
	bool neg = d1 < 0 || d2 < 0 || d3 < 0, pos = d1 > 0 || d2 > 0 || d3 > 0;
	return !(neg && pos);
}

// region whose top contains (x, z), only regions of the given surface (land or sea)
static int regionAt(float x, float z, bool sea)
{
	for (int i = 0; i < hdr.nregions; i++) {
		const Region* g = &regions[i];
		if ((g->kind == KIND_SEA) != sea) continue;
		if (x < g->x0 || x > g->x1 || z < g->z0 || z > g->z1) continue;
		const Vertex* v = verts + g->vstart;
		const u16* t = indices + g->istart;
		for (u32 k = 0; k + 2 < g->itop; k += 3)
			if (inTriangle(x, z, &v[t[k]], &v[t[k + 1]], &v[t[k + 2]])) return i;
	}
	return -1;
}

static int pick(const Camera* c, float px, float py)
{
	C3D_FVec d = cameraRay(c, px, py, 320, 240);
	if (d.y > -1e-4f) return -1;
	// the land plates first, then the sea under them
	float s = (hdr.land_h - c->eye.y) / d.y;
	int i = regionAt(c->eye.x + d.x * s, c->eye.z + d.z * s, false);
	if (i >= 0) return regions[i].kind == KIND_LAND ? i : -1;
	s = -c->eye.y / d.y;
	return regionAt(c->eye.x + d.x * s, c->eye.z + d.z * s, true);
}

static void regionColor(int i, float* rgb)
{
	const Region* g = &regions[i];
	static const float parch[3] = { 226, 210, 170 };
	if (g->kind == KIND_SEA) {
		float k = (g->id & 1) ? 1.0f : 0.94f;
		rgb[0] = 100 * k; rgb[1] = 140 * k; rgb[2] = 185 * k;
	} else if (g->kind == KIND_NEUTRAL || g->owner < 0) {
		rgb[0] = 180; rgb[1] = 170; rgb[2] = 150;
	} else {
		const Faction* f = &factions[g->owner];
		rgb[0] = 0.55f * f->r + 0.45f * parch[0];
		rgb[1] = 0.55f * f->g + 0.45f * parch[1];
		rgb[2] = 0.55f * f->b + 0.45f * parch[2];
	}
	for (int k = 0; k < 3; k++) rgb[k] /= 255;
	if (i == selected) {
		float b = 0.25f + 0.1f * sinf(pulse);
		for (int k = 0; k < 3; k++) rgb[k] += (1 - rgb[k]) * b;
	}
}

static void sceneInit(void)
{
	dvlb = DVLB_ParseFile((u32*)map_shbin, map_shbin_size);
	shaderProgramInit(&program);
	shaderProgramSetVsh(&program, &dvlb->DVLE[0]);
	uProj = shaderInstanceGetUniformLocation(program.vertexShader, "projection");
	uModelView = shaderInstanceGetUniformLocation(program.vertexShader, "modelView");
	uTint = shaderInstanceGetUniformLocation(program.vertexShader, "tint");

	AttrInfo_Init(&attrMap);
	AttrInfo_AddLoader(&attrMap, 0, GPU_FLOAT, 3);   // v0 = position
	AttrInfo_AddLoader(&attrMap, 1, GPU_FLOAT, 1);   // v1 = shade
	AttrInfo_Init(&attrBorder);
	AttrInfo_AddLoader(&attrBorder, 0, GPU_FLOAT, 3);
	AttrInfo_AddFixed(&attrBorder, 1);
	BufInfo_Init(&bufBorder);
	BufInfo_Add(&bufBorder, bverts, sizeof(BVertex), 1, 0x0);

	nameBuf = C2D_TextBufNew(4096);
	infoBuf = C2D_TextBufNew(512);
	for (int i = 0; i < hdr.nregions; i++) {
		C2D_TextParse(&names[i], nameBuf, regions[i].name);
		C2D_TextOptimize(&names[i]);
	}
}

static void drawMap(const C3D_Mtx* proj, const C3D_Mtx* view)
{
	C3D_BindProgram(&program);
	C3D_DepthTest(true, GPU_GREATER, GPU_WRITE_ALL);
	C3D_CullFace(GPU_CULL_NONE);
	C3D_TexEnv* env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_PRIMARY_COLOR, 0, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_REPLACE);
	for (int k = 1; k < 6; k++) C3D_TexEnvInit(C3D_GetTexEnv(k));
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uProj, proj);

	C3D_SetAttrInfo(&attrMap);
	C3D_BufInfo buf;
	for (int i = 0; i < hdr.nregions; i++) {
		const Region* g = &regions[i];
		C3D_Mtx mv = *view;
		if (i == selected && lift > 0.001f) Mtx_Scale(&mv, 1, (hdr.land_h + lift) / hdr.land_h, 1);
		C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uModelView, &mv);
		float c[3];
		regionColor(i, c);
		C3D_FVUnifSet(GPU_VERTEX_SHADER, uTint, c[0], c[1], c[2], 1);
		BufInfo_Init(&buf);
		BufInfo_Add(&buf, verts + g->vstart, sizeof(Vertex), 2, 0x10);
		C3D_SetBufInfo(&buf);
		C3D_DrawElements(GPU_TRIANGLES, g->icount, C3D_UNSIGNED_SHORT, indices + g->istart);
	}

	static const float bcol[BORDER_CLASSES][3] = {
		{ 70 / 255.f, 50 / 255.f, 30 / 255.f },    // land / land
		{ 30 / 255.f, 20 / 255.f, 10 / 255.f },    // coast
		{ 150 / 255.f, 185 / 255.f, 215 / 255.f }, // sea / sea
	};
	C3D_SetAttrInfo(&attrBorder);
	C3D_SetBufInfo(&bufBorder);
	C3D_FixedAttribSet(1, 1, 1, 1, 1);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uModelView, view);
	u32 first = 0;
	for (int k = 0; k < BORDER_CLASSES; k++) {
		C3D_FVUnifSet(GPU_VERTEX_SHADER, uTint, bcol[k][0], bcol[k][1], bcol[k][2], 1);
		if (bcount[k]) C3D_DrawArrays(GPU_TRIANGLES, first, bcount[k]);
		first += bcount[k];
	}
}

static void viewMatrix(const Camera* c, C3D_Mtx* view)
{
	Mtx_LookAt(view, c->eye, FVec3_New(c->tx, hdr.land_h, c->tz), FVec3_New(0, 1, 0), false);
}

static void drawLabels(const Camera* c, float w, float h)
{
	for (int i = 0; i < hdr.nregions; i++) {
		const Region* g = &regions[i];
		if (g->kind != KIND_LAND) continue;
		float y = hdr.land_h + (i == selected ? lift : 0), px, py;
		if (!cameraProject(c, g->cx, y, g->cz, w, h, &px, &py)) continue;
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
		printf("Cannot read romfs:/map3d.bin\nRun tools/make_m3.py, then rebuild.\nSTART: exit\n");
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
		if (held & KEY_DLEFT) cam.yaw += 0.03f;
		if (held & KEY_DRIGHT) cam.yaw -= 0.03f;
		if (held & KEY_L) cam.yaw += 0.03f;
		if (held & KEY_R) cam.yaw -= 0.03f;
		if (held & KEY_DUP) cam.dist *= 0.98f;
		if (held & KEY_DDOWN) cam.dist *= 1.02f;
		if (cam.dist < 12) cam.dist = 12;
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
				float k = cam.dist * 0.0035f;
				// the map follows the stylus
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
				lift = 0;
			}
		}
		if (cam.tx < -45) cam.tx = -45;
		if (cam.tx > 45) cam.tx = 45;
		if (cam.tz < -45) cam.tz = -45;
		if (cam.tz > 50) cam.tz = 50;
		cameraUpdate(&cam);

		pulse += 0.12f;
		float want = selected >= 0 && regions[selected].kind == KIND_LAND ? 0.5f : 0;
		lift += (want - lift) * 0.2f;

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
	shaderProgramFree(&program);
	DVLB_Free(dvlb);
	linearFree(verts);
	linearFree(indices);
	linearFree(bverts);
	C2D_Fini();
	C3D_Fini();
	romfsExit();
	gfxExit();
	return 0;
}
