# Plan pracy LiteLua

Status: `[ ]` do zrobienia, `[~]` w toku, `[x]` gotowe. Po każdym punkcie: build, aktualizacja
tego pliku, **dokumentacja API** (`docs/api/*.lua` + `python tools/apidoc.py`, D12),
**manual w `README.md`** (D15), commit
`P<n>: …`. Decyzje: `docs/DECISIONS.md`.

## Gdzie skończyliśmy
- **Ostatnio:** P6 — dual30 (D28): 3D na obu ekranach przez zrzut do banków C/D
  (przełączanie w przerwaniu VBlank), kolejność klatki: `_draw(TOP)` | `_draw(BOTTOM)` +
  `_update`, konsola 2D usunięta (`print` → log + nakładka L+R+X), ekran błędu i
  tymczasowa lista rysowane fontem 6×8, pomijanie BOM w plikach Lua. Kartridże testowe i
  demo przerobione na dwa ekrany. Testy w melonDS ok; na konsoli — do sprawdzenia.
- **D30 wdrożone:** reset stanu rysowania w `ll_gfx_begin` (`reset_draw_state`), setery
  poza `_draw` → jeden wpis w logu, nakładka bez odtwarzania stanu; README i API
  (`_draw(surface)`). Test: kartridż `gfx` celowo zostawia brudny stan na górze — dolny
  ekran ma pokazać białe „D30: state reset ok” z ramką, a log `color() outside _draw has
  no effect`. Do sprawdzenia w melonDS.
- **D31 wdrożone:** koła piksel w piksel (r ≤ 16), `stroke(w)` dla `line/rect/circ/tri`,
  test `tests/carts/shapes` (obraz sprawdzony w melonDS). Konsola DSi: `shapes` 2,3 ms,
  400 kół 13,0 ms, `gfx` 2,8 ms; D30 i D31 działają (log bez błędów).
- **D32 wdrożone:** L+R+START przez 1 s = wyjście z LiteLua (do loadera / wyłączenie);
  melonDS ok (bez loadera → wyłączenie). Na konsoli: sprawdzić powrót do loadera.
- **D33 wdrożone:** `_quit()` (zapis przy wyjściu, limit 1 s) i `sys.info()` (DS/DSi);
  starcatch zapisuje rekord w `_quit`. melonDS ok.
- **P7 zrobione (D34):** dźwięk — `sound/sfx/sfx_stop/music/music_volume`, efekty WAV w
  RAM, muzyka `.mas` albo WAV strumieniowany z karty (też z `.lcart`, wpis bez
  kompresji), pamięć dźwięku w limicie `memory`. Test `tests/carts/sound` w melonDS: logika
  i pamięć ok. Konsola DSi: moduł, strumień, głośność, `_quit`, L+R+START ok; efekty
  nie grały — błąd Maxmoda; własny bank próbek (D34), w melonDS uchwyty ok, **do odsłuchu
  na konsoli**. Do
  sprawdzenia: strumień WAV z `.lcart`.
- **P18 / D35:** kierunek Music Studio zatwierdzony, etapy S0–S4 w planie; S0 tylko na
  osobne polecenie. **S-1 zrobione (D36):** specyfikacja `.lsong` v1, `tools/lsong.py` +
  `litelua.py song check|convert|render`, 19 testów (`python -m unittest discover -s
  tests/tools`), przykład „Sky Hopper” (w teście `sound` pod X jako `sky.wav`).
  Do decyzji (D36): bezpieczne wczytywanie `cart.lua` (parser danych / hook) i strażnik
  L+R+B dla zawieszonej pętli w grze. **S-1b zrobione (D37):** import MIDI
  (`song import`), 33 testy narzędzi, „Pixel Riff” MIDI → `.lsong` → WAV → DS (test
  `sound`, X). **D38 zrobione:** `.lsong` v1.1 (tempo w playliście, `tie`), `cart.lua`
  przez parser danych (`source/ll_data.c`, 29/29 manifestów zgodnych), strażnik L+R+B dla
  zapętlonej gry (bez kosztu w normalnej grze); 40 testów narzędzi.
  **D39:** projekt `.lsong` v1.2 (sceny i klipy) zatwierdzony, bez implementacji.
  **S0 zrobione (D40):** synteza na żywo na DSi — przerwanie śr. 52 µs (ok. 0,3% CPU),
  tempo ±0,2%, 0 spóźnionych ticków, efekty i moduł Maxmoda naraz; trzaski akceptowalne.
  **S1 zaimplementowane (D41):** `music("x")` gra `music/x.lsong` na żywo (ładowarka →
  segmenty → sekwencer timera 3); test `tests/carts/song` — **do potwierdzenia odsłuchem
  na DSi** (Marsz Imperatora jako `private.lsong`, Metallica Extended `private2.lsong`).
