# Mechanika walki Heroes IV (do odwzorowania 1:1, decyzja H2)

Źródła (H3):
- **homm4-mac** (MIT): `ref/homm4-mac/native/Sources/H4Engine/` — `Combat.swift` (obrażenia),
  `Battle.swift` (pole bitwy, tury, wymiana ciosów), autor podaje adresy funkcji w `heroes4.exe`
  (w nawiasach niżej: „exe 0x…”, do weryfikacji w razie wątpliwości).
- **Manual H4** (`HoMM4_Manuals/`, tekst: `extracted/text/` po `pdftotext`) — rozdział Combat:
  zgodny co do zasad ogólnych (jednoczesny kontratak, szczęście zmniejsza otrzymywane obrażenia,
  atak jako mnożnik obrażeń).
- Liczby z gry (statystyki jednostek, czary) czytamy z plików gry (tabele w `text.h4r`) — C1b.

Status: **C1a — rdzeń** (ten plik). C1b — zdolności jednostek i umiejętności bohaterów,
C1c — czary (w tym obszarowe).

## 1. Pole bitwy

- Kwadratowa siatka **102 × 102 pól** (pole = 16 jednostek świata). Rysowana izometrycznie:
  pole to romb 32 × 16 px w oryginale (scena 1180 × 1024). Oś x biegnie na ekranie w dół
  w lewo, y w dół w prawo.
- Jednostka zajmuje **kwadrat rozmiar × rozmiar pól** (`combat_actor`, bajt 2: duszek 3,
  chłop 4, ork 5, tytan 6, smok 7). Pozycja = górny narożnik kwadratu.
- Atakujący (strona 0) startuje w lewym dolnym rogu i patrzy na `ne`, obrońca (strona 1)
  w prawym górnym i patrzy na `sw`. Szyk rozstawienia: tabela pól startowych w exe
  (`Battle.swift`: `deploy`); walczący do wręcz stoją z przodu, strzelcy i bohaterowie z tyłu.
- Przeszkody (`combat_object`) zajmują prostokąty pól; teren wpływa na ruch (manual: bagno).

## 2. Ruch

- Ruch po 8 kierunkach: krok prosty kosztuje **1**, ukośny **1,5** pola. Budżet na turę =
  statystyka **Move** (w polach; exe liczy w punktach ruchu = Move × 100).
- **Latanie**: przelatuje nad przeszkodami i jednostkami, ląduje tylko na wolnym miejscu.
  **Teleport**: dowolne wolne miejsce na polu.
- Jednostka zatrzymuje się tylko tam, gdzie zmieści się cały jej kwadrat.
- Modyfikatory (szczegóły w C1c): Haste/Speed +3 szybkości i +9 pól ruchu; Slow, Fatigue,
  Bind Flyer — połowa; Aging — połowa; Binding — brak ruchu.

## 3. Kolejność ruchów (runda)

- Runda: każdy oddział działa raz (atak, strzał, czar, ruch, obrona albo czekanie).
- **Klucz kolejności** (exe 0x5f3110): `Speed + 1000` (chyba że morale zawiodło)
  `+ 1000` przy dobrym morale; oddział, który **czekał**, ma klucz **ujemny**. Działa
  oddział z najwyższym kluczem. Remis: najpierw strona 0, potem kolejność oddziałów.
- **Czekanie** (Wait): raz na rundę; oddział przesuwa się na koniec rundy — czekający działają
  po wszystkich, **najwolniejszy pierwszy** (bo klucz ujemny). Berserk nie może czekać.
- **Obrona** (Defend): obrona ×2 do początku własnej następnej tury.
- Na początku każdej rundy każdy oddział losuje rzut morale 0–9 (sprawdzany, gdy przyjdzie
  jego kolej).
- Początek tury oddziału: regeneracja, trucizna, zaraza (C1c). Oddział oślepiony,
  ogłuszony, zamrożony, przerażony lub skonfundowany traci turę (czasy działania liczą się dalej).

## 4. Morale

- Zakres **−10 … +10**. Jednostki **mechaniczne i nieumarłe nie mają morale** (zawsze 0).
- **Morale z armii** (exe 0x640310): `+1`, potem za **każdy charakter** (alignment) obecny
  w armii (bohaterowie też) kara według relacji z własnym: ten sam 0, sąsiedni na kole −1,
  „might” (lub któryś z dwóch to might) −2, przeciwny −5; do tego −2, gdy w armii są nieumarli,
  a jednostka nie jest ze Śmierci.
  Koło charakterów (kolejność gry): życie, porządek, śmierć, chaos, natura (+ might osobno);
  sąsiednie = odległe o 1 na tym kole, przeciwne = odległe o 2.
