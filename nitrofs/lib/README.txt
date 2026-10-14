Built-in Lua libraries (NitroFS, nitro:/lib/). require() looks here last,
after the cart's src/ and lib/ and the shared litelua/lib/ on the SD card.

keyboard.lua - the on-screen keyboard of the system carts (code editor,
launcher). Games may use it too; its functions may still change.
