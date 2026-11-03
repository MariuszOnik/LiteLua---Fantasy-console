# HeroesDS — glyph test (HTML/JS)

Szybki test „totalnego downgrade'u” bitwy C4: **zero sprajtów i plików grafiki**. Stosy,
czary, liczby i tekst rysuje kod prymitywami w stylu LiteLua (`pset`, `rectfill`, `line`,
`trifill`, `circ`, `print`) do bufora 256×192 z paletą 16 kolorów, osobno dla każdego ekranu DS.

Otwórz `index.html` w przeglądarce (działa też na telefonie i z GitHub Pages).

## Co jest w środku
- **Dwa wyglądy** (przycisk / klawisz M): bitmapy 8×8 zapisane w kodzie jako napisy
  (`BMP`), albo litery jak w roguelike'u (`K` rycerz, `D` smok…) fontem 3×5.
- **Geometria jak w grze:** `grid.screen` z `combat/grid.lua`, skala 3/16 i lupa 2× z
  `c4/src/view.lua`, obrys stosu w kolorze strony, licznik nad głową, kropki zasięgu ruchu.
- **Animacje bez klatek:** postój (bujanie o 1 px), chód (podskoki), atak (wypad w stronę celu),
  trafienie (błysk), śmierć (zapadanie się w ziemię i kości).
- **Czary z prymitywów:** ogień (pocisk ze smugą i wybuch), błyskawica (zygzak), lód (odłamki).
- **Licznik kosztu** na górnym ekranie: wywołania prymitywów i zapisane piksele na klatkę
  dolnego ekranu. Bitmapy rysowane są ciągami jednego koloru (jeden `rectfill` na ciąg), tło
  pola budowane raz przy zmianie kamery (na DS: warstwa BG).

- **Wybór i potwierdzenie:** dotyk pokazuje znacznik celu (kolejne go przesuwają); wykonuje
  tylko OK w prawym pasku, „✔ Wykonaj” albo Enter; X w lewym pasku albo Esc anuluje.
- **Dźwięk** (przycisk / D): efekty to pliki `carts/g1/sfx/*.wav`, muzyka to podgląd
  `carts/g1/music/*.lsong` w `audio/` (`litelua.py song render --rate 16000 --bits 8`).

## Przenosiny do LiteLua
Gotowy cart: `HeroesDS/carts/g1` (ten sam wygląd i dźwięk w Lua).


Moduł z tym samym API co `c4/src/sprites.lua` (`get`, `effect`, `frame`, `length`, `draw`,
`tick`), rysujący jak `drawBitmap` / `drawUnit` stąd, zastępuje sprajty jedną linią
`require` w `c4/main.lua`. Logika walki (`combat/`) się nie zmienia.
