# Plan pracy LiteLua

Status: `[ ]` do zrobienia, `[~]` w toku, `[x]` gotowe. Po każdym punkcie: build, aktualizacja
tego pliku, **dokumentacja API** (`docs/api/*.lua` + `python tools/apidoc.py`, D12),
**manual w `README.md`** (D15), commit
`P<n>: …`. Decyzje: `docs/DECISIONS.md`.

## Gdzie skończyliśmy
- **Następny krok: P11 — edytor kodu na DS, razem z minimalnym wycinkiem P10** (D42;
  P8 mapy odłożone). Dwa etapy w kolejności:
  1. **P10-min (fundament):** kartridże systemowe w ROM (`nitro:/system/<nazwa>/`,
     uruchamiane `sys.run("@code")`), API `sys.system` widoczne **tylko** dla nich:
     lista kartridży (z manifestami), odczyt / zapis / lista plików w kartridżu-folderze
     (`.lcart` tylko do odczytu), tworzenie pliku i folderu, bezpieczny zapis (plik
     tymczasowy → zamiana), uruchomienie gry z powrotem do kartridża wywołującego
     z przekazaniem danych (plik, linia, kursor — D14 wariant A). Pełny launcher w Lua,
     menu pauzy, tryb awaryjny i nadpisywanie systemowych z karty zostają w P10.
  2. **P11 (edytor, kartridż systemowy w Lua `@code`):** wybór kartridża i pliku; kod na
     górnym ekranie (font 6×8: 42 kolumny × 24 wiersze, przewijanie, numery linii,
     kolorowanie składni), **klawiatura ekranowa na dolnym** (rysik, Shift, symbole Lua),
     krzyżak i L/R do kursora; wstawianie/usuwanie, zaznaczanie, kopiuj/wklej, cofnij;
     sprawdzanie składni przez `load` bez uruchamiania; zapis; „Uruchom” → gra → powrót
     do pliku/linii; po błędzie gry przycisk „Edytuj” na ekranie błędu (D13: błąd jako
     plik + linia). Podpowiedzi API — P11a, później.
  Przed startem przeczytać: `docs/UX.md` (ekrany, przyciski, kartridże systemowe), D8,
  D13, D14, D20 (piaskownica), D27. Prawdopodobnie potrzebne: powtarzanie klawiszy
  (`btnp` z autorepeat) — sprawdzić `docs/api/input.lua`.
- **Ostatnio (2026-10-13):** P18 S1 — utwory `.lsong` grane **na żywo** przez DS
  (`music("x")`, D41), potwierdzone nagraniem w melonDS i odsłuchem na DSi; import MIDI
  (D37), `.lsong` v1.1 (D38), projekt v1.2 (D39), manual `docs/COMPOSING.md`. Wcześniej
  w tej serii: D30–D33 (stan rysowania, koła i `stroke`, wyjście L+R+START, `_quit`,
  `sys.info`), P7 dźwięk (D34), `cart.lua` przez parser danych i strażnik L+R+B (D38).
- **Testowanie:** melonDS sterowany skryptem (klawisze tylko gdy okno melonDS jest na
  pierwszym planie); **dźwięk potwierdzać nagraniem wyjścia audio** (WASAPI loopback,
  Python `soundcard` w osobnym venv) — liczniki nie wystarczą (lekcja z S0, D40). Konsola:
  FTP pod adresem z DHCP (192.168.1.86 albo .89), port 5000.
- **Prywatne pliki** (Metallica, Marsz Imperatora — MIDI, `.lsong`, WAV) tylko w `private/`
  i w katalogu głównym, ignorowane przez git — nigdy do repo.
- **Wydania (D29):** tag `v0.6.0` na GitHubie; od tego czasu wiele zmian — kolejne
  wydanie (np. `v0.7.0`) do ustalenia z użytkownikiem.
- **Później (uzgodnione):** P8 mapy; P18: S2 (prototyp piano rolla), v1.2 w kodzie,
  panorama na żywo, Extended w imporcie dla dowolnych plików; P16/P17 (poradnik,
  biblioteka algorytmów); dźwięki: wbudowany zestaw `sound("@coin")` i nagrywanie
  mikrofonem; lista wyświetlania w RAM tylko po pomiarach (D28, D30).
- **Otwarte sprawy:** opóźnienie wejścia ~91 ms w melonDS (`tests/carts/latency`,
  wrócić przy P15 single60); strumień WAV z `.lcart` — niesprawdzony na konsoli.

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
- [ ] **P8 — Mapy kafelkowe** (odłożone za P11 — D42)
- [ ] **P9 — Narzędzie `litelua` na PC (Python)**
  `pack` (folder → `.lcart`), `audio` (MP3/OGG/FLAC → WAV ADPCM), `music` (→ `.mas`), `gfx`.
- [ ] **P10 — Ekran wyboru kartridży** (kartridż systemowy w Lua)
  Wyjście z gry (menu pauzy) → powrót do listy na zapamiętaną pozycję (D14).
  Wg D27 / `docs/UX.md`: menu pauzy (START 0,5 s), kartridże systemowe w ROM z
  nadpisaniem z `sd:/litelua/system/`, tryb awaryjny (SELECT przy starcie), kopiowanie
  systemowych na kartę, `sys.run("@nazwa")`, API `sys.system`, biblioteka `ui.lua`.
  README ma już opis (sekcja „System carts”) — uaktualnić, gdy będzie działać.
- [ ] **P11 — Edytor kodu na DS** z klawiaturą ekranową — **następny** (D42), razem z
  minimalnym wycinkiem P10 (kartridże systemowe w ROM, `sys.system`, powrót z gry)
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
  - [x] **S1 — rdzeń** (D41): ładowarka `.lsong` → segmenty → sekwencer w przerwaniu,
    `music("x")` gra `.lsong` na żywo; potwierdzone nagraniem w melonDS i odsłuchem na DSi.
  - **S2 — prototyp edytora (przed P10):** piano roll rysikiem, 4 kanały, patterny, wybór
    instrumentu, odtwarzanie, zapis do `save/` własnego kartridża (eksport do gry ręcznie
    lub później przez P10).
  - **S3 — pełne studio:** edytor instrumentów z presetami, playlista, efekty ze studia
    (kradzież kanału), integracja jako kartridż systemowy (po P10: zapis do innych
    kartridży, `sys.system`).
  - **S4 — rozszerzenia:** tryb Extended (więcej kanałów), DPCM/próbki, import MIDI /
    eksport w narzędziu `litelua` na PC, backend syntezy programowej dla portów.
