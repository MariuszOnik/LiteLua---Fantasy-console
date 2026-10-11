# Plan pracy LiteLua

Status: `[ ]` do zrobienia, `[~]` w toku, `[x]` gotowe. Po każdym punkcie: build, aktualizacja
tego pliku, **dokumentacja API** (`docs/api/*.lua` + `python tools/apidoc.py`, D12),
**manual w `README.md`** (D15), commit
`P<n>: …`. Decyzje: `docs/DECISIONS.md`.

## Gdzie skończyliśmy
- **Ostatnio:** P1 — jądro: pętla 30 FPS (`_init`/`_update`/`_draw(screen)`), alokator z
  licznikiem i limitem (2 MB domyślnie), ekran błędu ze śladem stosu i restartem (START),
  wejście `btn`/`btnp`/`btnr`/`touch` (D11). Bez `main.lua` na SD rusza wbudowane demo
  (`source/ll_demo.c`) — test w melonDS do potwierdzenia przez użytkownika.
- **Następny krok:** P2 — wydajność Lua (ARM + ITCM dla `lvm.c`, dzielnik sprzętowy, pomiar
  względem baseline z D3; benchmark z P0 usunięty z `main.c` — odtworzyć jako `main.lua`
  albo wbudowany test, `micros()` zostało).
- **Dokumentacja API:** od P1 prowadzona na bieżąco (D12) — `docs/api/core.lua`, `input.lua`.
- **Manual:** `README.md` (D15) — opisuje stan po P1.
- **Otwarte sprawy:** błąd jako struktura plik/linia (D13) — przy P3 lub P11; limit pamięci z manifestu (`cart.lua`) — do zrobienia w P3
  (`ll_mem_init` przyjmuje limit). Konsola tekstowa jest na dolnym ekranie tylko do P4.

## Punkty

- [x] **P0 — Repozytorium i build**
  git, `.gitignore`, licencja zlib, Makefile (szablon BlocksDS `rom_arm9_only`), Lua 5.4.8 w
  `vendor/lua`, `build.ps1`, `CLAUDE.md`, dokumentacja, test dymny z benchmarkiem.
- [x] **P1 — Jądro**
  Pętla w C wołająca `_init`, `_update`, `_draw(screen)`; własny `lua_Alloc` liczący bajty;
  ekran błędu ze śladem stosu (nie zawiesza konsoli); moduł wejścia (przyciski, dotyk).
  Pliki: `source/ll_runtime.c` (pętla), `ll_mem.c`, `ll_error.c`, `ll_input.c`, `ll_demo.c`.
- [ ] **P2 — Wydajność Lua**
  `lvm.c` (i ewentualnie `ltable.c`/`lgc.c`) w trybie ARM + ITCM; sprzętowy dzielnik DS dla
  `%` i `//`; pomiar względem baseline z D3.
- [ ] **P3 — Pliki i kartridże**
  Nazwy chunków względne do kartridża (`src/player.lua`, D13); limit pamięci z `cart.lua`;
  `sys.run(path)` + przełączanie stanów po powrocie z callbacku (D14).
  SD + NitroFS; manifest `cart.lua`; stała struktura katalogów (D6); czytnik `.lcart` (ZIP);
  piaskownica `io`/`os`; `require` z kolejnością z D6; katalog zapisów.
- [ ] **P4 — Grafika**
  Tekstury należą do stanu Lua kartridża i są zwalniane przy jego zamknięciu (D14).
  Dekompresja deflate (wspólna z P3) + własny dekoder PNG → tekstury 4/8/16 bpp wg D10
  (dopełnianie do potęgi dwójki, przezroczystość, licznik VRAM); sprite'y: obrót, skala,
  odbicia, kolorowanie 4 rogów; prymitywy; kamera; przycinanie; cache bindowania;
  wbudowany font 6×8 z polskimi znakami.
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
