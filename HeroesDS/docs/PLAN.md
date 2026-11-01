# HeroesDS — plan

Fanowska gra w stylu Heroes of Might and Magic IV na LiteLua (DS/DSi), na oryginalnych
zasobach gry (tylko do użytku prywatnego — H1). Dwa tryby:
- **mapa kontynentu** — prowincje, miasta, armie (jak w Imperial Glory),
- **walka** — jak w H4: dolny ekran = mapa walki, górny = animowane starcie dwóch jednostek
  w przeciwległych narożnikach — **zmienione decyzją H5**: walka na polu bitwy z małymi
  sprite'ami, bez zbliżenia.

## Gdzie skończyliśmy (notka dla nowego czatu, 2026-10-27)

**Przejście na 3DS (H13, 2026-11-01) — M3: mapa polityczna w pełnym 3D.**
`tools/make_m3.py` (ląd z `make_m2.generate`, ziarno 77): granice prowincji i stref
morskich jako wspólne łańcuchy z „noisy edges” (fraktalne ząbki jak na mapie rysowanej
ręcznie, bez przecięć). Każde podejście ma build w `3ds/builds/` (poza gitem;
`3ds\build.ps1 -tag <nazwa> -gen "<argumenty make_m3>"`, `run` = Azahar):
`m3a-smooth` (wygładzone granice, płyty lądu ze ściankami), `m3b-noisy` (fraktalne
granice w meshu, ~52 tys. trójkątów, ~12–16 ms na klatkę w Azaharze), `m3c-flat` (płaska
mapa = jeden prostokąt z teksturą 1024² z mipmapami, ~2,3 ms), `m3d` (kafle 1024²,
doczytywane w tle; `m3d-tiles2x2`, `m3d-big4x4`), **`m3e` (obecny): szczegóły wg
oddalenia** — `m3e-lod-2x2` (`-gen "--tiles 2"`; 80 regionów, 279 powiatów) i
`m3e-lod-big4x4` (`-gen "--size 144 --provinces 180 --tiles 4"`; 284 regiony, 1059
powiatów, 16 kafli). Prowincje lądu dzielone na powiaty (~12 komórek); linie powiatów
tylko na najdokładniejszych poziomach mipmap, prowincji na średnich, daleko samo
wybrzeże. Granice państw rysuje 3DS (paski, szerokość rośnie z oddaleniem, liczone
z właścicieli — zmienią się przy podbojach). Nazwy: państw z daleka (duże), prowincji,
powiatów z bliska; rozmiar wg odległości jak napis na mapie, nachodzące pomijane, też na
górnym ekranie. Kamera bez obrotu: L/R = kąt patrzenia (25–88°). Stuknięcie = powiat →
prowincja (opis: „prowincja - powiat”). Pod spodem tekstura przeglądowa; w pamięci do 6
kafli, doczytywane w wątku (zlib przez `vendor/miniz`). Azahar: 60 FPS; kafel 0,6–1,9 s
(do zmierzenia na konsoli). Format w `FORMATS.md`, testy `tests/test_make_m3.py`
(`pip install mapbox-earcut`). Dolny ekran — mapa, stuknięcie wybiera, przeciąganie
i gałka przesuwają, góra/dół zoom; górny — bliższy widok stereo i opis. **Na 3DS XL do
sprawdzenia** (pliki z `builds/` do `/3ds/` na karcie SD, Homebrew Launcher): czas
wczytania kafla, wolna pamięć, płynność. Do ustalenia: Lua na 3DS (H13). Dalej: rzeźba
terenu w teksturze, pionki armii i miast (modele 3D na płaskiej mapie).

