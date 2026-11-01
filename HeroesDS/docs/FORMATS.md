# Formaty plików Heroes IV

Opis formatów zasobów gry (wersja GOG), odczytany z danych i potwierdzony narzędziami
z `tools/`. Wszystkie liczby są little endian. „str16” = `u16 długość` + bajty latin-1.
Znaczenia części pól ustalił autor Anbrose/homm4-mac (MIT) z `heroes4.exe` — tu są
zapisane naszymi słowami i sprawdzone na naszych plikach (H3).

| Format | Narzędzie | Sprawdzone na |
|---|---|---|
| archiwum `.h4r` | `tools/h4r.py` | 8 archiwów, 21381 plików |
| obrazy `.h4d` (actor_sequence) | `tools/h4d.py` | 14449 sekwencji |
| `combat_actor` / `adv_actor` | `tools/h4actor.py` | 168 + 180 plików, co do bajtu |

## Archiwum `.h4r`

```
nagłówek   "H4R\x05", u32 offset_katalogu
dane       pliki jeden za drugim, każdy jako strumień gzip
katalog    u32 liczba, potem wpisy:
             u32 offset, u32 rozmiar_spakowany, u32 rozmiar, u32 czas
             str16 nazwa, str16 ścieżka_źródłowa, str16 alias, u32 (zawsze 3)
```

- Za nagłówkiem leży starsza kopia katalogu — prawdziwy jest ten pod `offset_katalogu`
  (na końcu pliku).
- **Alias**: wpis z niepustym aliasem nie ma danych (offset i rozmiar spakowany = 0),
  oznacza plik o nazwie z aliasu (`layers.buy_button.h4d` → `layers.button.buy.h4d`).
- Nazwy plików mają postać `kategoria.reszta.h4d`, np. `actor_sequence.bandit.combat.melee.sw.h4d`.
  Wielkość liter bywa różna — porównujemy bez rozróżniania.
- `*_override.h4r`, `x2.h4r`, `storm.h4r`, `updates.h4r` — dodatki i poprawki; plik
  o tej samej nazwie w archiwum „override” zastępuje starszy.
- Uszkodzone w danych GOG: alias `layers.sample_cursor.h4d` (cel nie istnieje),
  `actor_sequence.hero.spazz_sword.combat.death.ne.h4d` w `x2_override.h4r` (zły CRC gzip).

Zawartość `heroes4.h4r` (kategorie): `actor_sequence` 11285, `adv_object` 2767,
`combat_object` 1048, `sound` 990, `layers` 656 (interfejs), `animation` 325,
`combat_actor` 139, `adv_actor` 137, `terrain` 61, `battlefield_preset_map` 24, `font` 21.

## Obrazy `.h4d`

Wspólny rekord obrazu dla `actor_sequence`, `animation`, `adv_object` i `combat_object`
(różnią się tylko nagłówkiem i końcówką pliku). Rekordy leżą jeden za drugim.

```
paleta   u16 n, u16 1, u16 ?, u8 0, (n-1) × BGR     indeks 0 = przezroczysty
obraz    str16 nazwa                                   "frame 002 004", "shadow 001", "base_frame"
         u8 rodzaj                                     4 = pełny, 1 = delta, 0 = pusty
         u32 lewo, góra, prawo, dół                    prostokąt na płótnie
         (dół-góra) × (u16 x0, u16 x1, u32 offset)    nieprzezroczysty odcinek wiersza
         piksele                                       1 bajt (indeks palety) na piksel odcinków
         rodzaj 4: alfa                                4 bity na piksel (młodsze pierwsze), 0..15
                   podsumowanie                        ceil((piksele+4)/64) półbajtów — pomijamy
```

- Klatki: paleta do 255 kolorów + alfa 4-bitowa (krawędzie, smugi broni). Cienie: paleta
  z 1 kolorem (czarny) + alfa — sam kształt półprzezroczystości.
