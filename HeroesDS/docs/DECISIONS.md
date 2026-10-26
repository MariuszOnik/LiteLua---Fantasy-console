# HeroesDS — decyzje

Każdy wpis: data, decyzja, uzasadnienie. Nowe wpisy na końcu. Numeracja H<n>, żeby nie
mylić z decyzjami silnika (D<n> w `docs/DECISIONS.md` repo LuaDS).

## H1 (2026-10-26) — Część repo LuaDS, zasoby gry tylko lokalnie
HeroesDS żyje w podfolderze `HeroesDS/` repo LuaDS, razem z silnikiem. Oryginalne pliki
gry (`Data/*.h4r`), wyciągnięte z nich zasoby (`extracted/`), manuale, OST i narzędzia
innych autorów są wykluczone w `.gitignore` — gra jest do użytku prywatnego, zasoby nie
trafiają do repo ani do publicznych buildów. W repo są tylko nasze skrypty, kod i dokumenty.

## H2 (2026-10-26) — Walka: mechanika 1:1 z H4, grafika uproszczona pod DS
Zasady walki (statystyki, wzory obrażeń, inicjatywa, kontratak, morale/szczęście, moce,
czary) odwzorowujemy wiernie, ale w kodzie otwartym na rozbudowę (moce i czary jako dane +
hooki, nie zaszyte warunki). Prezentacja nie musi być 1:1 — układ ekranów, skala sprite'ów,
liczba klatek i kierunków mogą być uproszczone pod możliwości DS.
