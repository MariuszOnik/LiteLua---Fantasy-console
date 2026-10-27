# Imperial Glory — jak działa mapa strategiczna (notatki do M2)

Źródło: pliki gry z GOG (`C:\Program Files\GOG Galaxy\Games\Imperial Glory`). Pliki `*.pak`
to zwykłe ZIP-y. Wypakowane skrypty i reguły leżą lokalnie w `ref/ImperialGlory/`, poza repo
(`data/`, `Data1/`; teksty tylko po angielsku i po polsku). **Do wglądu — nie kopiujemy kodu
ani plików do projektu**, bierzemy pomysły i rzędy wielkości liczb.

Co gdzie jest:
- **Silnik (C++, `ImperialGlory.exe`)** — liczenie tury, ekonomia, ruch, bitwy, ocena
  „opłacalności” rozkazów AI (`get_preferencia_orden`). Tych wzorów w plikach nie ma.
- **`*.sb`** — tekstowe pliki parametrów (`.KLUCZ wartość # komentarz`, bloki w `[ ]`),
  które czyta silnik. Najważniejsze: `Game/GameModes/Gestion/Reglas/*`,
  `Gestion/IA/**`, `Gestion/CombateAutomatico/DefReglasCombateAutomatico.sb`.
- **`*.lua` (Lua 5.0)** — AI mapy (`Game/LuaScripts/IA_Gestion/`), AI bitwy
  (`IA_Batalla/`), samouczki i wstępy do bitew. Lua tylko *proponuje* rozkazy; silnik je
  punktuje i wykonuje.
- Binarnie (nie rozpracowane): statystyki jednostek `ModeloCombate.dt`,
  `CombateAutomatico/ModeloCombateAutomatico.dt`, graf mapy `Mapa/PosicionesMapa.gp`,
  drzewo technologii `ArbolTecnologias/DefGrafos.def`, odległości AI `*.GRF`.

## 1. Świat i tura

- 5 imperiów (gracze) + 19 państw neutralnych. Neutralne mają AI, ale nie anektują
  innych państw. Kolejność tur jest stała, ustalona dla każdego imperium gracza
  (`DefOrdenTurnos.sb`): najpierw pozostałe imperia, potem neutralne.
- Państwo = kilka prowincji; jedna to stolica, niektóre mają port.
- Limity w prowincji: 3 armie i 6 flot jednego gracza, 1 armia jako posiłki.
  Flota = 1 okręt (!), armia do 28 oddziałów w bitwie.
- Zasoby: złoto, surowce, żywność, ludność, nauka. Górny limit 99 999 każdego.

## 2. Ekonomia

- Budynki dają procent do produkcji danego zasobu, w trzech poziomach, np. złoto
  +50/+75/+100 %, surowce +50/+75/+100 %, nauka +50/+100/+150 %. Żywność i ludność podobnie.
- Utrzymanie armii zależy od miejsca: w koszarach 0 %, we własnej prowincji 50 %,
  w obcej 195 %, przy oblężeniu stolicy 200 %, na statku 55 %. **Dobry pomysł dla M2:**
  wojna na obcym terenie kosztuje 4× więcej niż obrona.
- Rozwiązanie jednostki zwraca część kosztu (20–40 % zależnie od zasobu i typu).
- Ujemne saldo złota co turę podnosi „niezadowolenie” (+5, −3 gdy produkcja dodatnia;
  dodatnie saldo obniża o 4). Powyżej 10 może wybuchnąć bunt (szansa 1/6), który tworzy
  milicję albo fizylierów.
- Handel: wewnętrzny daje 75/150/225 % „wartości handlowej” państwa zależnie od budynku
  (targ / drogi / giełda). Szlak zagraniczny (lądowy albo morski) daje 45/68/80 %
  sumy wartości obu państw zależnie od poziomu szlaku, a szlak morski ×2,5 (+150 %).
  Bonus za kategorię stolicy lub portu: +15/20/30 %. Zablokowany szlak nic nie daje
  (technologie przemytu i piractwa przywracają 50 %).
  Otwarcie szlaku poprawia relacje (+3).

## 3. Podbój i aneksja

- **Zbrojna aneksja to oblężenie z kumulacją siły**: każda prowincja ma „opór” 0–1 =
  0,45·(czy stolica) + 0,3·(czy port) + 0,25·(produkcja / największa produkcja w grze).
  Opór × największa możliwa siła w prowincji = siła potrzebna do zdobycia. Co turę
  dodaje się siłę wojska stojącego w prowincji; gdy suma dobije do progu, prowincja padła.
  Komisariat i technologia skracają to o 25–30 %.
