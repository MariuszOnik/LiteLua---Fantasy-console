// HeroesDS 3D political map prototype for the 3DS (tools/make_m3.py): a flat map in 3D.
// The picture (fractal borders, coast, paper, waves) comes as tiles of 1024x1024 --
// only the tiles near the camera are kept, loaded by a worker thread from
// romfs:/tiles/ -- over one texture of the whole map (romfs:/overview.bin) for the rest.
// Its mipmap levels carry less detail further away: county lines only near, province
// lines in the middle distance. Realms' borders are drawn here as strips (they change in
// the game), names by distance: realms far, provinces, counties near. Owners' colours
// are put on while loading. Each region's exact shape (romfs:/map3d.bin) is drawn only
// to light up the selected one. A scenario (romfs:/scenario.lua, read by LiteLua's data
// parser with Lua 5.4 -- the same as on the DS) sets the realms (city-states too), the
// player, owners and names; fog of war shows the player's view -- a small texture over
// the map, so turning it or the view changes nothing in the map's own textures. Bottom screen: the map,
// tap a province to select it, drag to pan, L/R tilt the camera, X fog on/off, Y the
// next realm's view. Top screen: a closer stereo view and the info.
#include <3ds.h>
#include <citro3d.h>
#include <citro2d.h>
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "miniz.h"
#include "lua.h"
#include "lauxlib.h"
#include "ll_data.h"
#include "map_shbin.h"
#include "maptex_shbin.h"
#include "border_shbin.h"

#define CLEAR_COLOR 0x96BEC8FF   // RGBA: the sea of the picture
#define TINT 0.62f               // as in make_m3.py: how strong the owners' colours are
#define SLOTS 6                  // tiles kept at once
#define MAX_LABELS 512           // names placed on one screen
#define COUNTY_ZOOM 24.0f        // nearer than this, taps pick counties (their lines show)
#define MAX_REALMS 32            // as in make_m3.py
#define FOG_TEX 512              // the fog texture's size (over the whole map)

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
	u16 tiles, ncounties;      // tiles per side
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

typedef struct {
	u16 region, pad;
	char name[20];
	float cx, cz;
	u32 vstart, vcount, istart, icount, itop;   // its shape (none: a province's only county)
} County;

typedef struct {
	u16 a, b;                  // the regions on its sides
	u32 start, count;          // its strip's vertices
} Border;

typedef struct { float x, y, z, shade; } Vertex;
typedef struct { float x, y, z, u, v; } TexVertex;

_Static_assert(sizeof(MapHeader) == 32, "header");
_Static_assert(sizeof(Faction) == 20, "faction");
_Static_assert(sizeof(Region) == 80, "region");
_Static_assert(sizeof(County) == 52, "county");
_Static_assert(sizeof(Border) == 12, "border");

enum { SLOT_FREE, SLOT_LOADING, SLOT_READY, SLOT_FAILED };

// one texture of the map: a tile, or the overview (tx = -1)
typedef struct {
	C3D_Tex tex;
	u16* ids;                  // county index per pixel, level 0, texture order
	int tx, ty;
	volatile int state;
	volatile bool stale;       // painted with colours that changed since: load again
	u32 used;                  // frame it was last wanted
} Slot;

// a realm of the scenario: a faction or a city-state
typedef struct {
	char id[32], name[24];
	u8 r, g, b;
	bool city;
} Realm;

static MapHeader hdr;
static Faction factions[8];
static Realm realms[MAX_REALMS];
static int nrealms, player = -1;
static bool fogOn;
static char title[48];
static lua_State* L;         // Lua 5.4 as on the DS: now for the scenario, later the game
static Region* regions;
static int* neighStart;      // region i's neighbours: neigh[neighStart[i] .. neighStart[i + 1]]
static int* neigh;           // region indices
static u8* regionFog;        // per region: 0 never seen, 1 seen before, 2 seen now
static u8* known;            // per region: seen at some time
static C3D_Tex fogTex;       // fog over the whole map, soft edges from filtering
static u16* fogRegion;       // region index per fog texel (texture order)
static County* counties;
static Border* borders;
static u32 nborders;
static u8 (*tint)[3];        // per county: the colour the paper is multiplied by
static Vertex* verts;        // the exact shapes of regions and counties (heap)
static u16* indices;

// a shape being lit up, copied to linear memory for the GPU (all shapes would not fit
// there next to the textures)
typedef struct {
	Vertex* v;
	u16* i;
	u32 itop, icount;
	int vstart;              // which shape it holds (-1: none)
} ShapeBuf;

static ShapeBuf shapeProv, shapeCounty;
static float* lineVerts;     // linear memory: border strips, (x, z, nx, nz) per vertex
static TexVertex* quad;      // linear memory: one unit quad, scaled per tile
static Slot overview, slots[SLOTS];
static u32 texPixels;        // pixels of a texture, all mipmap levels
static u8* fileBuf;          // a tile file
static size_t fileBufSize;
static u16* idsBuf;          // a tile's county indices, all levels
static u16* paperBuf;        // a tile's picture before the colours, all levels
enum { REALM_SPOTS = 64 };
static int realmSize[MAX_REALMS];     // provinces per realm (0: none, no name)
static int realmSpot[MAX_REALMS][REALM_SPOTS];   // provinces to put the name on, best first
static int realmSpots[MAX_REALMS];

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
	int uProj, uModelView, uTint, uWidth;
} Shader;

static Shader overlay, textured, lines;
static C3D_AttrInfo attrOverlay, attrTex, attrLine;
static C3D_BufInfo bufQuad, bufLine;

