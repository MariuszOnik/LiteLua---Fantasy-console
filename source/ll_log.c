// SPDX-License-Identifier: Zlib
//
// LiteLua - log file on the SD card (<drive>litelua/log.txt).
//
// Lines are buffered and committed (fflush + fsync) at most once per game
// frame, so a crash loses at most the last frame. Every line starts with the
// time since boot. The file stops growing at LOG_MAX_SIZE.

#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <fat.h>
#include <nds.h>

#include "lauxlib.h"

#include "ll_log.h"

#define LOG_MAX_SIZE (1024 * 1024)

static FILE *log_file;
static size_t log_size;
static bool log_dirty;
static volatile u32 vblank_count;

static void vblank_handler(void)
{
    vblank_count++;
}

static void log_raw(const char *s, size_t len)
{
    if (log_file == NULL)
        return;

    if (log_size + len > LOG_MAX_SIZE)
    {
        static const char msg[] = "--- log size limit reached ---\n";
        fwrite(msg, 1, sizeof(msg) - 1, log_file);
        ll_log_flush();
        fclose(log_file);
        log_file = NULL;
        return;
    }

    fwrite(s, 1, len, log_file);
    log_size += len;
    log_dirty = true;
}

static void log_timestamp(void)
{
    // One VBlank is 16.715 ms
    u32 ms = (u32)(((u64)vblank_count * 16715) / 1000);
    char buf[16];
    int n = snprintf(buf, sizeof(buf), "[%5lu.%03lu] ",
                     (unsigned long)(ms / 1000), (unsigned long)(ms % 1000));
    log_raw(buf, n);
}

void ll_log_init(bool fat_ok)
{
    irqSet(IRQ_VBLANK, vblank_handler);
    irqEnable(IRQ_VBLANK);

    if (!fat_ok)
        return;

    char dir[32], path[48], old[48];
    snprintf(dir, sizeof(dir), "%slitelua", fatGetDefaultDrive());
    snprintf(path, sizeof(path), "%s/log.txt", dir);
    snprintf(old, sizeof(old), "%s/log.old.txt", dir);

    mkdir(dir, 0777); // Fails harmlessly if it exists
    remove(old);
    rename(path, old);

    log_file = fopen(path, "w");
    if (log_file == NULL)
        return;
    setvbuf(log_file, NULL, _IOFBF, 4096);

    ll_log("LiteLua log, built " __DATE__ " " __TIME__);
    ll_log("console: %s, drive: %s", isDSiMode() ? "DSi" : "DS",
           fatGetDefaultDrive());
    ll_log_flush();
}

void ll_log_text(const char *s, size_t len)
{
    while (len > 0 && log_file)
    {
        const char *nl = memchr(s, '\n', len);
        size_t line = nl ? (size_t)(nl - s) + 1 : len;

        log_timestamp();
        log_raw(s, line);
        if (nl == NULL)
            log_raw("\n", 1);

        s += line;
        len -= line;
    }
}

void ll_log(const char *fmt, ...)
{
    if (log_file == NULL)
        return;

    char buf[256];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    if (n < 0)
        return;
    if ((size_t)n >= sizeof(buf))
        n = sizeof(buf) - 1;
    ll_log_text(buf, n);
}

void ll_log_flush(void)
{
    if (log_file == NULL || !log_dirty)
        return;
    fflush(log_file);
    fsync(fileno(log_file));
    log_dirty = false;
}

// Joins the arguments like print() does. Leaves the string on the stack.
static const char *join_args(lua_State *L, size_t *len)
{
    int n = lua_gettop(L);
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (int i = 1; i <= n; i++)
    {
        if (i > 1)
            luaL_addchar(&b, '\t');
        luaL_tolstring(L, i, NULL);
        luaL_addvalue(&b);
    }
    luaL_pushresult(&b);
    return lua_tolstring(L, -1, len);
}

static int l_log(lua_State *L)
{
    size_t len;
    const char *s = join_args(L, &len);
    ll_log_text(s, len);
    return 0;
}

static int l_print(lua_State *L)
{
    size_t len;
    const char *s = join_args(L, &len);
    fwrite(s, 1, len, stdout);
    fputc('\n', stdout);
    ll_log_text(s, len);
    return 0;
}

void ll_log_register(lua_State *L)
{
    lua_register(L, "log", l_log);
    lua_register(L, "print", l_print);
}
