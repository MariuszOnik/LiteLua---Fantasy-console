# Dokumentacja API — format źródłowy

Jedno źródło dokumentacji API Lua (D12). Każdy moduł to plik `docs/api/<moduł>.lua`, który
zwraca tabelę danych (bez kodu). Pliki czytają:
- edytor kodu na DS (P11) — podpowiedzi (`name`, `sig`) i pomoc (`desc`, `example`);
- `tools/apidoc.py` — generuje `docs/API.md` dla ludzi.

Język opisów: angielski. Po każdym punkcie planu, który zmienia API, aktualizuj te pliki i
uruchom `python tools/apidoc.py`.

```lua
return {
  module = "input",          -- identyfikator (nazwa pliku)
  title = "Input",           -- nagłówek w pomocy
  summary = "...",           -- jedno zdanie
  since = "P1",              -- punkt planu, w którym moduł powstał
  entries = {
    {
      name = "btn",          -- to, co podpowiada edytor (np. "gfx.spr" dla pól tabel)
      kind = "function",     -- function | callback | const | table | field
      sig = "btn(name) -> boolean",      -- jedna linia, mieści się w ~40 znakach
      args = { { "name", "string", "opis" } },   -- opcjonalne
      ret = { { "boolean", "opis" } },           -- opcjonalne
      type = "integer",      -- dla const/field, opcjonalne
      desc = "...",          -- zwykły tekst, bez Markdownu
      example = [[ ... ]],   -- opcjonalny, krótki kod, który da się uruchomić
    },
  },
}
```

Zasady: tylko literały (stringi, liczby, tabele, `..` między stringami) — pliki muszą się
dać wczytać na DS przez `load` w pustym środowisku i sparsować w Pythonie. Przykłady krótkie
(ekran DS ma 42 znaki szerokości przy foncie 6×8).
