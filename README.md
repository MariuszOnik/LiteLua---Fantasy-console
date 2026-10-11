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

A cartridge is either a folder or a single `.lcart` file (see below); both show up in the
list.

## Making a game on a PC, step by step

Until the editors on the DS are ready, games are written on a PC in any text editor
(VS Code, Notepad++, even Notepad) and tested in the melonDS emulator or on a DS.

**1. Make the cartridge folder.** A game is a folder with two files to start with:

```
mygame/
  cart.lua
  main.lua
```

`cart.lua` — the manifest:

```lua
return {
  id = "mygame",        -- lowercase letters, digits, _ - . (names the save folder)
  title = "My Game",
  author = "me",
  version = "1.0",
  api = 1,
}
```

`main.lua` — the game. A complete one that moves a ball with the buttons:

```lua
local x, y = 128, 96

function _update()
  if btn("left")  then x = x - 2 end
  if btn("right") then x = x + 2 end
  if btn("up")    then y = y - 2 end
  if btn("down")  then y = y + 2 end
end

function _draw(screen)
  if screen == TOP then
    cls(1)
    circfill(x, y, 8, 10)
  else
    cls(0)
    text("Move the ball with the D-pad", 4, 4, 12)
  end
end
```

Save the files as UTF-8 (Polish letters work in strings).

