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
Od P3 punkt i czas buildu (`P3 10-11 16:56`, opcjonalnie słowo z `LITELUA_TAG`) są w
drugiej linii banera ROM-u — menu ładowarek na konsoli pokazują baner, nie nazwę pliku.

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

## D19 (2026-10-11) — Wydajność VM: lvm.c + ltable.c w ARM/ITCM, bez sprzętowego dzielnika
- `lvm.c` i `ltable.c` kompilowane jako kod ARM i umieszczane w ITCM przez pliki-opakowania
  `source/ll_lvm.itcm.arm.c` i `source/ll_ltable.itcm.arm.c` (`#include` pliku z vendor;
  oryginały wyłączone z buildu w `Makefile`). Linker BlocksDS umieszcza w ITCM kod plików
  `*.itcm*`. Osobna reguła `%.itcm.arm.c` bez `-mlong-calls` — ITCM (0x01000000) i RAM
  główny są w zasięgu `BL`; zmierzone: szybciej i mniej miejsca. Reszta Lua zostaje w Thumb.
- ITCM: 24,3 KB z 32 KB (wektory libnds ~1 KB, `lvm` ~19 KB, `ltable` ~4,5 KB). `ldo.c`
  (~6 KB w ARM) się nie zmieścił z zapasem — zostawiamy ~7,7 KB na przyszłe gorące funkcje.
- **Sprzętowy dzielnik DS dla `//` i `%` — sprawdzony i odrzucony.** Na konsoli DSi
  (133 MHz) był wolniejszy od dzielenia programowego (libgcc): czekanie na rejestry dzielnika
  po wolnej szynie kosztuje więcej niż dzielenie małych liczb w kodzie. W melonDS (tryb DS)
  dawał ~7%, ale melonDS nie liczy cykli dokładnie. `lvm.c` wrócił do oryginału.
  Semantyka `//` i `%` (zaokrąglenie w dół, `n//0` błąd, `mininteger//-1`) zostaje
  sprawdzana w benchmarku.
- Benchmark: `tests/bench.lua` (od P3: kartridż `tests/carts/bench`), wyniki na ekranie i w logu.

Pomiar w melonDS 1.1 (tryb DS, bez JIT), N = 200 000, ms — przed (P1) → po (P2):
int `%` 922 → 779, float `*` 981 → 886, int `//` 935 → 784, wywołanie funkcji 1648 → 1460,
pole tabeli 1227 → 1057…1107, tablica 917 → 773, konkatenacja 1475 → 1456, `sqrt` 297 → 286;
razem 8401 → 7479…7530 (−10…11%). melonDS nie liczy cykli dokładnie (brak modelu cache,
tryb ARM vs Thumb), dlatego rozstrzyga pomiar na konsoli.

Pomiar na konsoli (DSi, tryb DSi, karta `sd:/`), ms — przed (P1) → ARM/ITCM + dzielnik →
**ARM/ITCM bez dzielnika (wybrane)**: int `%` 408 → 454 → **340**, int `//` 411 → 461 →
**341**, float `*` 435 → 366 → **366**, wywołanie 710 → 564 → **559**, pole tabeli 585 →
441…465 → **441**, tablica 418 → 310 → **310**, konkatenacja 1202 → 1194 → **1204**, `sqrt`
148 → 141 → **141**; razem 4317 → 3930 → **3702 (−14%)**. Pętle z samą arytmetyką i
tabelami: −16…26%; konkatenacja (alokacje, GC) bez zmian. Trybu DS (67 MHz) na konsoli nie
mierzyliśmy.
Baseline z D3 (457 ms) był mierzony w trybie DSi (ARM9 133 MHz zamiast 67 MHz) — melonDS był
wtedy ustawiony na DSi. Porównujemy tylko pomiary z tego samego trybu (linia `console:` w logu).

## D20 (2026-10-11) — Kartridże z folderów: start, manifest, piaskownica, sys
- **Start (do P10):** tymczasowa lista w C (`source/ll_menu.c`) — foldery z `litelua/carts`
  posortowane + „(built-in demo)” na początku; góra/dół, A. Kursor zapamiętany między
  wywołaniami. Bez karty SD od razu demo. `main.lua` w katalogu głównym karty już nie jest
  uruchamiany. Wyjście z gry: L+R+B trzymane razem (do menu pauzy w P10; pierwotnie L+R+START+SELECT —
  w melonDS klawiatura PC nie przekazywała czterech klawiszy naraz).
  Ekran błędu: START — restart, SELECT — lista.
- **Manifest `cart.lua`:** liczony w osobnym małym stanie Lua (limit 64 KB, puste `_ENV`,
  tylko tekst), więc może zawierać tylko dane. Pola z D6 plus `memory` (KB, 64…65536,
  domyślnie 2048) = limit pamięci Lua. Domyślne: `id` = nazwa folderu (małe litery, znaki
  spoza `a-z 0-9 _ - .` → `_`), `title` = id, `entry` = `main.lua`. `api` > 1 i `display`
  inny niż `dual30` → błąd przy otwarciu.
