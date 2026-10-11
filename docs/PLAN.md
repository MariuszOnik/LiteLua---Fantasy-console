# Plan pracy LiteLua

Status: `[ ]` do zrobienia, `[~]` w toku, `[x]` gotowe. Po każdym punkcie: build, aktualizacja
tego pliku, **dokumentacja API** (`docs/api/*.lua` + `python tools/apidoc.py`, D12),
**manual w `README.md`** (D15), commit
`P<n>: …`. Decyzje: `docs/DECISIONS.md`.

## Gdzie skończyliśmy
- **Ostatnio:** P4a — rysowanie podstawowe (D22, D23): 3D na górnym ekranie, globalne
  `cls color alpha camera clip pset line rect rectfill circ circfill tri trifill`, paleta
  Sweetie 16 + `0xRRGGBB`, kartridż testowy `tests/carts/gfx` (scena + test obciążenia:
  melonDS 500 `rectfill` = 13 ms). Wcześniej P3 (pliki, `.lcart`) potwierdzone na DSi.
  Testy w melonDS można robić automatycznie ze zrzutem ekranu (okno melonDS → PNG,
  czytany przez Read) — skrypt w scratchpadzie sesji, opis w D20.
- **Następny krok:** P4b — obrazy i sprite'y. Na starcie ustalić: jak podawać obrót, skalę,
  odbicie i kolory rogów w `spr` (dodatkowe argumenty czy osobna funkcja / tabela opcji).
  Konsola DSi: `rectfill` ~11,8 µs, poprawione tempo klatki potwierdzone (30 FPS do
  2600 prostokątów, D23).
- **Dokumentacja API:** od P1 prowadzona na bieżąco (D12) — `docs/api/core.lua`, `input.lua`,
  `gfx.lua`, `files.lua`, `sys.lua`.
- **Manual:** `README.md` (D15) — opisuje stan po P4a.
- **Otwarte sprawy:** błąd jako struktura plik/linia (D13) — przy P11. Konsola tekstowa jest
  na dolnym ekranie tylko do P4.

## Punkty

- [x] **P0 — Repozytorium i build**
  git, `.gitignore`, licencja zlib, Makefile (szablon BlocksDS `rom_arm9_only`), Lua 5.4.8 w
  `vendor/lua`, `build.ps1`, `CLAUDE.md`, dokumentacja, test dymny z benchmarkiem.
- [x] **P1 — Jądro**
  Pętla w C wołająca `_init`, `_update`, `_draw(screen)`; własny `lua_Alloc` liczący bajty;
  ekran błędu ze śladem stosu (nie zawiesza konsoli); moduł wejścia (przyciski, dotyk).
  Pliki: `source/ll_runtime.c` (pętla), `ll_mem.c`, `ll_error.c`, `ll_input.c`, `ll_demo.c`.
  Dodatek po P1: log na SD `ll_log.c` (D18), `print`/`log`.
- [x] **P2 — Wydajność Lua**
  `lvm.c` (i ewentualnie `ltable.c`/`lgc.c`) w trybie ARM + ITCM; sprzętowy dzielnik DS dla
  `%` i `//` (sprawdzony, odrzucony); pomiar względem baseline z D3. Zrobione wg D19 (`lvm` + `ltable` w ITCM,
  `tests/carts/bench`); na konsoli DSi −14%.
- [x] **P3 — Pliki i kartridże**
  Nazwy chunków względne do kartridża (`src/player.lua`, D13); limit pamięci z `cart.lua`;
  `sys.run(path)` + przełączanie stanów po powrocie z callbacku (D14).
  SD + NitroFS; manifest `cart.lua`; stała struktura katalogów (D6); czytnik `.lcart` (ZIP);
  piaskownica `io`/`os`; `require` z kolejnością z D6; katalog zapisów.
  Zrobione: D20 (foldery, manifest, piaskownica, `require`, zapisy, `sys`, lista), D21
  (`.lcart` przez miniz, NitroFS, `tools/litelua.py pack`).
