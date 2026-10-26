# Projekt systemu walki (C2)

Status: **zaakceptowany** (2026-10-26, razem z propozycją z §8). C3a zrobione — §11. Zasady gry są w `MECHANICS.md`
(„co liczymy”); ten dokument mówi, **jak** silnik jest zbudowany. Decyzje podjęte w C2:
H6 (ekrany), H7 (dzielenie obrony), H8 (skala pola + lupa) — `DECISIONS.md`.

## 1. Założenia

1. **Silnik walki = czysty Lua bez grafiki.** Nie wywołuje żadnego API LiteLua (`spr`,
   `btn`, `sys`…). Działa tak samo w kartridżu na DS i w testach na PC (`lupa`).
2. **Interfejs nigdy nie zmienia stanu bitwy.** Pyta silnik o dozwolone akcje, wysyła
   polecenie, dostaje listę **zdarzeń** do odegrania (animacje, dźwięki, dziennik).
3. **Determinizm**: ziarno + lista poleceń → zawsze ten sam przebieg, na PC i na DS.
   Daje to powtórki, testy regresji i porównanie PC ↔ konsola sumą kontrolną stanu.
4. **Zasady jako dane + hooki** (H2): zdolności, czary i artefakty to wpisy w tabelach
   z funkcjami podpiętymi pod nazwane punkty silnika, a nie warunki rozsiane po kodzie.

## 2. Liczby — całkowite, a float32 tam, gdzie oryginał

LiteLua ma `LUA_32BITS` (D3): liczby zmiennoprzecinkowe są pojedynczej precyzji, a na PC
(`lupa`) podwójnej. Gdyby te same wzory liczyły na różnych ułamkach, wynik na DS mógłby się
różnić od testu o 1 PW i powtórka by się rozjechała. Dlatego:
- **większość mechaniki liczy na liczbach całkowitych** (PW, rzuty, procenty, `//`, `>>`
  jak w exe), wartości jak na ekranie gry (atak bandyty 9, bohatera 10–40; artefakty
  podają premie bohatera w dziesiątych — dzielimy przy wczytaniu);
- **tam, gdzie oryginał liczy na `Float`** (stosunek atak/obrona z mnożnikami czarów,
  koszty ruchu 1 / 1,5 i strefy kontroli, linia strzału), liczymy na float32 — każdy wynik
  działania przechodzi przez `num.f32()`. Na PC to zaokrąglenie do najbliższej liczby
  float32 (`string.pack("f")`), co dla `+ − × ÷ √` daje dokładnie wynik arytmetyki float32;
  na DS `f32` nic nie robi. Tak jest bliżej exe niż przybliżanie liczbami całkowitymi;
- **odległości** w połówkach pól, porównywane jako kwadraty (bez `sqrt`): środek oddziału
  = `2·x + rozmiar` (pół-pola), „odległość ≥ 40 pól” → `(2dx)² + (2dy)² ≥ 6400`;
  kierunki (8 sektorów po 45°) też dokładnie na liczbach całkowitych.

Generator losowy (`rng.lua`, §6.1 mechaniki): `x = (x·214013 + 2531011) & 0xFFFFFFFF`,
wynik `(x >> 16) & 0x7FFF`. Działa identycznie na 32 i 64 bitach. **Żadnego `math.random`.**

**Kolejność iteracji**: `pairs()` nie gwarantuje kolejności, a kolejność rzutów zmienia
wynik. Wszystko, co losuje lub zależy od kolejności, iteruje po tablicach z indeksami
(oddziały w stałym porządku, zdolności w kolejności z exe — §12.5).

## 3. Moduły

Katalog `HeroesDS/combat/` (kod nasz, zlib jak repo; reguły z `MECHANICS.md`):