- **Ścieżki:** zawsze względne do kartridża, `/`; odrzucane: `/` na początku, `:`, `\`, `..`
  (`.` i podwójne `/` są usuwane). `save/...` → `litelua/saves/<id>/...` (folder tworzony
  przy pierwszym zapisie) — jedyne miejsce do zapisu. Pliki kartridża tylko do odczytu.
- **Zapisy:** tylko przez `io` w `save/` (bez osobnego API; wygodne funkcje mogą dojść jako
  biblioteka Lua).
- **io/os:** `io.open` (własna implementacja na `luaL_Stream`), `io.lines/input/output`
  z nazwą pliku przez nią; bez `io.popen/tmpfile`. `os`: `time/clock/date/difftime`;
  `remove/rename` tylko w `save/`; bez `execute/exit/getenv/tmpname/setlocale`.
- **Kod:** `load` wymusza tryb `"t"` (binarne chunki mogą wywrócić VM), `loadfile`/`dofile`
  czytają z kartridża. `require`: `package.preload` → `src/` → `lib/` kartridża →
  `litelua/lib/` (D6); `a.b` → `a/b.lua`; bez bibliotek C (`loadlib`, `cpath`).
- **Nazwy chunków (D13):** `@main.lua`, `@src/game/util.lua`; wspólne biblioteki
  `@litelua/lib/x.lua` (struktura kartridża nie ma folderu `litelua/`, więc bez kolizji).
- **sys:** `sys.run(name)` (folder w `litelua/carts`; manifest sprawdzany od razu — błąd w
  grze, jeśli zły) i `sys.exit()` (lista). Działają po powrocie z bieżącego callbacku
  (też z głównego chunku i `_init`), zgodnie z D14.
- **Testy:** kartridże testowe w `tests/carts/` (`bench`, `files`); `build.ps1` kopiuje je
  do `litelua/carts` na karcie emulatora (zastępując stare kopie). Testy w melonDS można
  prowadzić automatycznie: uruchomienie z ROM-em, klawisze przez `keybd_event` (domyślne
  mapowanie melonDS: A=`A`, B=`B`, X=`X`, START=Enter, SELECT=spacja, strzałki), zamknięcie
  okna i odczyt logu.

## D21 (2026-10-11) — `.lcart`: czytnik ZIP z miniz, NitroFS, narzędzie `pack`
- **miniz 3.0.2 (MIT)** w `vendor/miniz` bez zmian, zamiast samego `tinfl` z D10: daje też
  czytnik ZIP (katalog centralny, store/deflate), więc nie piszemy własnego. Konfiguracja w
  `Makefile`: `MINIZ_NO_STDIO` (odczyt przez własny callback na `FILE*` — bez ścieżki stdio
  miniz i jej ostrzeżeń), `MINIZ_NO_TIME`, `MINIZ_NO_ZLIB_COMPATIBLE_NAMES`,
  `MINIZ_NO_ARCHIVE_WRITING_APIS`. Kompresja deflate (`tdefl`) zostaje dostępna — przyda się
  do zapisu PNG w edytorze grafiki; inflate dla dekodera PNG (P4) też z miniz.
- **Kartridż `.lcart`:** archiwum otwarte przez cały czas działania kartridża (`FILE*` +
  katalog centralny w RAM C, nie liczony do limitu Lua). Pliki rozpakowywane w całości do
  pamięci przy odczycie (`ll_cart_read`); `io.open` na pliku kartridża dostaje `FILE*` z
  `fopencookie` nad tym buforem (zwalnianym przy `fclose`) — działa `read`, `lines`, `seek`.
  Duże pliki (muzyka) będą w P7 strumieniowane inaczej.
- Nazwy w ZIP porównywane bez rozróżniania wielkości liter (jak FAT dla folderów). Jeśli
  `cart.lua` nie leży na górze, a w jednym folderze (spakowany cały folder) — ten folder jest
  prefiksem. `sys.run("x")` i lista: folder `x` albo plik `x.lcart` (folder ma pierwszeństwo).
  Domyślne `id` z nazwy bez `.lcart`.
- **Własność otwartego kartridża:** `ll_cart_open`/`ll_cart_close`; `sys.run` otwiera
  następny kartridż od razu (błąd widoczny w grze), `main` przejmuje go
  (`ll_sys_take_next_cart`); niewykorzystany (błąd po `sys.run`, L+R+B) jest zamykany.
- **NitroFS:** `nitroFSInit(NULL)` przy starcie (wynik w logu), zawartość z `nitrofs/` w
  repo. `require` szuka na końcu w `nitro:/lib/` (nazwa chunku `@rom/lib/x.lua`). Na razie
  pusto; tu trafią wbudowane biblioteki, font i kartridże systemowe.
- **`tools/litelua.py pack`** (początek narzędzia z P9): folder → `.lcart` przez `zipfile`
  (ścieżki z `/`; PowerShell 5.1 `Compress-Archive` zapisuje `\`, co psuje ZIP). Deflate
  poziom 9, PNG i inne skompresowane formaty jako store, pomija pliki ukryte. `build.ps1`
  pakuje test `files` jako `files-zip.lcart` na karcie emulatora.

## D22 (2026-10-11) — API grafiki: globalne funkcje, kolory, stopnie, własny font
Ustalone z użytkownikiem przed P4:
- **Funkcje rysujące są globalne**, jak w PICO-8 (`cls`, `rect`, `spr`, `text`…) — najkrócej
  do pisania rysikiem na DS (D4). `print` zostaje konsolą/logiem (D18); tekst na ekranie
  rysuje `text`.
- **Kolory:** liczba `0xRRGGBB` (zaokrąglana do 15 bitów DS) **albo** numer `0`–`15` z
  wbudowanej palety 16 kolorów. Wartości 0–15 to zawsze numery palety (prawdziwe kolory
  `0x000000`–`0x00000F` są i tak praktycznie czarne). Paleta: **Sweetie 16** (GrafxKid,
  domyślna w TIC-80): `1a1c2c 5d275d b13e53 ef7d57 ffcd75 a7f070 38b764 257179 29366f
  3b5dc9 41a6f6 73eff7 f4f4f4 94b0c2 566c86 333c57`. Zmiana palety przez grę — później.
  Domyślny kolor rysowania (gdy brak argumentu): `color(c)`, startowo 12 (biały).
- **Prostokąty: `rect(x, y, w, h)`** (lewy górny róg + rozmiar, ujemny rozmiar rozszerza w
  lewo/górę), nie dwa rogi.
- **Kąty obrotu w stopniach** (0–360, zgodnie z ruchem wskazówek zegara na ekranie).
- **Wbudowany font 6×8 rysujemy sami** (ASCII + ąćęłńóśźż ĄĆĘŁŃÓŚŹŻ), w repo jako PNG,
  licencja zlib (D8). Teksty w UTF-8.

## D23 (2026-10-11) — Rysowanie (P4a): własne prymitywy na videoGL, clip przez viewport
- Z gl2d (libnds, zlib) bierzemy tylko inicjalizację (`glScreen2D`) i macierze
  (`glBegin2D`/`glEnd2D`, skala ×4). Prymitywy emitujemy sami (`source/ll_gfx.c`) z własnym
  licznikiem głębokości — gl2d trzyma swój prywatnie, a potrzebujemy też własnych
  wielokątów (koła, w P4b sprite'y z kolorami 4 rogów). Głębokość rośnie z każdym
  prymitywem (później = wyżej), maks. 4095 na klatkę.
- Półprzezroczystość: `POLY_ALPHA` 1–30 z rotującym `POLY_ID` 1–62 (DS nie miesza wielokątów
  o tym samym ID; 63 ma tło), `glFlush(GL_TRANS_MANUALSORT)` — kolejność rysowania zostaje.
  `alpha(0)` nic nie rysuje (alfa 0 to na DS tryb siatki).
- `clip` = zmiana viewportu i projekcji w trakcie klatki (DS przycina wielokąty sprzętowo);
  współrzędne zostają pikselami ekranu. `camera` odejmowana w C przed wysłaniem
  wierzchołków; współrzędne obcinane do ±8191 (wierzchołki 16-bit, skala ×4).
- Linia = zdegenerowany trójkąt (jak gl2d), koniec przedłużony o 1 px od startu (oba końce
  włącznie). Koło = pas trójkątów, 8 + r/2 segmentów (maks. 48); okrąg = tyle samo linii.
  `rect` = 4 paski 1 px wewnątrz prostokąta. `cls(c)` ustawia kolor tła; jeśli w klatce już
  coś narysowano, dodatkowo zakrywa to prostokątem na cały ekran.
- Stan rysowania (kolor, alfa, kamera, clip) trwa między klatkami, zerowany przy starcie
  kartridża. Do P6 rysuje tylko górny ekran (`ll_gfx_begin(TOP)`); wywołania w
  `_draw(BOTTOM)` są ignorowane z jednym wpisem w logu.
- Klatka: `_draw(TOP)` między `ll_gfx_begin/end` — `end` zawsze (też po błędzie), potem
  `glFlush`; obraz widać od następnego VBlanka i zostaje na obie połówki klatki 30 FPS.
- Pomiar `rectfill` z pętlą Lua — melonDS (tryb DS): ~26 µs na wywołanie (500 = 13 ms);
  **konsola DSi: ~11,8 µs** (scena testowa 4,8 ms, 500 = 5,9 ms, 900 = 10,6 ms, 1500 =
  17,8 ms). Ewentualna optymalizacja (pomijanie powtórzonych `glPolyFmt`/`glColor`) — przy P5.
- **Tempo klatki (poprawka po pomiarze na konsoli):** pętla czekała na „następny VBlank” po
  `_draw(TOP)`, więc gdy `_update` + `_draw(TOP)` trwało ponad 16,7 ms, klatka zajmowała
  3 VBlanki (20 FPS) mimo zapasu. Teraz czeka do numerów VBlanka: start klatki + 1 (przed
  `_draw(BOTTOM)`), start + 2 (koniec). Cała klatka może trwać do ~33 ms; dłuższa zajmuje
  3 VBlanki. Licznik VBlanków: `ll_vblanks()` (`ll_log.c`). Konsola DSi po poprawce:
  równe 30 FPS do 2600 × `rectfill` (31 ms); powyżej ~2048 kształtów DS i tak ich nie rysuje
  (limit wielokątów sprzętu). W trybie dual30 (P6) każdy
  ekran ma osobny VBlank — wtedy do przemyślenia na nowo.

## D24 (2026-10-11) — Obrazy i sprite'y (P4b)
- **API** (uzgodnione): `image(name, [fw, fh])` (z `gfx/<name>.png`, D4; nazwa z `.png`
  używana wprost; ten sam obraz z pamięci podręcznej o słabych wartościach), `sub(img, x,
  y, w, h, [fw, fh])` — fragment bez kopiowania (widok na tę samą teksturę, trzyma
  właściciela przy życiu), `spr(img, x, y, [frame], [flip])` (lewy górny róg),
  `sprx(img, x, y, [frame], [angle], [sx], [sy], [flip])` (środek, stopnie zgodnie z
  ruchem wskazówek, skala), `sspr(img, sx, sy, sw, sh, dx, dy, [dw], [dh], [flip])`
  (dowolny fragment, rozciągany; ujemny rozmiar odbija), `tint(c)` / `tint(c1..c4)`
  (stan jak `color`/`alpha`; rogi: lewy górny, prawy górny, prawy dolny, lewy dolny).
  `flip` = `"x"`, `"y"`, `"xy"`. Pola obrazu: `w`, `h` (rozmiar klatki), `frames`.
- **Klatki numerowane od 0** (wygodne z `t // n % frames`), po wierszach. Klatka spoza
  zakresu = błąd Lua (łatwiej znaleźć pomyłkę niż przy zawijaniu).