- **Straty** (exe 0x576390): strata strony = `−10 × (utracone PW / PW na początku)`; strona,
  która straciła więcej niż przeciwnik, dostaje różnicę jako karę morale.
- Plus/minus z czarów, umiejętności bohatera, artefaktów, budynków (C1b/C1c).
- **Rzut** (raz na rundę, gdy oddział ma działać; rzut r ∈ 0..9):
  - **złe morale**: `9 − r < −morale` → oddział spada za wszystkich bez złego morale
    (traci swoje +1000), w praktyce działa później w tej rundzie;
  - **dobre morale**: `r < morale` → +1000, działa wcześniej.
  Szansa ≈ |morale| × 10 %.

## 5. Szczęście

- Zakres **−10 … +10**, każda jednostka ma szczęście (także nieumarli).
- Działa **na otrzymywane obrażenia** (manual: „how much damage the troop receives”).
  Gdy cios trafia oddział o szczęściu L (rzut r ∈ 0..9, exe 0x5f2c50):
  - `r < L` → **dobre szczęście**: oddział dostaje **2/3** obrażeń (min. 1);
  - `r < −L` → **złe szczęście**: dostaje **1,5×** obrażeń.

## 6. Obrażenia

### 6.1 Podstawa (rzut)
- Każda jednostka w oddziale rzuca `losowo(min..max)` obrażeń i wyniki się sumują.
- **Oddział ≥ 10 jednostek**: 10 rzutów, suma × `liczebność / 10` (dzielenie całkowite).
- Bless: zawsze max; Curse: zawsze min; Dragon Strength ×2; Strength/Giant Strength +¼ (C1c).
- Generator liczb: LCG z biblioteki C (`x = x × 214013 + 2531011`, bity 16–30); rzut
  `next % (hi − lo + 1) + lo`. Seed na bitwę → powtarzalne walki (przydatne do testów).

### 6.2 Atak / obrona (exe 0x5ee380)
`obrażenia = zaokrąglij(podstawa × clamp(atak / obrona, 0,05 … 20))`, minimum 1.

Przed liczeniem stosunku podstawa może urosnąć:
- **Szarża** (Charge): cios wręcz po przejściu **> 5 pól** w tej turze →
  `podstawa × (85 + punkty_ruchu / 35) %` (punkty = pola × 100; 10 pól → ×1,13).
- **Giantslayer**: ×2 przeciw jednostkom 4. poziomu (Slayer z czaru: ×1,5).

Atak (wręcz albo dystans; mnożniki składają się):
- strzelec walczący wręcz **×0,5**, chyba że ma *Normal Melee* (bez kary);
- osłabienie (Weakness) ×0,75, starzenie (Aging) ×0,75, związanie (Binding) ×0,5;
- czary: Bloodlust ×1,25 (wręcz), Precision ×1,25 (dystans), Prayer ×1,25, Unholy Song ×0,8,
  Choking Gas ×0,85, Sorrow ×0,75 (szczegóły C1c); ruchome piaski ×0,75 (wręcz).

Obrona (minimum 1; mnożniki składają się):
- **broniący się** (Defend) ×2 (z czarem Defender jeszcze ×1,5);
- *Insubstantial* ×2; *Skeletal* ×2 przeciw strzałom; Blur ×1,5 przeciw strzałom;
- Stoneskin, Spiritual Armor ×1,25; Acid / Disrupting Ray / Unholy Song ×0,8;
  Choking Gas ×0,85; Aging ×0,8.

Po stosunku:
- **Ochrona przed charakterem** atakującego (Ward): ×2/3;
- ogień (fire / breath / arc breath / Greek fire) przeciw *Fire Resistance*: ½;
  zimno przeciw *Cold Resistance*: ½;
- *Block*: **30 % szansy na całkowite zablokowanie** ciosu (0 obrażeń; wręcz, strzał i atak
  obszarowy) — tak mówi opis zdolności w tabeli gry i tak liczy `Battle.swift` (rzut przed
  ciosem, exe 0x5f3f20; nie działa, gdy jednostka jest ogłuszona/zamrożona). Stałe −30 %
  w `Combat.swift` to tylko średnia do szybkiego rozstrzygania walki (auto-walka).

### 6.3 Strzał
- Strzelać może oddział z pociskami (`shots`; *Unlimited Shots* — bez limitu), **gdy żaden
  wróg nie stoi obok** (sąsiedztwo kwadratów, także po skosie).
