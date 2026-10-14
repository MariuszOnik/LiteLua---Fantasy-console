# LiteLua — instrukcje dla agenta

LiteLua to fantasy console w Lua 5.4 dla Nintendo DS/DSi (BlocksDS + Wonderful),
z kartridżami `.lcart` ładowanymi z karty SD i docelowo edytorami na samym DS.

## Zanim zaczniesz
1. Przeczytaj `docs/PLAN.md` — sekcja **„Gdzie skończyliśmy”** mówi, co robić dalej.
2. Decyzje i ich uzasadnienia są w `docs/DECISIONS.md`. Nie zmieniaj ich bez zgody użytkownika;
   nowe decyzje dopisuj tam jako kolejny wpis.
3. Użytkownik pisze po polsku — odpowiadaj po polsku. Kod i komentarze w kodzie po angielsku.

## Zasady pracy
- Praca idzie punktami z `docs/PLAN.md` (P0, P1, …). Po ukończeniu punktu:
  zbuduj, zaktualizuj `docs/PLAN.md` (status + „Gdzie skończyliśmy”), zrób lokalny commit
  `P<n>: <opis>`. Push na GitHub (`origin` =
  https://github.com/MariuszOnik/LiteLua---Fantasy-console) tylko na prośbę użytkownika.
- Licencja projektu: zlib. **Nie kopiuj kodu z µLibrary** (licencja copyleft + zakaz użytku
  komercyjnego) ani z MicroLua (GPLv3). `ref/` zawiera je tylko do wglądu i jest poza repo.
- Zależności tylko na licencjach permisywnych (zlib/MIT/BSD/public domain).
- Zmiany w `vendor/lua` oznaczaj komentarzem `LiteLua` i dopisuj do `vendor/lua/LICENSE`.

## Budowanie
- Toolchain: Wonderful w `C:\msys64\opt\wonderful`, BlocksDS w `/opt/wonderful/thirdparty/blocksds/core`.
- Buduj przez PowerShell: `.\build.ps1` (albo `.\build.ps1 clean`). Wynik: `litelua.nds`
  + kopia `builds/litelua-P<n>.nds` dla bieżącego punktu planu (D16, stare buildy zostają).
- Make z Git Basha NIE działa (gcc kończy się kodem 127 — brak `libstdc++-6.dll`, konflikt runtime'ów msys).
- Test (D17): melonDS w `D:\Programowanie\melonDS-1.1-windows-x86_64`, karta SD emulatora =
  folder `D:\Programowanie\sdcard` (DLDI „Sync SD to folder”). `.\build.ps1` sam kopiuje tam
  ROM i tworzy `litelua\carts|lib|saves`; `.\build.ps1 run` uruchamia też melonDS.
  Na konsoli testujemy, gdy trzeba sprawdzić sprzęt — timing melonDS nie jest cykliczny,
  ostateczne pomiary wydajności tylko na konsoli.

## Struktura repo
- `source/` — kod silnika (C)
- `vendor/lua/` — Lua 5.4.8 (LUA_32BITS=1)
- `source/ll_data.c` — parser plików danych w składni Lua (`cart.lua`, `.lsong`; D38) — nic nie jest wykonywane
- `vendor/miniz/` — miniz 3.0.2 (MIT): ZIP (`.lcart`) i deflate, bez zmian (D21)
- `nitrofs/` — pliki wbudowane w ROM (`nitro:/`), np. `nitrofs/lib/` dla `require`,
  `nitrofs/system/<x>/` — kartridże systemowe (`sys.run("@x")`; edytor kodu `@code`, D43)
- `docs/` — plan, decyzje, `UX.md` (projekt aplikacji: ekrany, przepływ, przyciski,
  kartridże systemowe), `newCzatWorkflow.md` (jak zaczynać nowy czat), `LSONG.md`
  (specyfikacja formatu muzyki), `COMPOSING.md` (manual kompozytora)
- Testy dźwięku potwierdzamy nagraniem wyjścia audio melonDS (WASAPI loopback, D41) —
  same liczniki wysłanych poleceń nie dowodzą, że coś gra (lekcja z S0)
- `docs/api/*.lua` — dokumentacja API Lua (źródło dla edytora na DS i `docs/API.md`, D12);
  aktualizuj w każdym punkcie zmieniającym API, potem `python tools/apidoc.py`
- `assets/` — zasoby generowane do podglądu/edycji (np. `font6x8.png` z `tools/make_font.py`)
- `examples/carts/` — przykładowe gry (np. `starcatch`); `build.ps1` kopiuje je na kartę emulatora
- `examples/songs/` — przykładowe utwory `.lsong` (D36, `docs/LSONG.md`)
- `tools/` — skrypty PC (Python): `litelua.py` (`pack` → `.lcart`, `song check|convert|render` — D36, reszta w P9), `lsong.py` (format `.lsong`), `midi.py` + `midi_import.py` (import MIDI, D37), `apidoc.py`, `make_font.py` (font 6×8), `make_tiles.py` (grafika testowa map), `tiledmap.py` (Tiled → mapa, `litelua.py map`, D50), `melon.py` (sterowanie melonDS w testach: klawisze, dotyk, zrzuty)
- `tests/carts/` — kartridże testowe (`bench` — benchmark VM, D19; `files` — piaskownica, D20; `sound` — P7; `song` — utwory `.lsong` na żywo, D41; `edit` — edytor kodu; `map` — mapy kafelkowe, D50); `build.ps1` kopiuje je na kartę emulatora
- `tests/tools/` — testy narzędzi PC: `python -m unittest discover -s tests/tools`
  (też edytor `@code` z atrapami API — wymaga pakietu `lupa`, inaczej pominięty)
- `README.md` — manual użytkownika (po angielsku, D15); aktualizuj w każdym punkcie, który
  zmienia coś widocznego dla twórców gier
- `.claude/commands/punkt.md` — komenda `/punkt`: cykl jednego punktu planu
- `ref/` — sklonowane projekty referencyjne (MicroLua, µLibrary, libnds, maxmod, libxm7), ignorowane przez git
