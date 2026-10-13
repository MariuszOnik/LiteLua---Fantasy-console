// SPDX-License-Identifier: Zlib
//
// LiteLua - carts: manifest, paths inside a cart and reading cart files.

#ifndef LL_CART_H__
#define LL_CART_H__

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

#include "lua.h"

#define LL_PATH_MAX 256
#define LL_NAME_MAX 64
#define LL_BASE_MAX 32

#define LL_CART_EXT ".lcart"

// Highest API version this build understands (manifest field 'api')
#define LL_API_VERSION 1

typedef struct {
    char name[LL_NAME_MAX];   // Name in litelua/carts (folder or x.lcart)
    char root[LL_PATH_MAX];   // Absolute path of the folder or .lcart file
    char id[LL_NAME_MAX];     // Manifest 'id' (default: name); names saves/<id>
    char title[LL_NAME_MAX];  // Manifest 'title' (default: id)
    char entry[LL_NAME_MAX];  // Manifest 'entry' (default: main.lua)
    size_t mem_limit;         // Manifest 'memory' in KB, stored in bytes
    void *zip;                // Open archive of a .lcart, NULL for a folder
    bool system;              // System cart "@name" from nitro:/system (D27)
} LLCart;

// Prefix of system cart names: sys.run("@code") runs nitro:/system/code
#define LL_SYSTEM_PREFIX '@'

// Base folder "<drive>litelua" (no trailing '/'); empty without a FAT drive.
extern char ll_base[LL_BASE_MAX];

// Sets ll_base and creates the D6 folders. Call once after fatInitDefault.
void ll_cart_init(bool fat_ok);

// Opens cart 'name' from litelua/carts: a folder, or a .lcart file ("game"
// also finds game.lcart when there is no folder "game"), and reads its
// manifest (cart.lua). On failure returns false with a message in 'err'.
// An opened cart must be closed with ll_cart_close.
bool ll_cart_open(LLCart *cart, const char *name, char *err, size_t err_size);

// Opens cart 'name' like ll_cart_open, but only to reach its files: the
// manifest is not read (an editor must open a cart with a broken cart.lua).
// Fields from the manifest keep their defaults.
bool ll_cart_open_files(LLCart *cart, const char *name, char *err,
                        size_t err_size);

// True if the files of the cart can be changed: a folder on the SD card
// (not a .lcart and not a built-in system cart).
bool ll_cart_writable(const LLCart *cart);

// Fills 'names' with the carts in litelua/carts (folders and .lcart files,
// strdup'ed, sorted). Returns their number.
int ll_cart_list_names(char *names[], int max);

// Pushes the list of folder 'dir' of the cart ("" for the top) as an array
// of { name = "x", dir = true|nil }, sorted, folders first. Returns false
// (nothing pushed) if the folder cannot be read.
bool ll_cart_push_list(lua_State *L, const LLCart *cart, const char *dir);

// Writes a file of a writable cart safely: the data goes to "<file>.new"
// first, which then replaces the file, so a failed write never leaves a
// half-written file. Returns false with a message in 'err'.
bool ll_cart_write(const LLCart *cart, const char *rel, const char *data,
                   size_t len, char *err, size_t err_size);

// Creates a folder in a writable cart (succeeds if it exists).
bool ll_cart_mkdir(const LLCart *cart, const char *rel, char *err,
                   size_t err_size);

// Closes the archive of a .lcart; does nothing for folders. Safe to repeat.
void ll_cart_close(LLCart *cart);

// True if 'name' ends with .lcart
bool ll_cart_is_file_name(const char *name);

// Checks a path used by a cart and turns it into a clean relative path:
// '/' separators, no "." or empty parts. Absolute paths, drives, '\' and
// ".." are rejected (returns false).
bool ll_path_clean(const char *path, char *out, size_t out_size);

// True if a clean relative path is in the save area ("save/...").
bool ll_path_is_save(const char *rel);

// Turns a clean relative path in the save area ("save/x") into the absolute
// file name litelua/saves/<id>/x. Returns false for other paths or if the
// result does not fit.
bool ll_cart_save_path(const LLCart *cart, const char *rel, char *out,
                       size_t out_size);

// Creates litelua/saves/<id> if needed.
void ll_cart_make_save_dir(const LLCart *cart);

// Skips a UTF-8 byte order mark (EF BB BF) at the start of source text.
// Windows editors (Notepad) add it; Lua does not accept it.
static inline const char *ll_skip_bom(const char *s, size_t *len)
{
    if (*len >= 3 && (unsigned char)s[0] == 0xef && (unsigned char)s[1] == 0xbb
        && (unsigned char)s[2] == 0xbf)
    {
        *len -= 3;
        return s + 3;
    }
    return s;
}

// Reads a whole file into a malloc'ed buffer with a terminating 0 (not
// counted in 'size'). Returns NULL if it cannot be read.
char *ll_file_read(const char *abs_path, size_t *size);

// The same for a file of the cart given by a clean relative path.
char *ll_cart_read(const LLCart *cart, const char *rel, size_t *size);

// Opens a cart file (clean relative path, not in the save area) for reading.
FILE *ll_cart_fopen(const LLCart *cart, const char *rel);

// Opens a cart file for streaming from the SD card (P7): a new FILE of its
// own, positioned at the file data, which take 'size' bytes from there. In a
// .lcart the file must be stored uncompressed. Returns NULL with a message in
// 'err' on failure.
FILE *ll_cart_open_stream(const LLCart *cart, const char *rel, long *size,
                          char *err, size_t err_size);

#endif // LL_CART_H__
