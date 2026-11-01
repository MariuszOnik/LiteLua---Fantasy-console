# Pole bitwy na 3DS — notka dla nowego czatu (2026-11-01)

> **Wizja użytkownika (najważniejsze):** wciągający miks **Heroes** (bohaterowie, rozwój, mapa)
> i **Imperial Glory** (prowincje, armie, bitwy taktyczne). Liczy się **rozgrywka, nie grafika** —
> projekt zaczął się na DS, żeby to udowodnić; DS to ukochana konsola, użytkownik kocha gry
> planszowe. Kolejność pracy: **zasady najpierw** (prototyp na papierze / w Tabletop Simulatorze,
> potem czysty Lua z testami na PC — jak silnik walki HeroesDS), grafika potem (DS: LiteLua,
> billboardy 1500 żołnierzy w 30 FPS; 3DS i rycerze 3D z tej notki to dodatek, nie warunek).
> Następny krok: sesja projektowa i **`DESIGN.md`** (filary, pętla mapa → bitwa → skutki,
> pierwsze zasady bitwy) — pytania z sekcji „Rozgrywka — do ustalenia” są punktem startu.

**Cel.** Turowa bitwa na heksach w 3D (3DS), robiona **równolegle z mapą prowincji**
(`HeroesDS/3ds`, plan: `HeroesDS/docs/PLAN.md`). Z czasem oba projekty mają się połączyć:
mapa strategiczna → bitwy taktyczne → wynik wraca na mapę. Temat: średniowiecze, pierwsza
bitwa testowa w stylu **Grunwaldu** (Zakon kontra Polska, potem Litwa). **Teraz najważniejsze:
dopracować rozgrywkę** (sekcja „Rozgrywka — do ustalenia”): technika już działa.

## Co jest (prototyp, działa w Azaharze na PC, telefonie i AYN Odin)
- Mapa 14×12 heksów (płaskie u góry, promień 6 m) na łagodnych wzgórzach (gładka funkcja
  `height()`), obramowania heksów drugą teksturą, cieniowanie od stoku; lasy (14 drzew na heks)
  i kamienie. Drzewa to **sprite'y z Imperial Glory** (billboardy obracane do kamery).
- 10 oddziałów po 8 rycerzy (Ritterbrüder i polscy rycerze z **Medieval II**), animacje
  postój / postój z ruchem głowy konia / galop / szarża (morph, mieszanie dwóch klatek na GPU).
- **Dolny ekran (dotyk):** pole w rzucie ortograficznym, 4 kamery co 90° (L/R), X/Y zoom,
  gałka/D-pad przesuwa. Stuknięcie w oddział = zaznacz (żółta obwódka), w wolny heks = jedź
  tam (obrót w miejscu, galop przez wzgórza, postój). B = odznacz.
- **Górny ekran:** perspektywa za zaznaczonym oddziałem + nazwa i stan (citro2d, biały tekst
  z cieniem).
- Ograniczenia: ruch w linii prostej (bez szukania drogi, przez las), brak ataku i zasad,
  stuknięcie w oddział wroga po prostu go zaznacza. Dotyk sprawdzony przez użytkownika na Odinie.

## Pliki
- `source/main.c` — cały program (teren, drzewa, oddziały, dotyk, kamery, rysowanie),
  `source/soldier.v.pica` (morph), `source/terrain.v.pica` (teren, ozdoby, obwódki).
- `build.ps1 [-tag nazwa] [run]` — robi modele (poniżej), buduje, kopiuje do
  **`HeroesDS/3ds/builds/battle3d-<tag>.3dsx`** (tam też buildy mapy). Tytuł i opis aplikacji
  = „Battle 3D <tag> <data godzina>” (Azahar na Androidzie pokazuje opis).
- `make_trees.py` — sprite'y drzew z `data.pak` Imperial Glory → `romfs/trees.bin` (LLTR).
- `../army/make_knight.py --unit teutonic|polish --anim idle,fidget,run,charge --tris 700`
  — rycerz z M2TW (jeździec + koń w jednej siatce, 3 tekstury w atlasie 512) → `romfs/*_lo.bin`
  (LLM2: kilka animacji w pliku; format w docstringu). `../army/optimize.py` — odchudzanie
  (ukryte trójkąty, zwijanie krawędzi z błędem po wszystkich klatkach). `../army/bin2gltf.py`
  — model z powrotem do glTF (podgląd w Blenderze).
