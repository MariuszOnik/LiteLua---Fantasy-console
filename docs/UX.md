# Projekt aplikacji LiteLua (UX)

Szkielet całej fantasy console: z czego się składa, jak przechodzi się między ekranami i jak
wygląda na dwóch ekranach DS. Decyzje: D8 (edytory jako kartridże w Lua), D14 (każdy
kartridż w nowym stanie, przejście edytor ↔ gra), D27 (ten projekt). Wdrażane po kolei:
P6 (dwa ekrany: ekran błędu, `print`, tymczasowa lista), P10 (launcher, menu pauzy,
kartridże systemowe), P11 (edytor kodu).

## 1. Składniki

```
┌──────────────── jądro w C (małe, stałe) ─────────────────┐
│ start, pętla klatki, grafika, dźwięk, pliki, ekran błędu │
│ menu pauzy, nakładki (statystyki, konsola)               │
│ uruchamia JEDEN kartridż naraz, każdy w nowym stanie Lua │
└──────────────────────────────────────────────────────────┘
        ▲ sys.run(...)              ▲ sys.run(...)
┌──────────────────┐   ┌──────────────────┐   ┌────────────┐
│ LAUNCHER         │   │ EDYTORY          │   │ GRY        │
│ wybór gier       │   │ kod/grafika/     │   │ (karta SD) │
│                  │   │ mapy/dźwięk      │   │            │
└──────────────────┘   └──────────────────┘   └────────────┘
   kartridże systemowe (ROM, mogą być           zwykła piaskownica (D20):
   nadpisane z karty): dodatkowe API            tylko własne pliki
```

- Launcher i edytory są pisane w Lua na tym samym API co gry, plus API systemowe (pkt 5).
- Wspólny wygląd: biblioteka `ui.lua` w ROM (przyciski, listy, zakładki, klawiatura,
  okna dialogowe) — paleta Sweetie 16, font 6×8 (D22, D25). Używają jej wszystkie
  kartridże systemowe; gry mogą jej używać przez `require("ui")` (wbudowane `nitro:/lib`).

## 2. Przepływ

```
 start ──► LAUNCHER ──A──► GRA ──START (0,5 s)──► MENU PAUZY
             ▲  │                                  ├ Wznów
             │  └─ „Edytuj” ─┐                     ├ Restart
             │               ▼                     ├ Edytuj kod ──► EDYTOR
             │            EDYTOR ◄─────────────────┘                  │
             │             │  ▲                                       │
             │      „Uruchom”  └── po wyjściu / błędzie ──────────────┤
             │             ▼        (wraca do pliku, linii, kursora)  │
             │            GRA ─── błąd ──► EKRAN BŁĘDU ───────────────┘
             └──────────── „Wyjdź” z pauzy / z błędu         („Edytuj” → plik:linia, D13)
```

- Gra uruchomiona z edytora po wyjściu (pauza → Wyjdź) albo po błędzie wraca do edytora
  w to samo miejsce (D14 wariant A). Gra uruchomiona z launchera wraca do launchera, na
  zapamiętaną pozycję listy.
- „Edytuj kod” z pauzy zamyka grę (bez zapisu jej stanu) i otwiera edytor z jej plikami.

## 3. Przyciski systemowe

| przycisk | działanie | od |
|---|---|---|
| START przytrzymany 0,5 s | menu pauzy (krótkie START dostaje gra) | P10 |
| L+R+B | awaryjne wyjście do launchera / listy (bez menu) | P3 |
| L+R+Y | nakładka statystyk (D26) | P5 |
| L+R+X | nakładka konsoli: ostatnie linie `print` | P6 |
| SELECT trzymany przy starcie | tryb awaryjny: kartridże systemowe tylko z ROM | P10 |

Kombinacje z L+R gra też widzi w `btn`/`btnp` (nie da się ich ukryć bez opóźniania
wejścia); gry nie powinny używać L+R razem z B/X/Y.

## 4. Ekrany

Gry mają oba ekrany dla siebie (P6, dual30). Systemowe ekrany:

```
LAUNCHER (P10)                   EDYTOR KODU (P11)
┌────────────────────────┐       ┌────────────────────────┐
│  [ikona]  Moja Gra     │ górny │ 12 function _update()  │
│  autor: Mariusz  v1.0  │       │ 13   if btn("a") then  │
│  opis / zrzut ekranu   │       │ 14     jump()█         │
├────────────────────────┤       ├────────────────────────┤
│ ▸ Moja Gra       [A]   │ dolny │ [pliki][kod][grafika]… │
│   Kosmici              │dotyk. │ ┌Q┐┌W┐┌E┐┌R┐┌T┐┌Y┐...  │
│   (nowa gra)           │       │ │ klawiatura ekranowa │ │
│ [Graj] [Edytuj] [Nowa] │       │ └──── podpowiedzi ────┘ │
└────────────────────────┘       └────────────────────────┘

MENU PAUZY (P10, rysuje jądro)   EKRAN BŁĘDU (P6, rysuje jądro)
┌────────────────────────┐       ┌────────────────────────┐
│   gra przyciemniona    │ górny │ src/enemy.lua:7:       │
│   ▸ Wznów              │       │ attempt to index nil   │
│     Restart            │       ├────────────────────────┤
│     Edytuj kod         │ dolny │ ślad stosu (dotknij)   │
│     Wyjdź do menu      │       │ [Restart][Edytuj][Menu]│
└────────────────────────┘       └────────────────────────┘
```

- **Ekran błędu i tymczasowa lista kartridży** (do P10) są rysowane w C fontem 6×8 na 3D,
  już w docelowym stylu (zrobione w P6, D28). „Edytuj” na ekranie błędu działa od P11.
- **Menu pauzy** rysuje jądro na ostatniej klatce gry (przyciemnionej), gra jest wtedy
  zatrzymana (nie są wołane `_update`/`_draw`).

## 5. Kartridże systemowe

- **Wbudowane w ROM** (NitroFS `nitro:/system/<nazwa>/`): `launcher`, `code` (edytor
  kodu), później `gfx`, `map`, `sfx`. Zawsze działają i zawsze pasują do wersji silnika.
- **Nadpisanie z karty:** jeśli istnieje `sd:/litelua/system/<nazwa>/` (folder albo
  `<nazwa>.lcart`), uruchamia się ta wersja. Silnik sprawdza `api` w jej `cart.lua`; gdy
  nie pasuje do wersji silnika, uruchamia wersję z ROM i zapisuje ostrzeżenie w logu.
- **Tryb awaryjny:** SELECT trzymany przy starcie LiteLua → tylko wersje z ROM (zepsuty
  launcher z karty nie zablokuje konsoli). Usunięcie folderu z karty przywraca wbudowaną
  wersję na stałe.
- **Kopiowanie do przerabiania:** launcher ma opcję „Kopiuj systemowe na kartę”
  (kopiuje wybrany kartridż systemowy z ROM do `sd:/litelua/system/`), potem można go
  edytować na DS jak każdą grę.
- **Uruchamianie:** `sys.run("@launcher")` — nazwa z `@` oznacza kartridż systemowy.
- **Dodatkowe API** (tylko dla kartridży systemowych, tabela `sys.system`, szczegóły w
  P10/P11): lista kartridży z manifestami i ikonami, odczyt i zapis plików dowolnego
  kartridża, tworzenie nowego kartridża, uruchomienie gry z powrotem do wywołującego
  (edytor ↔ gra, D14), przekazanie danych przy przełączeniu (np. plik i linia).
  Zwykłe gry nie widzą `sys.system`.

## 6. `print` i konsola

- `print` zawsze pisze do `litelua/log.txt` (D18).
- Od P6 dolny ekran nie jest konsolą; ostatnie ~20 linii `print` można podejrzeć w
  półprzezroczystej **nakładce konsoli** (L+R+X), jak nakładkę statystyk.
- `log` — tylko do pliku, bez nakładki.