**Dziś: mapa przygody (tor M).** Format `.h4c` rozpracowany (teren, przejścia, drogi,
wysokość, poziomy, obiekty z obszarem i wejściami) — `docs/FORMATS.md`, narzędzia
`tools/h4map.py`, `h4mapview.py` (podgląd PNG), `h4objects.py` (obiekty, przechodniość),
testy `tests/test_h4map.py`. W LiteLua **D58**: `quad` i `isogrid` (teren z wysokością w C,
~260 pól w 2,4 ms; w Lua 42 ms). Kartridż **`carts/m1`** (`tools/make_m1.py`): cała mapa
`obiekty.h4c` (teren z cieniowaniem, światło dopasowane do edytora; obiekty w stylu
stworzeń `test2`, 4 bpp, cień w obrazku, wczytywane przy ekranie z budżetem LRU) —
**sprawdzone na DSi: płynnie, wygląd ok**. W melonDS wczytanie zamku ~62 ms (drzewo ~13 ms);
na DSi użytkownik nie widział przycięcia. Mapy testowe użytkownika (`*.h4c` w HeroesDS)
są poza repo. Dalej: sekcja „Później” niżej (bohaterowie na mapie, animacje obiektów,
koszty ruchu, wersje zapasowe modeli, malowanie terenu na DS).

**Mapa polityczna (M2, decyzja użytkownika: mapa przygody jak w Imperial Glory —
prowincje, nie pola).** `tools/make_m2.py` generuje z ziarna wymyślony ląd (`--seed 77
--coast 1` domyślnie: postrzępione wybrzeże), prowincje (relaksacja Lloyda, granice na
grzbietach), strefy morskie bez właściciela, sąsiedztwo, nazwy i 6 państw (frakcje H4;
wyspy przez morze). `--cart` robi `carts/m2` bez grafiki z gry: dwie siatki `isogrid`
(pergamin z kolorami państw i atramentowymi granicami / rzeźba terenu, A), kolory z PC,
przekolorowanie jednej prowincji w Lua. Armie, floty wojenne (do 2 stref, przewóz armii)
i statki handlowe (`src/war.lua`): ruch po prowincjach, zajmowanie, „bitwa” na razie
liczebnością, Y = koniec tury, przeciwnicy stoją. Sprawdzone w melonDS, wysłane na DSi.
Dalej (do ustalenia z użytkownikiem): bitwa → kartridż walki H4, ruch przeciwników,
widok militarny, powiększenie prowincji (budowle, kopalnie), handel (dochód).
Dotyk w m2 (D59): stuknięcie w punkcie dociśnięcia, przewijanie po ruchu o 5 px,
przekolorowanie ~30 ms zamiast 145 ms; w melonDS 8/8 stuknięć — na DSi do sprawdzenia
(też przeciąganie) — użytkownik: „zaznaczanie działa idealnie”. Kierunek gry: H12 (miks
IG + H4, kolejność prac w uzupełnieniu H12). Zrobione: pas morza, łączenie cienkich
prowincji, ~37 mniejszych stref morskich. Granice stref morskich ciemniejsze i grubsze, mocniejsze
zaznaczenie — na DSi ok (2026-10-27). Następny krok: zasoby i kopalnie z miniaturami
H4 (stolice z zamkami) i dochód co tydzień.
**M2 w 3D (2026-10-29):** X przełącza mapę płaską / 3D (warstwa 3D LiteLua D60: L/R obrót,
B zoom, mgła; nazwy i armie w 2D przez `project3d`, stuknięcia przez `pick3d`). Sprawdzone
w melonDS, wysłane na DSi. Pomysły na 3D: `docs/IDEAS_3D.md` w LiteLua.
Ściąga z reguł i AI Imperial Glory (do wglądu, wypakowane lokalnie w `ref/ImperialGlory/`):
`docs/IMPERIAL_GLORY.md` — na końcu propozycje dla AI przeciwników i bitwy automatycznej.

**Walka (stan z 2026-10-26):**

**Stan:** tor A (grafika) do H2 włącznie; tor B: C1 (mechanika), C2 (projekt walki,
`docs/COMBAT.md`, zaakceptowany) i **C3 (silnik walki w czystym Lua) zamknięte**.
`HeroesDS/combat/`: `num` (float32 jak oryginał), `rng`, `grid` (pole, droga, strefy
kontroli), `stats`, `damage`, `battle` (rundy, kolejka, akcje, zdarzenia, powtórki —
jedyne API dla ekranu), `magic` (rdzeń czarów), `abilities` (zdolności jako hooki),
`heroes` (bohater, artefakty, premie armii, `heroes.build`), `casting` (czary), `ai`
(przeciwnik komputerowy). Szczegóły i podział C3a–C3f: `COMBAT.md` §11. Decyzje H6–H10
(ekrany, dzielenie obrony, skala pola + lupa, zabity nie oddaje, reguły bohatera z opisów).