- Pole `?` w palecie: 24 lub 16 w klatkach, 8 w cieniach. **To nie fps** (fps jest
  w `combat_actor`/`adv_actor`); znaczenie nieznane, nie jest potrzebne.
- Rodzaj 1 (delta): same indeksy bez alfy, rysowane nieprzezroczyście na `base_frame`
  (animowane miasta). Rodzaj 0: pusty obraz.
- Podsumowanie alfy to zgrubna alfa na bloki 64 pikseli (gra pomija nim puste bloki).

### `actor_sequence` — jedna animacja w jednym kierunku

```
nagłówek   u16 2, u16 typ, [typ 3: u16 1, i32 -1], u16 liczba_obrazów
obrazy     liczba_obrazów × rekord obrazu
końcówka   i32 origin_x, i32 origin_y               zwykle (-361, -347)
           u16 n, n × (str16 nazwa, u16 typ)       powiązania, np. ("combat_actor.bandit", 2)
```

- Nazwa: `actor_sequence.<jednostka>.<animacja>.<kierunek>` (mapa przygody) albo
  `actor_sequence.<jednostka>.combat.<animacja>.<kierunek>` (walka).
- **Numery w nazwie obrazu to numery klatek**, w których obraz występuje:
  „frame 002 004” = klatki 2 i 4; „shadow 002 004” = cień tych klatek. Liczba klatek =
  największy numer. Klatka = cień + `base_frame` (jeśli jest) + obraz klatki.
- Prostokąty są na wspólnym płótnie (800×600 dla walki); wszystkie klatki sekwencji
  mają ten sam układ współrzędnych, więc animacja nie „skacze”.
- Typ 3 (4449 plików) różni się tylko stałymi 6 bajtami w nagłówku.
- Rozmiary (bandyta): na mapie ~52×45 px na klatkę; w walce pojedyncza klatka do
  ~120×160, a cały cios zajmuje ~205×173.

## `combat_actor.<jednostka>.h4d` — jednostka w walce

```
u16 wersja                           5 albo 6 w danych
u8  rozmiar                          bok kwadratu na siatce walki (1..7; bandyta 4, smok 7)
u8  wysokość                         w jednostkach świata (efekty i cele pocisków)
u16 prewalk, walk, postwalk          dystans pokonywany przez każdą fazę chodu (16 j. = 1 pole)
[v6] 8 × (i32 x, y, z)               punkt wylotu pocisku dla każdego kierunku
u16 liczba_animacji
    str16 nazwa                      block, cast_spell, die, fidget, flinch, melee,
                                     melee_down, melee_up, postwalk, prewalk, ranged,
                                     base_frame, wait, walk (+ full_walk, wait_and_base, stand)
    u8 fps
    [v5+] u8 klatka_trafienia        dla ataków (bandyta melee 6, melee_up 3, ranged 1)
    8 × str16 sekwencja              kierunki ne, e, se, s, sw, w, nw, n; pusta = brak animacji
i32 dx, dy                           przesunięcie rysowania (dodawane do prostokątów klatek)
```

- **Kierunki bez grafiki**: animacja narysowana w 4 kierunkach ukośnych wpisuje dla
  pozostałych najbliższy narysowany (bandyta `die`: e → se, s → sw, w → sw, n → ne).
  Gra nie odbija grafiki w lustrze.
- **Klatka trafienia**: cios ląduje po `klatka_trafienia × (1/fps)` od początku animacji
  (bandyta: 6/9 s). Ma znaczenie dla mechaniki — przy jednoczesnej wymianie ciosów
  oddział zabity przed swoją klatką trafienia nie zadaje obrażeń (C1).
- Typowe fps: 9–10 (wait 5).
- Bohaterowie: `combat_actor.hero.<strona>_<fighter|archer|mage>_<płeć>`; ich sekwencje
  mają inne nazwy (199 odwołań nie trafia w nazwy z archiwów — do zbadania przy H3).
  Kilka jednostek z dodatków odwołuje się do nieistniejących sekwencji.
