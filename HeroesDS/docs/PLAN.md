# HeroesDS — plan

Fanowska gra w stylu Heroes of Might and Magic IV na LiteLua (DS/DSi), na oryginalnych
zasobach gry (tylko do użytku prywatnego — H1). Dwa tryby:
- **mapa kontynentu** — prowincje, miasta, armie (jak w Imperial Glory),
- **walka** — jak w H4: dolny ekran = mapa walki, górny = animowane starcie dwóch jednostek
  w przeciwległych narożnikach — **zmienione decyzją H5**: walka na polu bitwy z małymi
  sprite'ami, bez zbliżenia.

## Gdzie skończyliśmy
- **H1a ✅** czytnik archiwów `tools/h4r.py` + testy (`python -m unittest discover -s HeroesDS/tests`).
  Wszystkie 8 archiwów z `Data/` czytają się; z 21381 plików 2 nie dają się odczytać
  z winy danych gry (alias `layers.sample_cursor.h4d` na nieistniejący plik, uszkodzony
  `actor_sequence.hero.spazz_sword.combat.death.ne.h4d` w `x2_override.h4r`).
- **H1b ✅** dekoder sprite'ów `tools/h4d.py` → PNG (klatki z cieniem, strip, meta.json):
  `python HeroesDS/tools/h4d.py HeroesDS/Data/heroes4.h4r actor_sequence.bandit.combat.melee.sw.h4d HeroesDS/extracted/x`.
  Parsuje wszystkie 14449 `actor_sequence` ze wszystkich archiwów (liczba obrazów
  zgodna z nagłówkiem). Wynik zgodny z H4ResHelper (bandit.stand.e: 6 obrazów, 5 klatek).
- **H1c ✅** opisy jednostek `tools/h4actor.py` (`combat_actor` i `adv_actor`):
  `python HeroesDS/tools/h4actor.py HeroesDS/Data/heroes4.h4r combat_actor.bandit.h4d`.
  Wszystkie 348 plików (168 combat, 180 adv) czytają się co do bajtu. Daje: listę
  animacji, fps, klatkę trafienia, sekwencję dla każdego z 8 kierunków, rozmiar na siatce
  walki (1–7 pól), wysokość, dystanse chodu, punkty wylotu pocisków, przesunięcia.
- **H1d ✅** `docs/FORMATS.md` — opis formatów `.h4r`, `.h4d`, `combat_actor`,
  `adv_actor`. **H1 zamknięte.**
- `ref/homm4-mac/` — pełny klon Anbrose/homm4-mac (MIT, do czytania): silnik gry
  w Swifcie (`native/Sources/H4Engine/`: `Battle.swift`, `BattleSpells.swift`,
  `Combat.swift`, `Spells.swift`, `Tables.swift` …) z adresami w `heroes4.exe` —
  główne źródło dla C1. W nowym czacie, jeśli brak: `git clone --depth 1
  https://github.com/Anbrose/homm4-mac.git ref/homm4-mac`.
- **H2a ✅** analiza możliwości LiteLua i budżetu VRAM → `docs/DS_GRAPHICS.md`;
  propozycja zaakceptowana (decyzja H4).
- **H2b ✅ (melonDS)** kartridż `carts/h2b` + generator atlasów `tools/h4atlas.py`
  (animacja → atlas PNG z paletą, cień 2× mniejszy, meta `.lua`) i `tools/make_h2b.py`
  (generuje grafikę kartridża lokalnie i kopiuje na kartę emulatora). Wyniki
  w `DS_GRAPHICS.md`: bandyta melee 183 ms / 68 KB, smok melee 354 ms / 136 KB, cykle
  ładuj–zwolnij bez wycieków, starcie działa, dociąganie przy ataku ~290 ms.
  Uruchamianie w melonDS: launcher czasem gubi pierwsze klawisze — `tap 28 178`
  (przycisk Play) w skrypcie `tools/melon.py` działa pewnie.
- **H2c ✅** trzy style grafiki (current / smooth / oldschool) w `tools/h4atlas.py --style`,
  kartridż `h2b` z przełączaniem L/R (bandyta vs smok), poprawki falowania i palety (ogień);
  pomiar na DSi: oldschool 171–201 ms przestoju przy ataku, smooth nie mieści kompletu.
  Wyniki: `DS_GRAPHICS.md`, sekcja „Trzy style”. **Użytkownikowi podoba się oldschool** —
  do potwierdzenia jako decyzja (H5) i dostrojenia (kontrast, 16 vs 32 kolory?).