**C4b (bitwa na DS ze stubami grafiki) — zrobione.** Kartridż `carts/c4`
(`python HeroesDS/tools/make_c4.py`; wspólne kroki w `tools/cartkit.py`): `src/view.lua`
(skala 3/16, romby oddziałów z liczebnością, kropki zasięgu co 3 pola, droga i obrys celu),
`src/setup.lua` (armie testowe z ziarna jak w c4bench), `main.lua` (tura gracza: dotyk
oddziału wroga = atak / strzał z podglądem obrażeń i odwetu, dotyk ziemi = ruch na najbliższe
osiągalne miejsce, drugi dotyk lub A = wykonaj, B = anuluj; przyciski Cz(ekaj) / Ob(rona) po
lewej; komputer gra stroną 1 w korutynie z klepsydrą; Y = komputer gra też za gracza; górny
ekran: runda, aktywny oddział, wybór, kolejka, dziennik po polsku). Sprawdzone w melonDS:
podgląd, atak, ruch, autobitwa do końca.

**C4c (sterowanie i pokaz zdarzeń) — zrobione.** W `carts/c4`: lupa ×2 na L/R wokół
rysika / aktywnego oddziału (rysik przy krawędzi przewija; `view.set_camera`), krzyżak
przesuwa kursor, A dotyka w jego miejscu; Księga czarów (przycisk Ks po prawej, lista na
dolnym ekranie, cel wg `casting.aim`: oddział / pole / oba / dwa oddziały / oddział i
miejsce, podświetlone cele z `casting.check`, drugi dotyk = rzuć); zdarzenia pokazywane po
kolei (oddział idzie po drodze, liczby obrażeń / leczenia nad celem, krótkie pauzy).
Test `tests/c4_test.lua` (lupa, atrapy API LiteLua): tury gracza dotykiem, Magiczna Strzała
z Księgi, potem komputer kończy bitwę.

**Poprawki po teście na DSi (2026-10-26):** oddział stykający się z wrogiem atakuje z
miejsca (pole ataku = własne, gdy się da); dotyk ziemi już nigdy nie zatwierdza — rysik
można przeciągać, wybór idzie za nim; zatwierdza przycisk OK (prawy dolny róg) lub A,
a drugi dotyk tego samego wroga / celu czaru. Szczyt pamięci Lua w grze na DSi 1,57 MB
(wyniki `flood` po 2×41 KB czekają na GC) — pilnować.

**H3/H4 w C4 (2026-10-26):** grafika z gry na polu: `make_c4.py --gfx` (74 stwory + 2
bohaterów × wait/walk/melee/flinch/die × 8 kierunków, styl `test2` użytkownika, skala 3/16,
tło pola = kolor ziemi stylu), `--fx` (`tools/h4fx.py`: pociski `missile.*` wg tabeli
homm4-mac, 111 efektów `animation.spell.*` z kotwicą z pliku, 408 dźwięków jako WAV 8-bit
11 kHz, `data/actors.lua` — wysokości i pociski). Kartridż jako jeden `c4.lcart` (~17 MB,
bez kompresji). `src/sprites.lua` (leniwe wczytywanie, zwalnianie po ~10 s), `src/fx.lua`
(dźwięki). Pokaz: cios w klatce trafienia, pocisk leci do celu, efekt czaru nad celami,
dźwięki ciosu / strzału / wzdrygnięcia / śmierci / czaru (potwierdzone nagraniem wyjścia
melonDS, loopback `soundcard`); zabity gra tylko śmierć i znika.

**Menu walki testowej (tymczasowe):** `src/menu.lua` przed bitwą i po niej: dla każdej strony
bohater (brak / typ szkoła × rola — 17 modeli `hero.<szkoła>_<rola>_male`, poziom 1–30, do 6
artefaktów z 248) i do 6 oddziałów (stwór z listy 74, liczba krokiem 1/10/100); górny ekran:
statystyki stwora / działanie artefaktu; zapis w `save/army.txt`. `src/setup.lua`: typ
bohatera → umiejętności (rosną z poziomem) i czary szkoły; bitwa przez `heroes.build`
(premie armii, artefakty). Księga czarów przewijana (mag zna do ~40 czarów).

