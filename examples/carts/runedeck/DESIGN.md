# Runedeck — projekt gry

Karciany roguelike w duchu Slay the Spire na LiteLua. Mechaniki są ogólne
(energia, blok, zamiary przeciwnika); nazwy, teksty i grafiki są własne.

## Przebieg runu
- Start: 60 HP, talia startowa (5× Slash, 4× Guard, 1× Crush).
- 6 walk po kolei (`enemies.lua` → `fights`), ostatnia to boss (Ogre Chief).
- Po wygranej walce: wybór 1 z 3 losowych kart do talii (albo pominięcie).
- HP nie odnawia się między walkami. Śmierć = koniec runu.

## Walka
**Tura gracza**
1. Energia = 3, blok spada do 0, dobierasz 5 kart (pusta talia → przetasuj odrzucone).
2. Zagrywasz karty: koszt w energii; karta z celem → stuknij przeciwnika.
3. „End turn” → cała ręka idzie na stos odrzuconych.

**Tura przeciwników** — każdy wykonuje ruch pokazany wcześniej jako zamiar,
potem wybiera następny (kolejno albo losowo, bez powtórki pod rząd).

**Obrażenia:** `(bazowe + siła) × 0.75 jeśli atakujący ma Weak × 1.5 jeśli cel ma Vulnerable`,
zaokrąglone w dół; najpierw zjadają blok, reszta schodzi z HP.

**Statusy** (Weak, Vulnerable — liczba tur, spada o 1 na koniec tury właściciela;
Poison — na początku tury traci tyle HP, potem −1; Strength — stałe na walkę).

**Blok przeciwnika** też znika na początku jego tury.

## Ekrany DS
- **Górny:** przeciwnicy (64 px, boss 96 px), nad każdym zamiar (ikona + liczba), pasek HP,
  blok, statusy. Na górze: HP gracza, numer walki.
- **Dolny:** ręka (do 10 kart 48×64, zachodzą na siebie), energia, licznik talii i
  odrzuconych, przycisk „End turn”.
- Zagrywanie: stuknij kartę (podnosi się i pokazuje pełny opis) → stuknij jeszcze raz,
  żeby zagrać. Górny ekran nie jest dotykowy, więc **cel wybieramy na dolnym**: przy
  karcie z celem nad ręką pojawiają się przyciski z nazwami przeciwników.
- Przyciski: L/R zmienia kartę, A zagrywa, B anuluje, Start = koniec tury — da się
  grać też bez rysika.

## Grafika
- Ilustracja karty 40×34, 16 kolorów; przeciwnik 64×64 albo 96×96. Prompt w polu `art`.
- Generowane w ComfyUI (Flux schnell + ewentualnie LoRA), potem zmniejszane i
  kwantyzowane skryptem do PNG z paletą (indeks 0 = przezroczysty).
- Ramka karty, liczby i tekst rysowane w kodzie.

## Do sprawdzenia w prototypie
- Czy tekst kart mieści się czcionką 6×8 (ok. 7 znaków w linii na karcie 48 px →
  pełny opis tylko dla karty wybranej).
- Balans: czy da się przejść 6 walk talią startową + 5 kart.