**2. Add more when you need it** (all optional): `src/` for more Lua files loaded with
`require`, `gfx/` for PNG images, `data/` for your own data files. See
[Writing a game](#writing-a-game) below for the API, and [docs/API.md](docs/API.md) for
every function.

**3. Test it in melonDS.** Set up melonDS once as described in
[Testing in melonDS](#testing-in-melonds) (DLDI with "Sync SD to folder"), then:

1. copy the `mygame` folder to `litelua/carts/` in that SD folder,
2. start (or reset) `litelua.nds` in melonDS — melonDS reads the folder only when the ROM
   starts, so **reset after every change**,
3. choose `mygame` in the list.

When something goes wrong, the error screen shows the file and line. Hold **L+R** and
press **X** to see your `print` output, **L+R+Y** for the speed and memory numbers, and
**L+R+B** to go back to the list. Everything is also written to `litelua/log.txt` — in
melonDS it appears in the SD folder after you stop the emulation.

**4. Play it on the DS.** Copy the folder to `litelua/carts/` on the SD card of the DS. Or
pack it into one file first:

```
python tools/litelua.py pack mygame        # -> mygame.lcart
```

and copy `mygame.lcart` to `litelua/carts/` — easier to share.

**Example game.** [examples/carts/starcatch](examples/carts/starcatch) is a small complete
game: catch falling stars on the top screen, score and touch control on the bottom
screen, a module in `src/`, particles that make no garbage, a saved high score. Copy it to
`litelua/carts/` to play it, or use it as a starting point.

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

The manifest may only contain data (no function calls).

#### Packing a cartridge: `.lcart`

A `.lcart` file is the cartridge folder packed into one ZIP file — easier to copy and share.
LiteLua reads it directly, without unpacking. Pack it with the tool from the repository
(Python 3):

```
python tools/litelua.py pack mygame              # -> mygame.lcart
python tools/litelua.py pack mygame out.lcart
```

Any ZIP tool works too if `cart.lua` ends up at the top of the archive (or inside a single
top folder) and the file is renamed to `.lcart`. Copy it to `litelua/carts/`.
`sys.run("mygame")` finds both the folder `mygame` and `mygame.lcart`. `main.lua` is Lua 5.4 code that
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
    cls(1)                  -- clear with palette color 1
    circfill(x, y, 8, 10)   -- the player
  end
end
```

### The frame

The game runs at **30 frames per second** and draws on **both screens**. Every frame:

1. input is read and `_update()` is called,
2. `_draw(TOP)` is called for the top screen,
3. `_draw(BOTTOM)` is called for the bottom (touch) screen.

`TOP` is `0` and `BOTTOM` is `1`. Keep game logic in `_update` and only drawing in `_draw`.

The DS has one 3D engine, so it draws the two screens in turns: a game frame is two
screen refreshes (1/60 s each), one per screen. That gives each `_draw` about **16 ms**;
`_update` runs in the second half, together with `_draw(BOTTOM)`. If a screen takes
longer, the game slows down (to 20 FPS) but nothing flickers — both screens keep their
last picture.

### Drawing

The screen is 256×192 pixels, `0, 0` is the top left corner. Drawing uses the DS 3D
hardware, and the picture is built again in every frame: whatever `_draw` does not draw is
not on the screen, so start with `cls()` and draw everything. Things drawn later cover
things drawn earlier.

Both screens are drawn the same way. The drawing settings (`color`, `alpha`, `camera`,
`clip`, `tint`) are shared, so set them in each `_draw` where you need them; `cls` sets the
background of the screen being drawn.

```lua
cls(1)                          -- clear with a color
rectfill(10, 10, 40, 20, 8)     -- x, y, width, height, color
rect(10, 10, 40, 20, 12)        -- outline
line(0, 0, 255, 191, 4)
circfill(128, 96, 16, 10)       -- center x, y, radius, color
circ(128, 96, 24, 11)
trifill(10, 100, 50, 90, 30, 130, 6)
pset(5, 5, 7)
```

**Colors** are numbers: `0`–`15` are the built-in palette (Sweetie 16 by GrafxKid), any
other value is `0xRRGGBB`. The DS shows 32 levels per channel, so `0xRRGGBB` is rounded.
The color argument can be left out; then the color set with `color(c)` is used (12 by
default).

| | | | | | | | |
|---|---|---|---|---|---|---|---|
| 0 `1a1c2c` | 1 `5d275d` | 2 `b13e53` | 3 `ef7d57` | 4 `ffcd75` | 5 `a7f070` | 6 `38b764` | 7 `257179` |
| 8 `29366f` | 9 `3b5dc9` | 10 `41a6f6` | 11 `73eff7` | 12 `f4f4f4` | 13 `94b0c2` | 14 `566c86` | 15 `333c57` |

- `alpha(0.5)` makes what is drawn next half transparent, `alpha()` goes back to opaque.
- `camera(x, y)` scrolls: everything drawn after it moves by `-x, -y`. `camera(x, y, 2)`
  also zooms in 2× (from 1/16 to 16). `camera()` resets it (draw the HUD after that).
- `clip(x, y, w, h)` draws only inside that screen rectangle; `clip()` resets it.

### Images and sprites

Put PNG files in the cartridge's `gfx/` folder and load them once, e.g. in `_init`:

```lua
hero = image("hero")             -- gfx/hero.png
walk = image("walk", 16, 16)     -- a sheet of 16×16 frames, numbered from 0
door = sub(tiles, 32, 0, 16, 24) -- a part of another image (no copy)

function _draw(screen)
  cls(1)
  spr(hero, x, y)                          -- top left corner at x, y
  spr(walk, x, y, t // 6 % walk.frames)    -- animation
  spr(walk, x, y, 2, "x")                  -- mirrored ("x", "y" or "xy")
  sprx(ship, 128, 96, 0, angle, 2)         -- centered, rotated (degrees), scaled
  sspr(tiles, 0, 0, 8, 8, 10, 10, 32, 32)  -- any part, stretched
  tint(2) spr(hero, x, y) tint()           -- red tint (4 colors: corner gradient)
end
```

`img.w`, `img.h` and `img.frames` give the frame size and the number of frames.

**Which PNG to use.** The DS has 256 KB of video memory for images. LiteLua picks the
format from the PNG:

| PNG | memory per pixel | transparent |
|---|---|---|
| palette, up to 16 colors | ½ byte | palette index 0, or entries with alpha 0 |
| palette, up to 256 colors | 1 byte | the same |
| RGB / RGBA / gray | 2 bytes | pixels with alpha below 128 |

So a 16-color palette PNG is 4× smaller than an RGBA one — use it for pixel art. Sides are
padded to a power of two (a 40×24 image takes as much as 64×32). Images can be at most
1024×1024; interlaced PNGs are not supported. When video memory is full, `image` fails with
an "out of video memory" error. All images are freed when the game ends.

### Text

`text(s, x, y, [col])` draws text with the built-in font. Every character is 6×8 pixels,
so a screen holds 42 columns × 24 rows. `\n` starts a new line, `\t` goes to the next
multiple of 4 columns. Polish letters work (strings are UTF-8); other characters show as a
box. `textw(s)` returns the width and height of a text in pixels.

```lua
text("Score: " .. score, 2, 2, 12)
local w = textw("GAME OVER")
text("GAME OVER", (256 - w) // 2, 92, 2)   -- centered
```

`print` does not draw on the game screens: it writes to the log and to the console
overlay (hold **L+R** and press **X** to see the last lines). Use `text` to show text in
the game.

### Speed

The DS draws at most about 2000 shapes, sprites or characters per frame. Every call costs time in Lua
too: on a DSi about 12 µs per `rectfill` and a bit more per `spr`, so a 30 FPS frame has
room for roughly 1500–2000 of them, less if the game logic is heavy.

### More files: require and data

Split bigger games into modules in `src/`. `require("enemy")` loads `src/enemy.lua`,
`require("ai.path")` loads `src/ai/path.lua`. If it is not there, LiteLua looks in the
cartridge's `lib/`, then in the shared `litelua/lib/` on the card and last among the
libraries built into LiteLua.

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

`sys.run("othergame")` starts the cartridge `litelua/carts/othergame` (a folder or
`othergame.lcart`) and `sys.exit()` goes
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
error screen shows the message with the file and line (`main.lua:12: ...`) and the
memory use on the top screen, and the stack traceback (which functions were called) on
the bottom screen. Press **START** to restart the
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

- `print(...)` — to the log **and** the console overlay (L+R+X),
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

### Statistics overlay

Hold **L+R** and press **Y** to show or hide a small box in the top left corner of the top
screen:

```
FPS 30  CPU 23%        frames per second, part of the 33 ms frame in use
upd 1.2 ms             time of _update
drw 3.4 ms             time of _draw (both screens)
Lua 120/2048 KB        Lua memory in use / limit
RAM 3400 KB free       free memory of the console
VRAM 36/320 KB         video memory used by images
poly 512+40 vtx ...    shapes and vertices, top+bottom screen (at most ~2000 / 6144 each)
```

The overlay stays on for the next games until the console is turned off. A game can read
the same numbers with `sys.stats()`.

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

## System carts: launcher and editors (coming in P10)

*This describes how it will work; today a simple built-in list starts the games.*

The cart browser (launcher) and the editors are carts too, written in Lua. They come
**built into** `litelua.nds`, so they always work and always match the engine version.
You can still change them:

- **Your own version on the SD card wins.** If a folder `litelua/system/<name>/` (for
  example `litelua/system/launcher/`) exists on the card, LiteLua runs it instead of the
  built-in one. If its `api` in `cart.lua` does not match the engine, the built-in one is
  used and the log says why.
- **Make a copy to edit.** In the launcher, choose "Copy system carts to the card": the
  built-in cart is copied to `litelua/system/`, and you can edit it on the DS like any
  game.
- **Safe mode.** Hold **SELECT** while LiteLua starts: only the built-in system carts are
  used. A broken launcher on the card can never lock you out.
- **Back to the original.** Delete the folder from `litelua/system/` and the built-in
  version is used again.

System carts can do a few things games cannot: list all carts, read and write the files of
any cart and create new carts.

### System buttons

| buttons | what they do |
|---|---|
| hold **START** for half a second | pause menu: Resume, Restart, Edit code, Quit (coming in P10) |
| **L+R+B** | leave the game at once, back to the list |
| **L+R+Y** | statistics overlay on/off |
| **L+R+X** | console overlay with the last `print` lines (on the bottom screen) |
| hold **SELECT** at start | safe mode: built-in system carts only (coming in P10) |

Games see these buttons too, so avoid using L+R together with B, X or Y in a game.

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
replacing older copies, and the files test is also packed as `files-zip.lcart`.

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

zlib — see [LICENSE](LICENSE). Lua is MIT licensed (`vendor/lua/LICENSE`), miniz (ZIP and
deflate) is MIT licensed (`vendor/miniz/LICENSE`).
