Jak zacząć nowy punkt
W VS Code otwórz folder D:\Programowanie\LuaDS. Ważne, żeby był to ten folder, bo od niego zależy, co nowa sesja wczyta.

Otwórz nowy czat z Claude.

Napisz na przykład:

Kontynuujemy LiteLua. Zrób następny punkt z docs/PLAN.md.

Albo konkretnie: „Zrób P1”.

Nowa sesja sama wczytuje:

CLAUDE.md: zasady pracy, sposób budowania i polecenie, żeby zacząć od docs/PLAN.md;
moją pamięć dla tego folderu: gdzie jest toolchain i że plan oraz decyzje są w docs/.
Z docs/PLAN.md (sekcja „Gdzie skończyliśmy”) i docs/DECISIONS.md wynika, co już jest i co jest następne. Nie trzeba niczego wklejać ani opisywać od nowa.

Jak zamknąć punkt
Na końcu każdego punktu sesja:

buduje ROM przez .\build.ps1,
aktualizuje docs/PLAN.md,
robi commit P<n>: ….
Twoja rola to test w melonDS albo na konsoli i informacja zwrotna. Jeśli coś nie działa, poprawiamy to w tym samym czacie, zanim przejdziemy dalej.

Wskazówki
Jeden punkt na jeden czat. Jeśli punkt okaże się duży, sesja oznaczy go [~] i opisze w „Gdzie skończyliśmy”, na czym stanęła. Kolejny czat podejmie wątek od tego miejsca.
Nowe ustalenia zapisuj na bieżąco, np. „dopisz to do DECISIONS”. To, co zostanie tylko w rozmowie, przepadnie po zamknięciu okna.
Stan zawsze można sprawdzić w gicie, np. git log --oneline.
Komenda /punkt
W nowym czacie wpisz:

/punkt        — następny punkt z docs/PLAN.md (albo dokończenie punktu oznaczonego [~])
/punkt P4     — konkretny punkt

Komenda (plik .claude/commands/punkt.md) uruchamia cały cykl: przeczytanie planu i decyzji, krótki opis zakresu, wykonanie punktu, build, aktualizacja PLAN.md (i DECISIONS.md, jeśli zapadły nowe decyzje), commit i podsumowanie z tym, co przetestować.