- **Zoom kamery:** `camera(x, y, [zoom])` (1/16–16) — ekran = (świat − kamera) × zoom, dla
  wszystkiego. Na życzenie użytkownika.
- **Współrzędne w ćwiartkach piksela:** macierz modelview jednostkowa, wierzchołki ×4 w C
  (projekcja jak w gl2d) — `sprx` i zoom dostają pozycje podpikselowe. Wejście z Lua
  obcinane do ±2^20 px (32-bit w C); mnożenie 64-bit tylko przy zoomie ≠ 1.
- **PNG** (`source/ll_png.c`, własny): wszystkie typy i głębie bez przeplotu (interlace →
  błąd z podpowiedzią), inflate z miniz (D21), kanały 16-bit → starszy bajt, `tRNS` dla
  palety i klucza koloru. Konwersja wg D10 (`source/ll_image.c`): paleta ≤16 → 4 bpp,
  ≤256 → 8 bpp (przezroczyste wpisy alfa < 128 przestawiane na indeks 0; bez `tRNS`
  indeks 0 przezroczysty), reszta → RGBA 1555 (alfa < 128 przezroczysta). Boki do potęgi
  dwójki, maks. 1024.
- **VRAM:** banki A+B = tekstury (256 KB), E = palety (64 KB), przydział przez videoGL
  (`glTexImage2D`, `glColorTableEXT`). Własny licznik bajtów (dla P5). Brak miejsca →
  pełne GC i jedna ponowna próba, potem błąd Lua „out of video memory” z rozmiarami.
  Tekstury zwalnia `__gc` obrazu; przy starcie kartridża `glResetTextures()` (bezpiecznik
  po porzuconym stanie, D14).
- **Rysowanie:** quad z teksturą i kolorem wierzchołków (`tint`); jeden `glColor`, gdy tint
  jednolity; cache związanej tekstury (`ll_gfx_texture_changed` po uploadzie). Odbicie:
  współrzędne tekstury od wnętrza ostatniego tekla (DS próbkuje od lewej/górnej krawędzi
  piksela), bez gubienia rzędu. Sprawdzanie typu obrazu przez porównanie wskaźnika
  metatabeli (szybciej niż `luaL_checkudata`).
- **Linie (poprawka do D23):** koniec przedłużany o 1 px tylko wzdłuż dłuższej osi —
  przedłużanie obu osi (jak w gl2d) przechylało linie poziome/pionowe.
- Pomiar melonDS (tryb DS): 300 × `spr` z pętlą Lua = 11,1 ms (~37 µs), 500 × `rectfill` =
  13,8 ms. **Konsola DSi:** `spr` ~17,8 µs (300 = 5,4 ms, 900 = 16,0 ms, równe 30 FPS),
  scena testowa 1,45 ms, start kartridża z testem braku VRAM 0,85 s. Kandydat do
  optymalizacji w P5: `ll_gfx.c` w ITCM.

## D25 (2026-10-11) — Tekst (P4c): wbudowany font 6×8
- **Font własny, stałej szerokości:** każdy znak to pole 6×8 (glif 5 px + odstęp), 42×24
  znaki na ekran — także pod edytor kodu (P11). Wielkie litery i cyfry: wiersze 1–6 (wiersz
  0 na akcenty Ć Ń Ó Ś Ź Ż), małe litery: 2–6, laseczki i ogonki: wiersz 7. Zestaw: ASCII
  32–126, `ąćęłńóśźżĄĆĘŁŃÓŚŹŻ`, prostokąt dla nieznanych znaków (114 glifów).
- **Źródło:** wzory liter w `tools/make_font.py` (licencja zlib); skrypt generuje
  `assets/font6x8.png` (arkusz 16×8 pól, paleta 2 kolory) i `source/ll_font6x8.inc` (ten sam
  PNG jako tablica C). Font jest w kodzie programu, nie w NitroFS — działa nawet, gdy NitroFS
  nie wstanie. PNG dekodowany raz (`ll_png`) i wysyłany do VRAM przy starcie każdego
  kartridża (po `glResetTextures`), 4 KB.
- **API:** `text(s, x, y, [col])` — UTF-8, `\n` nowa linia, `\t` do wielokrotności 4
  kolumn; kolor przez kolor wierzchołków (biały glif × kolor), działa z kamerą/zoomem,
  `clip`, `alpha`; `tint` nie dotyczy tekstu. `textw(s)` → szerokość najdłuższej linii i
  wysokość w pikselach. Cały napis to jedna lista quadów (jedno `glBegin`, ta sama
  głębokość). `print` zostaje konsolą/logiem.
- Fonty z `font/` kartridża (też o zmiennej szerokości) — później (D10 przewiduje PNG z
  siatką + szerokości).
- Pomiar melonDS (tryb DS): 1560 znaków (40 × 39) = 7,4 ms (~4,7 µs/znak); scena testowa
  z wieloma wywołaniami 4 ms. **Konsola DSi:** ~2,7 µs/znak — pełny ekran 24 × 39 = 936
  znaków w 2,5 ms; scena testowa (dużo krótkich wywołań) 3,3 ms.

## D26 (2026-10-11) — Statystyki (P5): `sys.stats()` i nakładka L+R+Y
- **Nakładka:** L+R trzymane + Y wciśnięte przełącza (wybór użytkownika); stan trwa między
  kartridżami do wyłączenia konsoli. Półprzezroczyste okienko w lewym górnym rogu górnego
  ekranu, rysowane po `_draw(TOP)` w przestrzeni ekranu (bez kamery, zoomu, `clip`, alfy
  gry, które potem wracają). Tekst z poprzedniej klatki. Gra też widzi Y w `btnp` (jak B
  przy L+R+B).
- **Pomiary na klatkę** (`source/ll_stats.c`, mierzy `ll_runtime.c` licznikiem
  `cpuGetTiming`): czas `_update`, `_draw(TOP)`, `_draw(BOTTOM)`; CPU % = suma / 33 333 µs;
  FPS z liczby klatek na ~60 VBlanków. Wielokąty i wierzchołki: `glGetInt` (rejestry
  `GFX_POLYGON_RAM_USAGE` / `VERTEX`) tuż przed `glFlush`, przed rysowaniem nakładki — czeka
  na koniec pracy silnika geometrii, raz na klatkę.
- **Pamięć:** Lua z alokatora (bieżąca, szczyt, limit), wolny RAM = wolne bloki `mallinfo`
  + nieużyta część sterty (`getHeapLimit() - getHeapEnd()`), VRAM z licznika `ll_image`
  (całość: tekstury A+B 256 KB + palety E 64 KB = 320 KB).
- **`sys.stats()`** zwraca tabelę: `fps cpu update_us draw_us draw_top_us draw_bottom_us mem
  mem_peak mem_limit ram_free vram vram_total polys verts`.
- **`ll_gfx.c` w ITCM — odłożone:** ~11,5 KB w Thumb (w ARM więcej), a w ITCM zostało
  ~7,7 KB. Można by przenieść tylko gorące funkcje (`ITCM_CODE`/`ARM_CODE`), ale zysku nie
  da się sprawdzić w melonDS, a dużą część czasu zajmują wywołania API Lua. Wrócić, jeśli
  pomiary na konsoli (np. w edytorze) pokażą potrzebę.
- Wyniki w melonDS (tryb DS): scena `sprites` CPU 6%, 600 sprite'ów CPU 68%, „poly 600
  vtx 2400” — liczniki zgodne z liczbą narysowanych quadów.