- **Stan na 2026-10-13 (koniec sesji):** P18 S1 — `.lsong` grane na żywo; w melonDS
  potwierdzone nagraniem wyjścia audio (Sky Hopper, Pixel Riff, Marsz Imperatora). Na DSi
  jest jeszcze **stary ROM** (z błędem ciszy): FTP na konsoli nie łączy się z Wi‑Fi —
  wgrać `litelua.nds` i `private/marsz_imperatora.lsong` jako
  `litelua/carts/song/music/private.lsong`, posłuchać „Live songs (S1)”, zamknąć S1.
  Manual kompozytora: `docs/COMPOSING.md`. Prywatne pliki (Metallica, Marsz) tylko w
  `private/` i w katalogu głównym — ignorowane przez git.
- **Następny krok:** odsłuch S1 na DSi, potem P8 — mapy kafelkowe. Później w P18: S2
  (prototyp piano rolla), `.lsong` v1.2 (sceny i klipy, D39), panorama na żywo. (P7, D32/D33 sprawdzone na DSi: dźwięk, efekty,
  L+R+START, `_quit`.)
- **Wydania (D29):** repo na GitHubie, tag `v0.6.0` wypchnięty; pliki wydania w
  `builds/release-v0.6.0/` (`litelua.nds`, `starcatch.lcart`, `RELEASE_NOTES.md`) —
  wydanie na stronie GitHuba tworzy użytkownik (sprawdzić, czy opublikowane). Na
  konsoli jest build `v0.6.0`. Przykładowa gra: `examples/carts/starcatch`; instrukcja
  „Making a game on a PC” w README.
- **Później (uzgodnione):** poradnik dobrych praktyk i biblioteka algorytmów dla gier
  (P16, P17). Dźwięki (2026-10-12, README „Getting sound effects into a game”):
  **wbudowany zestaw ~20 klasycznych efektów w ROM** (`sound("@coin")`, generowane przez
  nas, prefiks `@` jak kartridże systemowe D27) i **nagrywanie efektów mikrofonem DS/DSi**
  (nagraj → przytnij → `sfx/x.wav`, w edytorze efektów P18 S3) — pomysł użytkownika. Optymalizacja: lista wyświetlania w RAM (D28) — tylko po pomiarach
  na konsoli; wspólne 33 ms kosztuje +1 klatkę opóźnienia (D30).
- **Dokumentacja API:** od P1 prowadzona na bieżąco (D12) — `docs/api/core.lua`, `input.lua`,
  `gfx.lua`, `files.lua`, `sys.lua` (z `sys.stats`).
- **Manual:** `README.md` (D15) — opisuje stan po P6.
- **Otwarte sprawy:** błąd jako struktura plik/linia (D13) — przy P11.
  **Potencjalny bug — opóźnienie wejścia (2026-10-12):** pomiar w melonDS (kartridż
  `tests/carts/latency`, A → biały ekran, 30 prób): górny ekran 76–105 ms (mediana 91),
  dolny 89–125 ms (104); ~15–20 ms dokłada melonDS. Eksperyment: wejście + `_update` tuż
  przed `_draw(TOP)` → mediana 69 / 90 ms (zmiana cofnięta, kolejność D28 bez zmian).
  Starcatch: dotyk wygładzany 0.3/klatkę (~200 ms do palca). Wrócić przy P15 (single60). Konsola tekstowa 2D
  usunięta w P6 (D28).

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
- [x] **P4 — Grafika** (D1, D5, D10, D22, D23, D24, D25) — trzy części, każda z commitem `P4 (część)`.
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
  - [x] **P4b — obrazy i sprite'y** (D24): własny dekoder PNG (inflate z miniz, D21) → tekstury
    4/8/16 bpp wg D10 (paleta ≤16 / ≤256 / RGB(A)), przezroczystość (indeks 0 / alfa 0),
    dopełnianie boków do potęgi dwójki, licznik VRAM (A+B = 256 KB tekstur, palety w E),
    błąd Lua przy braku miejsca. `img = image("hero")` ładuje `gfx/hero.png` (loader dopisuje
    katalog i rozszerzenie, D4); arkusze z klatkami (`image("chars", 16, 16)`).
    `spr(img, x, y, [frame])` + wariant z obrotem (stopnie), skalą, odbiciem i kolorem
    4 rogów (własny kod quadów, gl2d tego nie ma). Cache bindowania tekstur.
  - [x] **P4c — tekst** (D25): własny font 6×8 (D22) w ROM (NitroFS), `text(s, x, y, [col])`,
    szerokość tekstu (`textw`), UTF-8 z polskimi znakami. Fonty z `font/` kartridża —
    później (P12 albo osobny punkt).
  Test: kartridż `tests/carts/gfx` pokazujący wszystkie funkcje + pomiar (ile sprite'ów w
  klatce przy 30 FPS) na konsoli.
