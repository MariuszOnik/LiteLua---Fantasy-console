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

## 9. Bohater na polu bitwy (exe, `Combat.swift`)

- PW = `10 × poziom + 90`; obrażenia `(16L − 16)/10 + 16` … `(24L − 24)/10 + 24`
  (dzielenie całkowite); Speed 6.
- Atak i obrona z umiejętności (wartości ×10 w grze, poziomy 0–5):
  walka wręcz (Combat) atak 1; 1,5; 2; 3; 4; 4 · łucznictwo (Archery) atak dystansowy
  0,7; 1; 1,5; 2; 3; 3 · wytrzymałość (Toughness?) obrona 1; 1,5; 2; 3; 4; 6.
  **Do sprawdzenia w C1b** — nazwy umiejętności w kodzie źródłowym (`combat`, `archery`,
  `toughness`) nie pokrywają się 1:1 z nazwami z manualu.
- Pociski: 12 z Łucznictwem, 24 na poziomie arcymistrza; bohater nie ma kary wręcz.
- Bohater-mag strzela „magicznym pociskiem” zamiast strzały.

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

## Do ustalenia (C1b / C1c)

- Działanie każdej zdolności (efekty po ciosie: trucizna, ogłuszenie, spętanie, wyssanie
  życia, strach, …) — `Battle.swift`: `aftermath`, `extraTargets`, `startOfTurn`.
- Umiejętności bohatera (Taktyka: ruch i kolejność; Atak/Obrona: % do statystyk jednostek;
  Dowodzenie: morale/szczęście) — `HeroSkills.swift`, `table.skills`.
- Czary: obrażenia, obszar, odporność na magię, czasy trwania.