## D27 (2026-10-11) — Projekt aplikacji: przepływ, przyciski, kartridże systemowe
Pełny opis ze szkicami: `docs/UX.md`. Ustalone z użytkownikiem:
- **Menu pauzy:** START przytrzymany 0,5 s (krótkie START dostaje gra). Menu rysuje
  jądro na przyciemnionej ostatniej klatce: Wznów, Restart, Edytuj kod, Wyjdź. L+R+B
  zostaje jako awaryjne wyjście bez menu. (P10)
- **`print`** od P6: zawsze log + nakładka konsoli z ostatnimi liniami (L+R+X), bo dolny
  ekran przestaje być konsolą.
- **Ekran błędu i tymczasowa lista kartridży** do P10: rysowane w C fontem 6×8 na 3D, w
  docelowym stylu (błąd: komunikat na górze; ślad stosu i przyciski na dole).
- **Kartridże systemowe** (launcher, edytory): wbudowane w ROM (`nitro:/system/<nazwa>`),
  ale **wersja z karty `sd:/litelua/system/<nazwa>` ma pierwszeństwo**, jeśli jej `api`
  pasuje do silnika (inaczej ROM + ostrzeżenie w logu). **Tryb awaryjny:** SELECT
  trzymany przy starcie = tylko ROM. Launcher ma opcję skopiowania kartridża systemowego
  na kartę, żeby go przerabiać na DS. Nazwa `@nazwa` w `sys.run` = kartridż systemowy.
  Dodatkowe API (`sys.system`: lista kartridży, zapis plików dowolnego kartridża, nowy
  kartridż, uruchomienie gry z powrotem do wywołującego) tylko dla nich. (P10)
- Wspólny wygląd systemowych ekranów: biblioteka `ui.lua` w ROM (`nitro:/lib`), paleta
  Sweetie 16, font 6×8.
- Plan zostaje w dotychczasowej kolejności (decyzja użytkownika): P6 robi tylko to, co
  wynika z dwóch ekranów; launcher, pauza i kartridże systemowe w P10, edytor w P11.

## D28 (2026-10-11) — Tryb dual30 (P6): 3D na obu ekranach przez zrzut obrazu
- **Metoda „stabilna”** jak przykład BlocksDS `video_capture/dual_screen_3d` (CC0): silnik
  3D rysuje na przemian górny i dolny ekran, jeden na VBlank; każdy obraz trafia przez
  display capture do swojego banku: **górny → C, dolny → D**. Ekrany zawsze pokazują
  zrzuty: silnik główny wyświetla bank, do którego właśnie zrzuca (`MODE_VRAM_C/D`), a
  silnik pomocniczy drugi bank (C jako tło bitmapowe 16 bpp, D jako 12 sprite'ów
  bitmapowych 64×64). Spóźniona klatka = oba ekrany trzymają ostatni obraz, bez
  migania i zamiany ekranów.
- **Przełączanie w przerwaniu VBlank** (`ll_gfx_vblank`, wołane z handlera w `ll_log.c`):
  `ll_gfx_end` po `glFlush` zapisuje, który ekran czeka na zamianę buforów; przerwanie
  zaraz po zamianie ustawia LCD (`lcdMainOnTop/Bottom`), tryby obu silników, banki C/D i
  `REG_DISPCAPCNT`. Niezależne od tego, czy Lua akurat liczy.
- **Wysyłanie tekstur z wyłączonymi przerwaniami:** videoGL zapisuje i przywraca
  mapowanie banków A–D naraz (`vramRestorePrimaryBanks`) — przerwanie w środku
  cofnęłoby zmianę C/D. Upload i `glResetTextures` w `enterCriticalSection`.
- **Kolejność w klatce (zmiana D11):** połowa 1: `_draw(TOP)`; połowa 2: `_draw(BOTTOM)`,
  potem wejście i `_update` (następnej klatki; pierwsze `_update` przed pętlą). Każdy
  ekran musi wysłać obraz przed swoim VBlankiem — budżet ~16 ms na ekran, `_update`
  dzieli drugą połowę z dolnym ekranem. Czekanie na *następny* VBlank (polecenia dla
  drugiego ekranu nie mogą wejść przed zamianą buforów pierwszego). Dłuższa połowa =
  klatka 3 VBlanki (20 FPS). Pomiar melonDS: 500 × `rectfill` na górze (13,6 ms) = 30 FPS,
  800 (21,9 ms) = 20 FPS.
- **Możliwa optymalizacja później:** zapisywać polecenia geometrii do bufora w RAM (lista
  wyświetlania) i wysyłać DMA we właściwym VBlanku — wtedy oba ekrany razem miałyby ~33 ms
  niezależnie od podziału.
- **Konsola 2D usunięta:** `print` → log + bufor konsoli (`source/ll_console.c`, 32 linie po
  42 znaki, UTF-8, pomija kody ANSI), `io.write` → bufor konsoli. Nakładka konsoli L+R+X
  na dolnym ekranie (jak nakładka statystyk L+R+Y na górnym). Bufor czyszczony przy starcie
  kartridża.
- **Ekran błędu i tymczasowa lista** rysowane w C (`ll_gfx_text/rectfill/cls`,
  `ll_gfx_frame`): błąd — komunikat i pamięć na górze, ślad stosu i START/SELECT na dole;
  lista — na dole z podświetleniem (dotyk: wybór, drugi dotyk: start), na górze nazwa i
  podpowiedzi. Font wysyłany do VRAM już przy starcie (lista przed pierwszym kartridżem).
- **Stan rysowania** (kolor, alfa, kamera, clip, tint) wspólny dla obu ekranów; `cls` —
  osobny kolor tła dla każdego ekranu. Statystyki: wielokąty/wierzchołki osobno dla
  ekranów (`polys_top`, `polys_bottom`, `verts_top`, `verts_bottom`).
- **BOM UTF-8:** kod Lua i `cart.lua` z BOM (Notatnik, PowerShell) są wczytywane — BOM
  pomijany (`ll_skip_bom`), jak w `luaL_loadfile`.
- Demo i kartridże testowe przerobione: wyniki fontem na dolnym ekranie; demo nie używa
  X/Y (kolizja z L+R+X/Y): błąd = strzałka w górę, brak pamięci = w dół.

## D29 (2026-10-11) — Wydania na GitHubie: numeracja i build wydaniowy
- Repozytorium: https://github.com/MariuszOnik/LiteLua---Fantasy-console (`origin`). Push
  i wydania tylko na prośbę użytkownika.
- **Numeracja:** `v0.<n>.0` = stan po zamknięciu punktu P<n> (pierwsze wydanie `v0.6.0`
  po P6); poprawki w obrębie punktu → `v0.<n>.<k>`. `v1.0` — po edytorach. Wydania jako
  pre-release, dopóki jest przed 1.0.
- **Build wydaniowy:** `$env:LITELUA_VERSION='v0.6.0'; .\build.ps1` — baner ROM-u pokazuje
  wersję zamiast punktu planu i czasu (D16), ROM w `builds/litelua-<wersja>.nds`. Tag git
  `v0.<n>.0` na commicie wydania.
- **Pliki wydania:** `litelua.nds` + przykładowe gry jako `.lcart` (`tools/litelua.py pack`).
  Wydanie tworzy użytkownik na stronie GitHuba (brak `gh` na tym komputerze); notatki
  przygotowuje agent.

## D30 (2026-10-12) — Kontrakt stanu rysowania: powierzchnie TOP/BOTTOM, reset na początku `_draw`
Zmienia D23 (stan trwa między klatkami) i D28 (stan wspólny dla obu ekranów). `_draw(screen)`
i kolejność klatki z D28 bez zmian. Wynik przeglądu architektury (czy zastąpić `_draw(screen)`
dwoma callbackami albo wirtualnymi powierzchniami — nie: sygnatura oddaje sprzęt, pęknięcie
było we wspólnym stanie rysowania).
- **Powierzchnie:** `TOP` i `BOTTOM` to logiczne powierzchnie 256×192 (początek w lewym górnym
  rogu, Y w dół), nie fizyczne ekrany. Mapowanie na wyświetlacz należy do platformy (na DS:
  `lcdMainOnTop/Bottom` w `ll_gfx_vblank`, D28); port może je pokazać pod sobą, obok siebie
  albo w różnych rozmiarach bez zmiany API. W dokumentacji argument `_draw` nazywamy
  `surface` (stałe `TOP`/`BOTTOM` zostają).
