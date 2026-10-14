# Plan pracy LiteLua

Status: `[ ]` do zrobienia, `[~]` w toku, `[x]` gotowe. Po każdym punkcie: build, aktualizacja
tego pliku, **dokumentacja API** (`docs/api/*.lua` + `python tools/apidoc.py`, D12),
**manual w `README.md`** (D15), commit
`P<n>: …`. Decyzje: `docs/DECISIONS.md`.

## Gdzie skończyliśmy
- **Droga do 1.0 (D49):** ~~P8 mapy~~ (D50) → ~~P10 lekki launcher~~ (D52) → P19 lekka
  biblioteka `scene` → wydanie 1.0 (API, przykłady, `v1.0.0`). Wszystko inne po 1.0.
  **Następny krok: P19** (biblioteka `scene`, sama Lua) — zakres w D48/D49; na starcie
  ustalić z użytkownikiem format sceny i API.
- **Ostatnio (2026-10-14):** P10 (D52) — launcher `@launcher` w Lua (lista, opis z
  `cart.lua`, Play/Edit/New, nowa gra z klawiatury i szablonu, pamięć pozycji), menu
  pauzy w C (START 0,5 s: Resume/Restart/Edit code/Quit, dźwięk pauzowany — potwierdzone
  nagraniem), lista w C jako zapas i tryb awaryjny (SELECT na starcie), `sys.system.edit/
  demo/create/manifest`. Edytor: sekcja o zakładkach w pomocy. Sprawdzone w melonDS; **na
  konsoli do sprawdzenia**. Potem P10b (D53): `sys.menu(label, fn)` — własne pozycje
  gry w menu pauzy (np. Save/Load; przykład w `tests/carts/map`), słowa kluczowe Lua w
  pomocy, pomoc z kartridża (`help/*.lua`, D53). Dodatki do edytora z kodem — po 1.0
  (szkic w D48).
- **Wcześniej (2026-10-14):** P8 (D50) — mapy kafelkowe: `tilemap()`, rysowanie w C,
  kolizje przez flagi, ASCII i liczby, konwerter z Tiled (`litelua.py map`), grafika
  testowa ze skryptu (`make_tiles.py`), kartridż `tests/carts/map` (mała platformówka).
  Sprawdzone w melonDS i **potwierdzone na DSi** (z muzyką „Grass Run”, efektami i
  poprawką wejścia D51). Użytkownik ma Tiled na PC.
- **Kierunek (2026-10-14, D48, dyskusja otwarta):** studio z zakładkami zamiast osobnych
  edytorów, sceny jako dane z obiektami ze skryptami (jak MonoBehaviour), prefaby i lekkie
  przyczepienie zamiast hierarchii, prawdziwa grafika w edytorze, grafika ładowana według
  kamery. Kolejność: **P8 → P19 → P20 → P21**. Otwarte tematy (izometria, atlasy z
  klatkami różnych rozmiarów i kotwicami, szczegóły map) — w D48; użytkownik chce jeszcze
  dopisywać, więc przed P8 wrócić do rozmowy.
- **Wcześniej (2026-10-14):** P11d (D47) — zakładki otwartych plików w górnym pasku (do 5,
  Y+lewo/prawo, Y+B zamyka; cofanie przy puszczeniu Y), powrót z gry do tych samych
  zakładek; poprawka P11c: `words.lua` wczytywany po zapisie. Sprawdzone w melonDS.
  Word+ tylko dopisuje linię do `words.lua` (komentarze zostają).
- **Wcześniej (2026-10-14):** P11c (D46) — motywy kolorów kodu (Opts w pomocy, zapis w
  `saves/@code/settings.lua`), `words.lua` w kartridżu (własne słowa i sygnatury do
  podpowiedzi, Word+ w pomocy). Sprawdzone w melonDS; na konsoli jeszcze nie.
- **Wcześniej (2026-10-14):** P11a (D45) — pasek podpowiedzi nad klawiaturą (API, biblioteka
  Lua z nowego `docs/api/lua.lua`, słowa kluczowe, nazwy i pola z kodu), dotyk albo R+A
  wstawia, `>` następna strona; w nawiasach znanej funkcji sygnatura z bieżącym argumentem
  na żółto. Sprawdzone w melonDS; na konsoli jeszcze nie.
- **Wcześniej rozważane kolejne kroki** (przed D49): reszta P10
  (launcher w Lua, menu pauzy, tryb awaryjny, nadpisywanie systemowych z karty, nowy
  kartridż), P8 (mapy) albo wydanie `v0.7.0` (D29).
- **Wcześniej (2026-10-14):** P11b (D44) — w edytorze Ren/Del w widoku plików
  (`sys.system.remove/rename`), pomoc pod START: manual edytora i całe API z `docs/api`
  (kopiowane przez `build.ps1` do `nitrofs/system/code/api`), pomoc kontekstowa dla nazwy
  pod kursorem, „Copy ex”. Sprawdzone w melonDS i **potwierdzone na DSi**.
- **Wcześniej (2026-10-13):** P11 + P10-min (D43) — edytor kodu na DS jako kartridż
  systemowy `@code` (`nitrofs/system/code`): kod z kolorami i numerami linii, klawiatura
  ekranowa, zaznaczanie, schowek, cofnij/ponów, Check, Save, Run z powrotem do pliku/linii,
  Y na ekranie błędu → linia błędu + ślad stosu do dotknięcia; Y na liście → edytor.
  `sys.system` (pliki dowolnego kartridża, bezpieczny zapis, `run` z powrotem). Sprawdzone
  w melonDS skryptem i **potwierdzone na DSi (2026-10-14)**: pisanie rysikiem, przewijanie,
  Run → błąd → Y → linia błędu → Run → B → powrót.