- **Dzielnik odległości** (exe 0x650dc0), odległość = między środkami, w polach:
  - zwykły strzelec: **/2 od 40 pól**;
  - *Short Range*: /2 od 20 pól, /4 od 40;
  - *Long Range* (lub wieża w oblężeniu): bez kary;
  - **przeszkoda na linii strzału** (także dym, mur): **dzielnik ×2**, chyba że strzelec ma
    *No Obstacle Penalty* (w exe: słowo kluczowe `siege_machine`).
  Wynik: `max(1, obrażenia / dzielnik)`.
- Manual: linia strzału — cel musi być na prostej, **wrogowie** po drodze zasłaniają,
  przyjaciele nie.

### 6.4 Kolejność w ciosie
podstawa → atak/obrona → dzielnik strzału → wieża (atak z wieży ×2, cel na wieży /2) →
mur (oblężenie) → Stone Gaze → **szczęście celu** → ograniczenie do PW celu →
**blok** → zadanie obrażeń (najpierw ranna jednostka z przodu, potem całe jednostki).

### 6.5 Zadawanie obrażeń
- Oddział ma `liczebność`, `PW na jednostkę` i `rany` pierwszej jednostki. Obrażenia
  zabijają całe jednostki od przodu; reszta to rany pierwszej.
- Doświadczenie dla strony atakującej: za każdą zabitą jednostkę obrońcy (kolumna z tabeli).

## 7. Atak wręcz i kontratak

- Atak wręcz = (opcjonalnie) ruch do miejsca, z którego cel jest w zasięgu, potem wymiana.
  Zasięg: sąsiedztwo kwadratów (także po skosie); *Long Weapon* sięga o 1 pole dalej.
- **Kontratak** (exe 0x56ef40) — cel oddaje cios, jeśli:
  żyje, nie jest wyłączony (ślepota, ogłuszenie, zamrożenie…), atakujący nie ma
  *No Retaliation* ani aury strachu działającej na cel, **nie kontratakował jeszcze w tej
  rundzie** (chyba że *Unlimited Retaliation*), a atakujący jest w jego zasięgu.
- **Wymiana jednoczesna** (domyślnie, jak w manualu: „simultaneous retaliation”):
  oba ciosy są liczone ze stanu **sprzed** wymiany — cel oddaje pełnym oddziałem, nawet jeśli
  cios go zabił. Wyjątek animacyjny: oddział zabity, **zanim jego cios doszedł do klatki
  trafienia**, nie zadaje obrażeń (`hit_frame × 1/fps` od startu animacji; przy równych
  czasach pierwszy ląduje cios atakującego). Do decyzji w C2, czy odwzorowujemy ten szczegół.
- **First Strike**: atakujący z *First Strike* (gdy cel go nie ma i nie ma odporności) bije
  pierwszy, cel oddaje tym, co zostało. Cel z *First Strike* bije pierwszy **tylko gdy
  atakujący podszedł** (ruch ≥ 4 punkty) — atak z miejsca jest jednoczesny.
- Rzut na blok (cel) przed wymianą; blok po którejś stronie oznacza, że atakujący bije pierwszy.
- **Wiele ciosów** (exe 0x5f2160): 1; Quickness → 2; Cat Reflexes +1; *Strikes Twice* +1
  (wręcz) / *Shoots Twice* +1 (dystans, ograniczone liczbą pocisków). Kolejne ciosy po wymianie.
- Ciosy dodatkowe (*Multiple Attack*, *3-Headed*, oddech, atak obszarowy) trafiają też
  inne oddziały — tylko obrażenia, bez efektów dodatkowych (C1b).
- *Strike and Return*: po ataku wraca na miejsce startu.

## 8. Strzał i kontrstrzał

- **Strzelec ostrzelany odpowiada strzałem** (raz na rundę, jak kontratak), jeśli może
  strzelać (pociski, brak wroga obok) — jednocześnie, ze stanem sprzed strzału.
  *Ranged First Strike* (gdy cel go nie ma): strzela pierwszy, odpowiedź po.
- *Shoots Twice*: drugi strzał po całej wymianie.

## 9. Bohater na polu bitwy

Bohater to jednostka na polu bitwy (oddział 1 istoty) — szczegóły w §13.
- PW = `10 × poziom + 90`; obrażenia `(16L − 16)/10 + 16` … `(24L − 24)/10 + 24`
  (dzielenie całkowite); Speed 6 (exe, `Combat.swift`).
- Atak i obrona z umiejętności — §13.2. Pociski: 12 z Łucznictwem, 24 na poziomie arcymistrza;
  bohater nie ma kary wręcz. Bohater-mag strzela „magicznym pociskiem” zamiast strzały.

## 10. Koniec walki

- Przegrywa strona, której wszystkie oddziały i bohaterowie są pokonani; odwrót bohatera
  atakującego kończy walkę porażką (manual: pokonani bohaterowie trafiają do więzienia).