- Są też `combat_actor.missile.<x>` (pociski) i `combat_actor.spells.<x>` (efekty czarów).

## `adv_actor.<jednostka>.h4d` — jednostka na mapie przygody

```
u16 wersja (3), u8 głębia (1)
u16 prewalk, walk, postwalk          dystanse (prosty krok = 32)
u16 liczba_animacji
    str16 nazwa                      wait, fidget, prewalk, walk, postwalk, attack
    u8 fps                           zwykle 10 (wait 5, fidget 4)
    8 × str16 sekwencja              kierunki jak wyżej; na mapie wszystkie 8 narysowane
i32 x, y                             przesunięcie modelu
i32 x, y                             punkt flagi właściciela
```

## Co dalej (poza H1)

Nie rozpracowane, bo na razie niepotrzebne: `animation` (efekty czarów, flagi),
`adv_object` / `combat_object` (obiekty mapy i przeszkody — ten sam rekord obrazu,
inny nagłówek), `combat_header_table_cache` (lista przeszkód), `battlefield_preset_map`,
`terrain`, `sound` (nagłówek opisany w AKuHAK/mh4 `header_info.txt`), tabele (`table`).
Wzory dla nich są w `ref/homm4-mac` (`tools/*.py`, `native/Sources/H4Engine/*.swift`).

## ⚠ Ważne na później: mapa przygody i teren (wstępne, niesprawdzone w plikach)

Ustalenia z 2026-10-26 — do trybu mapy kontynentu i ewentualnie terenu walki.

- **Teren to 2.5D, nie 3D.** Edytor podnosi teren (pagórki ze światłem i cieniem), ale
  nie ma tu modeli 3D. Najpewniej: **mapa wysokości** (wysokość w narożnikach pól) +
  **płaska tekstura** terenu wyginana na podniesionych narożnikach + **cieniowanie z
  nachylenia** stoku. Kamera stała; jednostki i obiekty to sprite'y stawiane na wysokości pola.
- **Tekstury terenu**: `terrain.<rodzaj>.<a>.<b>.h4d` — 100 rombów 64×32 (paleta 256,
  RLE), razem jedna większa łata terenu (10 rzędów po 10, przesunięte co drugi), żeby
  teren się nie powtarzał. Opis: `ref/homm4-mac/tools/h4terrain.py`.
- **Plik mapy** `.h4c`: `"H4CAMPAIGN"` + gzip; siatka 76/152/228/304, 1–2 poziomy
  (powierzchnia/podziemia — to nie wysokość). Pole: u8 rodzaj (19 terenów), u8 wariant,
  **5 nieznanych bajtów**, nakładki przejść terenu (maski `transition.Transitions`),
  drogi. Opis: `ref/homm4-mac/tools/h4map.py` (niepełny).
- **Wysokość — sprawdzone 2026-10-27** (mapy testowe `plaska mapa.h4c` / `mapa ze
  wzniesieniem.h4c`, 76×76, bez obiektów; po rozpakowaniu oba po 35 918 B, różnią się
  tylko w 309 bajtach): wysokość **nie** siedzi w 5 nieznanych bajtach pola. Zaraz po
  polach terenu jest osobna **siatka wysokości: u8 na narożnik pola**, narożniki rombu
  mapy w kolejności wierszami (r, potem c), 3117 bajtów dla 76 (= liczba różnych
  narożników pól rombu; wiersze 3, 5, 7, … 77 … 7, 5, 3). Płaska mapa = same zera;
  pagórek z edytora to gładki kopiec, szczyt 218, stoki 6–16 na narożnik. Rzut: ekran
  x = (c − r)·32, y = (c + r)·16 − wysokość·K. Położenie potwierdzone zrzutem z edytora
  (lewy górny róg mapy, podniesiona górna krawędź). Skala z sylwetki krawędzi na zrzucie:
  **K ≈ 1 piksel na jednostkę** (przybliżenie ±20%, zrzut zapewne ze skalowaniem
  Windows 125%). Zakres: pełne 0–255; pędzel podnoszony dalej daje płaskowyż 255
  (mapa `max poziom.h4c`). **Dwa poziomy** (`podziemia.h4c`, 152×152): najpierw pola
  poziomu 0, potem pola poziomu 1 (tam rodzaj 8 = podziemia), dopiero potem siatka
  wysokości poziomu 0 i siatka poziomu 1 (po 12 009 bajtów dla 152; liczba narożników
  rombu, tak jak 3117 dla 76) — każdy poziom ma własną wysokość. Uwaga:
  `h4map.find_terrain` na pustej mapie łapie złe przesunięcie (powtarzalny wzór) — w tej
  mapie pola zaczynają się od bajtu 197, każde 11 B (`01 00 | 5×00 | 08 00 | 00 | 00`).
