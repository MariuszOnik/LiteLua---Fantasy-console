# LiteLua

A Lua 5.4 fantasy console for Nintendo DS / DSi homebrew, built with BlocksDS.
Games are cartridges (`.lcart` files or folders) loaded from the SD card.

Status: early development — see [docs/PLAN.md](docs/PLAN.md). This README is the user
manual and describes what works **now**; the full API reference is in
[docs/API.md](docs/API.md).

## Running

Copy `litelua.nds` to your flashcard or DSi SD card (or open it in melonDS).

- If there is a `main.lua` in the current directory of the SD card (usually the root), it is
  run.
- Otherwise a built-in demo starts. It shows the frame rate, input and memory use, and lets
  you test the error screen (SELECT, Y) and the memory limit (L+R).

Cartridges (`.lcart` and folders under `sd:/litelua/carts/`) are coming in a later version.

## Writing a game

A game is Lua 5.4 code that defines up to three callbacks. All of them are optional.

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
game from the beginning (with fresh memory).

You can raise your own errors with `error("message")`.

### Memory

Each game has its own Lua memory with a limit of **2 MB** (the same on DS and DSi, so games
run on both). When the limit is reached, the game stops with `not enough memory`.
`collectgarbage("count")` returns the memory in use in KB. Cartridges will be able to ask
for a bigger limit in their manifest.

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
thousand Lua operations per frame, not hundreds of thousands. Integer `//` and `%` use the
DS hardware divider and are cheap. Keep hot values in `local` variables.

`tests/bench.lua` in the repository is the VM benchmark: copy it to the SD card as
`main.lua` to run it.

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
the `litelua\carts`, `litelua\lib` and `litelua\saves` folders.

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
