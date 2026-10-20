# Runedeck — projekt gry

Roguelike z lochem ASCII i walką kartami w duchu Slay the Spire, na LiteLua.
Mechaniki są ogólne (energia, blok, zamiary przeciwnika); nazwy, teksty i grafiki są własne.

## Przebieg runu
- Ekran tytułowy: kontynuacja zapisu, nowy run (losowy seed) albo run z wpisanym seedem.
  Ten sam seed = te same piętra (układ, potwory, skarby); walki są losowe zawsze.
- 5 pięter: Sewers (1–2), Crypt (3–4), Orc Den (5). Na 5. w ostatnim pokoju czeka boss
  (Ogre Chief, `&`); pokonanie go wygrywa run.
- Zejście po schodach `>` leczy 30% max HP i **zapisuje run** (seed, piętro, HP, wyposażenie,
  plecak, wyuczone karty). Kontynuacja odtwarza piętro od wejścia. Śmierć/wygrana kasuje zapis.

## Mapa (górny ekran, 42×22 znaki)
- `@` gracz, `#` ściana, `.` podłoga, `>` schody; potwory to litery (grupa = wielka litera).
- Pole widzenia 7, ściany zasłaniają; zapamiętane pola przyciemnione.
- **Potwory:** śpią (60%) albo krążą. Krążący zauważa gracza w zasięgu wzroku do 4 pól,
  śpiący tylko tuż obok (albo z szansą 30% z 2 pól). Zauważony potwór goni; gdy nie widzi
  gracza przez 6 tur, wraca do krążenia. Na mapie nieświadome potwory są przyciemnione.
  Wolne (Zombie) ruszają się co drugą turę. Boss stoi i czeka.
- Wejście na potwora albo potwór na gracza → walka kartami.
- Skarby: `)` broń, `[` zbroja, `]` tarcza, `"` amulet, `!` mikstura, `?` zwój.
  Wejście na pole podnosi przedmiot (plecak: 8 miejsc). Po walce 60% szans na łup.

## Wyposażenie i talia
- Talia = karty z założonych przedmiotów (broń, zbroja, tarcza, amulet) + karty ze zwojów.
  Start: Rusty Sword (4× Slash, Crush), Leather Vest (3× Guard), Old Buckler (Guard, Slash).
- Zbroje/amulety mogą dawać max HP. Przedmioty mają poziom (tier): lepsze głębiej.
- Mikstury leczą — z plecaka albo w walce (przycisk Potion / Y).
- Zwój: wybierz 1 z 3 kart, dochodzi do talii na stałe.

## Walka
**Tura gracza:** energia 3, blok spada do 0, dobierasz 5 kart (pusta talia → tasujesz odrzucone).
Zagrywasz karty za energię; karta z celem przy kilku wrogach → przyciski celu. „End turn” → ręka
na odrzucone. **Tura wrogów:** każdy robi ruch pokazany wcześniej jako zamiar.

**Obrażenia:** `(bazowe + siła) × 0.75 jeśli Weak × 1.5 jeśli cel Vulnerable`, w dół; najpierw
blok. Pierce ignoruje blok. Statusy: Weak/Vulnerable (tury), Poison (traci HP na start tury,
potem −1), Strength (do końca walki). HP wrogów rośnie o 12% na piętro.

## Sterowanie
- Mapa: krzyżak (przytrzymany powtarza) albo dotykowy pad; A / `z` czeka; X / Bag — plecak.
- Walka: stuknij kartę → opis, stuknij znowu → zagraj; ←/→ wybór, A zagraj, B anuluj,
  START koniec tury, Y mikstura.
- Plecak: stuknij pole, potem przycisk; krzyżak + A (załóż/zdejmij/wypij/czytaj), Y wyrzuć, B zamknij.

## Grafika i dźwięk
- Ilustracje kart 40×34, przeciwnicy 64/96 px, ikony przedmiotów 32×32; 16 kolorów.
  Prompty w polach `art` danych; `tools/cardart.py gen|convert` (ComfyUI, SDXL + Pixel Art XL).
- Muzyka `.lsong` i efekty WAV z `make_audio.py` (eksploracja, walka, boss, wygrana, przegrana).

## Pomysły na później
- „Kuźnia Run”: AI tworzy nową kartę (opis + efekty z istniejących operacji + grafika) przez
  mostek na PC; wymaga modułu sieci w silniku (osobny punkt planu, decyzja w DECISIONS.md).