- Przywołane jednostki znikają po walce.

## 11. Dane jednostek (C1b)

- **Generator**: `python HeroesDS/tools/make_rules.py` → `extracted/rules/creatures.lua`
  (plik danych Lua dla silnika walki; z plików gry, więc poza repo).
- **Statystyki** z `table.creatures` (najnowsza wersja: `updates.h4r`; tekst w cp1250 —
  polska wersja GOG, nazwy jednostek po polsku): poziom, charakter, PW, obrażenia min–max,
  atak, obrona, **Move** (pola na turę), **Speed** (kolejka), pociski, punkty i moc czarów,
  przyrost, koszt, doświadczenie. 74 jednostki: 67 z gry podstawowej, 4 z dodatku 1, 3 z 2.
- **Zdolności** z tabeli w `heroes4.exe` (`tools/creature_abilities.py`, dane za homm4-mac,
  MIT). Tabela gry ma tylko nazwy wyświetlane i w polskiej wersji nie zawsze pasują do
  tabeli zdolności; logika gry bywa też inna niż opis (czarny smok: pełna niewrażliwość na
  magię, modliszka: spętanie, feniks: odporność na ogień + odrodzenie).
- **Rozmiar** na siatce z `combat_actor` (1–7 pól). **Odporność na magię** w % z opisu
  (krasnolud 50, złoty golem 75; niewrażliwość = 100).
- Opisy zdolności po polsku: `table.creature_abilities` (słowo kluczowe → nazwa, opis).

## 12. Zdolności jednostek (C1b-2)

Słowa kluczowe jak w `table.creature_abilities` (tam też polskie nazwy i opisy).
Źródło: `Battle.swift` (`aftermath` exe 0x553440, `extraTargets`, `startOfTurn` 0x567ef0,
`meleeExchange`, `rangeDivisor`); oznaczone **[tekst]** — tylko z opisu w grze, homm4-mac
tego nie odtwarza, do weryfikacji. „Żywa” jednostka = nie nieumarła, nie mechaniczna,
nie żywiołak.

### 12.1 Wliczone w statystyki (nic nie robią w walce)
`strength` (Siła), `toughness` (Wytrzymałość), `stone_skin` (Kamienna skóra) — tabela
jednostek ma już podwyższone wartości; exe ich nie sprawdza.

### 12.2 Ruch
- `flying` — nad przeszkodami, jednostkami i murami; ląduje na wolnym miejscu.
- `teleport` — dowolne wolne miejsce na polu (nie, gdy spętana).
- `strike_and_return` — po ataku wraca na miejsce startu (jeśli wolne).
- `long_weapon` — atak wręcz o 1 pole dalej (kontratak też).
- `berserk` — nie może czekać; musi atakować albo iść w stronę wroga.

### 12.3 Strzelanie
- `ranged` — strzelec (pociski z tabeli); wręcz ×0,5 ataku, chyba że `normal_melee`.
- `short_range` / `long_range` — dzielnik odległości (6.3).
- `siege_machine` (polska nazwa: Ignorowanie przeszkód) — bez kary za przeszkody i mury.
- `no_ranged_penalties` (Oblężnicza, katapulta) — pełne obrażenia mimo przeszkód.
- `unlimited_shots`, `shoots_twice` (drugi strzał po kontrstrzale), `ranged_first_strike`.
- `area_effect` (cyklop, gargantuan) — strzał trafia też **wszystkich** (swoich też) stojących
  obok celu; `large_area_effect` (katapulta, pociski zapalające) — to samo, ogniem.

### 12.4 Walka wręcz
- `first_strike`, `first_strike_immunity`, `no_retaliation`, `unlimited_retaliation`,
  `strikes_twice` (drugi cios po kontrataku), `charging` (6.2), `giantslayer` (×2 vs poziom 4).
- `hydra_strike` (Wielokrotne ataki, hydra) — trafia **wszystkich wrogów obok siebie**.
- `3_headed_attack` (cerber) — cel + do 2 wrogów stojących obok atakującego **i** obok celu
  (najbliżsi celu).
- `breath_attack` / `arc_breath_attack` (smoki, feniks) — trafia też jednostkę **tuż za celem**
  na linii atakujący → cel (punkt `rozmiar_celu/2 + 1,5` pola za środkiem celu), **swoją
  albo wrogą**, chyba że ma odporność na ogień.
- Cele dodatkowe dostają tylko obrażenia (bez efektów z 12.5).

