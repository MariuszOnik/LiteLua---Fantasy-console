// SPDX-License-Identifier: Zlib
//
// LiteLua - PNG decoder (D10).

#ifndef LL_PNG_H__
#define LL_PNG_H__

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct {
    int w, h;
    bool indexed;         // true: 'pixels' are palette indices, 1 byte each
    int num_colors;       // Palette entries (indexed images)
    uint32_t palette[256]; // 0xAARRGGBB (alpha from tRNS, else 0xff)
    bool has_trns;        // The image has transparency information
    uint8_t *pixels;      // Indexed: w*h bytes; else w*h RGBA (4 bytes each)
} LLPng;

// Decodes a PNG file in memory: all color types and bit depths, not
// interlaced. 16-bit channels keep their high byte; gray and RGB images
// become RGBA. On failure returns false with a message in 'err'.
bool ll_png_decode(const uint8_t *data, size_t size, LLPng *png,
                   char *err, size_t err_size);

void ll_png_free(LLPng *png);

#endif // LL_PNG_H__