- **Przejścia terenu — sprawdzone 2026-10-27** (`malowanie.h4c`, czytnik
  `tools/h4map.py`, podgląd `tools/h4mapview.py`, test `tests/test_h4map.py`). 5 bajtów
  pola to zawsze zera. Nakładka = inny teren rysowany przez maskę nr 0–92; kod maski to
  cztery cyfry 0–4 = jak daleko kształt sięga ku rogom E, S, W, N pola (rogi rombu na
  ekranie). Ostatni bajt nakładki to **kolejność rysowania** (0–19; drogi 10–14, więc
  teren rysowany po drodze nadgryza jej brzeg). Zestaw masek wg `MapScene.swift`
  z homm4-mac: ląd na lądzie `land 1–3`, woda na wodzie `water 1–2`, **woda na polu lądu
  `water_to_land 1–3`, ląd na polu wody `land_to_water 1–3`** (miękka alfa 4 bity);
  wariant 1–3 z położenia: `(r·3 + c·5) mod 3 + 1`. Edytor zapisuje przejście po obu
  stronach granicy — tylko to przypisanie daje gradienty, które się spotykają
  (odwrotne = ostre linie wzdłuż krawędzi pól, sprawdzone). Bagno liczę jak wodę
  (miękki brzeg jak w edytorze — ustalone z obrazu, nie z kodu gry).
  **Drogi** (`droga i rzeka.h4c`): 1. z „5 nieznanych bajtów” pola = **typ drogi pola**
  (0 brak, 1 żwir, 2 ziemia, 3 bruk); takie pole jest drogą — bez kawałków drogi cała
  jest drogą. Kawałek drogi: rodzaj 1–3 = pobocze tego typu (pole obok, maska `road 1`),
  0 = środek drogi (maska odwrócona: w masce widać teren). Rzeka (typ 9) to zwykły teren
  z przejściami. **Przechodniości nie ma w pliku**: edytor (podgląd „kolizji”) liczy ją
  z terenu — rzeka/woda blokuje nawet pod drogą — i z obiektów. Pozostałe 4 bajty pola
  wciąż zera. Krawędziowe piksele kolumn masek i
  kafelków trzeba rozciągnąć na zewnątrz, inaczej na krawędziach pól wychodzą kropkowane
  linie. **Światło** do cieniowania stoków: kierunek (wiersz 0, kolumna +1) — jaśniejsze
  stoki opadające ku kolumnie +, czyli w prawo-dół ekranu; słońce z prawej (cień drzewa
  pada w lewo). Dopasowane do zrzutu z edytora (`droga i rzeka.h4c` z pagórkiem, skala
  zrzutu 1,25, korelacja jasności 0,81 przy 90°; pierwsze ustawienie „na oko” (1, −1)
  było prawie odwrotne). Siła: ~1,1 × (nachylenie / 128) w jasności.