| plik | zawartość |
|---|---|
| `num.lua` | `f32`, zaokrąglanie jak Swift (`round` od zera), `trunc`, `clamp`, stałe float |
| `rng.lua` | LCG, `roll(lo, hi)`; stan = jedna liczba |
| `grid.lua` | siatka 102×102, zajętość, przeszkody, sąsiedztwo kwadratów, szukanie drogi, linia strzału, obszary |
| `stats.lua` | statystyki pochodne oddziału: baza + bohater armii + artefakty + efekty (hook `modify_stat`) |
| `damage.lua` | wzory §6: podstawa, atak/obrona, strzał, szczęście, blok, zadawanie obrażeń |
| `abilities.lua` | zdolności jednostek jako zestawy hooków (§12) |
| `spells.lua` | rzucanie czarów: cele, siła, odporność, obszar, odbicie; obsługa per typ i wyjątki (§14) |
| `effects.lua` | efekty trwające na oddziale (czary, ogłuszenie, trucizna…): czas, znoszenie, rozpraszanie |
| `battle.lua` | stan bitwy, rundy, kolejka, akcje, zdarzenia, koniec bitwy — **jedyne API dla UI** |
| `ai.lua` | prosty przeciwnik komputerowy (C3, osobny krok) |

Dane reguł (`creatures.lua`, `spells.lua`, `artifacts.lua` z `make_rules.py`) silnik dostaje
jako tabele — nie czyta plików sam. Na DS razem ~230 KB źródła; w kartridżu generator
pomija opisy (`help`), a czytamy je osobno tylko na ekranie informacji.

## 4. Model danych

```lua
battle = {
  seed, rng,              -- rng: current LCG state
  round = 1, phase,       -- "deploy" | "turn" | "over"
  sides = { [0] = side, [1] = side },
  stacks = { ... },       -- all stacks (both sides, heroes too) in a fixed order; index = id
  grid,                   -- occupancy (stack id per cell), obstacles, terrain, smoke, sand
  active,                 -- id of the stack whose turn it is
  winner,                 -- side or nil
}

side = {
  heroes = { ... },       -- ids of hero stacks
  best = { offense=, defense=, tactics=, leadership= },  -- army bonuses (§13.3)
  hp_start, hp_lost,      -- for morale from losses (§4)
  ai = false,
}

stack = {
  id, side, kind,         -- kind: creature key ("bandit") or "hero"
  def,                    -- creature data (or the hero's computed sheet)
  count, count_start,     -- count_start: limit for vampire/resurrection
  hp,                     -- hit points per unit (with hit_points_pct)
  wounds,                 -- damage on the first unit
  x, y, size, facing,     -- top corner of the footprint, 8 directions
  shots, mana,            -- shots left; spell points of the stack/hero
  abilities = {},         -- set: from data + artifacts + effects
  effects = { list },     -- active effects in the order they were applied
  -- per round/turn:
  retaliated, waited, defending, acted, moved_points, morale_roll, key,
  summoned,               -- disappears after the battle
}
```

Bohater to oddział o liczebności 1 z tabelą `hero = { level, skills, artifacts,
spellbook }`; jego `def` (PW, atak, obrona, obrażenia, pociski) jest wyliczany raz na
początku bitwy (§9, §13).

Polegli zostają w `stacks` z `count = 0` (ciała dla Wskrzeszenia, Ożywienia).

## 5. Przebieg bitwy

```
new(setup, seed)                  -- armies, heroes, battlefield, obstacles
  deploy                          -- start positions (deploy table from the exe, §1)
  loop:
    start_round                   -- morale rolls, reset retaliated/waited, durations
    while someone can act:
      next_actor                  -- highest key (§3); ties: side 0, then stack order
      start_of_turn               -- regeneration, poison, lost turn (stun, fear…)
      wait for a command          -- UI or AI
      perform action -> events
      check end of battle
```

`battle:order()` zwraca przewidywaną kolejność do końca rundy (pasek kolejki na górnym
ekranie). Przy ≤ 16 oddziałach wystarczy co ruch wybrać maksimum klucza — bez kolejki
sortowanej.

## 6. Akcje (API dla interfejsu)

```lua
local opts = battle:options()      -- for the active stack
-- opts.move:   reachable cells (with cost), opts.melee: { [target_id] = { cells to attack from } }
-- opts.shoot:  { [target_id] = divisor }, opts.spells: { [spell] = { targets, area } }
-- opts.wait, opts.defend: bool

local events = battle:act{ type = "melee", target = 7, x = 40, y = 52 }   -- x, y optional
-- types: move{x,y} · melee{target,x,y} · shoot{target} · cast{spell,target | x,y}
--        wait · defend · (later: retreat, surrender, auto)
local hint = battle:preview{ type = "melee", target = 7, x = 40, y = 52 }
-- { min, max, kills_min, kills_max, retaliation = {min, max} } — no rolls, for the top screen
```

