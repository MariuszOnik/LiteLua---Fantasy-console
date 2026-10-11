// SPDX-License-Identifier: Zlib
//
// LiteLua - Lua tables (vendor/lua/ltable.c) built as ARM code in ITCM (D19).
// Table lookups are the hottest calls of the VM after its own loop.
// vendor/lua/ltable.c itself is excluded from the build.

#include "ltable.c"