- [~] **P4 — Grafika** (D1, D5, D10, D22, D23) — trzy części, każda z commitem `P4 (część)`.
  Do P6 (dual30) 3D rysuje tylko **górny ekran**; dolny zostaje konsolą tekstową, a
  rysowanie w `_draw(BOTTOM)` jest ignorowane (jedno ostrzeżenie w logu). Tekstury i inne
  zasoby graficzne należą do stanu Lua kartridża i są zwalniane przy jego zamknięciu (D14).
  - [x] **P4a — rysowanie podstawowe** (D23): inicjalizacja 3D (gl2d, D1) na górnym ekranie, klatka:
    `_draw(TOP)` między `glBegin2D` a `glFlush`. API (szkic, nazwy do potwierdzenia przy
    implementacji): `cls([col])`, `pset(x, y, col)`, `line(x1, y1, x2, y2, col)`,
    `rect(x, y, w, h, col)` / `rectfill`, `circ(x, y, r, col)` / `circfill`,
    `tri(x1, y1, x2, y2, x3, y3, col)` / `trifill`, `camera([x, y])`, `clip([x, y, w, h])`,
    półprzezroczystość (`alpha(a)` dla kolejnych rysunków — DS: 32 poziomy). Kolory i
    paleta 16 wg D22. Kolejność rysowania = kolejność wywołań (głębokość rośnie sama).
    Limity sprzętu: 2048 czworokątów / 6144 wierzchołków na klatkę — liczone dla P5.
  - [ ] **P4b — obrazy i sprite'y:** własny dekoder PNG (inflate z miniz, D21) → tekstury
    4/8/16 bpp wg D10 (paleta ≤16 / ≤256 / RGB(A)), przezroczystość (indeks 0 / alfa 0),
    dopełnianie boków do potęgi dwójki, licznik VRAM (A+B = 256 KB tekstur, palety w E),
    błąd Lua przy braku miejsca. `img = image("hero")` ładuje `gfx/hero.png` (loader dopisuje
    katalog i rozszerzenie, D4); arkusze z klatkami (`image("chars", 16, 16)`).
    `spr(img, x, y, [frame])` + wariant z obrotem (stopnie), skalą, odbiciem i kolorem
    4 rogów (własny kod quadów, gl2d tego nie ma). Cache bindowania tekstur.
  - [ ] **P4c — tekst:** własny font 6×8 (D22) w ROM (NitroFS), `text(s, x, y, [col])`,
    szerokość tekstu (`textw`), UTF-8 z polskimi znakami. Fonty z `font/` kartridża —
    później (P12 albo osobny punkt).
  Test: kartridż `tests/carts/gfx` pokazujący wszystkie funkcje + pomiar (ile sprite'ów w
  klatce przy 30 FPS) na konsoli.
- [ ] **P5 — Statystyki**
  Nakładka (kombinacja przycisków) + `sys.stats()`: pamięć Lua, sterta C (`mallinfo`), VRAM
  (liczona przy uploadzie), wielokąty/wierzchołki (`glGetInt`), czas `update`/`draw`.
- [ ] **P6 — Tryb dual30 (domyślny)**
  Zrzut obrazu i zamiana banków C/D; `_draw(screen)` wołane dla ekranu rysowanego w klatce.
- [ ] **P7 — Dźwięk**
  Dźwięki/strumienie zatrzymywane i zwalniane przy zamknięciu stanu kartridża (D14).
  Maxmod: efekty WAV, muzyka `.mas` z SD (`mmPlayMAS`), strumieniowanie WAV/ADPCM z SD.
- [ ] **P8 — Mapy kafelkowe**
- [ ] **P9 — Narzędzie `litelua` na PC (Python)**
  `pack` (folder → `.lcart`), `audio` (MP3/OGG/FLAC → WAV ADPCM), `music` (→ `.mas`), `gfx`.
- [ ] **P10 — Ekran wyboru kartridży** (kartridż systemowy w Lua)
  Wyjście z gry (menu pauzy) → powrót do listy na zapamiętaną pozycję (D14).
- [ ] **P11 — Edytor kodu na DS** z klawiaturą ekranową
  Kod na górnym ekranie, klawiatura na dolnym; kolorowanie składni; przycisk „Edytuj” na
  ekranie błędu → plik i linia, dotknięcie ramki stosu (D13); sprawdzanie składni w tle
  (`load` bez uruchamiania); uruchomienie gry wg D14 wariant A (zapis buforów, powrót do
  pliku/linii/kursora).
- [ ] **P11a — Podpowiedzi i pomoc w edytorze**
  - Źródła: API z `docs/api/*.lua` (D12, w ROM przez NitroFS), słowa kluczowe Lua, wybrane
    funkcje biblioteki standardowej (osobny plik `docs/api/lua.lua`), nazwy z kodu gracza
    (funkcje, `local`, globalne, pola tabel — lekki tokenizer, bez pełnego parsera).
  - Kiedy: po 1–2 znakach identyfikatora, po `.` i `:` (pola znanej tabeli/modułu).
  - Gdzie: pasek podpowiedzi nad klawiaturą (jak w telefonie) — dotknięcie wstawia;
    L/R przewija, A akceptuje.
  - Kolejność: dopasowanie prefiksu, potem częstość użycia w pliku / ostatnio wybrane.
  - Po wpisaniu `(` za znaną funkcją pasek pokazuje `sig` z podświetlonym bieżącym argumentem.
  - Pomoc: przytrzymanie słowa (albo przycisk) otwiera stronę `desc` + `example`
    z opcją „wstaw przykład”.
  - Wydajność: indeks budowany raz przy starcie edytora (posortowana tablica, wyszukiwanie
    binarne); nazwy z kodu odświeżane przy zmianie linii, nie przy każdym znaku.
- [ ] **P12 — Edytor grafiki**
- [ ] **P13 — Edytor map**
- [ ] **P14 — Edytor efektów dźwiękowych**
- [ ] **P15 — Tryb single60, przegląd dokumentacji API, przykładowe kartridże**