typedef struct {
	float tx, tz;            // looked-at point on the ground
	float pitch, dist;
	float fovy, aspect;
	C3D_FVec eye, f, r, u;   // derived
} Camera;

static Camera cam;
static int selected = -1, selectedCounty = -1;
static float pulse;
static u32 frame;

static C2D_TextBuf nameBuf, infoBuf;
static C2D_Text* names;      // per region
static C2D_Text* countyNames;
static C2D_Text realmNames[MAX_REALMS];

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

// the colour the paper of a region is multiplied by: its owner's
static void regionTint(int i, u8* rgb)
{
	const Region* g = &regions[i];
	if (g->kind == KIND_SEA) {
		rgb[0] = rgb[1] = rgb[2] = 255;
	} else if (g->kind == KIND_NEUTRAL || g->owner < 0) {
		rgb[0] = 190; rgb[1] = 180; rgb[2] = 160;
	} else {
		const Realm* f = &realms[g->owner];
		rgb[0] = TINT * f->r + (1 - TINT) * 255;
		rgb[1] = TINT * f->g + (1 - TINT) * 255;
		rgb[2] = TINT * f->b + (1 - TINT) * 255;
	}
}

// what the player sees: own provinces and their neighbours (land and sea); what was
// seen once stays known
static void fogUpdate(void)
{
	for (int i = 0; i < hdr.nregions; i++) regionFog[i] = !fogOn || player < 0 ? 2 : 0;
	if (!fogOn || player < 0) return;
	for (int i = 0; i < hdr.nregions; i++) {
		if (regions[i].kind != KIND_LAND || regions[i].owner != player) continue;
		regionFog[i] = 2;
		for (int k = neighStart[i]; k < neighStart[i + 1]; k++) regionFog[neigh[k]] = 2;
	}
	for (int i = 0; i < hdr.nregions; i++) {
		if (regionFog[i] == 2) known[i] = 1;
		else if (known[i]) regionFog[i] = 1;
	}
}

// after owners change: the counties' colours and where the realms' names go -- on the
// realm's provinces nearest its middle (the middle of a realm in pieces can be at sea,
// or in another realm; the next ones when the name is off the screen or would cover
// another realm's)
static void ownersChanged(void)
{
	for (int c = 0; c < hdr.ncounties; c++) regionTint(counties[c].region, tint[c]);
	float mx[MAX_REALMS] = { 0 }, mz[MAX_REALMS] = { 0 };
	memset(realmSize, 0, sizeof realmSize);
	memset(realmSpots, 0, sizeof realmSpots);
	for (int i = 0; i < hdr.nregions; i++) {
		const Region* g = &regions[i];
		if (g->kind != KIND_LAND || g->owner < 0 || g->owner >= nrealms) continue;
		mx[g->owner] += g->cx;
		mz[g->owner] += g->cz;
		realmSize[g->owner]++;
	}
	for (int f = 0; f < nrealms; f++) {
		if (!realmSize[f]) continue;
		mx[f] /= realmSize[f];
		mz[f] /= realmSize[f];
		float best[REALM_SPOTS];
		for (int i = 0; i < hdr.nregions; i++) {
			const Region* g = &regions[i];
			if (g->kind != KIND_LAND || g->owner != f || !regionFog[i]) continue;
			float d = (g->cx - mx[f]) * (g->cx - mx[f]) + (g->cz - mz[f]) * (g->cz - mz[f]);
			int n = realmSpots[f], k = n < REALM_SPOTS ? n++ : REALM_SPOTS;
			if (k == REALM_SPOTS && d >= best[REALM_SPOTS - 1]) continue;
			if (k == REALM_SPOTS) k--;
			for (; k > 0 && best[k - 1] > d; k--) {
				best[k] = best[k - 1];
				realmSpot[f][k] = realmSpot[f][k - 1];
			}
			best[k] = d;
			realmSpot[f][k] = i;
			realmSpots[f] = n;
		}
	}
}

static bool loadMap(void)
{
	size_t size;
	u8* buf = readFile("romfs:/map3d.bin", &size);
	if (!buf) return false;
	u8* p = buf;
	memcpy(&hdr, p, sizeof hdr); p += sizeof hdr;
	if (memcmp(hdr.magic, "HM3D", 4) || hdr.version != 6 || hdr.nregions >= NO_REGION
		|| hdr.ncounties >= NO_REGION || hdr.nfactions > 8 || hdr.tex != 1024 || hdr.tiles < 1) {
		free(buf);
		return false;
	}
	memcpy(factions, p, hdr.nfactions * sizeof(Faction)); p += hdr.nfactions * sizeof(Faction);
	regions = malloc(hdr.nregions * sizeof(Region));
	memcpy(regions, p, hdr.nregions * sizeof(Region)); p += hdr.nregions * sizeof(Region);
	counties = malloc(hdr.ncounties * sizeof(County));
	memcpy(counties, p, hdr.ncounties * sizeof(County)); p += hdr.ncounties * sizeof(County);
	u32 nn = 0;
	for (int i = 0; i < hdr.nregions; i++) nn += regions[i].nneigh;
	// neighbours by the generator's ids -> region indices
	neighStart = malloc((hdr.nregions + 1) * sizeof(int));
	neigh = malloc(nn * sizeof(int) + 4);
	u32 k = 0;
	for (int i = 0; i < hdr.nregions; i++) {
		neighStart[i] = k;
		for (int j = 0; j < regions[i].nneigh; j++) {
			s16 id;
			memcpy(&id, p + 2 * (neighStart[i] + j), 2);
			for (int r = 0; r < hdr.nregions; r++)
				if (regions[r].id == id) { neigh[k++] = r; break; }
		}
	}
	neighStart[hdr.nregions] = k;
	p += (nn * sizeof(s16) + 3) & ~3;
	verts = malloc(hdr.nverts * sizeof(Vertex));
	memcpy(verts, p, hdr.nverts * sizeof(Vertex)); p += hdr.nverts * sizeof(Vertex);
	indices = malloc(hdr.nidx * sizeof(u16));
	memcpy(indices, p, hdr.nidx * sizeof(u16)); p += (hdr.nidx * sizeof(u16) + 3) & ~3;
	u32 nlv;
	memcpy(&nborders, p, 4);
	memcpy(&nlv, p + 4, 4);
	p += 8;
	borders = malloc(nborders * sizeof(Border) + 4);
	memcpy(borders, p, nborders * sizeof(Border)); p += nborders * sizeof(Border);
	lineVerts = linearCopy(p, nlv * 16);
	free(buf);

	tint = malloc(hdr.ncounties * sizeof *tint);
	regionFog = calloc(hdr.nregions, 1);
	known = calloc(hdr.nregions, 1);
	return true;
}