**Muzyka i drobiazgi (2026-10-26):** `make_c4.py --music` (OST z `homm4_ost/`, MP3 przez
`miniaudio`, MIT): Battle I i II jako `music/battle<n>.wav` (16-bit mono 16 kHz, ~17 MB,
`--music-all` = sześć), Win / Lose na koniec bitwy; głośność muzyki 0,6. Dźwięk chodu w
pętli podczas marszu. Liczebność nad głową, zaznaczenie = pulsujący `tint` (bez rombów),
cel ruchu = krzyżyk, zasięg = kropki na granicy, oddział zwraca się do celu ataku.

**⚠ Przed pushem:** dźwięki z gry (`carts/c4/sfx/*.wav`) weszły do lokalnych commitów
9b9cdc3, d63be51, bd58785 (teraz w `.gitignore` i zdjęte z repo). Trzeba je usunąć z
historii (przepisanie lokalnych commitów — za zgodą użytkownika), inaczej push je opublikuje.

**Następny krok:** dalsza gra na DSi i poprawki z rozgrywki; potem H3 (konwerter grafiki) i H4 (pole z prawdziwymi sprite'ami) — albo
decyzja o innym polu walki, jeśli sterowanie na drobnej siatce się nie sprawdzi.

**C4a (pomiar i przyspieszenie) — zrobione.** Kartridż `carts/c4bench`
(`python HeroesDS/tools/make_c4bench.py`: silnik + reguły bez opisów, wynik PC do
`data/pc.lua`, kopia na kartę melonDS; na DSi przez FTP). Szukanie drogi w C przez API
LiteLua `pathgrid` / `grid:flood` (D57), gdy jest (`grid.native`); Lua zostaje wzorcem (PC,
testy). melonDS (DS), 12 bitew komputer–komputer: szukanie 3,2 s → 37 ms, tura komputera
średnio 73 ms, najgorsza 0,6 s (diabeł z teleportem), najdłuższy kawałek bez `grid.tick`
0,19 s (jedno wywołanie C — klepsydra może lekko szarpnąć); C = Lua (0 różnic), 12/12 bitew =
PC bit w bit; pamięć Lua w bitwach do ~1,45 MB (śmieci przed GC). DSi (pierwsza wersja C):
szukanie 63 ms, tura 83 ms — DSi tylko ~25% szybsze od melonDS w trybie DS. Wczytanie: kod
0,65 s, reguły 0,36 s, kształt pola 0,6 s (raz). Przyspieszenia w Lua: `Field:fits` z sum
prefiksowych, koszty całkowite ×32, lot bez ponownego szukania, `attack_positions` / Iskry /
`free_spot` / teleport bez skanu całego pola po oddziałach, `Field:changed()` po zmianie pól.

**Przeczytaj najpierw:** `docs/DECISIONS.md` (H1–H10), `docs/COMBAT.md` (architektura walki, §11 — stan C3),
`docs/MECHANICS.md` (zasady walki 1:1, §1–14), `docs/DS_GRAPHICS.md` (pamięć wideo, style,
pomiary DSi), `docs/FORMATS.md`.

**Dane z gry** (lokalnie, poza repo — `Data/` i `extracted/` są w `.gitignore`):
- `python HeroesDS/tools/make_rules.py` → `extracted/rules/creatures.lua` (74 jednostki),
  `artifacts.lua` (248), `spells.lua` (193) — polskie nazwy (gra GOG po polsku, cp1250).
- Grafika: `tools/h4atlas.py --style test1` (styl użytkownika z `tools/styles.json`),
  `tools/style_tuner.py` (okno do strojenia stylu), `tools/h4d.py` (podgląd PNG).
- `ref/homm4-mac/` — klon Anbrose/homm4-mac (MIT): silnik H4 w Swifcie z adresami exe;
  źródło reguł. Jeśli brak: `git clone --depth 1 https://github.com/Anbrose/homm4-mac.git ref/homm4-mac`.
  Tylko czytamy (nie uruchamiamy pobranego kodu — blokada auto mode); tabele zbudowane
  w kodzie exe są już przeniesione do `tools/exe_tables.py` i `tools/creature_abilities.py`.

**Testy:** `python -m unittest discover -s HeroesDS/tests` (38 testów Pythona, w tym `test_combat`: 17 + 15 + 18 + 7 + 15 + 7 przypadków w Lua przez `lupa`; dane syntetyczne, `real_creatures` także na `extracted/rules/creatures.lua`, gdy jest).

**Konsola / emulator:** kartridże HeroesDS w `HeroesDS/carts/` (grafika generowana lokalnie);
melonDS: `tools/melon.py` (w skrypcie `tap 28 178` = Play w launcherze — klawisze bywają
gubione); DSi: FTP `192.168.1.86:5000` (DHCP — może się zmienić), `curl --ftp-create-dirs -T`
do `litelua/carts/<cart>/`, log `litelua/log.txt`.

**Styl pracy:** małe kroki — punkt = test na PC + lokalny commit + aktualizacja tej sekcji;
push tylko na prośbę. Po polsku. Edycje z `\` tylko narzędziem Edit lub skryptem z Write
(heredoc w bashu psuje znaki ucieczki).

## Co już wiemy
- `heroes4.h4r` (600 MB) to główne zasoby: `actor_sequence` (11285 animacji),
  `adv_object` (2767), `combat_object` (1048), `sound` (990), `layers` (656, interfejs),
  `combat_actor` (139), `adv_actor` (137), `terrain`, `battlefield_preset_map`.
  `x2*.h4r`, `storm*.h4r`, `updates.h4r` — dodatki i poprawki (override: nowsze wersje).
- Animacje jednostki (np. `bandit`): mapa przygody = `actor_sequence.bandit.<anim>.<kier>`
  (stand, walk, prewalk, postwalk, attack, fidget; 8 kierunków); walka =
  `actor_sequence.bandit.combat.<anim>.<kier>` (base_frame, wait, fidget, walk, melee,
  melee_up, flinch, die, …; część tylko w 4 kierunkach ukośnych).
  `combat_actor.<x>` / `adv_actor.<x>` mówią, która sekwencja gra w którym z 8 kierunków
  — brakujący kierunek wskazuje najbliższy narysowany (bandit die: e → se), bez odbić.
- Czas klatek: fps z `combat_actor`/`adv_actor` (walka zwykle 9–10, wait 5; mapa 10).
- Klatki animacji bywają współdzielone: nazwa obrazu „frame 002 004” = obraz klatek 2 i 4
  (cienie tak samo: „shadow 002 004”). Klatki 8-bit z paletą ≤255 kolorów + alfa 4 bity,
  cienie 1 kolor + alfa. Pozycje na płótnie 800×600, origin zwykle (−361, −347).
- Rozmiary: bandyta na mapie ~52×45 px/klatka, w walce do ~205×173 (cały ruch ciosu),
  pojedyncza klatka ~120×100 → na DS trzeba skalować (H3).
- Źródła i licencje: H3 w `DECISIONS.md`.

## Punkty

### H0 — Fundament ✅
Folder w repo LuaDS (H1), wykluczenia w `.gitignore`, plan i decyzje.

### Tor A — grafika
- **H1 — Formaty ✅** Wynik: `docs/FORMATS.md`.
  - **H1a ✅** czytnik `.h4r` (gzip w środku, aliasy) + testy.
  - **H1b ✅** dekoder obrazów `.h4d` → PNG (klatki, cienie, alfa) + testy.
  - **H1c ✅** `combat_actor` / `adv_actor`: animacje, fps, kierunki, rozmiar, dystanse.
  - **H1d ✅** `docs/FORMATS.md` — opis formatów własnymi słowami.
- **H2 — Możliwości LiteLua ✅** (H2a analiza, H2b/H2c pomiary melonDS i DSi, trzy style, H2d tuner stylu → `docs/DS_GRAPHICS.md`; decyzje H4, H5) Sprite'y, palety, rozmiary tekstur, budżet VRAM/RAM na
  dwie duże animacje na górnym ekranie, ładowanie/zwalnianie w locie. Braki → osobny punkt
  w planie LiteLua (`docs/PLAN.md` w głównym repo).
- **H3 — Konwerter PC → LiteLua.** Profile: *mapa* (małe sprite'y, mało klatek) i *walka*
  (większe klatki, skala pod 256×192). Paleta, atlas klatek, meta `.lua` (animacje,
  kierunki, offsety, czasy).
- **H4 — Makieta pola bitwy (kartridż).** 14 oddziałów w stylu `test1`, animacje,
  dociąganie akcji, zaznaczanie celu (H5). (Wcześniej: zbliżenie dwóch jednostek — zrobione
  w H2b i porzucone.)

### Tor B — walka (bez grafiki)
- **C1 — Mechanika ✅** Wynik: `docs/MECHANICS.md` (C1a rdzeń, C1b-1 dane jednostek,
  C1b-2 zdolności, C1b-3 bohater i artefakty, C1c czary) + generator `tools/make_rules.py`.
- **C2 — Projekt systemu walki ✅** Wynik: `docs/COMBAT.md`, decyzje H6–H8.
- **C3 — Silnik walki w czystym Lua ✅** + testy na PC: C3a wzory i siatka, C3b bitwa i akcje,
  C3c zdolności, C3d bohater i artefakty, C3e czary, C3f prosty AI (`COMBAT.md` §11).
- **C4 — Podpięcie do kartridża** ze stubami grafiki (pole bitwy + ekran informacji, H5).

### Później
Tryb mapy kontynentu — osobny plan, gdy walka będzie stała. **Najpierw przeczytać
sekcję „Ważne na później: mapa przygody i teren” w `docs/FORMATS.md`** (teren 2.5D
z mapą wysokości, tekstury rombów, format `.h4c`, test z dwiema mapami z edytora).

Stan na 2026-10-27: **teren `.h4c` rozpracowany** — `tools/h4map.py` (czytnik: pola,
nakładki, drogi, wysokości, poziomy), `tools/h4mapview.py` (podgląd PNG z teksturami
gry, przejściami, drogami, wysokością i światłem), `tests/test_h4map.py`. **Teren na DS (M1) — działa w melonDS, na konsoli jeszcze nie:** kartridż `carts/m1`
(`python HeroesDS/tools/make_m1.py`: wycinek mapy, pola złożone na PC i „wyprostowane”
do kwadratów 16×16 z ramką, arkusz 256 kolorów ~62 KB, wysokości i jasność narożników)
rysowany przez `isogrid` z LiteLua (D58): ~260 pól w 2,4 ms (w Lua przez `quad` 42 ms).
Klawisze: rysik/krzyżak przewijanie, A wysokość, X światło, L/R skala pagórków, Y C/Lua.
Kolejność dalej:
0. ~~M1 na DSi~~ — zrobione: płynnie, cień 0,4 (B zmienia), skala wysokości 0,5.
   Obiekty w M1: styl stworzeń, jeden PNG na model, pamięć podręczna z budżetem (SELECT
   96/20 KB). Do zrobienia: animacje obiektów (klatki to małe kawałki na bazie — tanie),
   wersje zapasowe modeli (LOD) i licznik budżetu w edytorze na DS, ew. szybszy format
   niż PNG, jeśli duże modele zaczną przycinać.
1. (tylko do malowania na DS) automat przejść i kształty pędzli — test:
   mapa `pedzle.h4c` z czterema kropkami piasku na trawie, po jednej każdym pędzlem;
   do tego składanie kwadratów pola na DS (teren + nakładki przez maski) i podmiana
   klatki w pamięci wideo — potrzebny zapis pikseli do obrazka w LiteLua (nowe API);
2. **obiekty na mapie** — częściowo (2026-10-27, `obiekty.h4c`): pozycja, model, typ
   (`h4map.find_objects`), pola zajęte i wejścia z modelu (`tools/h4objects.py`), zgodne z
   podglądem blokad edytora. Zostało: bohaterowie (zapisani inaczej), dane miast/kopalń
   (garnizon), obrazki obiektów na mapie (podgląd PC i DS);
3. **przechodniość**: w pliku jej nie ma, liczymy z terenu (woda/rzeka blokuje, także
   pod drogą) i obiektów (pkt 2) — `h4objects.passability` (zablokowane / woda / pola
   wejścia); zostały koszty ruchu terenu i droga = tańszy ruch (bajt drogi pola).
