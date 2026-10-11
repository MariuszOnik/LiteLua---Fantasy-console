// SPDX-License-Identifier: Zlib
//
// LiteLua - the Lua VM (vendor/lua/lvm.c) built as ARM code and placed in
// ITCM (D19). The ".itcm" part of the file name makes the linker put its code
// in ITCM, ".arm" selects ARM mode (see the .itcm.arm.c rule in the Makefile).
// vendor/lua/lvm.c itself is excluded from the build (Makefile).

#include "lvm.c"
