// Army test for the 3DS: a formation of 3D soldiers marching (romfs:/soldier.bin from
// make_army.py, knight.bin and polish.bin from make_knight.py). Every soldier is one draw of the
// same mesh; the vertex shader blends two frames of the animation (morph, no skeleton),
// each soldier at its own phase. The ground is a repeating checker moved under the
// formation, so it marches on the spot. Spacing and camera come from the model's size.
// Top screen: the view. Bottom: the numbers. Circle pad: turn and tilt the camera,
// L/R: zoom, D-pad: soldiers +-50 / +-10, X: next model, A: march / stand,
// Y: back faces on / off, START: exit.
#include <3ds.h>
#include <citro3d.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "soldier_shbin.h"

#define MAX_SOLDIERS 2000
#define MAX_MODELS 8
#define COLUMNS 20
#define GROUND_TEX 64          // checker texture size
#define GROUND_TILE 4.0f       // metres per checker texture
#define GROUND_SIZE 240.0f     // metres

#define DISPLAY_TRANSFER_FLAGS \
	(GX_TRANSFER_FLIP_VERT(0) | GX_TRANSFER_OUT_TILED(0) | GX_TRANSFER_RAW_COPY(0) | \
	GX_TRANSFER_IN_FORMAT(GX_TRANSFER_FMT_RGBA8) | GX_TRANSFER_OUT_FORMAT(GX_TRANSFER_FMT_RGB8) | \
	GX_TRANSFER_SCALING(GX_TRANSFER_SCALE_NO))

typedef struct {
	char magic[4];
	u16 verts, tris, frames, texSize;
	float seconds, speed;
} ModelHeader;

typedef struct {
	const char* name;
	ModelHeader hdr;
	float* uvs;                // linear memory
	u16* indices;              // linear memory
	float* frames;             // linear memory: frames * verts * 3
	C3D_Tex tex;
	float spaceX, spaceZ, height;
	int count;                 // soldiers shown
} Model;

static Model models[MAX_MODELS];
static int nmodels;
static C3D_Tex groundTex;
static float* groundPos;       // linear memory: 4 corners (x, y, z)
static float* groundUv;
static float phase[MAX_SOLDIERS];   // each soldier's offset in the animation, 0..1

static DVLB_s* dvlb;
static shaderProgram_s program;
static int uProj, uModelView, uBlend;
static C3D_AttrInfo attr;

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

// index of pixel (column x, row y from the top) in the texture: 8x8 tiles from the
// bottom row up, Morton order inside a tile (as in HeroesDS/3ds and make_army.py)
static u32 texIndex(u32 x, u32 y, u32 size)
{
	u32 yf = size - 1 - y;
	u32 tile = (yf >> 3) * (size >> 3) + (x >> 3);
	u32 xs = x & 7, ys = yf & 7;
	u32 m = (xs & 1) | ((ys & 1) << 1) | ((xs & 2) << 1) | ((ys & 2) << 2) | ((xs & 4) << 2) | ((ys & 4) << 3);
	return tile * 64 + m;
}

// one model file; false (and no model) when it is missing or broken
static bool loadModel(Model* m, const char* path, const char* name, int count)
{
	size_t size;
	u8* buf = readFile(path, &size);
	if (!buf) return false;
	memcpy(&m->hdr, buf, sizeof m->hdr);
	ModelHeader* h = &m->hdr;
	size_t uvSize = h->verts * 8, idxSize = h->tris * 6, idxPad = (idxSize + 3) & ~3u;
	size_t frameSize = (size_t)h->frames * h->verts * 12, texSize = (size_t)h->texSize * h->texSize * 2;
	if (memcmp(h->magic, "LLMS", 4) || sizeof *h + uvSize + idxPad + frameSize + texSize != size) {
		free(buf);
		return false;
	}
	u8* p = buf + sizeof *h;
	m->uvs = linearCopy(p, uvSize);
	p += uvSize;
	m->indices = linearCopy(p, idxSize);
	p += idxPad;
	m->frames = linearCopy(p, frameSize);
	p += frameSize;
	C3D_TexInit(&m->tex, h->texSize, h->texSize, GPU_RGB565);
	C3D_TexUpload(&m->tex, p);
	C3D_TexSetFilter(&m->tex, GPU_LINEAR, GPU_LINEAR);
	free(buf);

	// spacing in the formation from the first frame's size
	float lo[3] = { 1e9, 1e9, 1e9 }, hi[3] = { -1e9, -1e9, -1e9 };
	for (int i = 0; i < h->verts; i++)
		for (int k = 0; k < 3; k++) {
			float v = m->frames[i * 3 + k];
			if (v < lo[k]) lo[k] = v;
			if (v > hi[k]) hi[k] = v;
		}
	m->spaceX = (hi[0] - lo[0]) * 0.8f + 0.3f;
	m->spaceZ = (hi[2] - lo[2]) * 0.9f + 0.4f;
	m->height = hi[1];
	m->name = name;
	m->count = count;
	return true;
}