### 12.5 Efekty po ciosie (kolejność jak w exe)
1. Odwet (czar Retribution na celu) i Ognista aura (czar na atakującym) — C1c.
2. `poison` — trucizna = **¼ zadanych obrażeń** (Ochrona przed Śmiercią: połowa dawki);
   zostaje większa z dawek; zadaje ją **na początku każdej tury** zatrutego do końca bitwy.
3. `fire_shield` (efreet) — wręcz: **¼ ciosu** wraca do atakującego jako ogień (chyba że
   odporny na ogień; gdy właściciel tarczy ma Ochronę przed Chaosem — połowa tego).
4. Gdy cel żyje: `weakness` (czar Osłabienie, żywi) · `stunning` (wręcz; giermek) — szansa
   `obrażenia × 100 / zdrowie_celu_przed − 5` %, **bez rzutu na odporność**; ogłuszony traci
   turę i nie kontratakuje.
5. Tylko wręcz, gdy cel żyje:
   `aging` (duch; czar Postarzenie: atak −25 %, obrona −20 %, szybkość i ruch ½) ·
   `blinding` (jednorożec) 30 % na Ślepotę · `curse` — czar Klątwa (minimalne obrażenia) ·
   `devouring` — każdy atakujący ma 1/10 szansy połknąć jednostkę celu, najwyżej 1/10
   liczebności atakujących.
6. Tylko wręcz: `hypnotize` (syrena) — 30 % na przejęcie celu na 1 turę (gdy już
   zahipnotyzowany — uwolnienie) · `binding` (modliszka) — cel nie może się ruszać, dopóki
   atakujący się nie ruszy (nie działa na niematerialnych; może atakować i rzucać) ·
   `lightning` (ptak gromu) — błyskawica **30 obrażeń × liczba atakujących**, jak czar (odporność
   na magię działa) · `freeze` (lodowy demon) — 30 %, potem rzut na odporność; zamrożony
   traci tury (opis: 2 tury).
7. `vampire` (wampir; też czar Wampirzy dotyk) — wręcz, żywy cel: **½ obrażeń** (w górę) leczy
   rany i **wskrzesza** poległych, najwyżej do liczebności z początku bitwy (Ochrona przed
   Śmiercią celu: połowa).

Osobno, w samym ciosie (przed szczęściem):
- `stone_gaze` (meduza, nie w ciosach dodatkowych) — żywy, niewidomy-odporny cel bez
  niewrażliwości: na każdego atakującego 250/100/50/20 ‰ jednostki celu poziomu 1/2/3/4 zamienia
  się w kamień; działa, gdy uzbiera się co najmniej pół jednostki — doliczane do obrażeń jako
  `PW_celu × ‰ × liczba / 1000`.
- `block` — 30 % na całkowite zablokowanie (6.2).

### 12.6 Strach
- `panic` (kościany smok) i czar Aura strachu — zaatakowany **nie kontratakuje** (chyba że
  ma Ochronę przed Śmiercią lub strach go nie dotyczy — nieumarli, mechaniczni). [tekst]: po
  ataku przerażona ofiara wycofuje się na pewną odległość (homm4-mac tego nie robi).
- `terror` (koszmar) — w exe to **czar** jednostki (Groza: cel traci turę), nie efekt ciosu.

### 12.7 Obrona i odporności
- `block`, `insubstantial` (obrona ×2), `skeletal` (obrona ×2 vs strzały).
- `fire_resistance` / `cold_resistance` — pełna odporność na czary ognia/zimna, połowa
  obrażeń od ataków ogniem/zimnem (`fire_attack`, `cold_attack`, zionięcie).
- `life/order/death/chaos/nature_protection` — pełna odporność na czary tej szkoły;
  obrażenia od stworów tego charakteru **×2/3** (exe; polski opis Ochrony przed Śmiercią mówi
  „o połowę” — liczymy jak exe).
- `magic_resistance` (% z opisu), `magic_immunity`, `magic_mirror` (odbija wrogie czary) — C1c.
- `blind` (troglodyta) — odporny na ataki wzrokowe (Ślepota, Kamienne spojrzenie).
- `undead`, `mechanical`, `elemental` — nie są „żywe”: bez trucizny, ogłuszenia, osłabienia,
  wysysania życia, czarów umysłu; nieumarli i mechaniczni bez morale.

### 12.8 Początek tury, śmierć
- `regeneration` (troll) — na początku tury leczy rany **pierwszej** jednostki o **50 PW**
  (bohater z tą zdolnością: 20 + 2 × poziom). Opis w grze: „leczy wszystkie rany na końcu
  tury” — liczymy jak exe.
- `rebirth` (feniks) — gdy oddział zginie: wraca `55 × liczebność_startowa` PW (jeśli ma
  punkty czaru na Odrodzenie).

