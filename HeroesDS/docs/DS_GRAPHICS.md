# Grafika H4 na DS — co umie LiteLua (H2)

Stan silnika: `docs/DECISIONS.md` repo LuaDS (D5, D10, D24, D56) i `docs/api/gfx.lua`.

## Co LiteLua daje dziś

| Potrzeba HeroesDS | LiteLua | Uwagi |
|---|---|---|
| Obrazy z paletą 256 kolorów | PNG ≤256 kolorów → tekstura 8 bpp; ≤16 → 4 bpp | klatki H4 mają ≤255 kolorów — pasuje wprost |
| Klatki różnej wielkości | `image("x")` + `sub(img, x, y, w, h)` (widok bez kopiowania) | atlas PNG na animację + tabela prostokątów i przesunięć |
| Punkt zaczepienia (stopy) | `anchor`, albo przesunięcie z meta w `spr(img, x+ox, y+oy)` | |
| Skalowanie, odbicie | `sprx` (skala, obrót), `flip` | |
| Półprzezroczystość | `alpha(a)` — 32 poziomy na cały rysowany obiekt | **nie per piksel** |
| Pamięć wideo | tekstury 256 KB (banki A+B), palety 64 KB (bank E) | licznik w `sys.stats()` (`vram`) |
| Zwalnianie | tekstura znika z `__gc` obrazu (puścić referencje + `collectgarbage()`) | `image()` trzyma obraz w pamięci podręcznej o słabych wartościach |
| Rozmiar tekstury | boki dopełniane do potęgi dwójki, maks. 1024 | atlasy planować pod 128/256/512 |
| Ścieżki | `image("bandit/melee_sw")` → `gfx/bandit/melee_sw.png` | |
| Ekrany | dual30: oba ekrany 3D, 30 FPS (D5, D28) | górny ekran = scena starcia |

## Czego brakuje

1. **Alfa per piksel.** H4 ma 4-bitową alfę w każdym pikselu (miękkie krawędzie, smugi
   broni, cienie). LiteLua przy konwersji PNG robi z alfy 0/1 (alfa < 128 = przezroczysty).
   - Krawędzie: progowanie alfy wystarczy — po zmniejszeniu do ~0,5 schodki są mało widoczne.
   - Cienie: cień H4 to jeden kolor + alfa. Rysujemy go jako osobny obraz 1-kolorowy
     z `alpha(0.4)` — wspólna półprzezroczystość wygląda prawie jak oryginał.
   - Ewentualne rozszerzenie silnika (później, osobny punkt w planie LiteLua): tekstury DS
     z alfą **A5I3** (8 kolorów, 32 poziomy alfy) — idealne na cienie i efekty czarów,
     i **A3I5** (32 kolory, 8 poziomów alfy). Dla klatek jednostek (255 kolorów) się nie nadają.
2. **Pomiar wczytywania.** Nie wiemy, ile trwa `image()` atlasu 256×256 (SD + dekoder
   PNG + wysyłka do VRAM) na konsoli. Od tego zależy, czy animacje ładujemy w trakcie
   walki (przed każdym starciem), czy przy wejściu do bitwy. → **H2b**.

## Budżet pamięci (policzony z danych gry, kierunek sw, 8 bpp)

Atlas = unikalne klatki animacji upakowane w prostokąt o bokach potęgi dwójki.

| Animacja | klatek | skala 1,0 | skala 0,5 | skala 0,4 |
|---|---|---|---|---|
| bandyta wait | 5 | 158×102, 64 KB | 79×51, 16 KB | 16 KB |
| bandyta melee | 14 | 205×173, 256 KB | 102×86, **64 KB** | 32 KB |
| bandyta flinch | 9 | 199×135, 128 KB | 100×68, **32 KB** | 32 KB |
| bandyta die | 7 | 161×116, 64 KB | 80×58, 16 KB | 16 KB |
| czarny smok wait | 7 (4 unik.) | 240×155, 128 KB | 120×78, 32 KB | 32 KB |
| czarny smok melee | 9 | 349×253, 512 KB | 174×126, **128 KB** | 128 KB |
| czarny smok flinch | 8 | 317×193, 256 KB | 158×96, **64 KB** | 64 KB |
| czarny smok walk | 8 | 420×294, 512 KB | 210×147, 128 KB | 128 KB |

(„box” = obszar zajmowany przez całą animację, nie jedna klatka.)

**Wnioski:**
- Skala 1,0 nie wchodzi w grę (jedna animacja smoka > cała VRAM, bandyta zajmuje cały
  górny ekran 256×192).
- **Skala 0,5** pasuje do ekranu: dwie jednostki w przeciwległych rogach górnego ekranu
  (bandyta ~100×86, smok ~175×126 — smok zajmie dużą część ekranu, jak w H4).