- [x] **P5 — Statystyki** (D26)
  Nakładka (kombinacja przycisków) + `sys.stats()`: pamięć Lua, sterta C (`mallinfo`), VRAM
  (liczona przy uploadzie), wielokąty/wierzchołki (`glGetInt`), czas `update`/`draw`.
- [x] **Projekt aplikacji (UX)** (D27, `docs/UX.md`) — zrobione przed P6
  Szkielet całej konsoli: składniki (jądro w C, launcher i edytory jako kartridże
  systemowe), przepływ launcher → gra → pauza → edytor → gra, szkice ekranów, przyciski
  systemowe, kartridże systemowe w ROM z nadpisaniem z karty i trybem awaryjnym, `print`
  → log + nakładka. Realizują go P6 (zrobione), P10 i P11 — przy nich czytać `docs/UX.md`.
- [x] **P6 — Tryb dual30 (domyślny)** (D28)
  Zrzut obrazu i zamiana banków C/D; `_draw(screen)` wołane dla ekranu rysowanego w klatce.
  Wg D27 / `docs/UX.md`: ekran błędu i tymczasowa lista rysowane w C fontem 6×8 na 3D,
  `print` → log + nakładka konsoli (L+R+X), dolny ekran przestaje być konsolą 2D.
- [x] **P7 — Dźwięk** (D34)
  Dźwięki/strumienie zatrzymywane i zwalniane przy zamknięciu stanu kartridża (D14).
  Maxmod: efekty WAV, muzyka `.mas` z SD (`mmPlayMAS`), strumieniowanie WAV z SD
  (ADPCM — ewentualnie P9).
- [ ] **P8 — Mapy kafelkowe**
- [ ] **P9 — Narzędzie `litelua` na PC (Python)**
  `pack` (folder → `.lcart`), `audio` (MP3/OGG/FLAC → WAV ADPCM), `music` (→ `.mas`), `gfx`.
- [ ] **P10 — Ekran wyboru kartridży** (kartridż systemowy w Lua)
  Wyjście z gry (menu pauzy) → powrót do listy na zapamiętaną pozycję (D14).
  Wg D27 / `docs/UX.md`: menu pauzy (START 0,5 s), kartridże systemowe w ROM z
  nadpisaniem z `sd:/litelua/system/`, tryb awaryjny (SELECT przy starcie), kopiowanie
  systemowych na kartę, `sys.run("@nazwa")`, API `sys.system`, biblioteka `ui.lua`.
  README ma już opis (sekcja „System carts”) — uaktualnić, gdy będzie działać.
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
- [ ] **P16 — Poradnik: dobre praktyki pisania gier na LiteLua** (pomysł użytkownika)
  Dokument dla twórców gier (`docs/GUIDE.md` po angielsku + skrót w README), oparty na
  pomiarach z konsoli, z krótkimi przykładami kodu:
  - pamięć i GC: pule obiektów (pociski, cząsteczki, wrogowie — jak `src/particles.lua`
    w `starcatch`), bez nowych tabel/domknięć/stringów w każdej klatce, `table.concat`
    zamiast `..` w pętli, ponowne użycie tabel;
  - szybkość Lua: `local` dla gorących funkcji i wartości, liczby całkowite i `//`, stały
    krok fizyki, licznik klatek zamiast czasu (D3), unikanie `pairs` w gorących pętlach;
  - kod modułowy: `require` i moduły w `src/`, klasy na metatabelach i biblioteki typu
    middleclass — **kartridż testowy z pomiarem na DSi** (koszt obiektów i wywołań metod:
    middleclass vs zwykłe tabele vs domknięcia; śmieci na klatkę), wyniki w poradniku;
  - grafika: budżet ~16 ms na ekran (D28), limit ~2000 kształtów na ekran, wybór PNG
    (paleta 16 kolorów = 4× mniej VRAM), arkusze klatek i `sub` zamiast wielu plików,
    kamera i `clip` dla HUD;
  - struktura gry: maszyna stanów (tytuł / gra / koniec), oddzielenie logiki od
    rysowania, zapisy w `save/`;
  - mierzenie: nakładka L+R+Y, `sys.stats()`, `micros()`, log.
