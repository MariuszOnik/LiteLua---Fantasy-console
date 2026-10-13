-- LiteLua API documentation: sound (sound effects and music).
-- Format: see docs/api/README.md.
return {
  module = "sound",
  title = "Sound",
  summary = "Sound effects from WAV files and music from modules or "
         .. "streamed WAV files. Sound data counts in the cart memory.",
  since = "P7",
  entries = {
    {
      name = "sound", kind = "function",
      sig = "sound(name) -> sound",
      args = { { "name", "string", "file in sfx/, without .wav" } },
      ret = { { "sound", "a sound with fields length (s) and rate (Hz)" } },
      desc = "Loads sfx/<name>.wav into memory, or returns it if it is "
          .. "already loaded. PCM WAV, 8 or 16 bit, mono or stereo (mixed "
          .. "down to mono), 1000 .. 48000 Hz. The memory is freed when the "
          .. "sound is no longer used and when the game ends.",
      example = [[
local jump = sound("jump")  -- sfx/jump.wav]],
    },
    {
      name = "sfx", kind = "function",
      sig = "sfx(snd, [vol], [pan], [pitch])",
      args = {
        { "snd", "sound", "a sound from sound()" },
        { "vol", "number", "volume 0 .. 1, default 1" },
        { "pan", "number", "-1 left .. 1 right, default 0" },
        { "pitch", "number", "speed 1/16 .. 16, default 1 (2 = octave up)" },
      },
      ret = { { "integer", "handle for sfx_stop, or nil if no channel" } },
      desc = "Plays a sound effect. Several can play at once (the DS mixes "
          .. "up to 16 channels together with the music).",
      example = [[
sfx(jump)
sfx(jump, 0.5, -1, 1.5)]],
    },
    {
      name = "sfx_stop", kind = "function",
      sig = "sfx_stop([handle])",
      args = { { "handle", "integer", "from sfx; without it all stop" } },
      desc = "Stops one sound effect, or all of them.",
      example = [[
local h = sfx(engine)
sfx_stop(h)]],
    },
    {
      name = "music", kind = "function",
      sig = "music([name], [loop])",
      args = {
        { "name", "string", "file in music/; nil stops the music" },
        { "loop", "boolean", "default true" },
      },
      desc = "Plays music, one piece at a time. It looks for "
          .. "music/<name>.lsong (a chiptune song, docs/LSONG.md, played live "
          .. "by the DS sound channels: a few KB, almost no CPU), then "
          .. "music/<name>.mas (a module from MOD/XM/S3M/IT, made with "
          .. "mmutil -d -m), then music/<name>.wav, streamed from the SD card "
          .. "(PCM 8 or 16 bit, mono or stereo, at most 32768 Hz; in a .lcart "
          .. "stored uncompressed). A name with an extension picks that file. "
          .. "loop false plays it once. music() stops it.",
      example = [[
music("theme")        -- music/theme.lsong (or .mas, .wav)
music("intro.wav", false)
music()]],
    },
    {
      name = "music_volume", kind = "function",
      sig = "music_volume(v)",
      args = { { "v", "number", "0 .. 1" } },
      desc = "Sets the music volume (also for the next music of the game).",
      example = [[
music_volume(0.5)]],
    },
  },
}
