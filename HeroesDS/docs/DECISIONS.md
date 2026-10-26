# HeroesDS — decyzje

Każdy wpis: data, decyzja, uzasadnienie. Nowe wpisy na końcu. Numeracja H<n>, żeby nie
mylić z decyzjami silnika (D<n> w `docs/DECISIONS.md` repo LuaDS).

## H1 (2026-10-26) — Część repo LuaDS, zasoby gry tylko lokalnie
HeroesDS żyje w podfolderze `HeroesDS/` repo LuaDS, razem z silnikiem. Oryginalne pliki
gry (`Data/*.h4r`), wyciągnięte z nich zasoby (`extracted/`), manuale, OST i narzędzia
innych autorów są wykluczone w `.gitignore` — gra jest do użytku prywatnego, zasoby nie
trafiają do repo ani do publicznych buildów. W repo są tylko nasze skrypty, kod i dokumenty.
