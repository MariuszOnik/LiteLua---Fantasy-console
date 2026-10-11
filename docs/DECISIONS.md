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

## D11 (2026-10-11) — Jądro: pętla, wejście, limit pamięci
- **Pętla:** od razu 30 FPS (D5). Klatka gry = 2 VBlanki: `_update()` + `_draw(TOP)`, potem
  `_draw(BOTTOM)`. Wszystkie callbacki opcjonalne, wołane przez `pcall` z traceback.
- **Ekran w `_draw(screen)`:** liczba `0` = górny, `1` = dolny (dotykowy); stałe `TOP`, `BOTTOM`.
- **Wejście (styl PICO-8):** `btn(n)` trzymany, `btnp(n)` wciśnięty w tej klatce, `btnr(n)`
  puszczony; nazwy `a b x y l r start select up down left right touch`; `touch()` → `x, y`
  albo `nil`. Próbkowanie raz na klatkę gry (30 Hz).
- **Pamięć Lua:** własny `lua_Alloc` liczy bajty (bieżące, szczyt) i ma twardy limit;
  domyślnie 2 MB, jednakowo na DS i DSi (przenośność). Kartridż może prosić o więcej w
  `cart.lua` (P3). Przekroczenie → błąd „not enough memory” na ekranie błędu, nie crash.
- **Błąd:** ekran z komunikatem, śladem stosu i zużyciem pamięci; START restartuje kartridż
  (nowy `lua_State`). `micros()` zostaje jako globalna funkcja do pomiarów.

## D12 (2026-10-11) — Dokumentacja API: dane Lua, aktualizowana w każdym punkcie
Źródło: `docs/api/<moduł>.lua` — każdy plik zwraca tabelę z samymi literałami (format w
`docs/api/README.md`): nazwa, rodzaj, sygnatura, argumenty, wyniki, opis, przykład. Ten sam
plik czyta edytor kodu na DS (P11: podpowiedzi i pomoc z przykładami) i `tools/apidoc.py`
(generuje `docs/API.md`). Opisy po angielsku. Każdy punkt planu, który dodaje lub zmienia API,
aktualizuje te pliki w tym samym commicie.

## D13 (2026-10-11) — Błędy: plik i linia jako dane
Nie usuwamy informacji debugowych z chunków. Błędy składni: plik i linia z prefiksu
komunikatu `plik:linia:`. Błędy wykonania: handler błędów czyta ramki przez
`lua_getstack`/`lua_getinfo` i zwraca strukturę (plik, linia, komunikat, ramki stosu),
wskazując pierwszą ramkę z kodu gracza (pomija funkcje C, np. `error()`). Chunki ładowane z
nazwą względną do kartridża (`src/player.lua`), żeby edytor mógł otworzyć plik. Ekran błędu
w edytorze: „Edytuj” → plik i linia; dotknięcie ramki stosu → tamto miejsce. Edytor może
sprawdzać składnię w tle (`load` bez uruchamiania).

## D14 (2026-10-11) — Każdy kartridż w nowym `lua_State`
Gra, ekran wyboru i edytor działają każdy we własnym, nowym stanie; przy wyjściu `lua_close`
zwalnia całą pamięć Lua. Przełączanie: `sys.run(path)` tylko zapisuje żądanie, C zamyka stan
po powrocie z callbacku i tworzy nowy (manifest, limit pamięci, piaskownica). Zasoby poza Lua
(tekstury, dźwięki) należą do stanu i są zwalniane przy jego zamknięciu. Po `lua_close`
licznik alokatora powinien wynosić 0 (kontrola wycieków w wersji debug).
Edytor → gra: **wariant A** — edytor zapisuje bufory na SD, zamyka swój stan, gra dostaje
całą pamięć; po wyjściu lub błędzie edytor startuje od nowa i wraca do pliku, linii i
kursora. Odrzucony wariant B (dwa stany naraz) — za mało RAM na DS (4 MB).

## D15 (2026-10-11) — `README.md` jako manual, aktualizowany w każdym punkcie
README (po angielsku) to podręcznik użytkownika: jak uruchomić, jak napisać grę, cykl
klatki, wejście, błędy, pamięć, kartridże… Pełna referencja API jest w `docs/API.md`
(generowana, D12). Każdy punkt planu, który zmienia coś widocznego dla gracza/twórcy,
aktualizuje README w tym samym commicie.

## D16 (2026-10-11) — Archiwum buildów z numerem punktu
`build.ps1` po udanym buildzie (bez argumentów make) kopiuje ROM do
`builds/litelua-P<n>.nds`, gdzie `P<n>` to punkt, nad którym trwa praca: pierwszy `[~]`,
a jeśli go nie ma — pierwszy `[ ]` w `docs/PLAN.md`. Buildy wcześniejszych punktów zostają;
kolejne buildy w obrębie punktu nadpisują jego plik. Build kończący punkt robimy przed
oznaczeniem go `[x]` (kolejność z `/punkt`). `builds/` jest poza gitem.

## D17 (2026-10-11) — Testowanie: melonDS na PC, konsola do pomiarów sprzętu
Na co dzień testujemy w melonDS (`D:\Programowanie\melonDS-1.1-windows-x86_64`). melonDS ma
włączone DLDI z opcją „Sync SD to folder” = `D:\Programowanie\sdcard` — ten folder jest kartą
SD konsoli w emulatorze. Na prawdziwej konsoli testujemy, gdy trzeba sprawdzić sprzęt:
wydajność (timing melonDS nie jest cykliczny), zachowanie kart SD/DLDI, dźwięk, dotyk.
`build.ps1` po udanym buildzie kopiuje ROM do `sdcard\litelua.nds` i tworzy strukturę z D6
(`litelua\carts`, `lib`, `saves`); `.\build.ps1 run` dodatkowo uruchamia melonDS z tym ROM-em
(jeśli melonDS już działa — trzeba zresetować ROM). melonDS synchronizuje folder z obrazem
przy starcie ROM-u, więc po nowym buildzie zawsze restart/reset. Ścieżki można nadpisać
zmiennymi `LITELUA_SDCARD` i `LITELUA_MELONDS`.

## D18 (2026-10-11) — Log na karcie SD
`<dysk>litelua/log.txt` (poprzedni jako `log.old.txt`). Zawiera: start sesji (konsola, dysk,
data buildu), start kartridża, błędy z pełnym śladem stosu i pamięcią, panikę, kontrolę
pamięci po `lua_close` (powinno zostać 0 B), wszystko z `print` (konsola + log) i `log`
(tylko log). Każda linia ze znacznikiem czasu od startu (licznik VBlanków). Zapis buforowany,
zatwierdzany (`fflush` + `fsync`) raz na klatkę gry tylko gdy coś dopisano, i od razu po
błędzie — crash traci co najwyżej ostatnią klatkę. Limit 1 MB. melonDS przenosi log do
zsynchronizowanego folderu po zatrzymaniu emulacji.
