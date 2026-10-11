# LiteLua

A Lua 5.4 fantasy console for Nintendo DS / DSi homebrew, built with BlocksDS.
Games are cartridges (`.lcart` files or folders) loaded from the SD card.

Status: early development — see [docs/PLAN.md](docs/PLAN.md).

## Building

Requires the Wonderful toolchain with BlocksDS installed in `C:\msys64\opt\wonderful`.

```powershell
.\build.ps1          # produces litelua.nds
.\build.ps1 clean
```

## License

zlib — see [LICENSE](LICENSE). Lua is MIT licensed (`vendor/lua/LICENSE`).