static void getString(int t, const char* key, char* out, size_t size)
{
	lua_getfield(L, t, key);
	const char* v = lua_tostring(L, -1);
	if (v) snprintf(out, size, "%s", v);
	lua_pop(L, 1);
}

static int realmIndex(const char* id)
{
	for (int f = 0; f < nrealms; f++)
		if (!strcmp(realms[f].id, id)) return f;
	return -2;
}

// romfs:/scenario.lua over the map (none: the map's own factions): realms, player, fog,
// owners and names of provinces, names of counties
static bool loadScenario(char* err, size_t errSize)
{
	nrealms = hdr.nfactions;
	for (int f = 0; f < nrealms; f++) {
		snprintf(realms[f].name, sizeof realms[f].name, "%s", factions[f].name);
		snprintf(realms[f].id, sizeof realms[f].id, "%s", factions[f].name);
		realms[f].r = factions[f].r;
		realms[f].g = factions[f].g;
		realms[f].b = factions[f].b;
	}
	player = nrealms > 1 ? 1 : 0;
	size_t size;
	char* text = readFile("romfs:/scenario.lua", &size);
	if (!text) return true;
	static const LLDataLimits limits = { 512 * 1024, 8, 256 };
	bool ok = ll_data_parse(L, text, size, "scenario.lua", &limits, err, errSize);
	free(text);
	if (!ok) return false;
	int t = lua_gettop(L);
	getString(t, "title", title, sizeof title);
	lua_getfield(L, t, "fog");
	fogOn = lua_toboolean(L, -1);
	lua_pop(L, 1);

	lua_getfield(L, t, "realms");
	nrealms = 0;
	for (int i = 1; i <= (int)lua_rawlen(L, -1) && nrealms < MAX_REALMS; i++) {
		lua_rawgeti(L, -1, i);
		int e = lua_gettop(L);
		Realm* f = &realms[nrealms++];
		memset(f, 0, sizeof *f);
		getString(e, "id", f->id, sizeof f->id);
		getString(e, "name", f->name, sizeof f->name);
		lua_getfield(L, e, "color");
		lua_rawgeti(L, -1, 1); f->r = lua_tointeger(L, -1); lua_pop(L, 1);
		lua_rawgeti(L, -1, 2); f->g = lua_tointeger(L, -1); lua_pop(L, 1);
		lua_rawgeti(L, -1, 3); f->b = lua_tointeger(L, -1); lua_pop(L, 1);
		lua_pop(L, 1);
		lua_getfield(L, e, "city");
		f->city = lua_toboolean(L, -1);
		lua_pop(L, 2);
	}
	lua_pop(L, 1);
	char id[32] = "";
	getString(t, "player", id, sizeof id);
	player = realmIndex(id);
	if (player < 0) {
		snprintf(err, errSize, "scenario.lua: player: no realm '%s'", id);
		return false;
	}

	lua_getfield(L, t, "provinces");
	for (int i = 1; i <= (int)lua_rawlen(L, -1); i++) {
		lua_rawgeti(L, -1, i);
		int e = lua_gettop(L);
		lua_getfield(L, e, "id");
		int pid = lua_tointeger(L, -1);
		lua_pop(L, 1);
		Region* g = NULL;
		for (int r = 0; r < hdr.nregions; r++)
			if (regions[r].id == pid) g = &regions[r];
		if (!g) {
			snprintf(err, errSize, "scenario.lua: no province id %d", pid);
			return false;
		}
		getString(e, "name", g->name, sizeof g->name);
		lua_getfield(L, e, "owner");
		const char* own = lua_tostring(L, -1);
		if (own) {
			int f = *own ? realmIndex(own) : -1;
			if (f == -2) {
				snprintf(err, errSize, "scenario.lua: province %d: no realm '%s'", pid, own);
				return false;
			}
			g->owner = f;
		}
		lua_pop(L, 2);
	}
	lua_pop(L, 1);

	lua_getfield(L, t, "counties");
	for (int i = 1; lua_istable(L, -1) && i <= (int)lua_rawlen(L, -1); i++) {
		lua_rawgeti(L, -1, i);
		int e = lua_gettop(L);
		lua_getfield(L, e, "id");
		int c = lua_tointeger(L, -1);
		lua_pop(L, 1);
		if (c >= 0 && c < hdr.ncounties) getString(e, "name", counties[c].name, sizeof counties[c].name);
		lua_pop(L, 1);
	}
	lua_settop(L, 0);
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
// colours of its pixels; the county indices of level 0 kept for taps
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
	if (n < 4 || n == fileBufSize || memcmp(fileBuf, "HT01", 4)
		|| !unpack(&p, end, paperBuf, texPixels * 2) || !unpack(&p, end, idsBuf, texPixels * 2))
		return false;
	u16* out = s->tex.data;
	for (u32 k = 0; k < texPixels; k++) {
		u16 id = idsBuf[k];
		u32 c = paperBuf[k];
		if (id >= hdr.ncounties) {
			out[k] = c;
			continue;
		}
		const u8* t = tint[id];
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
		s->stale = false;    // colours changing from now on mark it again
		u64 t0 = svcGetSystemTick();
		bool ok = loadSlot(s);
		lastLoadMs = (svcGetSystemTick() - t0) / (float)(SYSCLOCK_ARM11 / 1000);
		if (ok) loadedCount++;
		if (s->state == SLOT_LOADING || !ok) s->state = ok ? SLOT_READY : SLOT_FAILED;
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
	fileBufSize = texPixels * 2;        // packed tiles are far smaller
	fileBuf = malloc(fileBufSize);
	idsBuf = malloc(texPixels * 2);
	paperBuf = malloc(texPixels * 2);
	if (!fileBuf || !idsBuf || !paperBuf || !slotInit(&overview)) return false;
	overview.tx = overview.ty = -1;
	if (!loadSlot(&overview)) return false;
	overview.state = SLOT_READY;
	for (int i = 0; i < SLOTS && hdr.tiles > 1; i++)
		if (!slotInit(&slots[i])) return false;
	LightEvent_Init(&wake, RESET_ONESHOT);
	{
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
	free(paperBuf);
}

// the fog texture: which region every texel lies in (from the overview's counties)
static bool fogInit(void)
{
	if (!C3D_TexInit(&fogTex, FOG_TEX, FOG_TEX, GPU_RGBA4)) return false;
	C3D_TexSetFilter(&fogTex, GPU_LINEAR, GPU_LINEAR);
	C3D_TexSetWrap(&fogTex, GPU_CLAMP_TO_EDGE, GPU_CLAMP_TO_EDGE);
	fogRegion = malloc(FOG_TEX * FOG_TEX * sizeof(u16));
	if (!fogRegion) return false;
	u32 step = hdr.tex / FOG_TEX;
	for (u32 y = 0; y < FOG_TEX; y++)
		for (u32 x = 0; x < FOG_TEX; x++) {
			u16 c = overview.ids[texIndex(x * step + step / 2, y * step + step / 2, hdr.tex)];
			fogRegion[texIndex(x, y, FOG_TEX)] = c < hdr.ncounties ? counties[c].region : NO_REGION;
		}
	return true;
}

// the fog as the player sees now: never seen -- dark, seen before -- a grey veil, seen
// now -- clear (a few milliseconds: the map's textures stay as they are)
static void fogPaint(void)
{
	// RGBA4: r g b a, 4 bits each
	static const u16 look[3] = { 0x432D, 0x7777, 0x0000 };
	u16* out = fogTex.data;
	for (u32 k = 0; k < FOG_TEX * FOG_TEX; k++) {
		u16 r = fogRegion[k];
		out[k] = r == NO_REGION ? 0 : look[regionFog[r]];
	}
	C3D_TexFlush(&fogTex);
}

// colours changed (owners): every texture is painted again, the one seen first
static void __attribute__((unused)) repaint(void)
{
	ownersChanged();
	overview.stale = true;
	for (int i = 0; i < SLOTS; i++) slots[i].stale = true;
}

static Slot* slotFor(int tx, int ty)
{
	for (int i = 0; i < SLOTS; i++)
		if (slots[i].tx == tx && slots[i].ty == ty && slots[i].state != SLOT_FREE) return &slots[i];
	return NULL;
}

// the camera looks north (to -z) from the south, tilted down by pitch
static void cameraUpdate(Camera* c)
{
	float cp = cosf(c->pitch), sp = sinf(c->pitch);
	C3D_FVec target = FVec3_New(c->tx, 0, c->tz);
	c->eye = FVec3_New(c->tx, sp * c->dist, c->tz + cp * c->dist);
	c->f = FVec3_Normalize(FVec3_Subtract(target, c->eye));
	c->r = FVec3_New(1, 0, 0);
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

// a point to the screen; depth = its distance along the view
static bool cameraProject(const Camera* c, float x, float z, float w, float h, float* px, float* py, float* depth)
{
	C3D_FVec v = FVec3_Subtract(FVec3_New(x, 0, z), c->eye);
	float d = FVec3_Dot(v, c->f);
	if (d < 0.1f) return false;
	float t = tanf(c->fovy / 2);
	*px = (FVec3_Dot(v, c->r) / (d * t * c->aspect) + 1) * w / 2;
	*py = (1 - FVec3_Dot(v, c->u) / (d * t)) * h / 2;
	*depth = d;
	return *px > -60 && *px < w + 60 && *py > -20 && *py < h + 20;
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
	if (hdr.tiles < 2) {
		if (!job && overview.stale) {
			job = &overview;
			LightEvent_Signal(&wake);
		}
		return;
	}
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
	// textures painted with old colours: the overview, then the tiles seen (a tile not
	// seen is let go)
	if (overview.stale) {
		job = &overview;
		LightEvent_Signal(&wake);
		return;
	}
	for (int k = 0; k < SLOTS; k++)
		if (slots[k].stale && slots[k].state == SLOT_READY && slots[k].used != frame) slots[k].state = SLOT_FREE;
	for (int i = 0; i < n; i++) {
		Slot* s = slotFor(want[i][0], want[i][1]);
		if (s && s->stale && s->state == SLOT_READY) {
			job = s;
			LightEvent_Signal(&wake);
			return;
		}
	}
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

// the county under a screen pixel: the ray meets the map, the pixel there says which
static int pickCounty(const Camera* c, float px, float py)
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
	if (id >= hdr.ncounties || regions[counties[id].region].kind == KIND_NEUTRAL) return -1;
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
	s->uWidth = shaderInstanceGetUniformLocation(s->program.vertexShader, "width");
}

static void shaderFree(Shader* s)
{
	shaderProgramFree(&s->program);
	DVLB_Free(s->dvlb);
}

static void parseName(C2D_Text* t, const char* s)
{
	C2D_TextParse(t, nameBuf, s);
	C2D_TextOptimize(t);
}

static void sceneInit(void)
{
	shaderInit(&overlay, (u32*)map_shbin, map_shbin_size);
	shaderInit(&textured, (u32*)maptex_shbin, maptex_shbin_size);
	shaderInit(&lines, (u32*)border_shbin, border_shbin_size);

	AttrInfo_Init(&attrOverlay);
	AttrInfo_AddLoader(&attrOverlay, 0, GPU_FLOAT, 3);   // v0 = position
	AttrInfo_AddLoader(&attrOverlay, 1, GPU_FLOAT, 1);   // v1 = shade
	AttrInfo_Init(&attrTex);
	AttrInfo_AddLoader(&attrTex, 0, GPU_FLOAT, 3);       // v0 = position
	AttrInfo_AddLoader(&attrTex, 1, GPU_FLOAT, 2);       // v1 = texcoord
	AttrInfo_Init(&attrLine);
	AttrInfo_AddLoader(&attrLine, 0, GPU_FLOAT, 4);      // v0 = (x, z, nx, nz)
	BufInfo_Init(&bufLine);
	BufInfo_Add(&bufLine, lineVerts, 16, 1, 0x0);

	// a unit quad (0..1 on x and z): picture row 0 (north, -z) is at t = 0
	TexVertex q[6] = {
		{ 0, 0, 0, 0, 0 }, { 1, 0, 0, 1, 0 }, { 1, 0, 1, 1, 1 },
		{ 0, 0, 0, 0, 0 }, { 1, 0, 1, 1, 1 }, { 0, 0, 1, 0, 1 },
	};
	quad = linearCopy(q, sizeof q);
	BufInfo_Init(&bufQuad);
	BufInfo_Add(&bufQuad, quad, sizeof(TexVertex), 2, 0x10);

	u32 chars = 64;
	for (int i = 0; i < hdr.nregions; i++) chars += strlen(regions[i].name) + 1;
	for (int i = 0; i < hdr.ncounties; i++) chars += strlen(counties[i].name) + 1;
	for (int f = 0; f < nrealms; f++) chars += strlen(realms[f].name) + 1;
	nameBuf = C2D_TextBufNew(chars);
	infoBuf = C2D_TextBufNew(512);
	names = calloc(hdr.nregions, sizeof(C2D_Text));
	countyNames = calloc(hdr.ncounties, sizeof(C2D_Text));
	for (int i = 0; i < hdr.nregions; i++) parseName(&names[i], regions[i].name);
	for (int i = 0; i < hdr.ncounties; i++) parseName(&countyNames[i], counties[i].name);
	// realms in capitals; city-states as they are written
	for (int f = 0; f < nrealms; f++) {
		char up[24];
		int k = 0;
		for (; realms[f].name[k] && k < 23; k++)
			up[k] = realms[f].city ? realms[f].name[k] : toupper((unsigned char)realms[f].name[k]);
		up[k] = 0;
		parseName(&realmNames[f], up);
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

static int ownerOf(int region)
{
	const Region* g = &regions[region];
	return g->kind == KIND_LAND ? g->owner : -1;
}

static bool shapeInit(ShapeBuf* b, u32 vmax, u32 imax)
{
	b->v = linearAlloc(vmax * sizeof(Vertex) + 16);
	b->i = linearAlloc(imax * sizeof(u16) + 16);
	b->vstart = -1;
	return b->v && b->i;
}

// a shape into its buffer (between frames: the GPU is not reading it)
static void shapeSet(ShapeBuf* b, u32 vstart, u32 vcount, u32 istart, u32 icount, u32 itop)
{
	if (b->vstart == (int)vstart) return;
	memcpy(b->v, verts + vstart, vcount * sizeof(Vertex));
	memcpy(b->i, indices + istart, icount * sizeof(u16));
	GSPGPU_FlushDataCache(b->v, vcount * sizeof(Vertex));
	GSPGPU_FlushDataCache(b->i, icount * sizeof(u16));
	b->itop = itop;
	b->icount = icount;
	b->vstart = vstart;
}

// a shape: its top lit with alpha `fill`, its outline strip with alpha `edge`
static void drawShape(const ShapeBuf* b, float fill, float edge)
{
	C3D_BufInfo buf;
	BufInfo_Init(&buf);
	BufInfo_Add(&buf, b->v, sizeof(Vertex), 2, 0x10);
	C3D_SetBufInfo(&buf);
	C3D_FVUnifSet(GPU_VERTEX_SHADER, overlay.uTint, 1, 1, 0.9f, fill);
	C3D_DrawElements(GPU_TRIANGLES, b->itop, C3D_UNSIGNED_SHORT, b->i);
	C3D_FVUnifSet(GPU_VERTEX_SHADER, overlay.uTint, 1, 0.95f, 0.6f, edge);
	C3D_DrawElements(GPU_TRIANGLES, b->icount - b->itop, C3D_UNSIGNED_SHORT, b->i + b->itop);
}

static bool shapesInit(void)
{
	u32 vmax = 0, imax = 0, cvmax = 0, cimax = 0;
	for (int i = 0; i < hdr.nregions; i++) {
		if (regions[i].vcount > vmax) vmax = regions[i].vcount;
		if (regions[i].icount > imax) imax = regions[i].icount;
	}
	for (int i = 0; i < hdr.ncounties; i++) {
		if (counties[i].vcount > cvmax) cvmax = counties[i].vcount;
		if (counties[i].icount > cimax) cimax = counties[i].icount;
	}
	return shapeInit(&shapeProv, vmax, imax) && shapeInit(&shapeCounty, cvmax, cimax);
}

static void drawMap(const C3D_Mtx* proj, const C3D_Mtx* view, float zoom)
{
	// the map is flat: no depth test, later layers simply cover earlier ones
	C3D_DepthTest(false, GPU_ALWAYS, GPU_WRITE_COLOR);
	C3D_CullFace(GPU_CULL_NONE);
	for (int k = 1; k < 6; k++) C3D_TexEnvInit(C3D_GetTexEnv(k));
	C3D_AlphaBlend(GPU_BLEND_ADD, GPU_BLEND_ADD, GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA,
		GPU_SRC_ALPHA, GPU_ONE_MINUS_SRC_ALPHA);

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

	// realms' borders: strips about as wide on screen at any zoom
	env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_PRIMARY_COLOR, 0, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_REPLACE);
	C3D_BindProgram(&lines.program);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, lines.uProj, proj);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, lines.uModelView, view);
	C3D_SetAttrInfo(&attrLine);
	C3D_SetBufInfo(&bufLine);
	float w = zoom * 0.0042f;
	if (w < 0.07f) w = 0.07f;
	C3D_FVUnifSet(GPU_VERTEX_SHADER, lines.uWidth, w, 0, 0, 0);
	C3D_FVUnifSet(GPU_VERTEX_SHADER, lines.uTint, 0.42f, 0.08f, 0.06f, 0.85f);
	for (u32 i = 0; i < nborders; i++)
		if (ownerOf(borders[i].a) != ownerOf(borders[i].b) && regionFog[borders[i].a] && regionFog[borders[i].b])
			C3D_DrawArrays(GPU_TRIANGLE_STRIP, borders[i].start, borders[i].count);

	// fog of war: one texture over the whole map
	if (fogOn) {
		C3D_BindProgram(&textured.program);
		C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, textured.uProj, proj);
		C3D_SetAttrInfo(&attrTex);
		C3D_SetBufInfo(&bufQuad);
		env = C3D_GetTexEnv(0);
		C3D_TexEnvInit(env);
		C3D_TexEnvSrc(env, C3D_Both, GPU_TEXTURE0, 0, 0);
		C3D_TexEnvFunc(env, C3D_Both, GPU_REPLACE);
		drawQuad(view, &fogTex, -half, -half, hdr.world);
		env = C3D_GetTexEnv(0);
		C3D_TexEnvInit(env);
		C3D_TexEnvSrc(env, C3D_Both, GPU_PRIMARY_COLOR, 0, 0);
		C3D_TexEnvFunc(env, C3D_Both, GPU_REPLACE);
	}

	if (selected < 0) return;

	// the selected region: a pulsing light over its exact shape and an outline inside it;
	// with a county selected the province is lit less and the county more
	C3D_BindProgram(&overlay.program);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, overlay.uProj, proj);
	C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, overlay.uModelView, view);
	C3D_SetAttrInfo(&attrOverlay);
	bool county = selectedCounty >= 0 && counties[selectedCounty].vcount;
	float s = sinf(pulse);
	drawShape(&shapeProv, county ? 0.08f : 0.18f + 0.1f * s, county ? 0.5f : 0.75f + 0.2f * s);
	if (county) drawShape(&shapeCounty, 0.22f + 0.1f * s, 0.8f + 0.2f * s);
}

