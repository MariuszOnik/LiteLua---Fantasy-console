# HeroesDS — plan

Fanowska gra w stylu Heroes of Might and Magic IV na LiteLua (DS/DSi), na oryginalnych
zasobach gry (tylko do użytku prywatnego — H1). Dwa tryby:
- **mapa kontynentu** — prowincje, miasta, armie (jak w Imperial Glory),
- **walka** — jak w H4: dolny ekran = mapa walki, górny = animowane starcie dwóch jednostek
  w przeciwległych narożnikach — **zmienione decyzją H5**: walka na polu bitwy z małymi
  sprite'ami, bez zbliżenia.

## Gdzie skończyliśmy (notka dla nowego czatu, 2026-10-26)

**Stan:** tor A (grafika) do H2 włącznie; tor B: C1 (mechanika), C2 (projekt walki,
`docs/COMBAT.md`, zaakceptowany) i **C3 (silnik walki w czystym Lua) zamknięte**.
`HeroesDS/combat/`: `num` (float32 jak oryginał), `rng`, `grid` (pole, droga, strefy
kontroli), `stats`, `damage`, `battle` (rundy, kolejka, akcje, zdarzenia, powtórki —
jedyne API dla ekranu), `magic` (rdzeń czarów), `abilities` (zdolności jako hooki),
`heroes` (bohater, artefakty, premie armii, `heroes.build`), `casting` (czary), `ai`
(przeciwnik komputerowy). Szczegóły i podział C3a–C3f: `COMBAT.md` §11. Decyzje H6–H10
(ekrany, dzielenie obrony, skala pola + lupa, zabity nie oddaje, reguły bohatera z opisów).

**C4b (bitwa na DS ze stubami grafiki) — zrobione.** Kartridż `carts/c4`
(`python HeroesDS/tools/make_c4.py`; wspólne kroki w `tools/cartkit.py`): `src/view.lua`
(skala 3/16, romby oddziałów z liczebnością, kropki zasięgu co 3 pola, droga i obrys celu),
`src/setup.lua` (armie testowe z ziarna jak w c4bench), `main.lua` (tura gracza: dotyk
oddziału wroga = atak / strzał z podglądem obrażeń i odwetu, dotyk ziemi = ruch na najbliższe
osiągalne miejsce, drugi dotyk lub A = wykonaj, B = anuluj; przyciski Cz(ekaj) / Ob(rona) po
lewej; komputer gra stroną 1 w korutynie z klepsydrą; Y = komputer gra też za gracza; górny
ekran: runda, aktywny oddział, wybór, kolejka, dziennik po polsku). Sprawdzone w melonDS:
podgląd, atak, ruch, autobitwa do końca.

**C4c (sterowanie i pokaz zdarzeń) — zrobione.** W `carts/c4`: lupa ×2 na L/R wokół
rysika / aktywnego oddziału (rysik przy krawędzi przewija; `view.set_camera`), krzyżak
przesuwa kursor, A dotyka w jego miejscu; Księga czarów (przycisk Ks po prawej, lista na
dolnym ekranie, cel wg `casting.aim`: oddział / pole / oba / dwa oddziały / oddział i
miejsce, podświetlone cele z `casting.check`, drugi dotyk = rzuć); zdarzenia pokazywane po
kolei (oddział idzie po drodze, liczby obrażeń / leczenia nad celem, krótkie pauzy).
Test `tests/c4_test.lua` (lupa, atrapy API LiteLua): tury gracza dotykiem, Magiczna Strzała
z Księgi, potem komputer kończy bitwę.

