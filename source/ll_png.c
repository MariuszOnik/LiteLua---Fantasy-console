// SPDX-License-Identifier: Zlib
//
// LiteLua - PNG decoder (D10).
//
// Reads the chunks, inflates the joined IDAT data with miniz (tinfl), undoes
// the scanline filters and expands the pixels to bytes: palette indices for
// indexed images, RGBA for everything else. CRCs are not checked.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "miniz.h"

#include "ll_png.h"

#define MAX_SIDE 1024 // Largest DS texture side

static uint32_t be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
         | ((uint32_t)p[2] << 8) | p[3];
}

static int paeth(int a, int b, int c)
{
    int p = a + b - c;
    int pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
    if (pa <= pb && pa <= pc)
        return a;
    return pb <= pc ? b : c;
}

// Undoes the filters in place. 'raw' holds h rows of (1 + row_bytes) bytes.
static bool unfilter(uint8_t *raw, int h, size_t row_bytes, int bpp)
{
    uint8_t *prev = NULL;
    for (int y = 0; y < h; y++)
    {
        uint8_t *row = raw + y * (row_bytes + 1);
        int type = row[0];
        uint8_t *cur = row + 1;

        for (size_t i = 0; i < row_bytes; i++)
        {
            int a = i >= (size_t)bpp ? cur[i - bpp] : 0;
            int b = prev ? prev[i] : 0;
            int c = (prev && i >= (size_t)bpp) ? prev[i - bpp] : 0;
            switch (type)
            {
                case 0: break;
                case 1: cur[i] += a; break;
                case 2: cur[i] += b; break;
                case 3: cur[i] += (a + b) / 2; break;
                case 4: cur[i] += paeth(a, b, c); break;
                default: return false;
            }
        }
        prev = cur;
    }
    return true;
}

// Sample 'index' of a row with 'depth' bits per sample (1, 2, 4, 8; for 16
// the high byte is returned)
static int sample(const uint8_t *row, int index, int depth)
{
    switch (depth)
    {
        case 8:
            return row[index];
        case 16:
            return row[index * 2];
        default:
        {
            int bit = index * depth;
            int shift = 8 - depth - (bit & 7);
            return (row[bit >> 3] >> shift) & ((1 << depth) - 1);
        }
    }
}

