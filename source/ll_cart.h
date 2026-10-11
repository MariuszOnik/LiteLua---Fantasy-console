// SPDX-License-Identifier: Zlib
//
// LiteLua - carts: manifest, paths inside a cart and reading cart files.

#ifndef LL_CART_H__
#define LL_CART_H__

#include <stdbool.h>
#include <stddef.h>
#include <stdio.h>

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
} LLCart;

// Base folder "<drive>litelua" (no trailing '/'); empty without a FAT drive.
extern char ll_base[LL_BASE_MAX];

// Sets ll_base and creates the D6 folders. Call once after fatInitDefault.
void ll_cart_init(bool fat_ok);

// Opens cart 'name' from litelua/carts: a folder, or a .lcart file ("game"
// also finds game.lcart when there is no folder "game"), and reads its
// manifest (cart.lua). On failure returns false with a message in 'err'.
// An opened cart must be closed with ll_cart_close.
bool ll_cart_open(LLCart *cart, const char *name, char *err, size_t err_size);

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

// Reads a whole file into a malloc'ed buffer with a terminating 0 (not
// counted in 'size'). Returns NULL if it cannot be read.
char *ll_file_read(const char *abs_path, size_t *size);

// The same for a file of the cart given by a clean relative path.
char *ll_cart_read(const LLCart *cart, const char *rel, size_t *size);

// Opens a cart file (clean relative path, not in the save area) for reading.
FILE *ll_cart_fopen(const LLCart *cart, const char *rel);

#endif // LL_CART_H__