- Oblężenie może wywołać bunt: do 2 armii rebeliantów (80 % milicja), mających 25–40 %
  siły oblegającego. Ustrój mnoży gniew ludności (0,2 przedrewolucyjny … 1,1 dyktatura).
- Pokojowa aneksja przez relacje (konsulat pozwala ją zacząć). Po aneksji przejmuje się
  70 % skarbu (zbrojnie) albo 20 % (dyplomatycznie).
- Wyzwolone państwo wraca z 30–70 % dezercją wojsk i mnożnikiem skarbu 1,5–3,75.

## 4. Automatyczne rozstrzyganie bitew

Obecny system (`DefReglasCombateAutomatico.sb`): symulacja na statystykach jednostek z
tabeli bitwy (obrażenia z dystansu, szarży i wręcz oraz odporności na każde z nich), z losowością
±5 % na lądzie i ±30 % na morzu. Poziom trudności mnoży obrażenia gracza (1,1 łatwy, 0,93 trudny).

Starszy, uproszczony system (`DefConflictoEjercitos.sb`, oznaczony jako przestarzały, ale
dobry wzór dla nas):
- Wartość oddziału: milicja 20, fizylierzy 40, grenadierzy 50, elita 70; kawaleria 40–60;
  artyleria 40–60; dowódca 100. Doświadczenie dodaje 0/10/20/30/40.
- Kary za niepełny oddział (mniej żołnierzy niż 10/20/30 → −30/−20/−10).
- Mnożniki: walka u siebie ×1,1, obrońca ×1,15.
- Przewaga rodzaju wojsk (kamień–papier–nożyce): piechota > kawaleria > artyleria >
  piechota, kara 5–30 zależnie od przewagi liczebnej danego rodzaju.
- Przegrany traci 15 % jako jeńców; straty zwycięzcy 70/50/30 % zależnie od przewagi
  (1×/2×/3×), domyślnie 10 %; losowość 10–50.

Po bitwie (`DefReglasResolucionBatalla.sb`): trudność = siła A / siła B. Wynik powyżej
1,3 to łatwa wygrana, poniżej 0,7 trudna. Doświadczenie: 1/2/3 pkt za łatwą, średnią
i trudną wygraną. Stopnie dowódców od 0/6/17/25 pkt (porucznik → marszałek), oddziałów od
0/6/12/18/25 (rekrut → elita).

Morze: 3 typy okrętów (liniowiec: kadłub 185, 39 dział na burtę, prędkość 8; fregata: 140,
25 dział, prędkość 10; korweta: 95, 12 dział, prędkość 13), 5 poziomów załogi (celność
0,1–0,8). Ucieczka floty: 20 % liczba okrętów, 10 % doświadczenie, 10 % wielkość, 60 % szczęście.
Naprawa: w porcie pełna w 1 turę, na morzu kadłub i żagle +30 %, załoga 0.

## 5. Dyplomacja

- Relacja = pasek „wrogości” 0–100. Powyżej 90 % jest stan wojny i można prosić o pokój.
- Zdarzenia zmieniają relację o stałe kwoty, np. propozycja ślubu +35, poprawa relacji
  +8, wysłanie wojsk +7, alianse +5, wypowiedzenie wojny −100, ultimatum −10,
  odrzucona oferta −1, wojna w ciągu 5 tur od pokoju −20, wykryty sabotaż −25.
  Zmiana między dwoma państwami częściowo (15 %) „rozlewa się” na resztę.
- Odległość (strefy wpływu 1–3) osłabia zmiany relacji z dalekimi państwami
  (×0,2–1,0 zależnie od ustroju).
- Budynki w obcym państwie co turę poprawiają relacje (gazeta, centrum kultury...).
- Ustroje (7, w 3 erach) mają tabelę wzajemnej tolerancji 0,2–1,0: demokracje lubią
  się nawzajem, monarchia absolutna nie lubi republik.
- Traktaty mają czas: ochrona wzajemna 12 tur, prawo przejścia 8, pokój „utrwalony”
  po 5. Sojusz obronny ma najwyżej 4 członków.
- **Jak AI przyjmuje ofertę** (`diplomacy.lua`): cena traktatu = cena bazowa
  (np. pokój 8, rozejm 4,2, prawo przejścia 5,5, sojusz 7,5, ślub 15) + część zależna
  od wrogości + liczba tur + ultimatum (siła nadawcy) − zgodność ustrojów. Oferta
  w zasobach jest przeliczana na złoto wg niedoboru (zasób, którego brakuje, jest wart
  więcej). Szansa na zgodę = oferta / cena − 1 (losowanie). Przy handlu AI może dać
  kontrofertę.

## 6. AI mapy strategicznej

