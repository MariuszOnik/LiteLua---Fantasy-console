// SPDX-License-Identifier: Zlib
//
// LiteLua - log file on the SD card (<drive>litelua/log.txt).

#ifndef LL_LOG_H__
#define LL_LOG_H__

#include <stdbool.h>
#include <stddef.h>

#include "lua.h"

// Number of VBlanks since boot (the log timestamps and the frame pacing use
// it). Counting starts in ll_log_init.
unsigned long ll_vblanks(void);

// Opens the log file; the previous one is kept as log.old.txt. Does nothing
// (and all other functions are no-ops) when there is no FAT drive.
void ll_log_init(bool fat_ok);

// Writes one line with a timestamp. A trailing newline is added.
void ll_log(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

// Writes text with a timestamp at the start of every line
void ll_log_text(const char *s, size_t len);

// Commits buffered text to the SD card if anything was written since the
// last call. Called once per game frame and after errors.
void ll_log_flush(void);

// Registers log(...) and replaces print(...) with a version that writes to
// both the console and the log.
void ll_log_register(lua_State *L);

#endif // LL_LOG_H__