### 12.9 Rzucanie czarów
`spellcaster` i jednostki z czarami w exe (archanioł: Wskrzeszenie, arcydiabeł: przywołanie
demonów — `summons_demons`, koszmar i mroczny czempion: Groza, feniks: Odrodzenie, dżin, mag,
smok wróżek, żywiołak wody, czarodziejka, chochlik/leprechaun, satyr, ogr mag) — lista czarów
jednostek w C1c. Punkty czaru na oddział (nie × liczebność), moc z kolumny Spell Power.

### 12.10 Niezweryfikowane / poza walką
- `mana_leech` (chochlik) [tekst]: co turę wysysa manę z wrogich czarodziejów i oddaje swoim.
- `random_curse` (obserwator) [tekst]: atak dokłada losowy czar ofensywny Chaosu lub Śmierci.
- `sea_bonus` (pirat) [tekst]: na okręcie szybszy, mocniejszy, lepsza obrona — wartości nieznane.
- Mapa przygody: `stealth`, `cave_dweller`, `taxpayer` (1 złota na turę za każdą istotę).

## 13. Bohater: statystyki, umiejętności, ekwipunek (C1b-3)

Źródła: opisy umiejętności i artefaktów w grze (`table.skills`, `table.Artifacts`, polskie),
tabele zbudowane w kodzie exe (`tools/exe_tables.py`, dane za homm4-mac, MIT),
`HeroSkills.swift`, `Artifacts.swift`. Generator: `make_rules.py` → `artifacts.lua`.

### 13.1 Umiejętności — słowa kluczowe gry ≠ polskie nazwy
36 umiejętności: 9 głównych, każda z 3 podrzędnymi. Ważne dla walki:

| klucz (exe) | polska nazwa | rodzaj |
|---|---|---|
| `tactics` | Taktyka | główna: `offense` Atak, `defense` Obrona, `leadership` Dowodzenie |
| `toughness` | **Walka** | główna: `combat` **Walka wręcz**, `archery` Łucznictwo, `resistance` Odporność na magię |
| `life` `order` `death` `chaos` `nature` | szkoły magii | główne (czary — C1c) |

Poziomy: podstawowy, zaawansowany, ekspercki, mistrzowski, arcymistrzowski (1–5).

### 13.2 Bohater sam (wartości z opisów w grze)
- **Walka** (`toughness`): obrona bohatera wręcz i przed strzałami **15 / 20 / 30 / 40 / 60**
  (bez umiejętności 10).
- **Walka wręcz** (`combat`): atak wręcz **15 / 20 / 30 / 40 / 40** (bez: 10) i **dzieli
  naturalną obronę wroga** przez **1,5 / 2 / 3 / 4 / 4**, nie poniżej 10, nigdy obrony bohatera.
- **Łucznictwo** (`archery`): atak dystansowy **10 / 15 / 20 / 30 / 30** (bez: 7 — exe) i dzieli
  obronę celu przez **1 / 1,5 / 2 / 2 / 2**, z tymi samymi ograniczeniami.
- **Odporność na magię** (`resistance`): **30 / 50 / 70 / 80 / 100 %** odporności bohatera.
- **[tekst]** Dzielenie obrony wroga jest tylko w opisie gry — homm4-mac go nie liczy. Do
  przyjęcia w C2 (zgodnie z H2 liczymy jak opis, dopóki exe nie mówi inaczej).
- Wartości ataku i obrony w exe są w dziesiątych (1,0 = 10 na ekranie) — przy liczeniu
  stosunku atak/obrona trzeba trzymać jedną skalę dla bohaterów i istot.

### 13.3 Premie dla armii (z opisów; działa najlepszy bohater w armii — homm4-mac)
- **Atak** (`offense`): atak wręcz i dystansowy wszystkich swoich jednostek **+10 % / poziom**.
- **Obrona** (`defense`): obrona **+10 % / poziom**.
- **Taktyka**: szybkość **+1…+5**, ruch **+1 / 1,5 / 2 / 2,5 / 3**.
- **Dowodzenie** (`leadership`): morale i szczęście **+1…+5**.
- Klasa bohatera (awansowana) może mieć własną premię jak artefakt (`CLASS_EFFECTS`, np.
  Ochrona przed Chaosem, Trucizna, Wyssanie życia, +morale dla armii).

### 13.4 Ekwipunek — sloty
14 miejsc: łuk, stopy, głowa, pierścień lewy i prawy, szyja, lewa ręka (tarcza), prawa ręka
(broń; „obie ręce” zajmuje lewą i prawą), ramiona (płaszcz), tors (zbroja), 4 × różne
(`miscellaneous`). Plecak nie działa. Mikstury (`potion`) się pije/rzuca, nie zakłada.
Poziomy artefaktów: przedmiot (`item`), drobny, główny, relikwia; zwoje i pergaminy niosą czar.