- **Obiekty — 2026-10-27** (`obiekty.h4c`, `tools/h4map.py` `find_objects`, `tools/h4objects.py`):
  rekord obiektu = i32 wiersz, i32 kolumna, u8 poziom, u32 0, nazwa modelu
  (`adv_object.<nazwa>.h4d`), u16 0, 3 × (u16 id, tekst): typ / podtyp / teren lub kierunek,
  potem dane zależne od typu (miasta i kopalnie: sloty garnizonu „seq”; dekoracje nic).
  Szukane po nazwach modeli z archiwum (ciała rekordów jeszcze nieodczytane). Model ma
  w nagłówku obszar w×h, maskę pól zajętych (bit i = pole (wiersz + i mod w, kolumna +
  i div w)) i maski krawędzi wejścia (brama miasta, wejście kopalni) → pola wejścia.
  Przykład: zamek 6×6 cały zajęty, brama 2 pola po stronie „wiersz +”; kopalnia złota 1×2;
  drzewa 1 pole. Bohater nie jest modelem `adv_object` — zapisany inaczej (do zrobienia).
  **Edytor spłaszcza teren pod dużymi obiektami** (obserwacja użytkownika) i zapisuje już
  spłaszczone wysokości — czytnik nic nie poprawia; własny edytor na DS musiałby to robić.
- **Na DS**: LiteLua rysuje przez sprzętowe 3D (D5, gl2d), więc teren z wysokością da się
  narysować jako siatkę z teksturą i jasnością w wierzchołkach (cieniowanie prawie za
  darmo). Alternatywa: prerender mapy na PC do płaskich obrazków (dużo pamięci).
  Romby 64×32 trzeba zmniejszyć (np. 32×16). Decyzja przy trybie mapy.

## `map3d.bin` + kafle mapy — mapa polityczna 3D dla 3DS (H13, nasz format)

Robi je `tools/make_m3.py`, czyta `3ds/source/main.c` (`romfs:/`). Mapa jest płaska
(płaszczyzna y = 0): tekstury z wszystkimi detalami — `tiles × tiles` kafli i jedna
tekstura całej mapy (przegląd, pod spodem i na oddalenie); dokładne kształty regionów
służą tylko do podświetlenia wybranego. Little-endian, sekcje bez przerw, każda wyrównana
do 4 bajtów. Współrzędne: komórka siatki M2 = 1×1, środek mapy w (0, 0), x = kolumna,
z = wiersz (północ = −z).

`map3d.bin` (wersja 6):
```
nagłówek (32 B)
  char[4] "HM3D"; u16 wersja = 6; u16 nregions; u16 nland; u16 nfactions
  u32 nverts; u32 nidx; u32 tex (bok tekstury, 1024); f32 world (szerokość mapy = kolumny)
  u16 tiles (kafli na bok); u16 ncounties
nfactions × 20 B:  u8 r, g, b, 0; char[16] nazwa
nregions × 80 B (region = prowincja, strefa morska albo ląd bez prowincji):
  i16 id (numer z M2; -1 = ląd bez prowincji); i8 rodzaj (0 ląd, 1 morze, 2 ląd bez
  prowincji); i8 właściciel (frakcja, -1 brak); u8 liczba sąsiadów; 3 × 0
  char[24] nazwa
  f32 cx, cz (stolica / środek strefy: napis); f32 x0, z0, x1, z1 (prostokąt otaczający)
  u32 vstart, vcount (wierzchołki regionu); u32 istart, icount (indeksy);
  u32 itop (pierwsze itop indeksów: dokładny wierzch; reszta: pas obrysu wewnątrz
  granicy, szeroki 0,3); u32 0
ncounties × 52 B (powiat; morze i ląd bez prowincji = jeden powiat):
  u16 region (indeks w tabeli regionów); 2 × 0; char[20] nazwa (powiat jedyny w
  prowincji ma jej nazwę); f32 cx, cz (napis); u32 vstart, vcount, istart, icount, itop
  (dokładny kształt jak u regionu, obrys 0,18; vcount = 0: powiat jedyny w prowincji,
  nie do zaznaczenia)
i16 × Σ sąsiadów     listy sąsiadów regionów po kolei (id), dopełnione do 4 B
nverts × 16 B        f32 x, y (= 0), z, 1 — kształty regionów, potem powiatów
nidx × u16           trójkąty, indeksy względem vstart kształtu (< 65536), dopełnione do 4 B
u32 nborders; u32 nlineverts
nborders × 12 B      granica między dwoma regionami — ląd, wybrzeże, strefy morskie (od M3r;
                     wcześniej tylko ląd–ląd) — odcinek między węzłami:
                     u16 a, b (regiony po bokach); u32 start, count (wierzchołki paska)
nlineverts × 16 B    f32 x, z, nx, nz: punkty granic jako pas trójkątów (triangle strip),
                     każdy punkt dwa razy — z normalną i z odwróconą; 3DS przesuwa punkt
                     o normalną × szerokość (rysuje granice państw tam, gdzie po obu
                     stronach ląd o różnych właścicielach, i obrys zaznaczonego regionu)
```

