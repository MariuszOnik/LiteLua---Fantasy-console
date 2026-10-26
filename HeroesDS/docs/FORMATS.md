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
- **Hipoteza**: wysokość siedzi w tych 5 nieznanych bajtach pola. **Test**: w edytorze
  zrobić dwie małe mapy — płaską i z jednym pagórkiem — i porównać pliki.
- **Na DS**: LiteLua rysuje przez sprzętowe 3D (D5, gl2d), więc teren z wysokością da się
  narysować jako siatkę z teksturą i jasnością w wierzchołkach (cieniowanie prawie za
  darmo). Alternatywa: prerender mapy na PC do płaskich obrazków (dużo pamięci).
  Romby 64×32 trzeba zmniejszyć (np. 32×16). Decyzja przy trybie mapy.