### 13.5 Efekty artefaktów (`artifacts.lua`, `effects`)
Każdy efekt: **typ**, **cel** (`self` bohater, `own_creatures` swoje jednostki, `own_heroes`
inni swoi bohaterowie, `enemy_creatures`, `enemy_heroes`, `all`) i **wartość**.
Jednostki: atak/obrona **bohatera w dziesiątych** (Zbroja z Adamantu 500 = „+50 obrony”,
Topór 80 = „+8 ataku”); dla armii w procentach (Tarcza z Adamantu: +50 % obrony armii);
ruch w setnych pola (Skrzydlate Sandały 600 = „+2 ruchu”).

Typy ważne w walce: `attack` (wręcz/dystans osobno), `defense`, `damage_pct` (Pierścień
Wojownika +20 % obrażeń armii), `speed`, `combat_move`, `morale`, `luck`,
`magic_resistance_pct`, `hit_points_pct`, `extra_damage`, `ability` (np. Strzał ogłuszający,
Wyssanie życia, Tarcza ogniowa), `spell_effect` (stały czar, np. Ochrona przed Chaosem),
`spell_on_hit` (czar przy trafieniu), `spell_immunity`, `charged_spell` (czar z ładunkami),
`spellbook`, `spell_points`, `spell_point_regen`, `spell_power_pct`, `spell_cost`,
`skill_bonus`. Poza walką: `income`, `adventure_move_pct`, `ignore_terrain` (numer terenu),
`dwelling_growth_pct`.
- **Komplety** (`set_bonus`): gdy bohater nosi wszystkie części — dodatkowe efekty (np.
  Płaszcz Ciemności + Pierścień Światła: Anioł Stróż na początku każdej walki).
- Nieznane jeszcze typy (`type_N`, ~13 wystąpień w kilku artefaktach) — do ustalenia z opisów,
  gdy będą potrzebne.

## 14. Czary (C1c)

Źródła: `table.Spells` (polska, 193 czary: poziom, koszt, szkoła, siła bazowa, przyrost,
flagi, opisy) → `make_rules.py` → `extracted/rules/spells.lua`; reguły rzucania z
`BattleSpells.swift` (homm4-mac, adresy exe w nawiasach).

### 14.1 Dane czaru (`spells.lua`)
`level` 1–5, `cost` (mana), `school` (life/order/death/chaos/nature), `base` + `increase`
× poziom rzucającego (gdy `per_level`), `creature` (przywoływana), `type` (damage, curse,
blessing, healing, summoning, resurrection…), `flags`: `combat`, `damage`, `curse`,
`blessing`, `mind`, `fire`, `cold`, `fear`, `line_of_sight`, `resisted`,
`resisted_if_enemy`, `enemies`/`friends` (na kogo), `undead`/`mechanical`/`elementals`
(czy działa na takie jednostki), `bodies` (na ciała poległych), `no_dispel`, `default`
(czar domyślny jednostki). Do tego: `id` (numer w exe), `area_radius`, `duration`, `cast_by`
(jednostki, które go rzucają).

### 14.2 Siła czaru (exe 0x865200)
- **Bohater**: `siła = (base + increase × poziom_bohatera) × pct / 100`,
  `pct = 100 + 20 × poziom umiejętności mocy szkoły` (życie: `spirit` Duch, porządek:
  `mind` Umysł, śmierć: `demonology` Demonologia, chaos: `pyromancy` Piromancja, natura:
  `meditation` Medytacja) `+ 20 × Magia Bitewna (sorcery)` dla czarów z obrażeniami
  `+` premie artefaktów (`spell_power_pct`). Graal szkoły strony: +50 % (natura +25 %).
- **Jednostka** rzuca na poziomie 0; czary z obrażeniami, przywołania i Wskrzeszenie:
  `pct × Spell Power × liczebność / 100`; Odrodzenie × liczebność startowa.
- **Przywołanie**: liczba istot = `siła / doświadczenie istoty` (min. 1).
- Wymóg: bohater zna szkołę na poziomie ≥ poziom czaru (podstawowy = 1 … arcymistrz = 5).

### 14.3 Koszt
Koszt z księgi (artefakty: `spell_cost`), + koszt czaru pod Power Drain, + jeszcze raz pod
Magic Leech, −2 pod Mana Flare, minimum 1. Jednostki mają punkty czaru **na oddział**.

