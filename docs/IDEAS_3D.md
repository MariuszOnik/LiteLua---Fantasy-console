# Pomysły na 3D w LiteLua (D60 i dalej)

Notatnik pomysłów z rozmowy z 2026-10-29 — co już jest, co da się zrobić i jak. Decyzje
zapisujemy w `DECISIONS.md` dopiero przy implementacji; tu jest „bank pomysłów”.

## Co już jest (D60, `tests/carts/army3d`)
- `camera3d(x, y, yaw, pitch, dist, fov, z)` — perspektywa, obrót, pochylenie, zoom; warstwa 3D
  zawsze za 2D tego ekranu (tylna połowa bufora głębi). Wierzchołki względem punktu kamery
  (to już jest „pływający początek układu” — ważne dla open world, niżej).
- Teren `isogrid:draw3d(hs, tpt, lod)` — display listy kawałków 8×8 pól (DMA), sprzętowy
  `BoxTest`, pasy (`GL_QUAD_STRIP`, jedna powtarzana tekstura), LOD: daleko co drugi narożnik.
- `fog3d(col, near, far)` — mgła sprzętowa, nic za mgłą nie jest rysowane.
- `billboards` — żołnierze z 9 zapisanych kierunków (16 z odbiciami), animacje i ruch w C,
  `b:ground` (stoją na terenie), LOD (daleko co drugi / co czwarty).
- Atlas z Cossacks: `tools/cossacks_atlas.py` (grafika gry tylko lokalnie).
- Pomiary: DSi — 1500 żołnierzy w 30 FPS; melonDS — dist 40 z LOD 1188 wielokątów / 3846
  wierzchołków (limity DS: 2048 / 6144 na ekran).

## Sztuczki z DSCraft (Smealum) — co z nimi robimy
Kod DSCraft jest bez licencji — bierzemy **tylko pomysły**, piszemy od nowa.

| Sztuczka | Stan |
|---|---|
| 3D na obu ekranach przez przechwytywanie obrazu (`REG_DISPCAPCNT`) | jest od D5/D28 |
| Światło policzone raz (kolory narożników) | jest (`isogrid` colors) |
| Liczby całkowite w wierzchołkach | jest (floaty tylko raz na wywołanie) |
| Display listy + DMA | **zrobione** (teren) |
| `BoxTest` (sprzętowy test widoczności) | **zrobione** (kawałki terenu) |
| Mgła ukrywająca krawędź świata | **zrobione** (`fog3d`) |
| Tylko widoczne ściany (bajt z 6 bitami sąsiedztwa) | do zrobienia przy budynkach / murach (oblężenia) |
| Okno świata doczytywane z karty, reszta w pliku | pomysł — open world (niżej) |
| Czytanie sektorów karty z pominięciem FAT | **nie** — kruche (przez to crashe w porcie) |

## Ozdoby terenu (następny krok)
- **Drzewa, krzaki, kamienie jako drugi batch `billboards`** z `dirs = 1` — te same mgła i LOD
  co żołnierze; 300 drzew ≈ 1200 wierzchołków (przy zwykłym ujęciu zostaje ~3200 wolnych).
- **Albo skrzyżowane quady w listach terenu** (jak kwiatki w Minecrafcie) — zero CPU, rysują się
  z kawałkiem; z bliska bardziej płaskie. Dobre na trawę, zboże, krzaki w masie.
- Las na wzgórzu w `army3d` jako test.

## Wydajność — dalsze pomysły
- **Kolor narodu przez paletę** — ten sam atlas dla wszystkich państw (DS: paleta per tekstura
  w banku E; trzeba API na „widok obrazu z inną paletą”).
- **LOD żołnierzy jako sprajt pułku** — z bardzo daleka cały oddział jednym quadem.
- **Szpary na styku LOD** — jeśli będzie je widać poza mgłą: „fartuchy” (pionowy pasek w dół
  na krawędzi kawałka) albo dopasowanie krawędzi gęstego kawałka do rzadkiego sąsiada.
- **Cień jednostek** — dziś szachownica w obrazku; można osobnym ciemnym quadem na ziemi.
- **Kolejność:** batch billboardów też jako display lista, gdy wszyscy stoją (bitwa turowa —
  między ruchami nic się nie zmienia).