- **Wywołania:** w trybie dual30 `_draw` raz na powierzchnię w każdej klatce, zawsze `TOP`,
  potem `BOTTOM`. W single60 (P15) tylko dla powierzchni 3D — szczegóły przy P15.
- **`touch()`** zwraca współrzędne w przestrzeni `BOTTOM`; port przelicza dotyk/mysz na nią.
- **Bez dodatkowych powierzchni** (offscreen, render-to-texture): na DS każda to osobny
  przebieg 3D (+1 VBlank) i 96 KB VRAM, a banki A–D są zajęte.
- **Reset w `ll_gfx_begin`:** każde `_draw` zaczyna od tego samego stanu, cokolwiek ustawiło
  poprzednie (druga powierzchnia, poprzednia klatka, przerwanie błędem): `color` 12
  (`DEFAULT_COLOR`), `alpha` 1, `camera` 0, 0, zoom 1, `clip` cała powierzchnia, `tint` brak
  (biały), kolor tła 0 z palety. Kolor tła nie jest wyjątkiem — `clear_color[2]` nie
  przecieka między ekranami, ale przeciekał między klatkami; gra z tłem woła `cls(c)` w
  `_draw` (jak wszystkie obecne kartridże). Liczniki `depth`, `poly_id`, `bound` jak dotąd.
- **Co trwa:** tylko zasoby kartridża (obrazy, `sub`, font) i stan Lua (D14, D24). Nic z
  rysowania nie przechodzi między powierzchniami ani klatkami.
- **Poza `_draw`:** `color`, `alpha`, `camera`, `clip`, `tint`, `cls` w `_init`/`_update` nie
  działają (reset i tak by je nadpisał); pierwsze takie wywołanie = jeden wpis w logu.
  Funkcje rysujące poza `_draw` są ignorowane już dziś. Wspólna kamera dla obu powierzchni:
  własna zmienna gry i `camera(cx, cy)` na początku `_draw`.
- **Implementacja (zrobione 2026-10-12):** `reset_draw_state()` (wartości domyślne w jednym miejscu) wołane z
  `ll_gfx_begin` i z `ll_gfx_reset` (która dokłada `active = false` i kolor tła obu ekranów).
  Ekran błędu i lista (`ll_gfx_frame`) dostają reset automatycznie; ich `ll_gfx_reset()`
  staje się zbędne. `draw_overlay` tylko ustawia swój stan, bez zapisywania i odtwarzania
  stanu gry (po nakładce nic już nie rysuje, następne `begin` resetuje). Do tego
  `docs/api/gfx.lua` + `tools/apidoc.py`, README (D15), komentarze D23/D28 w kodzie.
- **Koszt:** pamięć 0; czas kilkanaście zapisów do `gs` na powierzchnię. Obecne kartridże
  (`starcatch`, `tests/carts/*`) same przywracają stan i nic nie ustawiają poza `_draw` —
  zgodne wstecz, ręczne sprzątanie przestaje być obowiązkowe.
- **Poza zakresem:** rozmiar powierzchni w API zamiast `local W, H = 256, 192` w każdym
  kartridżu (nazwa do ustalenia, osobna decyzja). Lista wyświetlania z D28 — **korekta:**
  nie daje wspólnych 33 ms za darmo. Geometria powierzchni musi trafić do silnika 3D przed
  jej VBlankiem, więc pełny wspólny budżet wymaga nagrywania klatki N podczas wysyłania
  N−1 (+1 klatka opóźnienia, ~33 ms). Tylko po pomiarach na konsoli (FIFO/DMA, VBlanki).

## D31 (2026-10-12) — Koła piksel w piksel, grubość linii `stroke(w)`
Zmienia D23 (koło = wielokąt 8 + r/2 segmentów, okrąg = linie). Powód: małe koła były krzywe
i niesymetryczne (nieparzysta liczba boków, wierzchołki zaokrąglane do pikseli).
- **Koła r ≤ 16 (`CIRCLE_SPAN_R`):** piksel w piksel z poziomych pasków (quady), piksel
  należy do koła, gdy dx² + dy² ≤ r² + r (środek piksela w promieniu r + 0,5). Wiersze o tych
  samych paskach łączone w jeden quad. Cienki `circ` = brzeg `circfill` (piksele z
  zewnętrznym sąsiadem poza kołem) — 8-spójny i zgodny z `circfill`. Gruby `circ` = koło
  minus koło o promieniu r − w. Szerokości wierszy liczone na liczbach całkowitych (ARM9
  bez FPU — `sqrtf` na wiersz kosztował więcej niż rysowanie).
- **Koła r > 16:** wielokąt o liczbie boków podzielnej przez 8 (16…64), wierzchołki w
  ćwiartkach piksela, `sinLerp`/`cosLerp` z libnds zamiast `sinf`/`cosf`. Cienki okrąg =
  zdegenerowane trójkąty w jednym prymitywie, gruby = pas trójkątów (pierścień).
- **`stroke([w])`:** grubość 1…64 px linii i obrysów (`line`, `rect`, `circ`, `tri`), stan
  rysowania z D30 (reset do 1 na początku `_draw`, poza `_draw` → wpis w logu). Parametr
  przy każdej funkcji odrzucony (`line(x1, y1, x2, y2, nil, 3)` nieczytelne); tak jak
  `setLineWidth` w LÖVE.
- **Gruba linia:** jeden quad wokół odcinka między środkami pikseli, końce kwadratowe
  (przedłużone o w/2 — domykają narożniki `tri`). Parzyste grubości przesunięte o pół
  piksela, żeby linie poziome i pionowe pokrywały całe piksele. `rect` i `circ` rosną do
  środka (jak dotychczasowy obrys 1 px); `rect` za mały na obrys → wypełniony.
- **Jeden prymityw na kształt:** `rect`, gruby `tri`, koła — jeden `POLY_ID`, więc
  zachodzące części przy `alpha` nie mieszają się podwójnie.
- **Zoom:** linia 1 px zostaje 1 px (sprzętowa), grubsze i koła-paski skalują się z kamerą.
- **Pomiar melonDS:** scena `tests/carts/gfx` 10,0 ms (v0.6.0) → 4,5 ms; `tests/carts/shapes`
  (nowy test D31): scena 4,2 ms, 200 × `circfill` + 200 × `circ` r = 6 — 24,7 ms
  (z `sqrtf` było 44,3 ms). **Konsola DSi:** `shapes` scena 2,3 ms, 400 kół r = 6 — 13,0 ms
  (~32 µs na koło z pętlą Lua); `gfx` scena 2,8 ms, 500 × `rectfill` 6,5 ms. D30 na konsoli:
  wpis `color() outside _draw has no effect` w logu.

## D32 (2026-10-12) — Wyjście z LiteLua: L+R+START przez 1 s
- **L+R+START trzymane 1 s** (60 VBlanków, `ll_vblanks`) — w grze, na liście kartridży i na
  ekranie błędu (`ll_sys_quit_poll`). Sekunda chroni przed przypadkowym wyjściem (utrata
  niezapisanego stanu); L+R+B (do listy) zostaje natychmiastowe.
- Wyjście: wpis w logu, `ll_log_flush`, `exit(0)` — zamyka otwarte pliki (log, archiwum
  kartridża); libnds wraca do loadera przez jego boot stub, a bez niego wyłącza konsolę.
  melonDS bez loadera: wyłączenie (sprawdzone).
- Ekran błędu: START przy trzymanych L+R nie restartuje gry (to początek L+R+START).
- Gry nie powinny używać L+R razem ze START (jak z B/X/Y, UX.md §3).