static void viewMatrix(const Camera* c, C3D_Mtx* view)
{
	Mtx_LookAt(view, c->eye, FVec3_New(c->tx, 0, c->tz), FVec3_New(0, 1, 0), false);
}

// 0 below a, 1 above b, smooth between
static float ramp(float x, float a, float b)
{
	float t = (x - a) / (b - a);
	if (t <= 0) return 0;
	if (t >= 1) return 1;
	return t * t * (3 - 2 * t);
}

typedef struct { float x0, y0, x1, y1; } Rect;
static Rect placed[MAX_LABELS];
static int nplaced;

// a name at a map point, sized by its distance (as if written on the map), left out
// where it would cover a name already placed
static bool label(const Camera* c, float w, float h, C2D_Text* t, float x, float z,
	float size, float least, float most, u32 rgb, float alpha, bool shadow)
{
	if (alpha < 0.03f || nplaced == MAX_LABELS) return false;
	float px, py, depth;
	if (!cameraProject(c, x, z, w, h, &px, &py, &depth)) return false;
	float s = size / depth;
	if (s < least) return false;
	if (s > most) s = most;
	float tw, th;
	C2D_TextGetDimensions(t, s, s, &tw, &th);
	Rect r = { px - tw / 2 - 2, py - th / 2, px + tw / 2 + 2, py + th / 2 };
	if (shadow && (r.x0 < 0 || r.y0 < 0 || r.x1 > w || r.y1 > h)) return false;   // realms: whole
	for (int i = 0; i < nplaced; i++)
		if (r.x0 < placed[i].x1 && r.x1 > placed[i].x0 && r.y0 < placed[i].y1 && r.y1 > placed[i].y0) return false;
	placed[nplaced++] = r;
	if (shadow) {
		float o = s * 2.5f;
		C2D_DrawText(t, C2D_AlignCenter | C2D_WithColor, px + o, py - th / 2 + o, 0.5f, s, s,
			C2D_Color32(40, 25, 15, alpha * 150));
	}
	u32 col = rgb | (u32)(alpha * 255) << 24;
	C2D_DrawText(t, C2D_AlignCenter | C2D_WithColor, px, py - th / 2, 0.5f, s, s, col);
	return true;
}