- `../army/` — wcześniejszy test (szyk maszerujących: fizylier IG, rycerze M2TW pełni i lekcy).

## Zasoby gier — tylko lokalnie (prywatny użytek, poza repo)
Pełny przewodnik po czytnikach i eksporterach: **`docs/GAME_TOOLS.md`**.
- **Imperial Glory** (GOG): `data.pak` = ZIP. Format V3D rozpracowany: `tools/gameformats/ig/v3d.py`
  (opis w docstringu). Wypakowane w `E:\AI\IG`.
- **Medieval II** (Steam, Kingdoms/Teutonic): wypakowane do `E:\AI\M2TW` (unpacker gry, „Y” na
  pytanie o licencję wpisuje użytkownik). Narzędzia `tools/gameformats/m2tw`: `m2mesh.py` (.mesh),
  `m2anim.py` (animacje z `data/animations/pack.idx/.dat` w katalogu gry), `m2bake.py`
  (wypiekanie szkieletu do klatek, jeździec na koniu), `m2gltf.py`, `modeldb.py`.
- Pamięć asystenta ma notatki `imperial-glory-assets`, `medieval2-assets`,
  `handheld-test-devices` (FTP do telefonu/Odina; hasła podaje użytkownik).

## Pułapki, które już kosztowały czas
- UV: przy kolejności pikseli 3DS (`tile_order`) **v podaje się od góry obrazka**, bez `1 - v`.
- M2TW: bajty kości `(0, b2, b1, 0)` pasują do wag `(w1, w2)`; wagi `(0, 0)` = cały wierzchołek
  na pierwszej kości (bez tego znikały hełmy); jeździec siedzi wg `rider_offset` z
  `descr_mount.txt`; w UV jeźdźca lewa połowa = tekstura jednostki, prawa = zestaw dodatków.
- Shadery PICA: jedna instrukcja = najwyżej jeden rejestr wejściowy (`v0..v15`).
- citro2d: tekst rysować na końcu klatki; ciemny tekst ginie na drzewach — biały z cieniem.
- AYN Odin 1: Azahar tylko z **OpenGL ES** (Vulkan wisi przy starcie).
- Liczby z emulatora (60 FPS przy ~60–75 tys. trójkątów na ekran, oba ekrany rysowane) nic
  nie mówią o konsoli — **pomiar na prawdziwym 3DS jeszcze nie zrobiony**.

## Rozgrywka — do ustalenia z użytkownikiem (najpierw to)
Kierunek z rozmowy: oddział = 6–12 figurek na heksie w szyku (jak Cry Havoc / Basic Impetus),
większość oddziałów w turze stoi. Pytania:
1. **Tura:** obie strony po kolei (igo-ugo) czy aktywacje naprzemienne / kartami?
2. **Ruch:** punkty ruchu, koszt terenu (las, wzgórze, rzeka), kierunek oddziału (6 stron
   heksu: front / flanki / tył), obrót kosztuje ruch? strefy kontroli?
3. **Walka:** szarża (rozpęd, kopie), walka wręcz, strzelcy, przewaga wysokości, flanki i tył,
   morale i rozbicie, straty = mniej figurek na heksie?
4. **Oddziały:** typy (ciężka jazda, lekka, piechota, strzelcy, tabor), dowódcy, sztandary.
5. **Widoczność:** mgła wojny, las zasłania?
6. **Zwycięstwo** i **połączenie z mapą prowincji:** armie z mapy → oddziały w bitwie, straty i
   wynik → mapa; czy bitwa da się rozstrzygnąć automatycznie.
7. **Logika w Lua?** Mapa prowincji ma już Lua 5.4 w programie (H13) — zasady bitwy chyba też
   w Lua, C tylko rysuje (spójne z HeroesDS: `combat`, `war.lua`).

## Technika — kolejne kroki (gdy rozgrywka będzie jasna)
- Szukanie drogi po heksach (A*, koszty terenu), podgląd zasięgu ruchu (podświetlone heksy).
- 30 FPS i lżejszy model (~300 trójkątów) na dolnym ekranie; górny rzadziej / przy zmianie.
- Kolejne jednostki: Litwini (`lithuanian_cavalry`), piechota, strzelcy; animacje walki i śmierci.
- Wspólny kod z `HeroesDS/3ds` (oba w C + citro3d): ładowanie, kamera, tekst; docelowo jeden
  program z mapą i bitwą.
- Test na prawdziwym 3DS (budżet trójkątów na heks).