- Wysyłanie na konsolę: FTP `192.168.1.86:5000` (DHCP), pliki kartridża do
  `litelua/carts/h2b/` (`curl --ftp-create-dirs -T`), log: `litelua/log.txt`.
- **H2d ✅** narzędzie `tools/style_tuner.py` (okno z suwakami, presety, Reset, ograniczenia
  DS: 16/256 kolorów, kolory 15-bit, ocena pamięci; zapis do `tools/styles.json`).
  Użytkownik dostroił styl **`test1`** (skala 0,19, bez obrysu) — sprawdzony w `h2b`.
- **Decyzja H5:** bez zbliżenia starcia — walka na polu bitwy z małymi sprite'ami
  w stylu `test1`. Kartridż `h2b` (zbliżenie) jest już tylko historią pomiarów.
- **C1a ✅** rdzeń mechaniki walki → `docs/MECHANICS.md`: pole 102×102, ruch, kolejność
  (klucz Speed+1000, czekanie, obrona), morale, szczęście, wzór obrażeń, strzał (dzielniki),
  kontratak i wymiana jednoczesna, First Strike, kontrstrzał, bohater w walce.
  Źródło: `ref/homm4-mac` (`Combat.swift`, `Battle.swift`) + manual (tekst:
  `pdftotext` do `extracted/text/`, poza repo).
- **C1b-1 ✅** dane jednostek z gry: czytnik tabel `tools/h4table.py` (cp1250 — polska
  wersja), generator `tools/make_rules.py` → `extracted/rules/creatures.lua` (74 jednostki:
  statystyki, polskie nazwy, zdolności z exe — `tools/creature_abilities.py`, rozmiar,
  odporność na magię). Block rozstrzygnięty: 30 % szansy na pełny blok.
- **Następny krok: C1b-2** — działanie zdolności (efekty po ciosie, dodatkowe cele, początek
  tury) do `MECHANICS.md`; potem C1b-3 umiejętności bohaterów; C1c czary.
- Mapa świata: ustalenia o terenie 2.5D zapisane w `docs/FORMATS.md` (sekcja „Ważne na później”).
- Otwarte w formatach (`FORMATS.md`): pole `?` palety, sekwencje bohaterów.
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
- **H2 — Możliwości LiteLua.** (H2a ✅ analiza → `docs/DS_GRAPHICS.md`; H2b ✅ melonDS, DSi do zrobienia) Sprite'y, palety, rozmiary tekstur, budżet VRAM/RAM na
  dwie duże animacje na górnym ekranie, ładowanie/zwalnianie w locie. Braki → osobny punkt
  w planie LiteLua (`docs/PLAN.md` w głównym repo).
- **H3 — Konwerter PC → LiteLua.** Profile: *mapa* (małe sprite'y, mało klatek) i *walka*
  (większe klatki, skala pod 256×192). Paleta, atlas klatek, meta `.lua` (animacje,
  kierunki, offsety, czasy).
- **H4 — Makieta pola bitwy (kartridż).** 14 oddziałów w stylu `test1`, animacje,
  dociąganie akcji, zaznaczanie celu (H5). (Wcześniej: zbliżenie dwóch jednostek — zrobione
  w H2b i porzucone.)

### Tor B — walka (bez grafiki)
- **C1 — Mechanika.** Manuale, Monster Manual, h4.heroes.net.pl: statystyki, wzór obrażeń,
  inicjatywa, kontratak, morale/szczęście, moce jednostek, czary obszarowe.
  Wynik: `docs/MECHANICS.md`.
- **C2 — Projekt systemu walki.** Model danych (jednostka, oddział, pole bitwy), kolejka
  tur, akcje, moce jako hooki, deterministyczny seed.
- **C3 — Silnik walki w czystym Lua** + testy na PC.
- **C4 — Podpięcie do kartridża** ze stubami grafiki (dolny ekran mapa walki, górny starcie).

### Później
Tryb mapy kontynentu — osobny plan, gdy walka będzie stała. **Najpierw przeczytać
sekcję „Ważne na później: mapa przygody i teren” w `docs/FORMATS.md`** (teren 2.5D
z mapą wysokości, tekstury rombów, format `.h4c`, test z dwiema mapami z edytora).