### 14.4 Odporność na magię (exe 0x40cac0)
`r` = odporność jednostki w % (zdolność, umiejętność bohatera, artefakty); czar Odporność na
magię i **Ochrona przed szkołą** czaru — każde zabiera połowę **pozostałej** podatności
(`k = 100 − r`, `k −= k/2`). Niewrażliwość na magię / Anty-magia = 100 %.
- **Czary z obrażeniami**: obrażenia × (100 − r) % (w górę). Unholy Song na celu: +¼.
- **Inne czary z flagą `resisted`** (lub `resisted_if_enemy` na wrogu): rzut — z szansą r %
  czar w ogóle nie działa.
- Kto może być celem: flagi `enemies`/`friends`; nieumarli/mechaniczni/żywiołaki tylko gdy
  czar ma odpowiednią flagę; czary umysłu nie działają na nich (ani na odpornych na umysł);
  `fire`/`cold` nie działa na odpornych; Niewrażliwość, Anty-magia i Sanktuarium odbijają
  **każdy** czar (także przyjazny); linia wzroku blokowana tylko przez mury zamku.

### 14.5 Obszar
- Kula Ognia, Ogień Krigan, Chmura Konfuzji, Rozpacz, Duszący Gaz: promień **4 pola**;
  Inferno **7 pól**. Jednostka jest w zasięgu, gdy `odległość do środka jej kwadratu −
  rozmiar/2 < promień`; **swoje i wrogie** jednakowo.
- Łańcuch błyskawic: siła połowi się przy każdym skoku, do najbliższej nietrafionej
  jednostki, max 5 celów.
- Iskry: półkole przed rzucającym (podchodzi jak do ataku wręcz).
- Czary masowe = ten sam czar na każdy dozwolony cel.
- Ruchome piaski (siła = liczba pól), Dym (chmura 4 × 4, strzały przez nią ×½), Wzrost skał
  (głaz 3 × 3) — zmieniają pole bitwy.

### 14.6 Czas trwania
**Prawie wszystkie czary trwają do końca bitwy** (albo do rozproszenia). Stała długość
(w turach celu; +1, gdy rzucony na oddział, który właśnie ma turę): Konfuzja, ogłuszenie,
Pieśń pokoju, krótka hipnoza 1 · Szybkość (Quickness), Groza, zamrożenie 2 · Ślepota,
Tchórzostwo, Hipnoza 3 · Sanktuarium 6. Trucizna i Zaraza zadają obrażenia na początku każdej
tury celu; Regeneracja leczy.
- Przeciwieństwa się znoszą: Błogosławieństwo ↔ Klątwa, Fortuna ↔ Pech, Przyspieszenie/
  Szybkość ↔ Spowolnienie/Zmęczenie, Rozpacz/Smutek ↔ Radość, Szał ↔ Pieśń pokoju.
- Rozproszenie: wszystkie; Anulowanie — dobre; Egzorcyzm — złe; nigdy `no_dispel`.

### 14.7 Odbicie i kary
- **Magiczne lustro**: wrogi czar klątwy/obrażeń, który zadziałał, wraca do rzucającego
  z **połową siły**.
- Spell Shackle: rzucający dostaje `10 × koszt` obrażeń (po swojej odporności).

### 14.8 Czary jednostek (`exe_tables.CREATURE_SPELLS`, `cast_by` w `spells.lua`)
Archanioł: Wskrzeszenie · arcydiabeł: Przywołanie demona · smok wróżek: Błyskawica,
Konfuzja, Krąg ognia, Kula ognia · dżin: Lodowy pocisk, Spowolnienie, Tchórzostwo, Iluzoryczny
sojusznik, Pieśń pokoju, Duchowy zapał · leprechaun: Fortuna · mag: Magiczna pięść, Klątwa,
Trucizna, Wskrzeszanie szkieletów, Rozmycie · koszmar i mroczny czempion: Groza · ogr mag:
Żądza krwi · feniks: Odrodzenie · satyr: Duchowy zapał · żywiołak wody: Lodowy pocisk,
Ruchome piaski, Spowolnienie, Osłabienie · czarodziejka: Implozja, Masowe anulowanie,
Wygnanie, Masowe spowolnienie. (Nazwy polskie — z `spells.lua`.)

## Otwarte (do C2)
- Dzielenie obrony wroga przez Walkę wręcz / Łucznictwo bohatera (§13.2) — tylko w opisie.
- Szczegóły pojedynczych czarów (np. Wygnanie, Poświęcenie, Męczennik, Kradzież zaklęć) —
  w `BattleSpells.swift` `cast()`, przenosić przy implementacji.
- Zdolności tylko z opisu (§12.10), kilka nieznanych typów efektów artefaktów (§13.5).
