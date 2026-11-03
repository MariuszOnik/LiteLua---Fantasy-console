# HeroesDS G1 — bitwa bez sprajtów (cart LiteLua)

Wersja Lua testu `HeroesDS/glyphtest/`: pole jak w C4, stosy jako bitmapy 8×8 zapisane
w kodzie (`src/glyphs.lua`) albo litery, czary z linii i kół. Nie potrzebuje danych z gry.

**Na kartę:** skopiuj cały folder `g1` do `litelua/carts/g1` (albo
`python tools/litelua.py pack HeroesDS/carts/g1 g1.lcart`).

**Sterowanie:** dotyk wybiera (ziemia = ruch, wróg = atak), drugie dotknięcie w to samo
miejsce albo A wykonuje, B anuluje (bez wyboru: czekaj). X wygląd, Y lupa, L/R czar,
SELECT auto.

**Dźwięk:** `sfx/*.wav` (efekty chip, 8-bit 16 kHz) i `music/*.lsong` (marsz bitewny d-moll,
dżingle wygranej i przegranej) robi `python HeroesDS/tools/make_g1_sound.py`.

Górny ekran pokazuje koszt dolnego (`sys.stats`: czas rysowania, wielokąty, CPU, pamięć).
Zasady walki są zastępcze, nie `combat/`.