// names by zoom: realms far away, provinces in between, counties near; the selected
// province first, then the bigger names
static void drawLabels(const Camera* c, float w, float h)
{
	float zoom = c->dist;
	float aRealm = ramp(zoom, 40, 60), aProv = 1 - ramp(zoom, 75, 100), aCounty = 1 - ramp(zoom, 14, 20);
	nplaced = 0;
	const u32 dark = C2D_Color32(20, 12, 4, 0) & 0xFFFFFF, county = C2D_Color32(70, 50, 30, 0) & 0xFFFFFF;
	const u32 white = C2D_Color32(255, 255, 255, 0) & 0xFFFFFF;
	if (selectedCounty >= 0 && counties[selectedCounty].vcount)
		label(c, w, h, &countyNames[selectedCounty], counties[selectedCounty].cx, counties[selectedCounty].cz,
			8, 0, 0.45f, white, 1, false);
	if (selected >= 0 && regionFog[selected])
		label(c, w, h, &names[selected], regions[selected].cx, regions[selected].cz, 22, 0, 0.62f, white, 1, false);
	// realms: a pastel of their colour over a soft shadow
	// realms (city-states smaller) on their known provinces
	for (int f = 0; f < nrealms; f++) {
		const Realm* fc = &realms[f];
		u32 pastel = C2D_Color32(0.5f * fc->r + 128, 0.5f * fc->g + 128, 0.5f * fc->b + 128, 0) & 0xFFFFFF;
		float size = fc->city ? 34 : 70, most = fc->city ? 0.6f : 1.1f;
		// no room anywhere: once more, smaller
		bool done = false;
		for (int pass = 0; pass < 2 && !done; pass++, size *= 0.65f, most *= 0.65f)
			for (int k = 0; k < realmSpots[f] && !done; k++) {
				const Region* g = &regions[realmSpot[f][k]];
				done = label(c, w, h, &realmNames[f], g->cx, g->cz, size, 0.3f, most, pastel, aRealm * 0.95f, true);
			}
	}
	for (int i = 0; i < hdr.nregions; i++)
		if (i != selected && regions[i].kind == KIND_LAND && regionFog[i])
			label(c, w, h, &names[i], regions[i].cx, regions[i].cz, 22, 0.24f, 0.62f, dark, aProv, false);
	for (int i = 0; i < hdr.ncounties; i++) {
		const County* k = &counties[i];
		if (i != selectedCounty && k->vcount && regions[k->region].kind == KIND_LAND && regionFog[k->region] == 2)
			label(c, w, h, &countyNames[i], k->cx, k->cz, 8, 0.24f, 0.45f, county, aCounty, false);
	}
}

