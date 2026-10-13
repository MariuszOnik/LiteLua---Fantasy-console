// SPDX-License-Identifier: Zlib
//
// LiteLua - the chiptune sequencer (P18 S1, D41): plays an LLSong live on the
// DS sound channels.

#ifndef LL_SEQ_H__
#define LL_SEQ_H__

#include "ll_song.h"

// Starts playing 'song' (kept by the caller until ll_seq_stop). loop false:
// once, whatever the song says. volume: 0..1024.
void ll_seq_play(const LLSong *song, bool loop, int volume);

// Stops and frees the channels. Safe to repeat.
void ll_seq_stop(void);

void ll_seq_volume(int volume);

// True when a song played once has reached its end (call ll_seq_stop then).
bool ll_seq_finished(void);

#endif // LL_SEQ_H__
