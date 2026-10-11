# LiteLua

A Lua 5.4 fantasy console for Nintendo DS / DSi homebrew, built with BlocksDS.
Games are cartridges (`.lcart` files or folders) loaded from the SD card.

Status: early development — see [docs/PLAN.md](docs/PLAN.md). This README is the user
manual and describes what works **now**; the full API reference is in
[docs/API.md](docs/API.md).

## Running

Copy `litelua.nds` to your flashcard or DSi SD card (or open it in melonDS). On the first
start LiteLua creates the folder `litelua/` on the card:

```
litelua/carts/        your cartridges, one folder each
litelua/lib/          Lua libraries shared by all cartridges
litelua/saves/<id>/   save files, one folder per cartridge
litelua/log.txt       the log (see below)
```

LiteLua starts with a list of the cartridges in `litelua/carts` (Up/Down, **A** to run).
The first entry is a built-in demo that shows the frame rate, input and memory use and lets
you test the error screen (SELECT, Y) and the memory limit (X). Without an SD card the
demo starts directly. (This simple list will be replaced by a proper cartridge browser.)

To leave a running game and go back to the list, hold **L+R+B** together.

Packed cartridges (`.lcart` files) are coming in a later version; for now a cartridge is a
folder.

## Writing a game

A game is a cartridge: a folder in `litelua/carts/` with at least two files:

```
litelua/carts/mygame/
  cart.lua      the manifest (required)
  main.lua      the code that starts the game (required)
  src/          more of your code, loaded with require
  lib/          libraries used by the game
  gfx/ font/ map/ sfx/ music/ data/   assets (graphics and sound come later)
```

The folder names are fixed, so every cartridge looks the same. The manifest `cart.lua`
returns a table:

```lua
return {
  id = "mygame",          -- a-z 0-9 _ - . ; names the save folder (default: folder name)
  title = "My Game",      -- shown in lists (default: id)
  author = "me",
  version = "1.0",
  api = 1,                -- LiteLua API version the game was written for
  memory = 2048,          -- Lua memory limit in KB (optional, default 2048)
}
```

The manifest may only contain data (no function calls). `main.lua` is Lua 5.4 code that
defines up to three callbacks. All of them are optional.

```lua
local x, y

function _init()            -- once, after main.lua is loaded
  x, y = 128, 96
end

function _update()          -- 30 times per second: game logic
  if btn("left")  then x = x - 2 end
  if btn("right") then x = x + 2 end
  if btnp("a") then print("jump!") end
end

function _draw(screen)      -- once per screen per frame
  if screen == TOP then
    -- draw the game (graphics API comes in a later version)
  end
end
```

### The frame

The game runs at **30 frames per second**. Every frame:

1. input is read,
2. `_update()` is called,
3. `_draw(TOP)` is called for the top screen,
4. `_draw(BOTTOM)` is called for the bottom (touch) screen.

`TOP` is `0` and `BOTTOM` is `1`. Keep game logic in `_update` and only drawing in `_draw`.

### More files: require and data

Split bigger games into modules in `src/`. `require("enemy")` loads `src/enemy.lua`,
`require("ai.path")` loads `src/ai/path.lua`. If it is not there, LiteLua looks in the
cartridge's `lib/` and then in the shared `litelua/lib/` on the card.

```lua
-- src/enemy.lua
local M = {}
function M.new(x, y) return { x = x, y = y } end
return M

-- main.lua
local enemy = require("enemy")
```

Files are always given relative to the cartridge folder, with `/`: `"data/level1.txt"`.
Absolute paths, drive names and `..` are not allowed — a game only sees its own files.
The cartridge's files are **read only**: `io.open`, `io.lines`, `loadfile` and `dofile`
read them.

```lua
for line in io.lines("data/level1.txt") do
  print(line)
end
```

### Saving

Paths starting with `save/` go to the game's own save folder `litelua/saves/<id>/` (the
`id` from the manifest). This is the only place a game can write to; the folder is created
when needed. `os.remove` and `os.rename` work only there.

```lua
local f = io.open("save/score.txt", "w")
f:write(best_score)
f:close()

local f = io.open("save/score.txt")   -- nil if there is no save yet
if f then best_score = tonumber(f:read("a")) f:close() end
```

Not available to games: `os.execute`, `os.exit`, `os.getenv`, `os.tmpname`, `io.popen`,
`io.tmpfile`, loading C libraries and precompiled (binary) Lua chunks. The time functions
`os.time`, `os.clock`, `os.date` and `os.difftime` work.

### Switching cartridges

