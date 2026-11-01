# HeroesDS — decyzje

Każdy wpis: data, decyzja, uzasadnienie. Nowe wpisy na końcu. Numeracja H<n>, żeby nie
mylić z decyzjami silnika (D<n> w `docs/DECISIONS.md` repo LuaDS).

## H1 (2026-10-26) — Część repo LuaDS, zasoby gry tylko lokalnie
HeroesDS żyje w podfolderze `HeroesDS/` repo LuaDS, razem z silnikiem. Oryginalne pliki
gry (`Data/*.h4r`), wyciągnięte z nich zasoby (`extracted/`), manuale, OST i narzędzia
innych autorów są wykluczone w `.gitignore` — gra jest do użytku prywatnego, zasoby nie
trafiają do repo ani do publicznych buildów. W repo są tylko nasze skrypty, kod i dokumenty.

## H2 (2026-10-26) — Walka: mechanika 1:1 z H4, grafika uproszczona pod DS
Zasady walki (statystyki, wzory obrażeń, inicjatywa, kontratak, morale/szczęście, moce,
czary) odwzorowujemy wiernie, ale w kodzie otwartym na rozbudowę (moce i czary jako dane +
hooki, nie zaszyte warunki). Prezentacja nie musi być 1:1 — układ ekranów, skala sprite'ów,
liczba klatek i kierunków mogą być uproszczone pod możliwości DS.

## H3 (2026-10-26) — Źródła wiedzy o formatach i zasadach, licencje
- **Anbrose/homm4-mac** (MIT, © 2026 Anton Ozhigin): `tools/h4sprite.py` opisuje format
  sprite'ów `.h4d`, a `native/Sources/H4Engine/*.swift` zawiera zasady gry odtworzone
  z oryginału (m.in. `Combat.swift`, `Battle.swift`, `BattleSpells.swift`). Licencja MIT
  pozwala korzystać z kodu — przy przeniesieniu fragmentu podajemy autora i licencję
  w nagłówku pliku. Kopia do wglądu: `ref/homm4-mac/` (poza repo).
- **Anbrose/hommiv-remake-macos** — brak licencji: tylko do wglądu, bez kopiowania kodu.
- **AKuHAK/mh4** — brak licencji, opisuje tylko archiwum `.h4r` (mamy własny czytnik).
- Fakty o formatach i liczby z gry (wzory, statystyki) nie są kodem — zapisujemy je
  własnymi słowami w `docs/FORMATS.md` / `docs/MECHANICS.md`.

## H4 (2026-10-26) — Grafika jednostek w pierwszej wersji: bez zmian w silniku
Zaakceptowana propozycja z `DS_GRAPHICS.md` (H2a): atlas PNG 8 bpp na animację
i kierunek, skala 0,5 (do dopracowania per jednostka w H3), alfa klatek progowana na 50 %,
cienie jako osobny 1-kolorowy atlas rysowany z `alpha()`; animacje ładowane przed starciem
i zwalniane po nim; tekstury z alfą (A5I3) w silniku dopiero, gdy pierwsza wersja zadziała.
Uzupełnienie z H2b: cień przechowywany w połowie rozdzielczości i rysowany powiększony
(`sspr`) — inaczej dwa komplety animacji nie mieszczą się w 256 KB VRAM.

## H5 (2026-10-26) — Walka na polu bitwy z małymi sprite'ami, bez zbliżenia starcia
Rezygnujemy z osobnej sceny „zbliżenia” (dwie duże jednostki na górnym ekranie). Walka
toczy się na polu bitwy, jak w oryginalnym H4: wszystkie oddziały (do 7 na 7) jako małe
animowane sprite'y. Uzasadnienie (pomiary H2b/H2c): styl `test1` (skala ~0,19, 16 kolorów,
bez obrysu, cień z kropek) — `wait` bandyty 2 KB, smoka 4 KB na kierunek; akcje dociągane
na żądanie (~90 ms w melonDS); jedna skala zamiast dwóch = połowa konwersji i pamięci.
- Styl bazowy: `test1` z `tools/styles.json` (dostrojony przez użytkownika w `style_tuner.py`).
- Zaznaczenie celu / obszaru czaru: najpierw za darmo (znacznik na ziemi + pulsujący `tint`),
  prawdziwy obrys (atlas sylwetki rysowany 4× z przesunięciem) tylko jeśli to za mało czytelne.
