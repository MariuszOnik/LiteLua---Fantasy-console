# Narzędzia do plików gier (Imperial Glory, Medieval II) — jak działają i jak ich używać

Rozpracowane 2026-11-01 na potrzeby testów 3D na 3DS (`tests/3ds/army`, `tests/3ds/battle`).
**Zasoby gier są tylko do prywatnego użytku i nigdy nie trafiają do repo** (jak H4 i Cossacks).

Gdzie co leży:
| co | gdzie | w repo? |
|---|---|---|
| czytniki formatów IG | `E:\AI\IG\tools\` | **nie** (zrób kopię!) |
| czytniki formatów M2TW | `E:\AI\M2TW\tools\` | **nie** (zrób kopię!) |
| wypakowane pliki gier | `E:\AI\IG\`, `E:\AI\M2TW\base`, `E:\AI\M2TW\teutonic` | nie (nie wolno) |
| eksportery dla 3DS | `tests/3ds/army/*.py`, `tests/3ds/battle/make_trees.py` | tak |

Środowisko: Python 3.12 z `numpy` i `Pillow` (zwykły `python` w PATH ma oba; venv
`E:\AI\TripoSR\venv\Scripts\python.exe` też). Podglądy: Blender 5.2
(`C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`). Wszystkie skrypty mają
opis formatu w docstringu na początku pliku — to jest źródło prawdy, ta notka to przewodnik.

---

## 1. Imperial Glory (GOG, `C:\Program Files\GOG Galaxy\Games\Imperial Glory`)

### Dane
- `data.pak` to **zwykły ZIP** — `zipfile` w Pythonie, bez narzędzi.
- Wojsko: `Models/00EjercitoBase/<Infanteria|Caballeria|Artilleria>/<Generico*>/`: siatka
  `<Generico*>.V3D`, każda animacja to osobny `.V3D` (`Andar1` chód, `Correr` bieg,
  `DispararDePie` strzał, `Morir1` śmierć…), lista animacji z czasami w `<Generico*>_ANM.sb` (tekst).
- Nacje różnią się tylko teksturami: `Models/<nn><Nacja>/<Infanteria|Caballeria>/*.dds`
  (Polska = `20Polonia`). Która siatka i tekstura dla jednostki:
  `Game/GameModes/Batalla/DefUnidades*.sb` (`.GRX` siatka, `.TEX` / `.TEX2` tekstury, `.ANM`).
- Drzewa: `Game/GameModes/Batalla/Escenarios/<nn>/Models/` — atlasy `Setarbol*.tga` (z alfą),
  `Conoarbol.tga`; kępy `Bosque*.V3D` to czworokąty (sprite'y, tablica `kind 0x202`, 28 B na
  wierzchołek — `v3d.read_mesh` ich nie czyta, `make_trees.py` bierze same tekstury).

### Format V3D (szczegóły w `v3d.py`)
Bloki `u16 tag, u16 0, u32 rozmiar` (z nagłówkiem), dane niewyrównane. Obiekt `0x2000`
(nazwa, rodzic, 3 macierze — druga ustawia obiekt), w nim `0x2100` tablice (UV, pozycje),
`0x2300` indeksy, `0x2400` podsiatki (materiał). Animacja = **klatki pozycji wierzchołków
(morph, bez szkieletu)**; w klatce macierz M i pozycje zapisane jako `pozycja @ M`. Kawaleria:
2 obiekty (koń, jeździec), działo: 13 części w hierarchii. Jednostki: cm, Y w górę.

### Narzędzia (`E:\AI\IG\tools`)
| skrypt | do czego |
|---|---|
| `v3d.py` | czytnik V3D + eksport do glTF (animacje jako morph targets) |
| `scan.py PLIK...` | lista bloków znanych typów — pierwszy rzut oka na nowy plik |
| `walk.py PLIK START_HEX` | idzie po kolejnych blokach od podanego miejsca |
| `hx.py PLIK [OD [DO]]` | hexdump z kolumnami int32/float32 (do rozpracowywania) |
| `render.py`, `render_big.py` | Blender: render klatek glTF do PNG (`render_big`: env `AZ`, `EL`) |
| `sheet.py OUT.png KOLUMNY PNG...` | sklejanie renderów w planszę |

### Przepisy
```powershell
# fizylier polski z chodem i strzałem -> glTF (Blender: shape keys <Anim>_<klatka>)
$i = "E:\AI\IG\Models\00EjercitoBase\Infanteria\GenericoA"
python E:\AI\IG\tools\v3d.py "$i\GenericoA.V3D" E:\AI\IG\Models\20Polonia\Infanteria\Fusilero.dds out.gltf "$i\Andar1.V3D" "$i\DispararDePie.V3D"
# kawaleria: jedna tekstura na obiekt (koń, jeździec), po przecinku
python E:\AI\IG\tools\v3d.py "$c\GenericoE2\GenericoE2.V3D" "$pl\HusarCaballo.dds,$pl\Husar.dds" husar.gltf "$c\GenericoE2\Galopar1.V3D"
# artyleria: 'auto' = tekstury z materiałów (obok siatki), kwadraty cieni pomijane
python E:\AI\IG\tools\v3d.py "$a\Canon\Canon\Canon.V3D" auto canon.gltf "$a\Canon\Canon\Disparar.V3D"
# podgląd klatek
& $blender -b -P E:\AI\IG\tools\render.py -- out.gltf OUTDIR pref base Andar1_3
```
Wypakowanie z archiwum: `zipfile.ZipFile(data.pak).extract(...)` (np. do `E:\AI\IG`).
Tempo animacji: `v3d.py` zapisuje 15 kl./s; prawdziwe jest w `_ANM.sb` (`.TOTALTIME`, `.MOVBYSEC`).

---

## 2. Medieval II: Total War (Steam, z dodatkiem Kingdoms)

### Wypakowanie
Oficjalny `tools\unpacker\unpacker.exe` potrzebuje katalogu gry w PATH (`msvcr71.dll`) i
**czyta „Y” prosto z konsoli** (nie da się go zautomatyzować) — dlatego `E:\AI\M2TW\unpack_m2tw.bat`
uruchamia użytkownik i dwa razy wciska Y. Wynik: `E:\AI\M2TW\base\data` (gra) i
`E:\AI\M2TW\teutonic\mods\teutonic\data` (kampania krzyżacka; tego używamy).

### Gdzie co jest (`...\data\`)
- `unit_models/battle_models.modeldb` — które siatki (LOD), tekstury (dla frakcji), zestaw
  dodatków, szkielety ma model jednostki → `modeldb.py`.
- `export_descr_unit.txt` — `soldier` (model) i `mount` jednostki; `descr_mount.txt` — model
  wierzchowca i **`rider_offset`** (gdzie siedzi jeździec).
- Siatki: `unit_models/_units/<zestaw>/<model>_lod0..3.mesh` (większe lod = mniej trójkątów),
  tekstury `.../textures/*.texture` (**48 B nagłówka + DDS**), dodatki
  `unit_models/attachmentsets/*_diff.texture`, konie `unit_models/mounts/<typ>/`.
- **Animacje są w katalogu gry**, nie w paczkach: `<gra>\mods\teutonic\data\animations\pack.idx`
  + `pack.dat` (+ `skeletons.dat`). Pary jeździec/koń:
  `HR_lance/HR_lance_horse_req/HR_lance_fs_horse_<x>.cas` + `fs_horse/fs_horse_<x>.cas`
  (`<x>` = `stand_a_idle`, `stand_a_hf_idle_2`, `run`, `charge`…; tyle samo klatek).

### Formaty (szczegóły w docstringach)
- `.mesh` (`m2mesh.py`): archiwum boost; **grupy** (rodzaj: `Legs`, `Body`, `head0`,
  `shield0`, `primaryactive0`…, nazwa części, trójkąty — indeksy do wspólnej puli), potem
  **pula wierzchołków**: UV, wagi 2 kości, pozycja (m, Y w górę), indeksy kości, normalna;
  nazwy kości na końcu (jeździec 26, koń 23). Żołnierz = po jednej części każdego rodzaju
  (gra losuje warianty).
- UV jeźdźca: **lewa połowa = tekstura jednostki, prawa = zestaw dodatków**; koń — cała tekstura.
- Animacja (`m2anim.py`): `u16 klatki, u16 kości, u8`, potem kwaterniony (x, y, z, w) i
  przesunięcia kości na klatkę; hierarchii tu nie ma (wzięta z danych, sprawdzona `check_bind.py`).
  Kolejność kości = jak w `.mesh`. Poza wiązania: kości bez obrotu (T-pose).

### Narzędzia (`E:\AI\M2TW\tools`)
| skrypt | do czego |
|---|---|
| `modeldb.py MODEL [frakcja]` | co modeldb mówi o modelu (siatki, tekstury, szkielety) |
| `m2mesh.py PLIK.mesh` | wypisuje grupy, pulę, kości; w Pythonie `read()` → `(grupy, v, kości)` |
| `m2gltf.py` | jeden żołnierz statycznie do glTF (tekstura jednostki + dodatki) |
| `m2anim.py` | `index()`, `read(nazwa)` → `(q, t)`, `bake()` — skinning do klatek |
| `check_bind.py MESH ANIM p0,p1,...` | sprawdza zgadniętą hierarchię (stawy vs wierzchołki) |
| `m2bake.py OUT.gltf [wariant]` | Ritterbruder + koń w kropierzu, galop i szarża → glTF |
| `render_zoom.py` | Blender jak `render_big.py`, plus env `ZOOM` |

### Przepisy
```powershell
cd E:\AI\M2TW\tools
python modeldb.py polish_knights poland            # siatki i tekstury polskiego rycerza
python m2mesh.py "...\_units\cm_standard\ritterbruder_lod3.mesh"
python m2gltf.py MESH.mesh UNIT.texture out.gltf 0 "head=ATTACH.texture" "shield=ATTACH.texture"
python m2bake.py E:\AI\M2TW\out\knight.gltf 0      # jeździec na koniu z animacjami
```
Pułapki (już rozwiązane w kodzie): bajty kości `(0, b2, b1, 0)` pasują do wag `(w1, w2)`;
wagi `(0, 0)` = cały wierzchołek na pierwszej kości; `jaw`/`eyebrow` i kości broni/tarczy
przypięte do głowy/dłoni (`RIDER_FALLBACK`); ogon i tylne nogi konia wychodzą z korzenia
(`HORSE_PARENTS`); jeździec: `+ rider_offset` i podskoki siodła z animacji konia.

---

## 3. Eksportery dla 3DS (w repo)

| skrypt | wejście → wyjście |
|---|---|
| `tests/3ds/army/make_army.py` | fizylier IG → `romfs/soldier.bin` (LLMS, chód) |
| `tests/3ds/army/make_knight.py` | rycerz M2TW (`--unit teutonic\|polish`) → jedna siatka + atlas 512 (`--anim run` → LLMS, `--anim idle,fidget,run,charge` → LLM2; `--tris 700` lżejszy `*_lo.bin`; `--out` folder) |
| `tests/3ds/army/optimize.py MODEL.bin OUT.bin [trójkąty]` | odchudzanie: ukryte trójkąty + zwijanie krawędzi (błąd po wszystkich klatkach; wierzchołki zostają oryginalne, więc UV i klatki też) |
| `tests/3ds/army/bin2gltf.py MODEL.bin ATLAS.png OUT.gltf` | model dla 3DS z powrotem do glTF (podgląd) |
| `tests/3ds/battle/make_trees.py` | sprite'y drzew IG prosto z `data.pak` → `romfs/trees.bin` (LLTR, RGBA5551) |

Formaty plików dla 3DS: **LLMS** (jedna animacja) i **LLM2** (tabela animacji) — opis w
docstringach `make_army.py` / `make_knight.py`; **LLTR** — w `make_trees.py`. Tekstury w
kolejności kafelków 3DS (`tile_order`), **v od góry obrazka**. `build.ps1` w obu testach
odpala te skrypty sam (modele M2TW tylko gdy istnieje `E:\AI\M2TW\tools`).

Nowa jednostka M2TW (np. Litwini): `modeldb.py <model> <frakcja>` → dopisać wpis do `UNITS`
w `make_knight.py` (siatka, tekstura, dodatki, tekstura konia, nazwa pliku) → sprawdzić
`bin2gltf.py` w Blenderze → dodać do `main.c`. Inny koń / inna broń: inne `ANIMS`
(`HR_<broń>_horse_req`) i `rider_offset` z `descr_mount.txt`.

## 4. Czego jeszcze nie ma
- IG: kępy lasu `Bosque*.V3D` (tablica `0x202`), prawdziwe tempo animacji z `_ANM.sb`.
- M2TW: `skeletons.dat` (prawdziwa hierarchia — teraz wzięta z danych), końcówka danych
  animacji (pojedyncze ślady, prawdopodobnie zdarzenia), broń zapasowa (miecz u pasa),
  piechota (inne szkielety), drzewa (SpeedTree `.spt`).