Struktura: „prezydent” + 4 „ministrów” (wojsko, gospodarka, dyplomacja, technologia).
Każdy kandydat na rozkaz dostaje ocenę od każdego ministra, a ocena końcowa to średnia
ważona profilem państwa. Rozkaz wchodzi, gdy przekroczy minimalny próg (np. wojna 0,05,
prawo przejścia 0,1).

- **Profil państwa** (`IADefsPresidente.sb`): wagi wojsko/gospodarka/dyplomacja/technologia
  (domyślnie 0,40/0,35/0,25/0, Francja 0,25/0,30/0,33/0,12), **zuchwałość** 0–0,5
  (ile obrony wolno ogołocić na wojnę; domyślnie 0,28, Francja 0,15), preferencje budowania
  (budynki/wojsko/okręty), gałęzi technologii, typów jednostek, ustrojów.
- **„Incydenty”** (problemy do gaszenia): za mało obrony, za niski dochód danego zasobu,
  za dużo wojen naraz, za mało rozpoznania, brak podstawowych budynków. Jeśli obrona jest
  poniżej (1 − zuchwałość), AI buduje wojsko i szuka sojuszy zamiast atakować.
  Wojna jest „nie do utrzymania”, gdy wróg ma przewagę albo AI długo nie może zaatakować,
  i wtedy AI prosi o pokój.
- **„Inicjatywy”** (cele): aneksja (dla każdego widocznego państwa ocena wojny, pokoju,
  aneksji; najlepszy cel ataku → szukanie do 2 sojuszników przeciw niemu; osobno
  sojusz przeciw „najbardziej znienawidzonemu”), ulepszenia gospodarcze, wojskowe
  (leczenie oddziałów, rekrutacja najlepszego typu w każdych koszarach, okręty w portach),
  prawo przejścia, wysyłanie wojsk sojusznikom, ślub, kupno/sprzedaż prowincji, questy.
- Atak bez wypowiedzenia wojny, gdy średnia wrogość jest niska (< 25) albo wróg jest
  daleko (> 2 tury). W przeciwnym razie AI najpierw wysyła wypowiedzenie.
- Wybór celu aneksji: 70 % „łatwość” (słabość albo bliskość aneksji pokojowej) + 30 %
  „wartość” (produkcja).
- Trudność: AI nie oszukuje zasobami na średnim poziomie. Na trudnym imperia AI mają
  +5–10 % produkcji, a wrogość do gracza +0,4, plus dodatkowo wobec lidera rankingu.
- AI rozpoznania: część okrętów (50 %, maks. 3) pływa jako zwiad.

## 7. AI bitwy (`IA_Batalla/`)

Dwuetapowo: każde „zainteresowanie” (cel mapy, armia wroga, wzgórze, most, strefa)
rezerwuje potrzebne mu oddziały i mówi, czy jest „zadowolone”. Potem zadowolone cele
konkurują parami (funkcje `esmejor_X_Y` zależne od typów celów i sytuacji: atakuję czy
bronię, wygrywam czy przegrywam). Wygrywa jeden, dostaje oddziały, i pętla trwa, póki są
wolne oddziały i cele. Mapy historyczne mają własne skrypty (np. Austerlitz).

## 8. Punktacja i koniec gry

Utrzymanie stolicy 150, prowincji 300, zdobyta stolica imperium 100 i jego prowincja 60,
neutralna stolica 50 i prowincja 30, quest 50. Za miejsca 1–3 w zdobytych sztandarach,
sile wojskowej i gospodarce: 450/150/50. Progi wyniku: od 0 (klęska) do 4495
(zwycięstwo maksymalne).

## Co z tego brać do M2 (propozycje)

1. **Ruch przeciwników**: profil z kilkoma wagami (wojsko/gospodarka/dyplomacja +
   zuchwałość) na frakcję H4. Co turę: 1) jeśli obrona < 1 − zuchwałość, rekrutuj i nie
   atakuj; 2) wybierz cel = 0,7·słabość + 0,3·wartość prowincji wśród sąsiadów; 3) idź tam
   armiami, które nie są potrzebne do obrony.
2. **Bitwa automatyczna**: wartości oddziałów + bonus obrońcy (×1,15) i u siebie (×1,1),
   trudność = A/B z progiem ±0,3, straty zwycięzcy zależne od przewagi. To wystarczy,
   dopóki nie podłączymy kartridża walki H4.
3. **Oblężenie z kumulacją siły**: stolica i port trudniejsze, więc prowincje nie padają
   od razu.
4. **Utrzymanie zależne od miejsca** (obcy teren drożej) i **handel morski ×2,5**
   z blokadą szlaku przez wrogą flotę — pasuje do statków handlowych z M2.
