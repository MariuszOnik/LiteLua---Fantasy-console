# HeroesDS — plan

Fanowska gra w stylu Heroes of Might and Magic IV na LiteLua (DS/DSi), na oryginalnych
zasobach gry (tylko do użytku prywatnego — H1). Dwa tryby:
- **mapa kontynentu** — prowincje, miasta, armie (jak w Imperial Glory),
- **walka** — jak w H4: dolny ekran = mapa walki, górny = animowane starcie dwóch jednostek
  w przeciwległych narożnikach — **zmienione decyzją H5**: walka na polu bitwy z małymi
  sprite'ami, bez zbliżenia.

## Gdzie skończyliśmy (notka dla nowego czatu, 2026-10-26)

**Stan:** tor A (grafika) do H2 włącznie i tor B **C1 (mechanika) zamknięte**. Kodu walki
jeszcze nie ma — jest komplet zasad i danych.

**Następny krok: C2 — projekt systemu walki** (dokument, bez kodu; do akceptacji użytkownika):
model danych (oddział, bohater, pole bitwy 102×102, efekty czarów), kolejka tur, akcje
(ruch, atak, strzał, czar, czekanie, obrona), zdolności i czary jako dane + hooki (H2),
deterministyczny seed (LCG z `MECHANICS.md` §6.1), zdarzenia dla animacji. Do rozstrzygnięcia
z użytkownikiem w C2: który ekran = pole bitwy (dotyk!), który = informacje (H5); czy liczymy
dzielenie obrony przez Walkę wręcz/Łucznictwo (tylko w opisie gry, `MECHANICS.md` §13.2);
skala siatki na DS (102×102 pól na 256×192). Potem C3 (silnik w czystym Lua + testy na PC,
`lupa`), C4 (kartridż ze stubami grafiki), H4 (makieta pola bitwy w stylu `test1`).

**Przeczytaj najpierw:** `docs/DECISIONS.md` (H1–H5), `docs/MECHANICS.md` (zasady walki 1:1,
§1–14), `docs/DS_GRAPHICS.md` (pamięć wideo, style, pomiary DSi), `docs/FORMATS.md`.

**Dane z gry** (lokalnie, poza repo — `Data/` i `extracted/` są w `.gitignore`):
- `python HeroesDS/tools/make_rules.py` → `extracted/rules/creatures.lua` (74 jednostki),
  `artifacts.lua` (248), `spells.lua` (193) — polskie nazwy (gra GOG po polsku, cp1250).
- Grafika: `tools/h4atlas.py --style test1` (styl użytkownika z `tools/styles.json`),
  `tools/style_tuner.py` (okno do strojenia stylu), `tools/h4d.py` (podgląd PNG).
- `ref/homm4-mac/` — klon Anbrose/homm4-mac (MIT): silnik H4 w Swifcie z adresami exe;
  źródło reguł. Jeśli brak: `git clone --depth 1 https://github.com/Anbrose/homm4-mac.git ref/homm4-mac`.
  Tylko czytamy (nie uruchamiamy pobranego kodu — blokada auto mode); tabele zbudowane
  w kodzie exe są już przeniesione do `tools/exe_tables.py` i `tools/creature_abilities.py`.

**Testy:** `python -m unittest discover -s HeroesDS/tests` (31 testów, dane syntetyczne).

**Konsola / emulator:** kartridże HeroesDS w `HeroesDS/carts/` (grafika generowana lokalnie);
melonDS: `tools/melon.py` (w skrypcie `tap 28 178` = Play w launcherze — klawisze bywają
gubione); DSi: FTP `192.168.1.86:5000` (DHCP — może się zmienić), `curl --ftp-create-dirs -T`
do `litelua/carts/<cart>/`, log `litelua/log.txt`.

