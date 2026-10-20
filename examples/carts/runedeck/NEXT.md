# Runedeck — gdzie skończyliśmy (2026-10-20)

Przerwa od rozwoju silnika: robimy grę na LiteLua. Zasady gry i sterowanie: `DESIGN.md`.

## Stan
- Gra działa na DSi (wgrana przez FTP 2026-10-20 wieczorem, pełny kartridż + ROM z 18:45).
- Commity: `9ada10c` (walka kartami), `05166b8` (loch ASCII), `a87ad24` (plecak,
  wyposażenie → talia), `bd14505` (seed, zapis, skradanie, nowe karty/wrogowie, muzyka mapy).
- Nic niewypchnięte na GitHub (push tylko na prośbę).
- Testy: `python -m unittest tests.tools.test_runedeck` (bot 300 runów, piętra osiągalne,
  `main.lua` z atrapą API, seed). Bot wygrywa ~16% (walczy z każdym potworem).

## Jak pracujemy nad grafiką i dźwiękiem
- ComfyUI: `D:\AI\ComfyUI_windows_portable\run_nvidia_gpu.bat` (API na 127.0.0.1:8188).
  Model SDXL + LoRA `pixel-art-xl` (nerijs, OpenRAIL-M). Flux wypadł gorzej w małych rozmiarach.
- `python tools/cardart.py gen examples/carts/runedeck [nazwy]` → `assets/runedeck/raw/`
  (poza gitem), `python tools/cardart.py convert examples/carts/runedeck` → `gfx/` + podgląd
  `assets/runedeck/preview.png`. Prompty w polach `art` (cards/enemies/items.lua).
- Dźwięk: `python examples/carts/runedeck/make_audio.py` (muzyka .lsong + sfx WAV).
- Konsola: FTP `192.168.1.89:5000` (DHCP, czasem .86), wgrywanie `curl -T` do
  `litelua/carts/runedeck/`. Użytkownik włącza FTP na konsoli.

## Do zrobienia — propozycje na jutro
1. **Opinia z konsoli:** trudność (czy da się przejść), wygoda skradania i plecaka.
2. **Poprawki grafiki:** karta `fortify` (słaba), `pact` (wygląda jak apteczka),
   `i_fury_ring` (biały środek pierścienia), `i_scroll`. `gen` + `convert` tylko dla nich.
3. **Balans:** możliwe ułatwienia — mniej potworów na piętrach 3–5, więcej mikstur,
   tańsze karty; sprawdzać botem.
4. **Pomysły w kolejce:** kapliczka (usuń kartę z talii), złoto i sklep, animacje
   (drganie przy trafieniu), zapamiętane wyniki/seedy.
5. **Kuźnia Run (punkt 3 użytkownika) — czeka na zgodę:** AI tworzy nową kartę (nazwa,
   opis, efekty z istniejących operacji + grafika) przez mostek na PC (Python: Ollama/OpenAI
   + ComfyUI, walidator, 16 kolorów). DS łączy się po Wi-Fi: BlocksDS `dswifi` (MIT, tryb
   DSi, WPA2, lwIP, getaddrinfo) — **wymaga nowego modułu `net` w silniku** = nowy punkt
   planu + wpis w `docs/DECISIONS.md`. Klucz OpenAI tylko w zmiennej środowiskowej na PC,
   nigdy w czacie ani na karcie SD.