- Otwarte do C2: który ekran pokazuje pole bitwy (dotyk!), a który informacje (aktywny
  oddział, cel, kolejka tur, dziennik, ewentualnie portret 2×).
- Propozycja dla silnika LiteLua (osobny punkt w planie LiteLua, gdy będzie potrzebna):
  zamiana ekranów (`sys.swap()` — odwrócenie `lcdMainOnTop/Bottom` w dual30); dotyk zostaje
  na fizycznie dolnym ekranie.

## H6 (2026-10-26) — Pole bitwy na dolnym ekranie, informacje na górnym
Pole bitwy jest na dolnym ekranie: cel, ruch i obszar czaru wskazuje się rysikiem (dotyk
działa tylko tam). Górny ekran: aktywny oddział, cel z podglądem obrażeń, kolejka tur,
dziennik, czary. Nie wymaga zmian w silniku LiteLua (`sys.swap()` z H5 niepotrzebne).
Krzyżak + A jako alternatywa dla rysika. Szczegóły: `COMBAT.md` §9.

## H7 (2026-10-26) — Walka wręcz / Łucznictwo bohatera dzielą obronę wroga
Liczymy dzielenie naturalnej obrony celu przez Walkę wręcz / Łucznictwo bohatera tak, jak
mówi opis w grze (`MECHANICS.md` §13.2), choć homm4-mac tego nie robi — zgodnie z H2
(opis, dopóki exe nie pokaże inaczej). Reguła ma przełącznik w danych, żeby dało się ją
wyłączyć bez zmian w kodzie.

## H8 (2026-10-26) — Całe pole bitwy w skali 3/16, lupa ×2
Widoczna scena H4 (1180×1024; pola siatki 102×102, których środki się w niej mieszczą)
w skali 3/16 = 0,1875 ma 221×192 px, czyli całe pole mieści się na ekranie DS bez przewijania.
Pole siatki to romb 6×3 px, więc dotyk wskazuje oddział lub punkt, który gra dociąga do
najbliższego dozwolonego miejsca. Przytrzymanie L/R włącza lupę ×2 (skala 0,375) wokół
rysika — te same atlasy powiększone `sprx`. Styl `test1` przechodzi z 0,19 na 0,1875.

## H9 (2026-10-26) — Zabity w wymianie nie oddaje ciosu
W jednoczesnej wymianie wręcz cios atakującego ląduje pierwszy: cel, który od niego zginął,
nie oddaje (tak liczy homm4-mac bez czasów animacji i exe przy równych czasach trafienia).
Zastępuje propozycję z `COMBAT.md` §8, by zabity oddawał pełnym oddziałem — przy przewadze
atakującego dawało to obrażenia od oddziału, który już nie żyje. Strzały bez zmian: strzelec
ostrzelany zawsze odpowiada stanem sprzed strzału. Przełącznik `battle.dead_strike_back`.

## H10 (2026-10-26) — Bohater: reguły z opisów umiejętności, ruch z przedmiotów w punktach
- Zdolności bohatera z opisów Walki wręcz i Łucznictwa (pierwsze uderzenie, drugi cios, bez
  kar za przeszkody / odległość, pierwszy i drugi strzał) liczymy jak opis (H2, H7) —
  homm4-mac ich nie ma. Przełącznik `heroes.skill_abilities`.
- Dowodzenie daje armii także szczęście (+1…+5, jak opis; homm4-mac liczy, ale nie nakłada).
- Ruch z przedmiotów w punktach ruchu (100 = 1 pole siatki; 300 = „+1” na ekranie) —
  homm4-mac dzieli przez 300, co przeczy Taktyce (+1 na ekranie = 3 pola). Obrona
  bohatera z przedmiotów osobno wręcz i przed strzałami (pola `melee` / `ranged`).