static void freeModel(Model* m)
{
	C3D_TexDelete(&m->tex);
	linearFree(m->uvs);
	linearFree(m->indices);
	linearFree(m->frames);
}

static void groundInit(void)
{
	u16* px = malloc(GROUND_TEX * GROUND_TEX * 2);
	for (u32 y = 0; y < GROUND_TEX; y++)
		for (u32 x = 0; x < GROUND_TEX; x++) {
			bool dark = ((x / (GROUND_TEX / 2)) ^ (y / (GROUND_TEX / 2))) & 1;
			u32 noise = (x * 7 + y * 13 + (x * y) % 5) % 3;
			u32 r = (dark ? 9 : 11) + noise, g = (dark ? 26 : 31) + noise, b = (dark ? 4 : 6);
			px[texIndex(x, y, GROUND_TEX)] = r << 11 | g << 5 | b;
		}
	C3D_TexInit(&groundTex, GROUND_TEX, GROUND_TEX, GPU_RGB565);
	C3D_TexUpload(&groundTex, px);
	C3D_TexSetFilter(&groundTex, GPU_LINEAR, GPU_LINEAR);
	C3D_TexSetWrap(&groundTex, GPU_REPEAT, GPU_REPEAT);
	free(px);
	float h = GROUND_SIZE / 2, t = GROUND_SIZE / GROUND_TILE;
	float pos[] = { -h, 0, -h, h, 0, -h, -h, 0, h, h, 0, h };
	float uv[] = { 0, 0, t, 0, 0, t, t, t };
	groundPos = linearCopy(pos, sizeof pos);
	groundUv = linearCopy(uv, sizeof uv);
}

// frame a and b of the mesh (or the ground's corners twice) as the shader's inputs
static void setBuffers(const float* a, const float* b, const float* uv)
{
	C3D_BufInfo* buf = C3D_GetBufInfo();
	BufInfo_Init(buf);
	BufInfo_Add(buf, a, 12, 1, 0x0);
	BufInfo_Add(buf, b, 12, 1, 0x1);
	BufInfo_Add(buf, uv, 8, 1, 0x2);
}

static void texEnvTexture(float brightness)
{
	C3D_TexEnv* env = C3D_GetTexEnv(0);
	C3D_TexEnvInit(env);
	C3D_TexEnvSrc(env, C3D_Both, GPU_TEXTURE0, GPU_CONSTANT, 0);
	C3D_TexEnvFunc(env, C3D_Both, GPU_MODULATE);
	u32 c = (u32)(brightness * 127.5f);
	C3D_TexEnvColor(env, 0xFF000000 | c << 16 | c << 8 | c);
	C3D_TexEnvScale(env, C3D_RGB, GPU_TEVSCALE_2);
}