**Następny krok:** gra na DSi (C4 wrzucone przez FTP do `litelua/carts/c4`) i poprawki
z rozgrywki; potem H3 (konwerter grafiki) i H4 (pole z prawdziwymi sprite'ami) — albo
decyzja o innym polu walki, jeśli sterowanie na drobnej siatce się nie sprawdzi.

**C4a (pomiar i przyspieszenie) — zrobione.** Kartridż `carts/c4bench`
(`python HeroesDS/tools/make_c4bench.py`: silnik + reguły bez opisów, wynik PC do
`data/pc.lua`, kopia na kartę melonDS; na DSi przez FTP). Szukanie drogi w C przez API
LiteLua `pathgrid` / `grid:flood` (D57), gdy jest (`grid.native`); Lua zostaje wzorcem (PC,
testy). melonDS (DS), 12 bitew komputer–komputer: szukanie 3,2 s → 37 ms, tura komputera
średnio 73 ms, najgorsza 0,6 s (diabeł z teleportem), najdłuższy kawałek bez `grid.tick`
0,19 s (jedno wywołanie C — klepsydra może lekko szarpnąć); C = Lua (0 różnic), 12/12 bitew =
PC bit w bit; pamięć Lua w bitwach do ~1,45 MB (śmieci przed GC). DSi (pierwsza wersja C):
szukanie 63 ms, tura 83 ms — DSi tylko ~25% szybsze od melonDS w trybie DS. Wczytanie: kod
0,65 s, reguły 0,36 s, kształt pola 0,6 s (raz). Przyspieszenia w Lua: `Field:fits` z sum
prefiksowych, koszty całkowite ×32, lot bez ponownego szukania, `attack_positions` / Iskry /
`free_spot` / teleport bez skanu całego pola po oddziałach, `Field:changed()` po zmianie pól.

**Przeczytaj najpierw:** `docs/DECISIONS.md` (H1–H10), `docs/COMBAT.md` (architektura walki, §11 — stan C3),
`docs/MECHANICS.md` (zasady walki 1:1, §1–14), `docs/DS_GRAPHICS.md` (pamięć wideo, style,
pomiary DSi), `docs/FORMATS.md`.

**Dane z gry** (lokalnie, poza repo — `Data/` i `extracted/` są w `.gitignore`):
- `python HeroesDS/tools/make_rules.py` → `extracted/rules/creatures.lua` (74 jednostki),
  `artifacts.lua` (248), `spells.lua` (193) — polskie nazwy (gra GOG po polsku, cp1250).
- Grafika: `tools/h4atlas.py --style test1` (styl użytkownika z `tools/styles.json`),
  `tools/style_tuner.py` (okno do strojenia stylu), `tools/h4d.py` (podgląd PNG).
- `ref/homm4-mac/` — klon Anbrose/homm4-mac (MIT): silnik H4 w Swifcie z adresami exe;
  źródło reguł. Jeśli brak: `git clone --depth 1 https://github.com/Anbrose/homm4-mac.git ref/homm4-mac`.
  Tylko czytamy (nie uruchamiamy pobranego kodu — blokada auto mode); tabele zbudowane
  w kodzie exe są już przeniesione do `tools/exe_tables.py` i `tools/creature_abilities.py`.

**Testy:** `python -m unittest discover -s HeroesDS/tests` (38 testów Pythona, w tym `test_combat`: 17 + 15 + 18 + 7 + 15 + 7 przypadków w Lua przez `lupa`; dane syntetyczne, `real_creatures` także na `extracted/rules/creatures.lua`, gdy jest).

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
- **C2 — Projekt systemu walki ✅** Wynik: `docs/COMBAT.md`, decyzje H6–H8.
- **C3 — Silnik walki w czystym Lua ✅** + testy na PC: C3a wzory i siatka, C3b bitwa i akcje,
  C3c zdolności, C3d bohater i artefakty, C3e czary, C3f prosty AI (`COMBAT.md` §11).
- **C4 — Podpięcie do kartridża** ze stubami grafiki (pole bitwy + ekran informacji, H5).

### Później
Tryb mapy kontynentu — osobny plan, gdy walka będzie stała. **Najpierw przeczytać
sekcję „Ważne na później: mapa przygody i teren” w `docs/FORMATS.md`** (teren 2.5D
z mapą wysokości, tekstury rombów, format `.h4c`, test z dwiema mapami z edytora).