## H11 (2026-10-26) — Tura komputera w korutynie, ekran żyje (klepsydra)
- Nie walczymy o to, by tura komputera mieściła się w klatce. Ekran woła `ai.act` w
  korutynie; silnik w długich pętlach (szukanie drogi, ocena czarów) woła `grid.tick()`,
  które ekran ustawia na `yield` po zużyciu plasterka czasu (~20 ms), więc klepsydra /
  „Tura przeciwnika…” się animuje. Na PC i w testach `grid.tick` nic nie robi.
- Kilka sekund tury komputera na DS jest do przyjęcia (decyzja użytkownika); kilkanaście
  już nie — wtedy przyspieszamy silnik (pomiar C4a).

## H12 (2026-10-27) — Mapa strategiczna: miks Imperial Glory i Heroes IV
Warstwa strategiczna jak w Imperial Glory (prowincje, oblężenia, AI z profilami — ściąga
`docs/IMPERIAL_GLORY.md`), ekonomia i walka z H4. Decyzje użytkownika:
- **1 tura = 1 tydzień** (przyrost stworzeń w siedliskach i dochód na koniec tury).
- **Miasto w prowincji za pieniądze i zasoby**: każda prowincja może dostać miasto (drzewko
  budynków H4 frakcji), jeśli gracz je opłaci. Na start każde państwo ma **jedno miasto —
  stolicę**; scenariusz może to zmienić (więcej miast, gotowe budynki). Prowincja bez miasta
  daje kopalnie i dochód z terenu.
- Zasoby H4 (złoto, drewno, ruda, kryształ, klejnoty, rtęć, siarka); kopalnie wynikają z terenu.
- **Utrzymanie armii kosztuje** co tydzień, zależnie od miejsca jak w IG (w mieście tanio,
  na swoim taniej, na obcym drożej). Liczby do ustalenia przy implementacji.
- **Armia musi mieć bohatera** (jak oficer w IG): oddziały bez bohatera stoją w garnizonie
  i nie ruszają się. **Poziom bohatera wyznacza, iloma oddziałami może dowodzić**
  (progi do ustalenia; maksimum 7 jak w H4).
- Bitwa: z udziałem gracza — kartridż walki H4; między komputerami — automat na wartościach
  stworzeń H4 z bonusami obrońcy (IG). Miasto z murami wymaga oblężenia.
- Neutralni to potwory H4 strzegące prowincji, kopalni i skarbów (zamiast 19 państw IG).
- Kolejność: zasoby i dochód → miasto w prowincji → ruch komputera z bitwą automatyczną →
  walka H4 i oblężenia → handel → dyplomacja.
- **Uzupełnienie (2026-10-27, decyzja użytkownika):** część neutralnych prowincji to
  **niezależne miasta-państwa**, które można przejąć pokojowo (relacje, budynki, złoto,
  jak w IG) albo zbrojnie. Pozostałe neutralne to potwory H4 strzegące kopalni i skarbów.
  Kolejność prac nad mapą: pas morza → zasoby i kopalnie z miniaturami H4 (stolice
  z zamkami) i dochód → minimapa → ekran miasta → szlaki handlowe na mapie (dochód,
  blokada) → dyplomacja i pokojowe przejęcie → ewentualnie zoom.
- **Generator M2 (2026-10-27):** wokół lądu jest pas 6 kafli otwartego morza (ląd wygasa
  przed nim). Prowincje bez wnętrza (mniej niż 4 kafle otoczone tylko swoimi) łączą się
  z sąsiadem. Strefy morskie mają ~110 kafli (na mapie 84×84 to ~37 stref zamiast 12),
  żeby flota miała gdzie pływać. Ziarna państw wybierane są na największym lądzie
  (wcześniej państwo mogło utknąć na wysepce z 1 prowincją). Ziarno 77 daje inną mapę.

## H13 (2026-11-01) — Mapa polityczna w pełnym 3D na Nintendo 3DS
Użytkownik kupił 3DS XL i przenosimy grę na 3DS (devkitPro: libctru + citro3d/citro2d,
emulator Azahar w `D:\Programowanie\azahar-windows-mxe-2127.0-alpha3`). Mapa polityczna
jest w pełnym 3D (wzór: obrazki „Risk” — płaskie prowincje jak płytki, falujące granice):
- Prowincje i strefy morskie to **siatki 3D** z `tools/make_m3.py` (ten sam generator lądu
  co M2, to samo ziarno): wielokąty z wygładzonymi, wspólnymi granicami, ląd jako płyty
  nad morzem ze ściankami, granice jako wstęgi. Format `map3d.bin` w `docs/FORMATS.md`.