`act` sprawdza polecenie z `options()`; nieprawidłowe zwraca błąd i niczego nie zmienia.
`preview` liczy na kopii bez losowania (min/max rzutu, bez szczęścia i bloku).

## 7. Hooki — zdolności, efekty, artefakty

Każda zdolność i każdy efekt to wpis z funkcjami pod nazwanymi punktami silnika:

```lua
abilities.first_strike = { melee_order = function(ctx) ... end }
abilities.poison       = { after_hit = function(ctx) ... end }   -- §12.5 step 2
effects.bless          = { base_damage = function(ctx) ctx.roll = "max" end,
                           opposite = { "curse" } }
```

Punkty (pierwsza lista; rozszerzamy w C3):

| hook | kiedy | przykłady |
|---|---|---|
| `modify_stat` | liczenie statystyk | Przyspieszenie, Spowolnienie, Starość, Tarcza z Adamantu |
| `move_mode` | ruch | latanie, teleport, spętanie |
| `base_damage` | rzut podstawy | Błogosławieństwo, Klątwa, Siła smoka |
| `attack_mods` / `defense_mods` | §6.2 | Żądza krwi, Kamienna skóra, obrona, niematerialny |
| `after_ratio` | §6.2 po stosunku | ochrona przed charakterem, odporność na ogień, blok |
| `melee_order` | §7 | pierwsze uderzenie |
| `can_retaliate` | §7 | brak kontrataku, strach, ogłuszenie |
| `strikes` | §7 | podwójny cios, Koci Refleks |
| `extra_targets` | §12.4 | hydra, cerber, zionięcie, `area_effect` |
| `after_hit` | §12.5 | trucizna, tarcza ognia, ogłuszenie, wampir… |
| `start_of_turn` | §3 | regeneracja, trucizna, utrata tury |
| `on_death` | śmierć oddziału | odrodzenie feniksa |
| `spell_target` / `spell_resist` | §14.4 | ochrona przed szkołą, Magiczne lustro, niewrażliwość |

**Kolejność** wywołań w punkcie jest stała: najpierw zdolności w kolejności z exe (lista
w `abilities.lua`), potem efekty w kolejności nałożenia, potem artefakty. `ctx` to tabela
z bitwą, oddziałami i wartościami do zmiany. Kontekst nie tworzy nowych tabel w pętli
ciosu (GC na DS — tworzymy jeden `ctx` na cios i go czyścimy).

**Czary**: obsługa per `type` z `spells.lua` (`damage`, `curse`, `blessing`, `healing`,
`summoning`, `resurrection`) pokrywa większość; czary nietypowe (Wygnanie, Poświęcenie,
Męczennik, Kradzież zaklęć, piaski, dym, skały…) mają własną funkcję w `spells.lua`.
Czar trwający = efekt z tą samą nazwą w `effects.lua`.

## 8. Zdarzenia (dla animacji)

Silnik liczy całą akcję od razu; UI dostaje listę zdarzeń w kolejności, w jakiej mają się
odegrać. Stan po `act()` jest już końcowy — animacja tylko go pokazuje.

```lua
{ t = "turn", stack = 3 }                         { t = "round", n = 2 }
{ t = "morale", stack = 3, good = true }          { t = "luck", stack = 7, good = false }
{ t = "move", stack = 3, path = { {x,y}, ... } }  { t = "face", stack = 3, dir = "ne" }
{ t = "melee", stack = 3, target = 7 }            { t = "shoot", stack = 3, target = 7 }
{ t = "retaliate", stack = 7, target = 3 }        { t = "block", stack = 7 }
{ t = "damage", stack = 7, amount = 41, killed = 3, left = 12 }
{ t = "death", stack = 7 }                        { t = "spell", spell = "fireball", caster = 3, x =, y =, targets = {...} }
{ t = "effect", stack = 7, effect = "poison", on = true }
{ t = "summon", stack = 15 }                      { t = "over", winner = 0 }
```

`left` w `damage` pozwala UI pokazywać liczebność w trakcie animacji, zanim dojdzie do
końcowego stanu (tak robi homm4-mac).