- **Wcześniej:** P18 S1 — utwory `.lsong` grane **na żywo** przez DS
  (`music("x")`, D41), potwierdzone nagraniem w melonDS i odsłuchem na DSi; import MIDI
  (D37), `.lsong` v1.1 (D38), projekt v1.2 (D39), manual `docs/COMPOSING.md`. Wcześniej
  w tej serii: D30–D33 (stan rysowania, koła i `stroke`, wyjście L+R+START, `_quit`,
  `sys.info`), P7 dźwięk (D34), `cart.lua` przez parser danych i strażnik L+R+B (D38).
- **Testowanie:** melonDS sterowany skryptem `tools/melon.py` (klawisze, stuknięcia w dolny
  ekran, zrzuty; okno melonDS musi być na pierwszym planie); **dźwięk potwierdzać nagraniem wyjścia audio** (WASAPI loopback,
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

## Droga do 1.0 (D49)

- [x] **P8 — Mapy, preset `platform`** (D50)
- [x] **P10 — Launcher (lekki)**: lista w Lua, Graj / Edytuj / Nowa gra, menu pauzy (D52)
- [x] **P10b — Własne pozycje gry w menu pauzy** (`sys.menu`, D53)
- [ ] **P19 — Biblioteka `scene` (lekka)**
- [ ] **Wydanie 1.0**: przegląd API, 2–3 przykładowe gry (w tym platformówka), `v1.0.0`

Po 1.0: P20, P21, preset `iso`, atlasy, P12, P13, P14, P9, P15, P16, P17, P18 (dalsze etapy).

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
- [x] **P8 — Mapy kafelkowe** (D50; odłożone za P11 — D42, zrobione wg D49): format mapy,
  `map()` w C, kolizje z kafelkami; fundament dla gry i edytora sceny. Na początku ustalić
  rozmiar kafelka, warstwy, ewentualny tryb izometryczny (D48 — otwarte tematy).
- [ ] **P9 — Narzędzie `litelua` na PC (Python)**
  `pack` (folder → `.lcart`), `audio` (MP3/OGG/FLAC → WAV ADPCM), `music` (→ `.mas`), `gfx`.
- [x] **P10 — Ekran wyboru kartridży** (kartridż systemowy w Lua; lekka wersja wg D49 —
  D52; nadpisywanie z karty i kopiowanie systemowych na kartę po 1.0)
  Wyjście z gry (menu pauzy) → powrót do listy na zapamiętaną pozycję (D14).
  Wg D27 / `docs/UX.md`: menu pauzy (START 0,5 s), kartridże systemowe w ROM z
  nadpisaniem z `sd:/litelua/system/`, tryb awaryjny (SELECT przy starcie), kopiowanie
  systemowych na kartę, biblioteka `ui.lua`. Już zrobione w P11 (D43): `sys.run("@nazwa")`
  z ROM, `sys.system`, powrót z gry do wywołującego, Y na liście i ekranie błędu.
  README ma opis (sekcja „System carts”) — uaktualnić, gdy będzie działać.
- [x] **P11 — Edytor kodu na DS** z klawiaturą ekranową (D42, D43), razem z
  minimalnym wycinkiem P10 (kartridże systemowe w ROM, `sys.system`, powrót z gry)
  Kod na górnym ekranie, klawiatura na dolnym; kolorowanie składni; przycisk „Edytuj” na
  ekranie błędu → plik i linia, dotknięcie ramki stosu (D13); sprawdzanie składni w tle
  (`load` bez uruchamiania); uruchomienie gry wg D14 wariant A (zapis buforów, powrót do
  pliku/linii/kursora).
- [x] **P11b — Pliki i pomoc w edytorze** (D44): usuwanie i zmiana nazw plików/folderów,
  pomoc (START): manual edytora i API z `docs/api` w ROM, pomoc kontekstowa.
- [x] **P11c — Opcje edytora i własne słowa** (D46): motywy kolorów (Soft dark domyślny,
  Light jak Notepad++, Classic), `words.lua` w kartridżu z własnymi słowami podpowiedzi,
  Word+ w pomocy.
- [x] **P11d — Zakładki plików w edytorze** (D47): do 5 otwartych plików, nazwy w górnym
  pasku, Y+lewo/prawo przełącza, Y+B zamyka.
- [x] **P11a — Podpowiedzi i pomoc w edytorze** (D45; pomoc już w P11b)
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
- [ ] **P13 — Edytor map** (wg D48 prawdopodobnie część zakładki Scena — P21)
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
- [ ] **P19 — Biblioteka `scene`** (D48): sceny z plików danych, prefaby, obiekty ze
  skryptami (`start`/`update`/`draw`, zdarzenia), przyczepienie (`parent` + przesunięcie),
  przejścia z maską „Loading” i zwalnianiem grafiki, grafika typów ładowana według kamery.
  Wbudowana (`require("scene")`), opis w pomocy i API, przykład + pomiar czasu masek na DSi.
- [ ] **P20 — Studio z zakładkami** (D48): `@code` → jeden kartridż systemowy z zakładkami
  (na start Kod i Pliki), bez zmian w działaniu edytora kodu.
- [ ] **P21 — Zakładka Scena** (D48): mapa kafelków z prawdziwym tilesetem, obiekty z
  prawdziwymi sprite'ami (symbole dla obiektów bez grafiki), prefaby, grupy, właściwości,
  „Edit script” → zakładka Kod, Run od wybranej sceny.
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
