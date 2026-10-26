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