## D33 (2026-10-12) — `_quit()` przy wyjściu z gry, `sys.info()` (DS / DSi)
- **Cel sprzętowy: DS.** Gra ma działać na DS (melonDS w trybie DS ≈ najgorszy przypadek);
  DSi daje dodatki. Na DSi (i 3DS w trybie DSi) ARM9 działa z 134 MHz — Lua ~2× szybciej
  bez żadnych zmian (pomiar: D31); limity 3D, VRAM i tempo klatki takie same.
- **`sys.info()`** → `{ console = "DS" | "DSi", cpu_mhz = 67 | 134, ram_kb = 4096 | 16384 }`
  (`isDSiMode`, `REG_SCFG_CLK`). Wersja LiteLua — później (dziś tylko w banerze ROM-u, D29).
- **`_quit()`:** wołane, gdy gra kończy się bez błędu — L+R+B, L+R+START (D32),
  `sys.exit()`, `sys.run()`; nie po błędzie (stan gry może być zepsuty). Do zapisu gry.
  `sys.run`/`sys.exit` usuwane z tabeli `sys` przed wywołaniem (wyjście już trwa). Limit
  1 s (hook licznika instrukcji co 1000): błąd lub przekroczenie → wpis w logu, gra i tak
  zamykana. L+R+START w grze: runtime zwraca `LL_RUN_QUIT`, `main` zamyka kartridż i
  woła `ll_sys_quit()` (D32). Na liście i ekranie błędu — od razu `ll_sys_quit()`.
- Starcatch: `_quit` zapisuje rekord z nieskończonej gry. Test: `tests/carts/gfx` loguje
  `sys.info()` i `_quit`; zapętlony `_quit` sprawdzony w melonDS (przerwany po 1 s).

## D34 (2026-10-12) — Dźwięk (P7): efekty WAV, muzyka `.mas` lub strumień WAV
Rozwija D7.
- **Maxmod bez pliku soundbanku** (`mmInit` z pustym bankiem w RAM, licencja ISC): każdy
  kartridż ładuje własne pliki. Kod: `source/ll_sound.c`.
- **API globalne** jak grafika (D22): `sound(name)` → `sfx/<name>.wav` (cache po nazwie,
  słabe wartości, jak `image`), `sfx(snd, [vol], [pan], [pitch])` → uchwyt,
  `sfx_stop([h])`, `music([name], [loop])`, `music_volume(v)`. Pola dźwięku: `length`,
  `rate`.
- **Efekty:** WAV PCM 8/16-bit, mono/stereo (stereo miksowane do mono przy wczytaniu),
  1000–48000 Hz, w RAM jako próbki w formacie MAS we własnym banku (niżej). Czyta je
  ARM7, więc blok jest zwalniany dopiero po końcu ostatniego odtworzenia (licznik
  VBlanków, lista „do zwolnienia”), nie w `__gc`.
- **Muzyka, jedna naraz:** `music/<name>.mas` (moduł z `mmutil -d -m`, cały w RAM,
  `mmPlayMAS`) albo `music/<name>.wav` strumieniowany z karty: bufor pierścieniowy na pół
  sekundy, wywołanie Maxmoda w przerwaniu timera 2 (timery 0+1 = `micros()`) kopiuje z
  bufora (cisza przy niedoborze), `ll_sound_update` w obu połówkach klatki dočytuje do
  8 KB z pliku. Strumień: PCM 8/16-bit, mono/stereo, ≤ 32768 Hz. ADPCM w strumieniu —
  nie (Maxmod nie strumieniuje ADPCM; dekodowanie na ARM9 ewentualnie w P9).
- **`.lcart`:** strumień czyta nieskompresowany wpis wprost z archiwum (własny `FILE*`,
  przesunięcie z lokalnego nagłówka ZIP, `ll_cart_open_stream`); skompresowany → błąd z
  podpowiedzią. `tools/litelua.py pack` zapisuje `.wav` bez kompresji.
- **Pamięć:** dane dźwięku liczą się do limitu `memory` kartridża razem z Lua
  (`ll_mem_charge/release`, decyzja użytkownika: jeden limit). Przy braku miejsca — pełne
  GC i ponowna próba, potem błąd. `sys.stats().mem` pokazuje całość.
- **Koniec kartridża (D14):** `ll_sound_stop_all` (przed ekranem błędu i przed
  `lua_close`) zatrzymuje muzykę i efekty; `ll_sound_end` po `lua_close` czeka (≤ 3
  VBlanki), aż cała pamięć dźwięku zostanie zwolniona. Po panice — dane porzuconego stanu
  zostają (jak pamięć Lua).
- **Test:** `tests/carts/sound` (dźwięki generowane przez `make_assets.py`: pisk 8-bit,
  wybuch 16-bit stereo, melodia WAV, mały moduł MOD → `.mas`). melonDS: wczytanie,
  moduł, strumień z folderu i `.mas` z `.lcart`, zwolnienie (75 → 30 KB), po zamknięciu
  0 bajtów. Odsłuch i strumień WAV z `.lcart` — do sprawdzenia.
- **Własny bank próbek zamiast „zewnętrznych próbek” (po teście na DSi: muzyka grała,
  efekty nie):** na ARM7 `mmEffectEx` (`core/effect.c`) odrzuca efekt, gdy
  `id >= liczba próbek soundbanku`, zanim rozpozna wskaźnik do zewnętrznej próbki — bez
  soundbanku nic nie grało (liczba próbek idzie do ARM7 jako 2 bajty, więc nie da się jej
  „podbić” ponad adres). Rozwiązanie: `mmInit` z pustym bankiem 256 slotów w RAM
  (`sample_bank`); `sound()` buduje próbkę w formacie MAS (`mm_mas_prefix` +
  `mm_mas_ds_sample` + dane, `mm_mas.h`), wpisuje jej przesunięcie od 0x02000000 do
  wolnego slotu, `sfx()` gra przez numer slotu — główna ścieżka Maxmoda. Slot i blok
  zwalniane razem po końcu ostatniego odtworzenia. Limit: 256 wczytanych dźwięków naraz.
  melonDS: uchwyty efektów poprawne. Warto zgłosić błąd do BlocksDS/Maxmod.

## D35 (2026-10-12) — LiteLua Music Studio: kierunek architektury (P18, etapy S0–S4)
Zatwierdzony kierunek (użytkownik + przegląd „Javisa”); implementacja S0 dopiero na
osobne polecenie.
- **Cel stylistyczny, nie emulacja:** brzmienie inspirowane NES (np. *Chip 'n Dale:
  Rescue Rangers*); nie deklarujemy wierności 1:1 układowi APU (np. nieliniowy miks NES
  nie jest odtwarzany).
- **Edytor jak FL Studio, nie tracker:** piano roll rysikiem (dolny ekran), channel rack /
  playlista / instrument na górnym; bez wpisywania `C-4 01 F A03`.
- **Warstwy:** edytor (Lua) → dane utworu (format niezależny od edytora) → sekwencer (C,
  przenośny rdzeń) → backend audio. Edytor nie steruje sprzętem.
- **Backend DS:** kanały sprzętowe — PSG 8–13 (prostokąt, 8 stopni wypełnienia ⊇ 12,5/25/
  50/75% NES), szum 14–15; trójkąt NES (32 kroki) i „krótki” szum jako malutkie zapętlone
  próbki; DPCM = próbki. Kanały sekwencera rezerwowane w Maxmodzie (`mmLockChannels`),
  efekty WAV / moduły / strumień z P7 dzielą resztę. **Inne platformy:** synteza programowa
  z tym samym rdzeniem sekwencera i tymi samymi plikami.
- **Odrzucone na DS:** synteza programowa na ARM9 do strumienia — identyczna wszędzie, ale
  ~5–15% CPU (szacunek) zabrane Lua i zajmuje jedyny strumień Maxmoda (konflikt z muzyką WAV).
- **Timing:** sekwencer w przerwaniu timera 3 (0+1 = `micros()`, 2 = strumień P7),
  niezależnie od FPS Lua; tick zależny od tempa (np. 24 na ćwierćnutę). Parametry kanałów
  przez FIFO do ARM7 (`soundPlayPSG`/`soundSetFreq`/`soundSetVolume` z libnds); własny kod
  ARM7 tylko, jeśli S0 pokaże taką potrzebę.