int main(void)
{
	gfxInitDefault();
	consoleInit(GFX_BOTTOM, NULL);
	romfsInit();
	C3D_Init(0x100000);   // one draw per soldier: a big command buffer

	if (loadModel(&models[nmodels], "romfs:/soldier.bin", "fusilier (Imperial Glory)", 200)) nmodels++;
	if (loadModel(&models[nmodels], "romfs:/knight.bin", "Ritterbruder (Medieval II)", 40)) nmodels++;
	if (loadModel(&models[nmodels], "romfs:/polish.bin", "Polish knight (Medieval II)", 40)) nmodels++;
	if (loadModel(&models[nmodels], "romfs:/knight_lo.bin", "Ritterbruder, light (optimize.py)", 120)) nmodels++;
	if (loadModel(&models[nmodels], "romfs:/polish_lo.bin", "Polish knight, light (optimize.py)", 120)) nmodels++;
	if (!nmodels) {
		printf("No model in romfs:/\nRun make_army.py / make_knight.py,\nthen rebuild.\nSTART: exit\n");
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
	groundInit();
	for (int i = 0; i < MAX_SOLDIERS; i++) phase[i] = (rand() % 1000) / 1000.0f * 0.25f;

	C3D_RenderTarget* top = C3D_RenderTargetCreate(240, 400, GPU_RB_RGBA8, GPU_RB_DEPTH24_STENCIL8);
	C3D_RenderTargetSetOutput(top, GFX_TOP, GFX_LEFT, DISPLAY_TRANSFER_FLAGS);

	dvlb = DVLB_ParseFile((u32*)soldier_shbin, soldier_shbin_size);
	shaderProgramInit(&program);
	shaderProgramSetVsh(&program, &dvlb->DVLE[0]);
	uProj = shaderInstanceGetUniformLocation(program.vertexShader, "projection");
	uModelView = shaderInstanceGetUniformLocation(program.vertexShader, "modelView");
	uBlend = shaderInstanceGetUniformLocation(program.vertexShader, "blend");
	AttrInfo_Init(&attr);
	AttrInfo_AddLoader(&attr, 0, GPU_FLOAT, 3);
	AttrInfo_AddLoader(&attr, 1, GPU_FLOAT, 3);
	AttrInfo_AddLoader(&attr, 2, GPU_FLOAT, 2);

	int cur = nmodels - 1;     // the newest model first
	bool marching = true, cull = true;
	float yaw = 0.5f, pitch = 0.2f, zoom = 1, walked = 0, animTime = 0;
	u64 last = osGetTime();
	float fps = 0, cpuMs = 0, gpuMs = 0;
	int fpsFrames = 0;
	u64 fpsStart = last;

	while (aptMainLoop()) {
		hidScanInput();
		u32 down = hidKeysDown(), held = hidKeysHeld();
		Model* m = &models[cur];
		if (down & KEY_START) break;
		if (down & KEY_X) {
			cur = (cur + 1) % nmodels;
			m = &models[cur];
			consoleClear();
		}
		if (down & KEY_DUP) m->count += 50;
		if (down & KEY_DDOWN) m->count -= 50;
		if (down & KEY_DRIGHT) m->count += 10;
		if (down & KEY_DLEFT) m->count -= 10;
		if (m->count < 1) m->count = 1;
		if (m->count > MAX_SOLDIERS) m->count = MAX_SOLDIERS;
		if (down & KEY_A) marching = !marching;
		if (down & KEY_Y) cull = !cull;
		circlePosition cp;
		hidCircleRead(&cp);
		if (abs(cp.dx) > 15) yaw += cp.dx / 156.0f * 0.04f;
		if (abs(cp.dy) > 15) pitch += cp.dy / 156.0f * 0.03f;
		if (pitch < 0.08f) pitch = 0.08f;
		if (pitch > 1.5f) pitch = 1.5f;
		if (held & KEY_L) zoom *= 1.03f;
		if (held & KEY_R) zoom /= 1.03f;
		if (zoom < 0.2f) zoom = 0.2f;
		if (zoom > 15) zoom = 15;

		const ModelHeader* h = &m->hdr;
		u64 now = osGetTime();
		float dt = (now - last) / 1000.0f;
		last = now;
		if (dt > 0.1f) dt = 0.1f;
		if (marching) {
			animTime += dt;
			walked += dt * h->speed;
		}
		if (++fpsFrames == 30) {
			fps = fpsFrames * 1000.0f / (now - fpsStart);
			fpsStart = now;
			fpsFrames = 0;
		}

		int rows = (m->count + COLUMNS - 1) / COLUMNS;
		float dist = m->height * 4.5f * zoom;
		C3D_FVec target = FVec3_New(0, m->height * 0.5f, -(rows - 1) * m->spaceZ / 4);
		C3D_FVec eye = FVec3_New(target.x + dist * cosf(pitch) * sinf(yaw), target.y + dist * sinf(pitch),
			target.z + dist * cosf(pitch) * cosf(yaw));
		C3D_Mtx proj, view, model, mv;
		Mtx_PerspTilt(&proj, C3D_AngleFromDegrees(45), C3D_AspectRatioTop, 0.2f, 400, false);
		Mtx_LookAt(&view, eye, target, FVec3_New(0, 1, 0), false);

		C3D_FrameBegin(C3D_FRAME_SYNCDRAW);
		C3D_RenderTargetClear(top, C3D_CLEAR_ALL, 0x9CC4E8FF, 0);
		C3D_FrameDrawOn(top);
		C3D_BindProgram(&program);
		C3D_SetAttrInfo(&attr);
		C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uProj, &proj);
		C3D_DepthTest(true, GPU_GREATER, GPU_WRITE_ALL);

		// ground: the checker slides back as the formation walks forward (+Z)
		C3D_CullFace(GPU_CULL_NONE);
		texEnvTexture(1.0f);
		C3D_TexBind(0, &groundTex);
		Mtx_Identity(&model);
		Mtx_Translate(&model, 0, 0, -fmodf(walked, GROUND_TILE), true);
		Mtx_Multiply(&mv, &view, &model);
		C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uModelView, &mv);
		C3D_FVUnifSet(GPU_VERTEX_SHADER, uBlend, 0, 0, 0, 0);
		setBuffers(groundPos, groundPos, groundUv);
		C3D_DrawArrays(GPU_TRIANGLE_STRIP, 0, 4);

		// soldiers
		C3D_CullFace(cull ? GPU_CULL_BACK_CCW : GPU_CULL_NONE);
		texEnvTexture(1.25f);
		C3D_TexBind(0, &m->tex);
		float cycle = animTime / h->seconds;
		for (int i = 0; i < m->count; i++) {
			int c = i % COLUMNS, r = i / COLUMNS;
			float f = fmodf(cycle + phase[i], 1.0f) * h->frames;
			int fa = (int)f, fb = (fa + 1) % h->frames;
			Mtx_Identity(&model);
			Mtx_Translate(&model, (c - (COLUMNS - 1) / 2.0f) * m->spaceX, 0, -r * m->spaceZ, true);
			Mtx_Multiply(&mv, &view, &model);
			C3D_FVUnifMtx4x4(GPU_VERTEX_SHADER, uModelView, &mv);
			C3D_FVUnifSet(GPU_VERTEX_SHADER, uBlend, f - fa, 0, 0, 0);
			setBuffers(m->frames + (size_t)fa * h->verts * 3, m->frames + (size_t)fb * h->verts * 3, m->uvs);
			C3D_DrawElements(GPU_TRIANGLES, h->tris * 3, C3D_UNSIGNED_SHORT, m->indices);
		}
		C3D_FrameEnd(0);
		cpuMs = C3D_GetProcessingTime();
		gpuMs = C3D_GetDrawingTime();

		printf("\x1b[1;1HArmy 3D test\n%-38s\n\n", m->name);
		printf("soldiers  %5d  (D-pad +-50/+-10)  \n", m->count);
		printf("triangles %7d (%d per soldier) \n", m->count * h->tris + 2, h->tris);
		printf("fps       %5.1f                  \n", fps);
		printf("cpu ms    %5.2f                  \n", cpuMs);
		printf("gpu ms    %5.2f                  \n", gpuMs);
		printf("cmdbuf    %3d%%                  \n", (int)(C3D_GetCmdBufUsage() * 100));
		printf("\nA march: %s   Y back faces: %s  \n", marching ? "on " : "off", cull ? "culled" : "drawn ");
		printf("X: next model (%d of %d)\n", cur + 1, nmodels);
		printf("pad: turn/tilt  L/R: zoom  START: exit\n");
	}

	for (int i = 0; i < nmodels; i++) freeModel(&models[i]);
	C3D_TexDelete(&groundTex);
	linearFree(groundPos);
	linearFree(groundUv);
	shaderProgramFree(&program);
	DVLB_Free(dvlb);
	C3D_Fini();
	romfsExit();
	gfxExit();
	return 0;
}
