# HeroesDS — plan

Fanowska gra w stylu Heroes of Might and Magic IV na LiteLua (DS/DSi), na oryginalnych
zasobach gry (tylko do użytku prywatnego — H1). Dwa tryby:
- **mapa kontynentu** — prowincje, miasta, armie (jak w Imperial Glory),
- **walka** — jak w H4: dolny ekran = mapa walki, górny = animowane starcie dwóch jednostek
  w przeciwległych narożnikach (duże sprite'y bojowe ładowane i zwalniane w locie).

## Gdzie skończyliśmy
H0 zrobione. Otwarte pytania przed H1/C1:
- walka wierna zasadom H4 (wzory 1:1) czy „w stylu H4”, uproszczona pod DS?
- kolejność: H1 i C1 na zmianę, czy najpierw jeden tor do końca?

Szkic czytnika archiwów: `tools/h4r.py` (format opisany w docstringu; nie czyta jeszcze
całego katalogu — błąd przy końcówce wpisu, do poprawy w H1).

## Punkty

### H0 — Fundament ✅
Folder w repo LuaDS (H1), wykluczenia w `.gitignore`, plan i decyzje.

### Tor A — grafika
- **H1 — Formaty.** Czytnik `.h4r` (gzip w środku), format sekwencji aktorów (klatki,
  offsety, kierunki, cienie, prędkość, klatki współdzielone). Wynik: `docs/FORMATS.md`.
  Najpierw sprawdzić, czy formaty są już opisane w sieci.
- **H2 — Możliwości LiteLua.** Sprite'y, palety, rozmiary tekstur, budżet VRAM/RAM na
  dwie duże animacje na górnym ekranie, ładowanie/zwalnianie w locie. Braki → osobny punkt
  w planie LiteLua (`docs/PLAN.md` w głównym repo).
- **H3 — Konwerter PC → LiteLua.** Profile: *mapa* (małe sprite'y, mało klatek) i *walka*
  (większe klatki, skala pod 256×192). Paleta, atlas klatek, meta `.lua` (animacje,
  kierunki, offsety, czasy).
- **H4 — Przeglądarka animacji (kartridż).** Dwie jednostki w rogach górnego ekranu:
  ładowanie, animacja, zwalnianie, pomiar pamięci.

### Tor B — walka (bez grafiki)
- **C1 — Mechanika.** Manuale, Monster Manual, h4.heroes.net.pl: statystyki, wzór obrażeń,
  inicjatywa, kontratak, morale/szczęście, moce jednostek, czary obszarowe.
  Wynik: `docs/MECHANICS.md`.
- **C2 — Projekt systemu walki.** Model danych (jednostka, oddział, pole bitwy), kolejka
  tur, akcje, moce jako hooki, deterministyczny seed.
- **C3 — Silnik walki w czystym Lua** + testy na PC.
- **C4 — Podpięcie do kartridża** ze stubami grafiki (dolny ekran mapa walki, górny starcie).

### Później
Tryb mapy kontynentu — osobny plan, gdy walka będzie stała.