## Open world (pytanie użytkownika: „dało by się open world na DS?”)
Tak, w stylu DSCraft:
- **Okno kawałków wokół gracza** — np. 16×16 kawałków po 8×8 pól (128×128 pól) w RAM;
  przy ruchu dochodzi pas kawałków z przodu, z tyłu wypada. Kawałek = już dziś jednostka
  display listy, więc to naturalne rozszerzenie.
- **Pływający początek** — wierzchołki już są względem kamery (±60 pól), więc świat może być
  dowolnie duży (pozycje w int32 = ±4 mln pól).
- **Zapis tylko zmian** gracza (na karcie, plik na region), reszta z generatora.
- Doczytywanie z karty przez zwykłe pliki (nie sektory), po kawałku na klatkę, żeby nie szarpało.

## Teren proceduralny
- **Szum w C** (value noise / Perlin na liczbach całkowitych, kilka oktaw) — wysokość
  narożnika z (x, y, ziarno). Kawałek 8×8 to 81 narożników — ułamek milisekundy w C;
  w Lua ~kilka ms (do przyjęcia przy 1 kawałku na klatkę, ale lepiej C).
- Z tego samego szumu: biomy (wilgotność, temperatura) → kolory narożników, gdzie drzewa,
  rzeki (w dół zbocza), drogi między miastami.
- Nieskończony świat z ziarna — nic nie trzeba trzymać na karcie poza zmianami.
- API (szkic): `heightfield(seed, opts)` jako źródło dla `isogrid`/okna kawałków.

## FPP — widok z oczu postaci
- **Teren: tak** — trzeba zdjąć ograniczenie `pitch >= 5` (patrzenie w górę/poziomo), oko na
  wysokości postaci (`z`), małe `near`; mgła obowiązkowo (horyzont), LOD już jest.
- **Postacie: problem grafiki, nie sprzętu.** Sprajty Cossacks/H4 są narysowane z góry pod
  kątem ~30–40° — z poziomu oczu wyglądałyby „z lotu ptaka”. Do FPP potrzebne sprajty z boku
  (jak w Doomie: 8 kierunków na wysokości oczu) albo proste modele 3D (DS ma do tego sprzęt:
  macierze, światło z normalnych).
- Ruch: prosta kolizja z terenem (wysokość pod stopami już jest: `b:ground` / szum).
- Limity bez zmian: ~2048 wielokątów, 30 FPS na ekran przy 3D na obu ekranach (albo 60 FPS,
  gdyby 3D było tylko na jednym — inny tryb, decyzja na później).

## Modele 3D z Imperial Glory na 3DS (2026-11-01, `tests/3ds/army`)
- Format V3D z Imperial Glory rozpracowany (narzędzia i opis poza repo: `E:\AI\IG\tools\v3d.py`;
  zasoby gry tylko lokalnie). Piechur: 228 wierzchołków, 246 trójkątów, tekstura 256×256 na
  nację; animacje to klatki pozycji wierzchołków (morph, bez szkieletu), np. chód 12 klatek /
  1,06 s. Kawaleria = koń + jeździec w jednym pliku; działo = 13 części w hierarchii.
- Na DS siatki odpadają (limit 2048 wielokątów = ~5 żołnierzy obok terenu) — tam billboardy;
  ewentualnie sprajty wyrenderowane z modeli IG zamiast Cossacks.
- Na 3DS: `tests/3ds/army` (citro3d, C) — jeden draw na żołnierza, shader miesza dwie
  klatki (`soldier.v.pica`), model z `make_army.py`. Azahar: 200 fizylierów, 49 tys.
  trójkątów, 60 FPS. Na konsoli do zmierzenia (500–2000 żołnierzy).
- Dalej: postój/strzał/śmierć, kawaleria i działa, instancing (mniej poleceń GPU na żołnierza).
- (2026-11-01) Medieval II: `.mesh` i animacje `pack.dat` rozpracowane (narzędzia poza repo:
  `E:\AI\M2TW	ools`), rycerze wypiekani do klatek morph (`make_knight.py`, kilka animacji w
  formacie `LLM2`), odchudzanie `optimize.py` (3209 → 700 trójkątów, błąd po wszystkich
  klatkach). `tests/3ds/battle`: heksy 14×12 na wzgórzach (24 trójkąty na heks, obramowanie
  drugą teksturą), drzewa i kamienie w jednej siatce, 10 oddziałów × 8 rycerzy — Azahar 74 tys.
  trójkątów, 60 FPS. Pomysł na turówkę: rysować tylko przy zmianie (ruch, walka, kamera).