`sys.run("othergame")` starts the cartridge `litelua/carts/othergame` and `sys.exit()` goes
back to the cartridge list. Both take effect when the current callback returns: the game is
closed and all its memory is freed, then the next one starts fresh.

### Numbers

LiteLua uses 32-bit integers and 32-bit floats (the DS has no floating point unit).
Integers are exact up to about ±2 billion; floats have about 7 significant digits.
Tips: count time in frames (integers), use a fixed physics step, and prefer `//` and integer
math where you can.

### Input

| Function | Result |
|---|---|
| `btn(name)` | `true` while the button is held |
| `btnp(name)` | `true` in the frame the button was pressed |
| `btnr(name)` | `true` in the frame the button was released |
| `touch()` | `x, y` while the bottom screen is touched, otherwise `nil` |

Button names: `a b x y l r start select up down left right touch`.

```lua
local tx, ty = touch()
if tx then
  print("touched at", tx, ty)
end
```

### Errors

When your code fails — a syntax error or an error while running — the game stops and the
error screen shows the message with the file and line (`main.lua:12: ...`), the stack
traceback (which functions were called) and the memory use. Press **START** to restart the
game from the beginning (with fresh memory) or **SELECT** to go back to the cartridge list.
File names are relative to the cartridge (`src/enemy.lua:7: ...`).

You can raise your own errors with `error("message")`.

### Memory

Each game has its own Lua memory with a limit of **2 MB** (the same on DS and DSi, so games
run on both). When the limit is reached, the game stops with `not enough memory`.
`collectgarbage("count")` returns the memory in use in KB. A cartridge can ask for a
different limit with `memory` (in KB) in `cart.lua`. A DS has only 4 MB of RAM in total,
so limits much above the default only help on a DSi (16 MB).

### Debugging and the log file

LiteLua writes a log to `litelua/log.txt` on the SD card; the previous run is kept as
`litelua/log.old.txt`. It contains the start of each game, all errors with the full
stack traceback and memory use, and everything your game sends with:

- `print(...)` — to the screen console **and** the log,
- `log(...)` — only to the log.

Every line starts with the time since start in seconds:

```
[    3.142] run: built-in demo (Lua mem limit 2048 KB)
[   10.861] B pressed in frame 230
```

The log is saved to the card once per frame (only if something was written), so even after
a crash at most the last frame is lost. Saving takes time, so do not log every frame in a
finished game. The file stops growing at 1 MB.

In melonDS the log appears in the synced SD folder after the emulation is stopped (or
melonDS is closed).

### Measuring speed

`micros()` returns microseconds since start (wraps after about 128 s):

```lua
local t = micros()
heavy_work()
print("took " .. (micros() - t) .. " us")
```

Rough costs on a DS (ARM9 at 67 MHz, measured in melonDS): a simple loop iteration with
integer math takes about 4 µs, a Lua function call about 7 µs, a table field read+write
about 5 µs. At 30 FPS a frame has about 33 ms for `_update` and `_draw`, so plan for a few
thousand Lua operations per frame, not hundreds of thousands. Keep hot values in `local`
variables.

The repository has a VM benchmark cartridge in `tests/carts/bench`: copy the folder to
`litelua/carts/` to run it.

## Building from source

Requires the Wonderful toolchain with BlocksDS installed in `C:\msys64\opt\wonderful`.

```powershell
.\build.ps1          # produces litelua.nds and archives builds/litelua-P<n>.nds
.\build.ps1 clean
```

Every build is also copied to `builds/` named after the plan point in progress, so older
builds stay available for comparison.

### Testing in melonDS

In melonDS, enable DLDI and "Sync SD to folder" (Emu settings → DLDI) and point it to a
folder, by default `D:\Programowanie\sdcard` (override with the `LITELUA_SDCARD` environment
variable). After each build `build.ps1` copies the ROM there as `litelua.nds` and creates
the `litelua\carts`, `litelua\lib` and `litelua\saves` folders. The test cartridges from
`tests\carts` (VM benchmark, files and sandbox test) are copied to `litelua\carts`,
replacing older copies.

```powershell
.\build.ps1 run      # build, copy to the SD folder and start melonDS
```

melonDS reads the folder when the ROM starts, so reset the ROM after every build. Final
performance measurements need real hardware — melonDS timing is not cycle accurate.

The API reference is generated from `docs/api/*.lua`:

```powershell
python tools/apidoc.py   # writes docs/API.md
```

## License

zlib — see [LICENSE](LICENSE). Lua is MIT licensed (`vendor/lua/LICENSE`).