- [ ] **P17 — Biblioteka przydatnych algorytmów dla gier** (pomysł użytkownika)
  Moduły Lua wbudowane w ROM (`nitro:/lib/`, `require("…")` działa od P3, D21), licencja
  zlib, każdy z dokumentacją w `docs/api/` (podpowiedzi w edytorze, D12) i małym
  przykładem; napisane pod DS (bez śmieci na klatkę, liczby całkowite, gdzie się da).
  Kandydaci:
  - `pool` — pula obiektów; `timer` — opóźnienia, powtórzenia; `tween` — interpolacja i
    funkcje wygładzania (easing);
  - `vec` / `mathx` — clamp, lerp, sign, odległość, kąt, wektory bez alokacji;
  - `collide` — prostokąty (AABB), koła, punkt w prostokącie/kole, odcinki;
    `grid` — siatka/mapa kafelków, kolizja z kafelkami, sąsiedzi;
  - `path` — A* na siatce, przeszukiwanie wszerz (mapa odległości), linia widzenia
    (Bresenham);
  - `spatial` — hash przestrzenny do szybkiego szukania bliskich obiektów;
  - `rng` — generator z ziarnem (powtarzalne poziomy), losowanie ważone, tasowanie;
    `noise` — szum wartości/Perlina do terenu;
  - `fsm` — maszyna stanów; `anim` — odtwarzanie animacji z arkusza klatek;
    `camera` — podążanie za graczem, martwa strefa, trzęsienie;
  - `save` — zapis/odczyt tabeli Lua do `save/` (serializacja tekstowa);
  - `ui` — przyciski, listy, okna (wspólne z kartridżami systemowymi, D27).
  Kolejność i zakres ustalić na starcie punktu (część może wejść wcześniej, np. `ui` w
  P10, `anim` przy P12).
- [ ] **P18 — LiteLua Music Studio: chiptune w stylu NES, edytor jak FL Studio** (D35)
  - [x] **S-1 — format `.lsong` v1** (D36): `docs/LSONG.md`, walidator, konwersja
    Lua ↔ JSON, renderer WAV (`tools/litelua.py song`), testy `tests/tools`, przykład
    `examples/songs/sky_hopper.lsong`.
  - [x] **S-1b — import MIDI** (D37): `song import`, role, redukcja polifonii (arp),
    perkusja GM, pomiar błędu czasu przy zmianach tempa, wykrywanie powtórzeń; przykład
    `examples/songs/demo_rock.mid`. Propozycja `.lsong` v1.1 (tempo we wpisie playlisty,
    nuty łączone) — do decyzji.
  - [x] **`.lsong` v1.1** (D38): `tempo` we wpisie playlisty, `tie`; import tnie patterny
    przy zmianach tempa (też w środku taktu) i łączy nuty.
  - [x] **S0 — próba sprzętu** (D40): synteza na żywo działa na DSi — ok. 0,3% CPU, tempo
    ±0,2%, razem z Maxmodem; libnds przez FIFO wystarcza. (1–2 dni, tylko na osobne polecenie): sekwencer na sztywno w C
    (2× pulse, triangle, noise) w przerwaniu timera 3, odsłuch na DSi. Zweryfikować: timing
    ARM9 → FIFO → ARM7 (opóźnienia, równość tempa), współpracę z Maxmodem
    (`mmLockChannels`, efekty i muzyka z P7 naraz), zachowanie kanałów przy zmianie
    parametrów w trakcie nuty (wypełnienie, głośność, częstotliwość — trzaski, restart
    fazy), koszt CPU. Wynik decyduje: libnds przez FIFO czy własny kod ARM7.
  - [~] **S1 — rdzeń** (D41): ładowarka `.lsong` → segmenty → sekwencer w przerwaniu,
    `music("x")` gra `.lsong` na żywo; melonDS potwierdzone nagraniem wyjścia audio,
    czeka na odsłuch na DSi (`tests/carts/song`, Marsz Imperatora).
  - **S2 — prototyp edytora (przed P10):** piano roll rysikiem, 4 kanały, patterny, wybór
    instrumentu, odtwarzanie, zapis do `save/` własnego kartridża (eksport do gry ręcznie
    lub później przez P10).
  - **S3 — pełne studio:** edytor instrumentów z presetami, playlista, efekty ze studia
    (kradzież kanału), integracja jako kartridż systemowy (po P10: zapis do innych
    kartridży, `sys.system`).
  - **S4 — rozszerzenia:** tryb Extended (więcej kanałów), DPCM/próbki, import MIDI /
    eksport w narzędziu `litelua` na PC, backend syntezy programowej dla portów.
