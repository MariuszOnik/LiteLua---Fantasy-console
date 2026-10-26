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