**Wymiana jednoczesna (§7, otwarte z C1)** — nie wiążemy zasad z klatkami animacji (fps
i klatki na DS są uproszczone, H2, H4). Zmienione decyzją **H9**: cios atakującego ląduje
pierwszy, cel zabity w wymianie wręcz nie oddaje (jak exe przy równych czasach trafienia).

## 9. Ekrany i sterowanie (H6, H8)

**Dolny ekran — pole bitwy** (dotyk). Cała scena w skali **3/16 (0,1875)**:
1180×1024 → **221×192 px**, wycentrowana (17 px marginesu po bokach na przyciski: Czekaj,
Obrona, Księga, Opcje). Pole siatki = romb 6×3 px. Sprite'y w stylu `test1` (skala
w `styles.json` zmieni się z 0,19 na 0,1875 — różnica 1 %).

- **Dotyk na oddział** wroga = cel (atak / strzał / czar); swój = informacja; **dotyk na
  ziemię** = ruch. Pole nie jest wskazywane co do piksela: gra dociąga punkt do najbliższego
  dozwolonego miejsca (dla ataku wręcz — z której strony podejść, wg położenia rysika
  względem celu).
- **Dwa dotknięcia**: pierwsze wybiera i pokazuje podgląd (droga na ziemi, cel pulsuje
  `tint`, na górnym ekranie przewidywane obrażenia), drugie w to samo miejsce potwierdza.
  B anuluje.
- **Lupa (H8)**: przytrzymanie **L** (lub R — dla leworęcznych) powiększa ×2 okolicę
  rysika/kursora: skala 0,375 (romb 12×6), widać ok. połowę pola w każdą stronę. Przesuwanie
  rysikiem przy krawędzi przewija. Sprite'y w lupie: ten sam atlas powiększony `sprx` ×2
  (pikselowo) — bez drugiego kompletu grafiki. Puszczenie L wraca do całego pola, wybór
  zostaje.
- **Krzyżak** jako alternatywa dla rysika: kursor skacze po oddziałach (cele) / po polach,
  A = dotknięcie.

**Górny ekran — informacje**: aktywny oddział (portret, liczebność, PW, statystyki,
efekty), cel i podgląd obrażeń (min–max, zabici, kontratak), pasek kolejki do końca rundy,
dziennik ostatnich zdarzeń; przy czarach — lista z kosztem i opis.

## 10. Testy (C3)

- `HeroesDS/tests/test_combat.py` przez `lupa` (jak testy edytora w LuaDS): moduły Lua
  ładowane z dysku, dane reguł z `extracted/rules/` (test pomijany, gdy ich brak) albo
  syntetyczne.
- Przypadki z liczbami z `MECHANICS.md`: wzór obrażeń, szarża, strzał z dzielnikami,
  kolejka z morale i czekaniem, kontratak raz na rundę, pierwsze uderzenie, zdolności
  z §12.5, odporność na magię, obszar Kuli Ognia, znoszenie czarów.
- **Powtórka**: ziarno + polecenia → suma kontrolna stanu; ta sama powtórka w C4 na DS
  musi dać tę samą sumę (sprawdza 32-bitowe liczby).
- Gdzie się da — porównanie z wynikami `Battle.swift` liczonymi ręcznie (nie uruchamiamy
  pobranego kodu).

## 11. Podział C3 (propozycja)

- **C3a ✅** — `num`, `rng`, `grid` (pole, zajętość, sąsiedztwo, droga ze strefami kontroli,
  latanie, teleport, linia strzału), `stats` (oddział, bohater, szybkość, ruch, morale,
  szczęście, PW), `damage` (rzut, atak/obrona, H7, dzielnik strzału, szczęście); testy
  `tests/combat_test.lua`. `grid.reachable` dostaje opis ruchu (`budget`, `flies`,
  `teleport`, `zoc`, koszty) — wylicza go bitwa ze statystyk, siatka nie zna zasad.
  Szukanie drogi sprawdza zajętość leniwie (tylko odwiedzane pola); czas na DS do
  zmierzenia w C4.