Tekstury: `overview.bin` (cała mapa) i `tiles/<kolumna>_<wiersz>.bin` (kafel `i, j`
obejmuje x od `i·world/tiles` do `(i+1)·world/tiles` od zachodniego brzegu, z tak samo
od północnego). Każdy plik:
```
char[4] "HT01"
u32 rozmiar, u32 spakowane; zlib: obraz bez kolorów właścicieli, RGB565 (u16)
u32 rozmiar, u32 spakowane; zlib: numer powiatu na piksel (u16, indeks w tabeli
                                  powiatów; 0xFFFF = brak)
```
(każda spakowana część dopełniona do 4 B). Obie części mają wszystkie poziomy mipmap
(1024, 512, … 8 px — tak jak układa je `C3D_TexInitMipmap`), każdy w kolejności
tekstury 3DS (kafle 8×8 od dolnego wiersza, w kaflu porządek Mortona; `tile_order`).
Numery na mniejszych poziomach są brane z pikseli, nie mieszane. Każdy poziom ma swoje
linie: wybrzeże zawsze, granice prowincji i stref morskich od 3 pikseli na komórkę
(`K_PROVINCE`), granice powiatów od 14 (`K_COUNTY`) — karta, wybierając poziom wg
odległości, sama pokazuje mniej szczegółów daleko. Kafle rysowane są
z zakładką, a szum i fale leżą na całej mapie, więc na stykach nie ma szwów. 3DS przy
wczytaniu mnoży obraz przez kolor właściciela regionu powiatu piksela (`0,62 × kolor frakcji
+ 0,38 × biały`; morze bez zmian), a numery poziomu 0 zostawia do stuknięć.

## `scenario.lua` — scenariusz mapy politycznej (nasz format)

Plik danych w podzbiorze składni Lua jak `cart.lua` (D38: nic nie jest wykonywane, tylko
klucze napisowe). Robi go `tools/make_m3.py` (`--dump-scenario plik.lua` = scenariusz
samej mapy do edycji; `--scenario plik.lua` = sprawdź i włóż do romfs; bez niego do romfs
idzie scenariusz mapy). 3DS czyta `romfs:/scenario.lua` parserem LiteLua (`ll_data.c`,
Lua 5.4 jak na DS) i nakłada na `map3d.bin`. Id prowincji i powiatów należą do jednej
wygenerowanej mapy (ziarno, rozmiar) — nie zmieniać ich.