static void drawInfo(void)
{
	char text[256];
	int ready = 0;
	for (int i = 0; i < SLOTS && hdr.tiles > 1; i++) ready += slots[i].state == SLOT_READY;
	char stats[96];
	snprintf(stats, sizeof stats, "%d reg, %d cty | tiles %dx%d: %d kept, %d loads, %.0f ms | free %lu KB",
		hdr.nregions, hdr.ncounties, hdr.tiles, hdr.tiles, ready, loadedCount, lastLoadMs,
		(unsigned long)(linearSpaceFree() / 1024));
	char view[96];
	snprintf(view, sizeof view, "%s | you: %s | fog %s (X), Y: next realm", title,
		player >= 0 ? realms[player].name : "-", fogOn ? "on" : "off");
	if (selected < 0) {
		snprintf(text, sizeof text, "%s\nTap: province (near: county)  L/R: tilt  Up/Down: zoom\n%s", view, stats);
	} else if (!regionFog[selected]) {
		snprintf(text, sizeof text, "Unexplored %s\n%s\n%s", regions[selected].kind == KIND_SEA ? "sea" : "land",
			view, stats);
	} else {
		const Region* g = &regions[selected];
		const char* owner = g->kind == KIND_SEA ? "sea zone" : g->owner >= 0 ? realms[g->owner].name : "-";
		const char* cty = selectedCounty >= 0 && strcmp(counties[selectedCounty].name, g->name)
			? counties[selectedCounty].name : "";
		snprintf(text, sizeof text, "%s%s%s  (%s, %d neighbours)\n%s\n%s", g->name, *cty ? " - " : "", cty,
			owner, g->nneigh, view, stats);
	}
	C2D_TextBufClear(infoBuf);
	C2D_Text t;
	C2D_TextParse(&t, infoBuf, text);
	C2D_TextOptimize(&t);
	C2D_DrawRectSolid(0, 0, 0.5f, 400, 58, C2D_Color32(0, 0, 0, 140));
	C2D_DrawText(&t, C2D_WithColor, 8, 4, 0.5f, 0.52f, 0.52f, C2D_Color32(255, 240, 200, 255));
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
	C2D_Init(4096);

	char err[160] = "";
	L = luaL_newstate();
	bool ok = loadMap() && loadScenario(err, sizeof err);
	if (ok) {
		fogUpdate();
		ownersChanged();
		ok = texturesInit() && shapesInit() && fogInit();
		if (ok) fogPaint();
	}
	if (!ok) {
		consoleInit(GFX_BOTTOM, NULL);
		printf("Cannot read the map from romfs:/\n%s\nRun tools/make_m3.py, then rebuild.\nSTART: exit\n", err);
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

	cam = (Camera){ .tx = 0, .tz = 4, .pitch = C3D_AngleFromDegrees(55), .dist = 60,
		.fovy = C3D_AngleFromDegrees(50), .aspect = C3D_AspectRatioBot };

	bool touching = false, dragged = false;
	touchPosition t0 = { 0 }, tl = { 0 };
	float lim = hdr.world / 2, farPlane = hdr.world * 3;
	const float minPitch = C3D_AngleFromDegrees(25), maxPitch = C3D_AngleFromDegrees(88);

	while (aptMainLoop()) {
		hidScanInput();
		u32 down = hidKeysDown(), held = hidKeysHeld(), up = hidKeysUp();
		if (down & KEY_START) break;
		frame++;

		// camera: pan with the circle pad, tilt with L/R, zoom with up/down
		float step = cam.dist * 0.012f;
		circlePosition cp;
		hidCircleRead(&cp);
		cam.tx += cp.dx / 156.0f * step;
		cam.tz -= cp.dy / 156.0f * step;
		if (held & KEY_L) cam.pitch -= 0.02f;
		if (held & KEY_R) cam.pitch += 0.02f;
		if (cam.pitch < minPitch) cam.pitch = minPitch;
		if (cam.pitch > maxPitch) cam.pitch = maxPitch;
		if (down & KEY_X) {
			fogOn = !fogOn;
			fogUpdate();
			ownersChanged();   // realms' names go on known provinces only
			fogPaint();
		}
		if (down & KEY_Y && nrealms > 0) {
			// the next realm's view: what it has seen starts again
			player = (player + 1) % nrealms;
			memset(known, 0, hdr.nregions);
			fogUpdate();
			ownersChanged();
			fogPaint();
		}
		if (held & KEY_DUP) cam.dist *= 0.98f;
		if (held & KEY_DDOWN) cam.dist *= 1.02f;
		if (cam.dist < 8) cam.dist = 8;
		if (cam.dist > hdr.world * 1.3f) cam.dist = hdr.world * 1.3f;

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
				cam.tx -= (tp.px - tl.px) * k;
				cam.tz -= (tp.py - tl.py) * k / sinf(cam.pitch);
			}
			tl = tp;
		} else if (touching && (up & KEY_TOUCH)) {
			touching = false;
			if (!dragged) {
				// near enough to see counties, a tap picks a county; further, a province
				int c = pickCounty(&cam, t0.px, t0.py);
				int r = c >= 0 ? counties[c].region : -1;
				if (c >= 0 && !(cam.dist < COUNTY_ZOOM && counties[c].vcount)) c = -1;
				if (r == selected && c == selectedCounty) r = c = -1;   // the same again: off
				selected = r;
				selectedCounty = c;
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
		top.pitch = cam.pitch - C3D_AngleFromDegrees(20);
		if (top.pitch < C3D_AngleFromDegrees(20)) top.pitch = C3D_AngleFromDegrees(20);
		top.aspect = C3D_AspectRatioTop;
		if (selectedCounty >= 0) {
			top.tx = counties[selectedCounty].cx;
			top.tz = counties[selectedCounty].cz;
		} else if (selected >= 0) {
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
		if (selected >= 0) {
			const Region* g = &regions[selected];
			shapeSet(&shapeProv, g->vstart, g->vcount, g->istart, g->icount, g->itop);
		}
		if (selectedCounty >= 0 && counties[selectedCounty].vcount) {
			const County* k = &counties[selectedCounty];
			shapeSet(&shapeCounty, k->vstart, k->vcount, k->istart, k->icount, k->itop);
		}

		viewMatrix(&top, &view);
		for (int eye = 0; eye < (iod > 0 ? 2 : 1); eye++) {
			C3D_RenderTarget* tgt = eye ? topR : topL;
			C3D_RenderTargetClear(tgt, C3D_CLEAR_ALL, CLEAR_COLOR, 0);
			C3D_FrameDrawOn(tgt);
			Mtx_PerspStereoTilt(&proj, top.fovy, top.aspect, 0.5f, farPlane, eye ? iod : -iod, top.dist, false);
			drawMap(&proj, &view, top.dist);
			render2D(tgt);
			drawLabels(&top, 400, 240);
			drawInfo();
			C2D_Flush();
		}

		C3D_RenderTargetClear(bot, C3D_CLEAR_ALL, CLEAR_COLOR, 0);
		C3D_FrameDrawOn(bot);
		Mtx_PerspTilt(&proj, cam.fovy, cam.aspect, 0.5f, farPlane, false);
		viewMatrix(&cam, &view);
		drawMap(&proj, &view, cam.dist);
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
	shaderFree(&lines);
	free(verts);
	free(indices);
	linearFree(shapeProv.v);
	linearFree(shapeProv.i);
	linearFree(shapeCounty.v);
	linearFree(shapeCounty.i);
	linearFree(lineVerts);
	linearFree(quad);
	free(names);
	free(countyNames);
	free(borders);
	free(counties);
	free(tint);
	free(neigh);
	free(neighStart);
	free(regionFog);
	free(fogRegion);
	C3D_TexDelete(&fogTex);
	free(known);
	lua_close(L);
	C2D_Fini();
	C3D_Fini();
	romfsExit();
	gfxExit();
	return 0;
}