- **C3b ✅** — `battle`: rozstawienie (tabela z exe, szyki luźny/zwarty/kwadrat), morale
  armii i strat, rundy i kolejka (morale, czekanie, utrata tury), ruch (też „w stronę” celu
  dalej niż tura), wręcz z kontratakiem (jednocześnie / pierwsze uderzenie / blok / wiele
  ciosów, wybór strony ataku `x, y` albo najtańsza), strzał z odpowiedzią, obrona, koniec
  bitwy (też po 60 rundach), zdarzenia, `options` / `act` / `preview` / `queue` /
  `attack_positions` / `checksum`; testy `tests/battle_test.lua` (powtórka z ziarna daje tę
  samą sumę kontrolną). Hooki dla C3c–C3e: `battle.hooks` (`start_of_turn`,
  `extra_targets`, `aftermath`, `on_death`, `fears`).
  - **Przełącznik `battle.dead_strike_back`** (domyślnie `false`, decyzja H9): cios
    atakującego ląduje pierwszy, zabity nie oddaje; `true` — zabity oddaje pełnym oddziałem.
  - **Wydajność (do C4)**: na PC zasięg ruchu na turę (ruch 27, rozmiar 4) = 7 ms, szukanie
    na 12 tur (atak na daleki cel) = 21 ms. DS jest wielokrotnie wolniejszy — zmierzyć;
    w razie potrzeby: mapa zajętości liczona raz na turę (sumy prefiksowe zamiast
    `fits`/`overlaps` po kwadracie), kopiec bez tabel na węzeł, krótszy zasięg „12 tur”.
- **C3c ✅** — `magic` (rdzeń czarów wspólny z C3e: cele, odporność, nakładanie / zdejmowanie
  z przeciwieństwami i czasem trwania, obrażenia czaru, przywracanie PW, moc czaru istoty),
  `abilities` (`abilities.install(battle)`: dodatkowe cele — hydra, cerber, zionięcie, strzał
  obszarowy; efekty po ciosie w kolejności exe; kamienne spojrzenie; strach; początek tury —
  regeneracja, trucizna, zaraza; śmierć — czyszczenie czarów, odrodzenie feniksa); testy
  `tests/abilities_test.lua` (+ `real_battles`: 25 pełnych bitew na prawdziwych danych, gdy są).
  Bitwa dostaje `spells` (z `spells.lua`) w `battle.new`. Uwaga do testów: kolejne ziarna
  (1, 2, 3…) dają w LCG bardzo podobne rzuty po tej samej liczbie kroków — pętle po ziarnach
  rozrzucamy (`seed * 7919 + 13`).
- **C3d ✅** — `heroes`: arkusz bohatera (umiejętności, artefakty, komplety, zdolności
  z opisów — H10), premie armii, czary z przedmiotów na wroga, `heroes.build(spec, data)` →
  `setup` dla `battle.new` (bohaterowie w pierwszych slotach). Testy `tests/heroes_test.lua`
  (+ `real_artifacts`: każdy artefakt z gry na bohaterze).
- **C3e ✅** — `casting` (`casting.install(battle)`, polecenie `{ type = "cast", spell, target?,
  x?, y?, second? }`, `options().spells = { [klucz] = { aim, cost } }`): księga bohatera
  (`heroes.caster`: znane czary, księgi i zwoje z przedmiotów, punkty czarów, premie siły
  i kosztu), czary istot (`cast_by`), koszt, siła (`magic.power`), celowanie (`aim`: none / unit /
  cell / unit_or_cell / unit_and_point / two_units / unit_then_cell), obszar, czary masowe,
  obsługa per `type` + wyjątki z `cast()` homm4-mac (łańcuch, Iskry, Wygnanie, rozpraszanie,
  kradzież zaklęć, Teleport, Przemieszczenie, Ruchome piaski, Dym, Wzrost skał, przywołania
  i ożywianie, fantomy, Męczennik, Poświęcenie, leczenie), Magiczne lustro, Kajdany. W `wound`:
  Niebiańska Tarcza, Męczennik, Anioł Stróż, Lustro Bólu (zdarzenia odroczone jak w exe).
  Testy `tests/casting_test.lua` (+ `real_spells`: każdy czar bojowy z gry rzucony przez
  arcymistrza na prawdziwych danych).
- **C3f** — prosty AI (najbliższy/najsłabszy cel, strzelcy strzelają, czary z obrażeniami).

Potem C4 (kartridż: pole bitwy ze stubami grafiki, H6/H8) i H4 (prawdziwe sprite'y).
