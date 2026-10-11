# Decyzje projektowe

Każdy wpis: data, decyzja, uzasadnienie. Nowe wpisy na końcu.

## D1 (2026-10-11) — Renderer: libnds videoGL + gl2d zamiast µLibrary
gl2d jest szybszy (mniej słów do GPU na prostokąt, cache bindowania tekstur), dokładniejszy przy
obrotach (skala ×4 w projekcji) i utrzymywany w BlocksDS. Funkcje, których brakuje (kolorowanie
4 rogów, PNG w runtime, fonty, dwa ekrany, mapy), piszemy sami.

## D2 (2026-10-11) — Licencja zlib, bez kodu µLibrary i MicroLua
µLibrary: copyleft + zakaz użytku komercyjnego. MicroLua: GPLv3. Oba niekompatybilne z zlib.
Służą tylko jako wzór. Zależności wyłącznie permisywne.

## D3 (2026-10-11) — Lua 5.4.8 z LUA_32BITS=1
ARM9 nie ma FPU — `double` jest emulowany. 5.4 daje natywne int32, operatory bitowe, `//`,
generacyjny GC, `<close>`, `utf8`. `float` (24-bitowa mantysa) wystarcza do fizyki 2D na
256×192: przy 16 000 px dokładność ~0,002 px. Zalecenia dla gier: licznik czasu jako liczba
klatek (int), stały krok fizyki, przesuwanie układu współrzędnych w bardzo dużych światach.
Baseline P0 (melonDS): 200k iteracji — int z `%` 457 ms, float 499 ms (~150 cykli/iterację).

## D4 (2026-10-11) — Nowe, zwięzłe API (bez zgodności z MicroLua)
Gracze będą pisać skrypty na samym DS (rysik/klawiatura ekranowa) — krótkie nazwy, mało
argumentów, loadery same dopisują katalog i rozszerzenie.

## D5 (2026-10-11) — Domyślny tryb: 30 FPS, 3D na obu ekranach
Jedno API dla obu ekranów, ~33 ms CPU na klatkę gry (Lua jest wolna), jak domyślne 30 FPS w
PICO-8. Koszt: banki VRAM C/D na zrzut obrazu (tekstury: A+B = 256 KB), mapy wielokątami.
Tryb 60 FPS (3D na jednym + 2D na drugim) później jako opcja `display = "single60"`.

## D6 (2026-10-11) — Pliki z karty SD, kartridże `.lcart`
`fatInitDefault()`: `fat:/` (DLDI) lub `sd:/` (DSi). W ROM tylko silnik, wbudowany font i
kartridże systemowe (NitroFS). Kartridż = folder (wersja robocza) albo `.lcart` = ZIP
(store/deflate), czytany bez rozpakowywania. Kartridże są tylko do odczytu, piaskownica
ogranicza dostęp do plików do własnego kartridża i katalogu zapisów.

Struktura kartridża (stała, niekonfigurowalna; wymagane tylko `cart.lua` i `main.lua`):
```
cart.lua  main.lua  icon.png
src/ lib/ gfx/ font/ map/ sfx/ music/ data/
```
Manifest `cart.lua`: `return { id, title, author, version, api=1, display="dual30", entry="main.lua", icon="icon.png" }`.

Karta SD:
```
sd:/litelua/carts/  lib/  saves/<id>/  config.lua
```
`require`: `src/` → `lib/` kartridża → `sd:/litelua/lib/` → wbudowane. Eksport do `.lcart`
kopiuje użyte biblioteki wspólne do `lib/` kartridża (przenośność między konsolami).

## D7 (2026-10-11) — Dźwięk: Maxmod
Moduły MOD/XM/S3M/IT jako `.mas` (konwersja `mmutil` na PC) + strumieniowanie WAV
(PCM/IMA-ADPCM) z SD przez `mmStream`. MP3/OGG — konwersja na PC narzędziem `litelua`.
Odrzucone: libxm7 (surowe XM/MOD bez konwersji, ale bez strumieniowania; wyklucza się z Maxmod).

## D8 (2026-10-11) — Edytory w Lua jako kartridże systemowe
Jedna aplikacja (wybór kartridży, runtime, edytory) jak PICO-8. Jądro w C małe; edytory
pisane w Lua na tym samym API co gry. Jeden wbudowany font 6×8 (ASCII + polskie znaki) w ROM.

## D9 (2026-10-11) — Nazwa: LiteLua
Na GitHubie są 3 małe, niezwiązane projekty o tej nazwie (żaden dla DS). Przed publicznym
wydaniem sprawdzić EUIPO/USPTO. Unikać „DS”/„Nintendo”/„Pico” w nazwie.

## D10 (2026-10-11) — Grafika: wyłącznie PNG
Jeden format w kartridżach i w edytorze na DS (zapis PNG z paletą 16 kolorów domyślnie).
Bez GIF/JPG/BMP. Dekompresja deflate współdzielona z czytnikiem `.lcart` (np. `tinfl` z miniz,
MIT); dekoder PNG piszemy sami.

Mapowanie na tekstury DS (wybór automatyczny):
- PNG z paletą ≤16 kolorów → tekstura 16-kolorowa (4 bpp)
- PNG z paletą ≤256 kolorów → tekstura 256-kolorowa (8 bpp)
- RGB/RGBA → 15 bitów + 1 bit przezroczystości (16 bpp)

Zasady: przezroczystość = indeks 0 palety albo alfa 0 (alfa 1–254 zaokrąglana, półprzezroczystość
sprite'a przez API); kolory zaokrąglane do 15 bitów; boki tekstur dopełniane do potęgi dwójki
(8–1024 px), zalecane arkusze 64/128/256 px; fonty = PNG z siatką znaków w `font/` + opcjonalny
`.lua` z szerokościami. Opcjonalnie później: cache przekonwertowanych tekstur w `saves/`
(poza specyfikacją kartridża).