- Starcie bandyta vs bandyta: melee 64 + flinch 32 + 2× wait 16 = **~130 KB** z 256 KB.
- Starcie smok vs smok: melee 128 + flinch 64 + 2× wait 32 = **~256 KB** — za dużo,
  bo VRAM to też font, interfejs i dolny ekran. Rozwiązania (do wyboru, H3):
  - duże jednostki w 4 bpp (16 kolorów, połowa pamięci) albo mniejsza skala (0,35),
  - tylko jedna animacja na jednostkę naraz (wait → melee → wait: zwalniamy wait,
    ładujemy melee), czyli więcej wczytywania (patrz H2b),
  - mniej klatek (co druga klatka przy 9 fps → 4,5 fps — wyraźnie gorzej).
- Mapa przygody: bandyta 52×45 → ~26×22 przy 0,5 — małe sprite'y, budżet nie jest problemem.

## Propozycja (do akceptacji)

1. **Pierwsza wersja bez zmian w silniku**: atlas PNG 8 bpp na animację i kierunek,
   skala 0,5, alfa progowana, cienie jako osobne obrazy z `alpha()`, meta w pliku `.lua`
   (prostokąty klatek, przesunięcia, fps, klatka trafienia, kierunki zastępcze).
2. **Ładowanie na starcie**: przy rozpoczęciu starcia ładujemy animacje obu jednostek
   potrzebne do tego starcia, po starciu zwalniamy. Czy zdążymy w czasie gry — pokaże H2b.
3. **A5I3 dla cieni/efektów** — dopiero gdy pierwsza wersja zadziała, jako punkt w planie
   LiteLua (zmiana w silniku).

## H2b — wyniki (melonDS, 2026-10-26)

Kartridż `carts/h2b` (grafika generowana lokalnie: `python HeroesDS/tools/make_h2b.py`,
kopiuje też na kartę emulatora). Atlasy przez `tools/h4atlas.py`, skala 0,5.

| Animacja (+ cień) | atlas | czas `image()` ×2 + meta | VRAM |
|---|---|---|---|
| bandyta wait | 256×64 | 54 ms | 17 KB |
| bandyta flinch | 128×256 | 97–105 ms | 34–36 KB |
| bandyta melee | 256×256 | 183 ms | 68 KB |
| bandyta melee, 16 kolorów | 256×256 | 163 ms | 36 KB |
| czarny smok melee | 256×512 | 354 ms | 136 KB |
| czarny smok melee, 16 kolorów | 256×512 | 308 ms | 72 KB |
| czarny smok walk | 256×512 | 379 ms | 144 KB |

- **Cienie**: pierwsza próba (cień w pełnej rozdzielczości, 4 bpp) — cienie zajmowały
  prawie tyle co klatki i dwa komplety bandytów (292 KB) nie weszły do VRAM. Teraz cień
  jest 2× mniejszy i rysowany powiększony (`sspr`, `alpha(0.45)`) — wygląda dobrze,
  zajmuje ~4× mniej.
- **Cykl ładuj–zwolnij**: 20 × (4 atlasy różnych rozmiarów, szczyt 194 KB) — VRAM wraca
  do stanu początkowego za każdym razem, bez błędów braku pamięci (bez fragmentacji
  w tej skali).
- **Starcie** bandyta vs bandyta z dociąganiem: na stałe tylko `wait` obu (39 KB); atak
  ładuje melee atakującego + flinch obrońcy: **~290 ms przestoju**, VRAM 144 KB. Animacje,
  cienie i trafienie w klatce `hit` działają.
- **Czas wczytywania rośnie z wielkością PNG** (~0,7 ms/KB VRAM); 16 kolorów prawie nie
  skraca czasu (dekoder PNG + odczyt), ale połowi pamięć.
- **Wielkość na ekranie**: bandyta przy 0,5 ma ~45×50 px — na górnym ekranie zostaje dużo
  miejsca. Do rozważenia w H3: skala zależna od rozmiaru jednostki (małe większe, smoki
  mniejsze).
- **Uwaga**: timing melonDS nie jest cykliczny — czasy trzeba potwierdzić na DSi.

## Wnioski po H2b
1. Atlas PNG 8 bpp + cień w połowie rozdzielczości działa bez zmian w silniku.
2. Dociąganie animacji przy każdym ataku = ~0,3 s przestoju (emulator). Do gry lepiej
   ładować animacje **przy wejściu do bitwy**, a dociągać tylko to, co się nie mieści —
   do decyzji po pomiarze na DSi.
3. Duże jednostki (smok) wymagają mniejszej skali lub 16 kolorów — do decyzji w H3.

## Następny pomiar — konsola DSi
Ten sam kartridż na konsoli (ROM `litelua.nds` + `litelua/carts/h2b`), wynik
z `litelua/log.txt` (FTP).
