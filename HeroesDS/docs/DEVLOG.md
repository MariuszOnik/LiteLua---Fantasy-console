# HeroesDS — dziennik prac

Krótko, co zrobiliśmy danego dnia i co z tego wyszło. Szczegóły: `git log`, plan i stan
w `PLAN.md` („Gdzie skończyliśmy”), decyzje w `DECISIONS.md`, formaty w `FORMATS.md`.
Nowy wpis na górze.

## 2026-11-03 — Glyph test: bitwa C4 bez sprajtów (HTML/JS)

- **`glyphtest/index.html`**: prototyp w przeglądarce, jak wyglądałaby bitwa narysowana
  wyłącznie prymitywami (bitmapy 8×8 w kodzie albo litery), z animacjami i czarami z kodu
  oraz licznikiem kosztu na klatkę. Geometria jak w `grid.lua` / `view.lua`. Następny krok,
  jeśli się sprawdzi: moduł z API `sprites.lua` dla carta C4.

## 2026-11-01 — Wygląd mapy 3DS: style, pergamin, skóra, granice jak w Imperial Glory (M3k–M3x)

- **`style.lua`** (H14): kolory i wygląd mapy w pliku stylu zamiast w kodzie. `map` —
  wypalane w tekstury (`make_m3.py --style`), `view` — czyta 3DS; kopia na karcie
  `sdmc:/3ds/heroes3d/style.lua` nadpisuje `view` bez budowania.
- **Trzy podejścia do papieru**, każde jako build: pergamin z kodu (plamy, włókna, spalona
  krawędź — `m3l`), obraz z ComfyUI/SDXL (`tools/paperart.py`, `styles/parchment.png` —
  `m3n`), ziarno nakładane na GPU (`grain.bin`, drugi stopień texenv — `m3o`). Do tego
  skóra (pory, zmarszczki — `m3m`). Użytkownikowi podobają się wszystkie; ulubiona skóra,
  rozjaśniona polem `gamma` (`m3p` 1,35 → `m3q` 1,6) i jaśniejszą mgłą.
- **Granice:** najpierw linie wzorem na GPU (kreska-kropka, przerywany obrys zaznaczenia —
  `m3r`/`m3s`). Użytkownik poprawił kierunek: przynależność pokazują kolory, granica
  prowincji jest w teksturze (kreska-kropka, `map.patterns`) i nie jest podświetlana
  (`m3t`/`m3u`).
- **Zaznaczenie:** poświata trzymająca się z dala od granicy (stencil, `m3v`/`m3w`), potem
  mnożąca kolor prowincji, miękko gasnąca przy granicy i wolno pulsująca (`m3x`/`m3y`).
- **Edytor stylu na PC** `tools/styler.py`: mapa z góry jak na 3DS, suwaki, zoom, zapis
  na SD. Przy okazji: listy sąsiadów w `map3d.bin` są po **id** regionów (indeks = id + 1,
  indeks 0 to neutralna wysepka) — 3DS zamienia je dobrze, podgląd na początku nie.
- **Lekcje:** zrzuty z Azahara skryptem `3ds/azshot.ps1`; klikanie myszą w okno emulatora
  trafiało w VS Code użytkownika — nie klikamy automatycznie, zaznaczenie testujemy buildem
  z `selected` ustawionym na chwilę w kodzie. Skrypty edycji z `\3`, `\b` w napisach Pythona
  psują ścieżki Windows — ścieżki z ukośnikami albo `chr(92)`.
- Najnowsze buildy: `m3x-leather-gentleselect`, `m3y-parchment-gentleselect`.