**Styl pracy:** małe kroki — punkt = test na PC + lokalny commit + aktualizacja tej sekcji;
push tylko na prośbę. Po polsku. Edycje z `\` tylko narzędziem Edit lub skryptem z Write
(heredoc w bashu psuje znaki ucieczki).

## Co już wiemy
- `heroes4.h4r` (600 MB) to główne zasoby: `actor_sequence` (11285 animacji),
  `adv_object` (2767), `combat_object` (1048), `sound` (990), `layers` (656, interfejs),
  `combat_actor` (139), `adv_actor` (137), `terrain`, `battlefield_preset_map`.
  `x2*.h4r`, `storm*.h4r`, `updates.h4r` — dodatki i poprawki (override: nowsze wersje).
- Animacje jednostki (np. `bandit`): mapa przygody = `actor_sequence.bandit.<anim>.<kier>`
  (stand, walk, prewalk, postwalk, attack, fidget; 8 kierunków); walka =
  `actor_sequence.bandit.combat.<anim>.<kier>` (base_frame, wait, fidget, walk, melee,
  melee_up, flinch, die, …; część tylko w 4 kierunkach ukośnych).
  `combat_actor.<x>` / `adv_actor.<x>` mówią, która sekwencja gra w którym z 8 kierunków
  — brakujący kierunek wskazuje najbliższy narysowany (bandit die: e → se), bez odbić.
- Czas klatek: fps z `combat_actor`/`adv_actor` (walka zwykle 9–10, wait 5; mapa 10).
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
- **H1 — Formaty ✅** Wynik: `docs/FORMATS.md`.
  - **H1a ✅** czytnik `.h4r` (gzip w środku, aliasy) + testy.
  - **H1b ✅** dekoder obrazów `.h4d` → PNG (klatki, cienie, alfa) + testy.
  - **H1c ✅** `combat_actor` / `adv_actor`: animacje, fps, kierunki, rozmiar, dystanse.
  - **H1d ✅** `docs/FORMATS.md` — opis formatów własnymi słowami.
- **H2 — Możliwości LiteLua ✅** (H2a analiza, H2b/H2c pomiary melonDS i DSi, trzy style, H2d tuner stylu → `docs/DS_GRAPHICS.md`; decyzje H4, H5) Sprite'y, palety, rozmiary tekstur, budżet VRAM/RAM na
  dwie duże animacje na górnym ekranie, ładowanie/zwalnianie w locie. Braki → osobny punkt
  w planie LiteLua (`docs/PLAN.md` w głównym repo).
- **H3 — Konwerter PC → LiteLua.** Profile: *mapa* (małe sprite'y, mało klatek) i *walka*
  (większe klatki, skala pod 256×192). Paleta, atlas klatek, meta `.lua` (animacje,
  kierunki, offsety, czasy).
- **H4 — Makieta pola bitwy (kartridż).** 14 oddziałów w stylu `test1`, animacje,
  dociąganie akcji, zaznaczanie celu (H5). (Wcześniej: zbliżenie dwóch jednostek — zrobione
  w H2b i porzucone.)

### Tor B — walka (bez grafiki)
- **C1 — Mechanika ✅** Wynik: `docs/MECHANICS.md` (C1a rdzeń, C1b-1 dane jednostek,
  C1b-2 zdolności, C1b-3 bohater i artefakty, C1c czary) + generator `tools/make_rules.py`.
- **C2 — Projekt systemu walki.** Model danych (jednostka, oddział, pole bitwy), kolejka
  tur, akcje, moce jako hooki, deterministyczny seed.
- **C3 — Silnik walki w czystym Lua** + testy na PC.
- **C4 — Podpięcie do kartridża** ze stubami grafiki (pole bitwy + ekran informacji, H5).

### Później
Tryb mapy kontynentu — osobny plan, gdy walka będzie stała. **Najpierw przeczytać
sekcję „Ważne na później: mapa przygody i teren” w `docs/FORMATS.md`** (teren 2.5D
z mapą wysokości, tekstury rombów, format `.h4c`, test z dwiema mapami z edytora).