- Klikanie: dolny ekran (dotykowy) pokazuje mapę 3D; promień z kamery przez punkt dotyku
  przecina płaszczyznę lądu, potem morza, i szuka trójkąta prowincji (CPU, bez bufora ID).
  Górny ekran: bliższy widok stereo i informacje.
- Prototyp `3ds/` jest w C (bez Lua). **Do ustalenia:** czy logika gry (silnik walki
  `combat/` w Lua, `war.lua`) idzie na 3DS przez port LiteLua, czy przez samo Lua 5.4
  wbudowane w program 3DS. Wersja DS (m2, c4) zostaje, jak jest.
- **Uzupełnienie (2026-11-01, decyzja użytkownika):** mapa jest **płaska** (bez unoszenia
  prowincji i bez ścianek), **detale są w teksturze**, mesh prosty: cała mapa to jeden
  prostokąt; dokładne kształty regionów tylko do podświetlenia wybranego. Klikanie przez
  mapę numerów regionów (piksele tekstury) zamiast trójkątów. Każdy pomysł = osobny commit
  i osobny build w `3ds/builds/heroes3d-<tag>.3dsx` (stare zostają do porównań). Głębię
  dadzą później pionki (armie, miasta) na mapie.
- **Uzupełnienie (2026-11-01):** duża mapa w **kaflach 1024²** (więcej się nie da w jednej
  teksturze 3DS) z teksturą przeglądową całej mapy pod spodem; w pamięci tylko kafle
  widziane przez kamery (do 6), doczytywane w wątku w tle. Koszt klatki nie zależy od
  wielkości mapy; ograniczeniem jest pamięć i czas doczytania. Numery regionów 16-bit
  (było 8: do 254 regionów). Rozsądnie dla rozgrywki: 200–400 prowincji.
- **Uzupełnienie (2026-11-01, decyzja użytkownika):** szczegóły wg oddalenia jak w grach
  strategicznych: daleko granice i nazwy państw, średnio prowincje, blisko powiaty
  (prowincje dzielone na powiaty). Granice prowincji i powiatów są w poziomach mipmap
  tekstury (karta sama wybiera), granice państw rysuje 3DS z właścicieli, bo zmieniają
  się w grze. Nazwy nie znikają z odległością w jednym widoku — skalowane perspektywą,
  nachodzące pomijane. Kamera bez obrotu; L/R zmienia kąt patrzenia.
- **Uzupełnienie (2026-11-01, prośba użytkownika):** powiaty da się zaznaczać — z bliska
  (gdy widać ich linie) stuknięcie wybiera powiat, z dalszej odległości prowincję. Nazwy
  państw pastelowe (kolor frakcji rozjaśniony do połowy) z cieniem.

- **Rozstrzygnięcie H13 (2026-11-01, decyzja użytkownika):** Lua na 3DS jak na DS — to samo
  Lua 5.4 z `vendor/lua` (`LUA_32BITS`, bez zmian) wkompilowane w program 3DS; mapa 3D
  zostaje w C. Pierwsze użycie: scenariusz czytany parserem LiteLua (`ll_data.c`, ten sam
  plik). Logika gry (walka, `war.lua`) przejdzie na 3DS przez to samo Lua.
- **Scenariusze i mgła wojny (2026-11-01):** scenariusz to plik danych `scenario.lua`
  (państwa, państwa-miasta, gracz, właściciele i nazwy) nakładany na mapę — jedna mapa,
  wiele scenariuszy; edycja na PC, później na 3DS. Mgła wojny wg powiatów: nieznane /
  widziane wcześniej / widoczne teraz (własne prowincje i sąsiedzi), kolory nakładane
  przy malowaniu kafli.
- **Mgła jako nakładka (2026-11-01, prośba użytkownika):** mgła nie przemalowuje mapy —
  to tekstura 512² nad mapą (stan regionu na piksel), liczona w milisekundy; kolory mapy
  zależą tylko od właścicieli (przemalowanie kafli tylko przy zmianie właściciela).