bool ll_png_decode(const uint8_t *data, size_t size, LLPng *png,
                   char *err, size_t err_size)
{
    static const uint8_t sig[8] = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };

    memset(png, 0, sizeof(*png));
    if (size < 8 || memcmp(data, sig, 8) != 0)
    {
        snprintf(err, err_size, "not a PNG file");
        return false;
    }

    int depth = 0, ctype = -1, interlace = 0;
    uint8_t trns[256];
    size_t trns_len = 0;
    uint8_t *idat = NULL;
    size_t idat_len = 0;
    bool ok = false;

    // First pass over the chunks: header, palette, transparency, data size
    size_t pos = 8;
    while (pos + 12 <= size)
    {
        uint32_t len = be32(data + pos);
        const uint8_t *type = data + pos + 4;
        const uint8_t *body = data + pos + 8;
        if (len > size - pos - 12)
        {
            snprintf(err, err_size, "PNG is truncated");
            goto done;
        }

        if (memcmp(type, "IHDR", 4) == 0 && len >= 13)
        {
            png->w = (int)be32(body);
            png->h = (int)be32(body + 4);
            depth = body[8];
            ctype = body[9];
            interlace = body[12];
        }
        else if (memcmp(type, "PLTE", 4) == 0)
        {
            png->num_colors = (int)(len / 3 > 256 ? 256 : len / 3);
            for (int i = 0; i < png->num_colors; i++)
            {
                const uint8_t *c = body + i * 3;
                png->palette[i] = 0xff000000u | ((uint32_t)c[0] << 16)
                                | ((uint32_t)c[1] << 8) | c[2];
            }
        }
        else if (memcmp(type, "tRNS", 4) == 0)
        {
            trns_len = len > sizeof(trns) ? sizeof(trns) : len;
            memcpy(trns, body, trns_len);
            png->has_trns = true;
        }
        else if (memcmp(type, "IDAT", 4) == 0)
        {
            uint8_t *p = realloc(idat, idat_len + len);
            if (p == NULL)
            {
                snprintf(err, err_size, "not enough memory for the PNG");
                goto done;
            }
            idat = p;
            memcpy(idat + idat_len, body, len);
            idat_len += len;
        }
        else if (memcmp(type, "IEND", 4) == 0)
        {
            break;
        }
        pos += 12 + len;
    }

    if (png->w <= 0 || png->h <= 0 || ctype < 0)
    {
        snprintf(err, err_size, "PNG has no valid header");
        goto done;
    }
    if (png->w > MAX_SIDE || png->h > MAX_SIDE)
    {
        snprintf(err, err_size, "image is %dx%d, at most %dx%d is allowed",
                 png->w, png->h, MAX_SIDE, MAX_SIDE);
        goto done;
    }
    if (interlace != 0)
    {
        snprintf(err, err_size, "interlaced PNG is not supported, save it "
                 "without interlacing");
        goto done;
    }

    int channels;
    switch (ctype)
    {
        case 0: channels = 1; break; // Gray
        case 2: channels = 3; break; // RGB
        case 3: channels = 1; break; // Indexed
        case 4: channels = 2; break; // Gray + alpha
        case 6: channels = 4; break; // RGBA
        default:
            snprintf(err, err_size, "unknown PNG color type %d", ctype);
            goto done;
    }
    bool depth_ok = ctype == 3 ? (depth == 1 || depth == 2 || depth == 4 || depth == 8)
                  : ctype == 0 ? (depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16)
                  : (depth == 8 || depth == 16);
    if (!depth_ok || (ctype == 3 && png->num_colors == 0))
    {
        snprintf(err, err_size, "unsupported PNG (color type %d, %d bits)",
                 ctype, depth);
        goto done;
    }

    // Inflate and unfilter
    int bits_per_pixel = channels * depth;
    size_t row_bytes = ((size_t)png->w * bits_per_pixel + 7) / 8;
    int bpp = bits_per_pixel >= 8 ? bits_per_pixel / 8 : 1;
    size_t raw_len = (row_bytes + 1) * png->h;
    uint8_t *raw = malloc(raw_len);
    if (raw == NULL)
    {
        snprintf(err, err_size, "not enough memory for the PNG");
        goto done;
    }
    size_t got = tinfl_decompress_mem_to_mem(raw, raw_len, idat, idat_len,
                                             TINFL_FLAG_PARSE_ZLIB_HEADER);
    if (got != raw_len || !unfilter(raw, png->h, row_bytes, bpp))
    {
        free(raw);
        snprintf(err, err_size, "PNG data is damaged");
        goto done;
    }

    // Expand to bytes
    size_t count = (size_t)png->w * png->h;
    png->indexed = ctype == 3;
    png->pixels = malloc(png->indexed ? count : count * 4);
    if (png->pixels == NULL)
    {
        free(raw);
        snprintf(err, err_size, "not enough memory for the PNG");
        goto done;
    }

    if (png->indexed && png->has_trns)
    {
        for (size_t i = 0; i < trns_len && i < (size_t)png->num_colors; i++)
            png->palette[i] = (png->palette[i] & 0xffffff) | ((uint32_t)trns[i] << 24);
    }

    // Transparent color key of gray and RGB images (tRNS), as 8-bit values
    int key_r = -1, key_g = -1, key_b = -1;
    if (png->has_trns && ctype == 0 && trns_len >= 2)
    {
        int v = depth == 16 ? trns[0] : trns[1]; // 16-bit big-endian value
        if (depth < 8)
            v = v * 255 / ((1 << depth) - 1);
        key_r = key_g = key_b = v;
    }
    else if (png->has_trns && ctype == 2 && trns_len >= 6)
    {
        bool wide = depth == 16;
        key_r = wide ? trns[0] : trns[1];
        key_g = wide ? trns[2] : trns[3];
        key_b = wide ? trns[4] : trns[5];
    }

    for (int y = 0; y < png->h; y++)
    {
        const uint8_t *row = raw + y * (row_bytes + 1) + 1;
        for (int x = 0; x < png->w; x++)
        {
            size_t i = (size_t)y * png->w + x;
            if (png->indexed)
            {
                png->pixels[i] = (uint8_t)sample(row, x, depth);
                continue;
            }

            int r, g, b, a = 255;
            int s = x * channels;
            if (ctype == 0 || ctype == 4)
            {
                r = sample(row, s, depth);
                if (depth < 8)
                    r = r * 255 / ((1 << depth) - 1);
                g = b = r;
                if (ctype == 4)
                    a = sample(row, s + 1, depth);
            }
            else
            {
                r = sample(row, s, depth);
                g = sample(row, s + 1, depth);
                b = sample(row, s + 2, depth);
                if (ctype == 6)
                    a = sample(row, s + 3, depth);
            }
            if (r == key_r && g == key_g && b == key_b)
                a = 0;

            uint8_t *out = png->pixels + i * 4;
            out[0] = (uint8_t)r;
            out[1] = (uint8_t)g;
            out[2] = (uint8_t)b;
            out[3] = (uint8_t)a;
        }
    }

    free(raw);
    ok = true;

done:
    free(idat);
    if (!ok)
        ll_png_free(png);
    return ok;
}

void ll_png_free(LLPng *png)
{
    free(png->pixels);
    png->pixels = NULL;
}