- **Format:** nuty jako lista zdarzeń (start, długość, wysokość, głośność) na kanał —
  naturalny dla piano rolla; instrumenty (wypełnienie, obwiednia głośności, arpeggio,
  vibrato, slide, presety); utwór = tempo + playlista patternów. Plik tekstowy z danymi
  Lua (`.lsong`, jak `cart.lua`), kompilowany przy wczytaniu do postaci binarnej.
- **Lua:** nazwy, nie numery (spójnie z D34): `music("level1")` → `music/level1.lsong`.
  Efekty ze studia mogą na chwilę zabierać kanał utworu (jak w grach NES).
- **Tryby:** „NES Classic” (ograniczenia NES w edytorze: kanały, wypełnienia) i „Extended”
  (więcej kanałów DS) — ten sam silnik.
- Etapy S0–S4 w `docs/PLAN.md` (P18). Edytor-prototyp może powstać przed P10 jako zwykły
  kartridż zapisujący utwory w swoim `save/`; pełna integracja (zapis do innych kartridży,
  kartridż systemowy) po P10.

## D36 (2026-10-12) — Format `.lsong` v1, narzędzia na PC, bezpieczne wczytywanie danych (P18 S-1)
- **Specyfikacja:** `docs/LSONG.md` (po angielsku — format publiczny dla twórców, narzędzi
  i modeli językowych). Opis muzyki, nie sprzętu. Wysokość = numer nuty MIDI, czas w
  tickach, `ppq` = ticki na ćwierćnutę (nie „beat”); metrum tylko dla edytora.
- **Model:** instrumenty `pulse` / `triangle` / `noise` / `kit` (obwiednia i `release` na
  klatkę 1/60 s, `arp`, `vibrato`, `duty`, `mode`); ścieżki monofoniczne z instrumentem
  domyślnym, „rodzaj” ścieżki = typ instrumentu, nuta może zmienić instrument tego samego
  rodzaju; zestaw perkusyjny `kit` mapuje wysokość nuty na instrument i wysokość; nuty
  `{t, d, p, v?, i?, s?}`; playlista `{pattern, times, transpose}` (`times`, bo `repeat`
  to słowo kluczowe Lua) i `loop` (numer wpisu albo `false`). Profile `nes` (2 pulse,
  1 triangle, 1 noise, wypełnienia NES) i `extended` (do 8 ścieżek).
- **Kolizje:** nuta zaczynająca się w trakcie poprzedniej ucina ją (ostrzeżenie), dwie nuty
  z tym samym `t` na ścieżce — błąd, nuta za końcem patternu — ucięta (ostrzeżenie).
- **Limity:** plik 256 KB, zagnieżdżenie 16, napis 512, 16384 nut w utworze, 1024 na
  ścieżkę w patternie, 32 instrumenty / 8 ścieżek / 256 patternów / 256 wpisów
  playlisty, 30 minut jednego przejścia. Nieznane pola to błąd (literówki), poza `x_*`.
- **Dwa zapisy, jeden model:** dane Lua (`.lsong`, czyta DS) i JSON (`.lsong.json`,
  wymiana na PC); konwersja bezstratna. Na DS (S1) dane są kompilowane przy wczytaniu do
  postaci binarnej — bez JSON-a na DS.
- **Narzędzia:** `tools/lsong.py` (parser, zapis Lua/JSON, walidator, renderer) i
  `python tools/litelua.py song check|convert|render`. Renderer = **odsłuch przybliżony**
  (synteza programowa pulse / 32-stopniowy trójkąt / LFSR szumu, parametry na klatkę,
  filtr DC), nie emulacja DS ani NES. WAV gra w grach już teraz przez `music("x.wav")`.
- **Testy:** `python -m unittest discover -s tests/tools` — 19 testów (zwrot Lua ↔ JSON,
  17 złośliwych/zepsutych plików odrzuconych, zakresy, monofonia, profile, kit,
  transpozycja, limity, wysokość renderu 440 Hz ±1%, ucinanie nut, obwiednia, pętla).
- **Przykład:** `examples/songs/sky_hopper.lsong` (+ `.json`, generator
  `make_sky_hopper.py`): C-dur, 150 BPM, 4 ścieżki, 368 nut, 54 s; render w teście
  dźwięku jako `music/sky.wav` (poza gitem, robi go `make_assets.py`).
- **Bezpieczeństwo wczytywania danych (sprawdzone na prośbę użytkownika):** `cart.lua` jest
  dziś *wykonywany* jako kod Lua w osobnym stanie z pustym `_ENV` i limitem pamięci 64 KB —
  pamięć jest ograniczona, **czas nie**: `while true do end` w manifeście zawiesza DS przy
  otwieraniu kartridża (pętle i funkcje nie potrzebują globali). Dlatego `.lsong` **nie
  jest wykonywany**: czyta go parser podzbioru danych Lua (tabele, napisy, liczby,
  `true/false`, komentarze; bez pętli, funkcji, wyrażeń, `nil`) — w Pythonie już jest, w C
  powstanie w S1 z tą samą gramatyką i limitami. **Propozycje (do decyzji):** (1) ten sam
  parser dla `cart.lua` (manifest to i tak same dane); (2) do tego czasu szybka łatka:
  hook licznika instrukcji przy wczytywaniu manifestu; (3) osobno: strażnik dla kodu gry —
  hook co N instrukcji sprawdza L+R+B, żeby zawieszona pętla w `_update` dała się przerwać
  (dziś nie da się z niej wyjść).

## D37 (2026-10-12) — Import MIDI → `.lsong` (P18 S-1b)
- **Kod:** `tools/midi.py` (czytanie SMF typu 0 i 1: running status, sysex/meta kasują
  running status, note-on z prędkością 0 = note-off, nakładające się te same nuty —
  najstarsza kończy się pierwsza, nuty bez końca → koniec ścieżki z ostrzeżeniem; mapa
  tempa, metrum, nazwy ścieżek; zapis SMF do testów i przyszłego eksportu) i
  `tools/midi_import.py`; komenda `python tools/litelua.py song import x.mid out.lsong`
  (`--list` pokazuje źródła).
- **MIDI zostaje źródłem:** import to konfigurowalna aranżacja; ustawienia zapisywane w
  utworze (`x_import`: plik, role, tryby, tryb tempa, `ppq`, takty na pattern), więc da
  się go powtórzyć z innymi ustawieniami. Format v1 bez zmian.
- **Źródła i role:** źródło = ścieżka + kanał. Role `lead`, `lead2` (tylko profil
  `extended`), `chords`, `bass`, `drums`; ręcznie (`--lead 2 --chords 1,3 …`) albo
  automatycznie (perkusja = kanał 10, bas = program basowy lub najniższa partia, akordy =
  najbardziej polifoniczna, melodia = najwyższa z pozostałych). Nieużyte źródła w raporcie.
- **Redukcja polifonii (konfigurowalna, `--<rola>-mode`):** `top` (melodia, domyślnie),
  `bottom` (bas, domyślnie), `last` (ostatnio zagrana), `arp` (akordy, domyślnie):
  współbrzmienie → nuta podstawowa + instrument z `arp` (interwały, maks. 4 dźwięki w 2
  oktawach; kształty najczęstsze, reszta w limicie 32 instrumentów → pojedyncza nuta z
  ostrzeżeniem). Liczba nut, których nie słychać, jest raportowana.
- **Perkusja GM → `kit`:** stopa, werbel, tom (wysokość wg numeru), hi-hat zamknięty /
  otwarty, crash, ride; inne nuty perkusyjne → hi-hat (raport). Jeden bęben naraz wg
  priorytetu stopa > werbel > tom > crash > hi-hat otwarty > hi-hat > ride (raport).
