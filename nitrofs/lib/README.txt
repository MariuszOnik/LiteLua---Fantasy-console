Built-in Lua libraries (NitroFS, nitro:/lib/). require() looks here last,
after the cart's src/ and lib/ and the shared litelua/lib/ on the SD card.

middleclass.lua - classes (middleclass 4.1.1 by Enrique Garcia Cota,
https://github.com/kikito/middleclass), MIT license, unchanged; the license
text is in the file. P10c, D54.

keyboard.lua - the on-screen keyboard of the system carts (code editor,
launcher). Games may use it too; its functions may still change.