```lua
return {
  title = "Six realms (seed 77)",
  player = "order",          -- id państwa gracza (jego widok: mgła wojny)
  fog = true,                -- mgła wojny na starcie
  realms = {                 -- do 32; kolejność = numery państw
    { id = "order", name = "Order", color = { 60, 110, 220 } },
    { id = "city_belpel", name = "Free City of Belpel", color = { 190, 175, 145 }, city = true },
  },
  provinces = {              -- każda prowincja i strefa morska: id z generatora
    { id = 0, name = "Weneth", owner = "order" },   -- owner = "": niczyja
    { id = 45, name = "Arnorval Sea" },             -- morze: bez właściciela
  },
  counties = {               -- id = numer powiatu w map3d.bin
    { id = 12, name = "Margor" },
  },
}
```
Ograniczenia: nazwy państw i prowincji 1–23 bajty, powiatów 1–19, kolory 0–255; id państw
różne. `city = true` = państwo-miasto (nazwa mniejsza, nie wersalikami). Na 3DS: X mgła
wł./wył., Y widok następnego państwa.

## `style.lua` — wygląd mapy politycznej (nasz format)

Plik danych jak `scenario.lua` (D38). Style są w `styles/` (`classic` = wygląd sprzed M3k,
`parchment`, `leather`, `parchment-image`, `parchment-grain`); `tools/make_m3.py --style
plik.lua` (domyślnie `styles/classic.lua`). Dwie części:
- `map` — wypalane w tekstury przez `make_m3.py` (zmiana = generowanie i build od nowa):
  `surface` (`plain` / `parchment` / `leather` / `image`), `paper`, `sea`, `shore`,
  `rim` (spalona krawędź całej mapy 0–1), `gamma` (>1 jaśniejsze półcienie), `stain` (plamy/zmarszczki), `image` +
  `image_cells` (obraz obok pliku stylu, powtarzany bez szwu co tyle komórek), `lines`
  (`coast`, `land`, `county`, `sea`), `patterns` (np. `land = "------  .  "` — ten rodzaj
  linii wzorem, okres `dash` komórek). Wzory leżą na całej mapie (kafle bez szwów).
- `view` — czyta 3DS przy starcie z `romfs:/style.lua`, a potem z
  **`sdmc:/3ds/heroes3d/style.lua`** (jeśli jest — nadpisuje to, co podaje; zmiana kolorów
  bez budowania): `background`, `tint`, `neutral`, `fog.unseen` / `fog.seen` (r, g, b,
  alfa), `border` (`color`, `alpha`, `width`), `labels` (`province`, `county`, `shadow`,
  `selected`), `grain` (`strength` 0–1, `cells`). Wzory linii: `border.pattern` i
  `select.pattern` — napis, każdy znak to równy kawałek okresu: `-` tusz, spacja przerwa,
  `.` kropka; `dash` = okres w grubościach linii (kreski wyglądają tak samo przy każdym
  przybliżeniu). `select` = zaznaczona prowincja: `pattern` (pusty = dawne świecenie z
  obrysem), `color`, `alpha`, `width` (× grubość granic), `dash`, `fill` (poświata 0–1),
  `mode` (`glow` / `line` / `fill` / `none`); poświata (`line`, `fill`) mnoży mapę
  (prowincja × (1 + `fill`) w kolorze `light` — zostaje kolor prowincji), `flicker` (0–1,
  jak mocno przygasa), `period` (sekundy na cykl), `gap` (komórki od granicy bez
  poświaty, co najmniej), `soft` (miękkie przejście = tyle × `gap`, 3 pasy w stencilu); `border.show = false` — bez pasków granic
  państw (przynależność tylko kolorami).

Kolory `{ r, g, b }` lub `{ r, g, b, a }`, 0–255. Pełny przykład z opisem pól:
`styles/classic.lua`.

`grain.bin` (zawsze w romfs): ziarno papieru, które 3DS mnoży z mapą na GPU (drugi stopień
texenv, 128 = bez zmiany), powtarzane co `grain.cells` komórek — ostre przy każdym
przybliżeniu. `b"HG01"`, u32 rozmiar (256), u32 raw, u32 packed, zlib(L8, poziomy mipmap
256…8 w kolejności tekstur 3DS jak kafle).