- **Tempo:** v1 ma jedno tempo (średnie, zachowuje długość utworu). Zmiany tempa są
  wykrywane i zgłaszane. Tryb `grid` zachowuje siatkę taktów, tryb `time` zachowuje
  czas; `auto` wybiera `time`, gdy `grid` myli się o > 30 ms. **Błąd czasu jest mierzony**
  dla każdej nuty (maks. i średni, w raporcie), nie zakładany.
- **Patterny:** podział na takty (metrum z pliku), patterny po 1/2/4/8/16 taktów —
  wybierany wariant mieszczący się w limitach v1 z najmniejszą liczbą zapisanych nut;
  identyczne patterny zapisywane raz, powtórzenia jako `times`. Nuty przechodzące przez
  granicę patternu są tam grane od nowa (raport — v1 nie ma nut łączonych).
- **Testy:** `tests/tools/test_midi.py` (14): typ 0 z ręcznie zapisanym running status i
  note-on 0, zapis z running status, typ 1 (ścieżki, kanały, nazwy, metrum), nakładające
  się te same nuty, mapa tempa, 5 zepsutych plików, tryby `top/bottom/arp`, raport
  niesłyszalnych nut, perkusja GM (priorytet, mapowanie, spoza GM), powtórzone takty →
  1 pattern `times = 8`, zmiana tempa (auto → `time` < 25 ms; `grid` > 300 ms), jedno
  tempo → `grid` < 1 ms, automatyczne role + render, `lead2` wymaga `extended`. Razem z
  D36: 33 testy.
- **Przykład całej drogi:** `examples/songs/demo_rock.mid` („Pixel Riff”, własny utwór,
  generator `make_demo_rock.py`: typ 1, 130 → 150 BPM, akordy mocy, perkusja GM) →
  `song import` → `demo_rock.lsong` (tryb `time`, błąd maks. 8,9 ms) → WAV → DS (test
  `sound`, `rock.wav`). W trybie `grid` ten sam plik: błąd do 992 ms, ale 9 różnych
  patternów z 16 taktów.
- **Propozycja v1.1 (do decyzji, nie wdrożona):** (1) opcjonalne `tempo` we wpisie
  playlisty — import dzieliłby utwór przy zmianach tempa i miałby jednocześnie dokładny
  czas i siatkę taktów (dziś trzeba wybrać); (2) `tie = true` na nucie z `t = 0` —
  kontynuacja nuty z poprzedniego patternu bez ponownego ataku (długie nuty na granicach
  patternów); (3) ewentualnie `meter` we wpisie playlisty dla zmian metrum (tylko edytor).
  Wszystkie trzy są zgodne wstecz (pola opcjonalne).

## D38 (2026-10-12) — `.lsong` v1.1, `cart.lua` przez parser danych, strażnik L+R+B
- **`.lsong` v1.1** (zgodne wstecz: pliki v1 bez zmian, `lsong = 1`; nowe pola wymagają
  `lsong = 1.1`): `tempo` we wpisie playlisty (obowiązuje od tego wpisu, pętla przywraca
  tempo wpisu, do którego skacze) i `tie = true` na nucie z `t = 0` (ciąg dalszy nuty z
  końca poprzedniego patternu, bez nowego ataku; walidator ostrzega, gdy nie ma czego
  kontynuować — wtedy gra jak nowa nuta). Renderer liczy czas w sekundach (tempo na wpis),
  nuty łączone przedłużają poprzednią. Zmiany metrum — później.
- **Zmiana tempa w środku taktu bez przesuwania nut:** import (tryb `entries`, domyślny
  przy zmianach tempa i v1.1) tnie pattern dokładnie w miejscu zmiany, a nuty przez nią
  przechodzące łączy `tie`. „Pixel Riff”: błąd czasu maks. 9,6 ms (kwantyzacja `ppq` 24,
  perkusja przesunięta w MIDI o 10/480 ćwierćnuty), 10 różnych patternów z 16 taktów —
  dokładny czas *i* powtórzenia (v1: albo jedno, albo drugie). **Mapa zdarzeń tempa**
  (globalna lista `{t, bpm}` niezależna od patternów) — na razie niepotrzebna; propozycja
  na przyszłość, gdyby utwory z płynnymi zmianami tempa (accelerando: dziesiątki zmian)
  przekraczały limit 256 wpisów playlisty przez cięcia.
- **`cart.lua` przez parser danych** (`source/ll_data.c`, ta sama gramatyka i limity co
  `tools/lsong.py`; użyje go też `.lsong` w S1): manifest jest parsowany, nie wykonywany —
  pętla czy wywołanie to błąd składni, czas liniowy, pamięć z limitem stanu (64 KB),
  rozmiar ≤ 16 KB, zagnieżdżenie ≤ 16, napis ≤ 512 B; BOM pomijany. **Zgodność:** 29/29
  manifestów (konsola 9, karta emulatora 9, repo 9, przykłady README 2) bez zmian.
  melonDS: `while true do end` w `cart.lua` → od razu błąd „must start with 'return'”
  (wcześniej zawieszenie), `memory = 4 * 1024` → błąd; komentarz długi, BOM, `;`, hex,
  `['klucz']`, `[[napis]]`, `\u{17C}`, `\x42`, `\067` — poprawnie.
- **Strażnik L+R+B:** callback (`_init`, `_update`, `_draw`, kod główny) działający > 1 s
  przy trzymanym L+R+B jest przerywany: powrót do listy bez ekranu błędu, wpis w logu, bez
  `_quit` (stan gry niepewny). Sprawdzane w przerwaniu VBlank; dopiero wtedy
  `lua_sethook(..., LUA_MASKCOUNT, 1)` (dozwolone asynchronicznie, jak Ctrl+C w `lua.c`;
  pętle odświeżają `trap` na skokach) — błąd przy każdej instrukcji, więc `pcall` w grze
  go nie zatrzyma. **Koszt:** w normalnej grze żadnego hooka (stały hook licznika
  instrukcji odrzucony — w Lua 5.4 włącza `luaG_traceexec` przy *każdej* instrukcji);
  zostaje kilka porównań na VBlank. Funkcje C (np. długie `string.rep`) nie dają się
  przerwać. melonDS: pętla w `_update` → L+R+B → lista, pamięć 0 B.
- **Testy narzędzi:** 40 (`python -m unittest discover -s tests/tools`): +7 dla v1.1
  (stare pliki ważne, nowe pola wymagają 1.1, reguły `tie`, tempo na wpis i pętla, brak
  ponownego ataku przy `tie`, zmiana tempa w playliście, zmiana tempa w środku taktu).

## D39 (2026-10-12) — `.lsong` v1.2: sceny i klipy (projekt zatwierdzony, bez implementacji)
- **Pomiar** (Master of Puppets Extended z obiema gitarami rytmicznymi, 7 ścieżek, `ppq` 96,
  prywatny plik użytkownika — poza repo): v1.1 9985 nut, 299 KB (ponad limit); **sceny**
  (klip = nuty jednej ścieżki, pattern = scena wskazująca klip każdej ścieżki) 5652 nuty,
  ~214 KB; **osie czasu** (każda ścieżka z własnymi klipami w dowolnych miejscach, jak
  Playlist FL Studio) 5689 nut, ~217 KB.
- **Wybór: sceny** — ten sam rozmiar, prosty sekwencer na DS (jeden kursor, tempo/pętla/`tie`
  jak w v1.1), ewolucja v1.1 (pattern z `notes` nadal ważny), import MIDI prawie bez zmian,
  aranżacja na 256×192 jako lista scen. Osie czasu odrzucone dla pliku (osobne kursory,
  globalna mapa tempa, trudny import); mogą być *widokiem* w edytorze.
- **Warunek z przeglądu:** klip ma własną długość — krótszy od sceny gra raz (reszta cisza;
  zapętlanie `repeat = true` — kandydat), dłuższy od sceny w v1.2 jest ucinany, sposób
  grania przez granice scen zarezerwowany na później. Odwołanie do klipu może mieć
  `transpose`.
- Szkic w `docs/LSONG.md` sekcja 11; nazwy pól mogą się zmienić przy implementacji.
  Kolejność prac: S0 (test sprzętu), potem P8; v1.2 w kodzie — przy S1/S2.
