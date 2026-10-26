# HeroesDS — plan

Fanowska gra w stylu Heroes of Might and Magic IV na LiteLua (DS/DSi), na oryginalnych
zasobach gry (tylko do użytku prywatnego — H1). Dwa tryby:
- **mapa kontynentu** — prowincje, miasta, armie (jak w Imperial Glory),
- **walka** — jak w H4: dolny ekran = mapa walki, górny = animowane starcie dwóch jednostek
  w przeciwległych narożnikach (duże sprite'y bojowe ładowane i zwalniane w locie).

## Gdzie skończyliśmy
- **H1a ✅** czytnik archiwów `tools/h4r.py` + testy (`python -m unittest discover -s HeroesDS/tests`).
  Wszystkie 8 archiwów z `Data/` czytają się; z 21381 plików 2 nie dają się odczytać
  z winy danych gry (alias `layers.sample_cursor.h4d` na nieistniejący plik, uszkodzony
  `actor_sequence.hero.spazz_sword.combat.death.ne.h4d` w `x2_override.h4r`).
- **H1b ✅** dekoder sprite'ów `tools/h4d.py` → PNG (klatki z cieniem, strip, meta.json):
  `python HeroesDS/tools/h4d.py HeroesDS/Data/heroes4.h4r actor_sequence.bandit.combat.melee.sw.h4d HeroesDS/extracted/x`.
  Parsuje wszystkie 14449 `actor_sequence` ze wszystkich archiwów (liczba obrazów
  zgodna z nagłówkiem). Wynik zgodny z H4ResHelper (bandit.stand.e: 6 obrazów, 5 klatek).
- **Następny krok: H1c** — meta sekwencji: co znaczy pole „speed” w palecie (klatki: 24/16,
  cienie: 8 — raczej nie prędkość; H4ResHelper pokazuje Speed 100), skąd czas klatek,
  nagłówek typu 3 (+6 bajtów: 4449 plików — jeźdźcy/strzelcy?), które kierunki istnieją
  (walka bandyty: melee ma 8, die/fidget 4 ukośne), `combat_actor.*` i `adv_actor.*`.
- Pobrany kod z sieci (`ref/`) — nie uruchamiamy go (blokada auto mode); czytamy opis
  i piszemy własny.
- Pracujemy małymi krokami: jeden podpunkt = test na PC + lokalny commit + ta sekcja.

## Co już wiemy
- `heroes4.h4r` (600 MB) to główne zasoby: `actor_sequence` (11285 animacji),
  `adv_object` (2767), `combat_object` (1048), `sound` (990), `layers` (656, interfejs),
  `combat_actor` (139), `adv_actor` (137), `terrain`, `battlefield_preset_map`.
  `x2*.h4r`, `storm*.h4r`, `updates.h4r` — dodatki i poprawki (override: nowsze wersje).
- Animacje jednostki (np. `bandit`): mapa przygody = `actor_sequence.bandit.<anim>.<kier>`
  (stand, walk, prewalk, postwalk, attack, fidget; 8 kierunków); walka =
  `actor_sequence.bandit.combat.<anim>.<kier>` (base_frame, wait, fidget, walk, melee,
  melee_up, flinch, die, …; często tylko 4 kierunki ukośne — reszta przez odbicie?).
  Do tego `combat_actor.bandit.h4d` i `adv_actor.bandit.h4d` (meta jednostki, do zbadania).
- Klatki animacji bywają współdzielone: nazwa obrazu „frame 002 004” = obraz klatek 2 i 4
  (cienie tak samo: „shadow 002 004”). Klatki 8-bit z paletą ≤255 kolorów + alfa 4 bity,
  cienie 1 kolor + alfa. Pozycje na płótnie 800×600, origin zwykle (−361, −347).
- Rozmiary: bandyta na mapie ~52×45 px/klatka, w walce do ~205×173 (cały ruch ciosu),
  pojedyncza klatka ~120×100 → na DS trzeba skalować (H3).
- Źródła i licencje: H3 w `DECISIONS.md`.

## Punkty

### H0 — Fundament ✅
Folder w repo LuaDS (H1), wykluczenia w `.gitignore`, plan i decyzje.

### Tor A — grafika
- **H1 — Formaty.** Wynik: `docs/FORMATS.md`.
  - **H1a ✅** czytnik `.h4r` (gzip w środku, aliasy) + testy.
  - **H1b ✅** dekoder obrazów `.h4d` → PNG (klatki, cienie, alfa) + testy.
  - **H1c** meta sekwencji: kolejność i czas klatek, origin, kierunki (które są odbiciami),
    `combat_actor` / `adv_actor`.
  - **H1d** `docs/FORMATS.md` — opis formatów własnymi słowami.
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
