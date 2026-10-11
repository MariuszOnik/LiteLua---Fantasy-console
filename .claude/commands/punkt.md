---
description: Wykonaj następny (lub wskazany) punkt planu LiteLua — build, PLAN.md, commit
argument-hint: "[P<n>] (domyślnie: następny punkt z docs/PLAN.md)"
---

Wykonujesz jeden punkt planu projektu LiteLua. Punkt do zrobienia: $ARGUMENTS
(jeśli puste — weź punkt z „Następny krok” w sekcji „Gdzie skończyliśmy” w `docs/PLAN.md`;
jeśli jakiś punkt ma status `[~]`, kontynuuj najpierw jego).

1. **Kontekst.** Przeczytaj `docs/PLAN.md` i `docs/DECISIONS.md`, potem `git log --oneline -10`
   i `git status`. Jeśli są niezacommitowane zmiany, których nie rozumiesz — zatrzymaj się i
   zapytaj użytkownika.
2. **Zakres.** Napisz użytkownikowi krótko (kilka punktów), co zrobisz w tym punkcie i jakie
   decyzje są jeszcze otwarte. Jeśli punkt wymaga decyzji, której nie ma w `DECISIONS.md`, zapytaj
   zamiast zgadywać. Gdy brak otwartych decyzji — od razu działaj.
3. **Praca.** Implementuj zgodnie z `CLAUDE.md` (licencje, styl, bez kodu z µLibrary/MicroLua).
   Przykłady i źródła BlocksDS: `C:\msys64\opt\wonderful\thirdparty\blocksds\core\examples`
   i `ref/`.
4. **Build.** `.\build.ps1` przez PowerShell musi przejść bez błędów i nowych ostrzeżeń.
   Jeśli punkt ma coś widocznego na ekranie, przygotuj test (np. testowy `main.lua`) i powiedz
   użytkownikowi, co ma sprawdzić w melonDS / na konsoli.
5. **Dokumentacja.** Zaktualizuj `docs/PLAN.md`: status punktu (`[x]` albo `[~]`, jeśli nie
   skończony), sekcję „Gdzie skończyliśmy” (ostatnio / następny krok / otwarte sprawy) tak, żeby
   nowe okno czatu mogło kontynuować bez tej rozmowy. Nowe decyzje dopisz do `docs/DECISIONS.md`
   jako kolejne `D<n>`. Wyniki pomiarów zapisz przy odpowiedniej decyzji lub punkcie.
6. **Commit.** Lokalny commit `P<n>: <krótki opis>` (bez push). Jeśli punkt jest `[~]`,
   commit `P<n> (część): …`.
7. **Raport.** Podsumuj po polsku: co zrobione, co przetestować, co jest następne.
