# Asset/ cleanup log — 2026-07-26

## Done

Deleted MacroTileSet.tres.bak_cleanup
Deleted MacroTileCatalog.tres.bak_cleanup
Shelved humanoid_spritesheets/Demo -> _shelf/humanoid_Demo
Shelved Dusty Concrete -Dark_small.png
Shelved Dusty Concrete -Dark_small.png.import
Removed plains snowy clone of north/hex_snowy_light.png: Grassland - Painted - snowy_hex_19.png
Removed plains snowy clone of north/hex_snowy_light_2.png: Grassland - Painted - snowy_hex_20.png
Removed plains snowy clone of north/hex_snowy_med.png: Grassland - Painted - snowy_hex_21.png
Removed plains snowy clone of north/hex_snowy_high_3.png: Grassland - Painted - snowy_hex_22.png
Removed plains snowy clone of north/hex_snowy_high_2.png: Grassland - Painted - snowy_hex_23.png
Removed plains snowy clone of north/hex_snowy_high.png: Grassland - Painted - snowy_hex_26.png
Removed plains snowy clone of north/hex_snowy_med_2.png: Grassland - Painted - snowy_hex_27.png
Removed plains snowy clone of north/hex_snowy_med_3.png: Grassland - Painted - snowy_hex_28.png
Removed 8 plains/north snowy clones
Blood pack 1: kept 26, deleted 34 pad frames
Blood pack 2: kept 24, deleted 36 pad frames
Blood pack 3: kept 29, deleted 31 pad frames
Blood pack 4: kept 24, deleted 36 pad frames
Blood pack 5: kept 27, deleted 33 pad frames
Blood pack 6: kept 26, deleted 34 pad frames
Blood pack 7: kept 27, deleted 33 pad frames
Blood pack 8: kept 28, deleted 32 pad frames
Blood pack 9: kept 29, deleted 31 pad frames
Blood max content frames across packs: 29
Deleted unused shotgun RELOAD_SHELL_01 duplicate

## Policy

| Keep | Role |
| --- | --- |
| HexTiles/_BIOMES | Game hex packs (no cross-biome byte clones) |
| Innawoods_Asset | Item/equip icons (heavily referenced) |
| humanoid_spritesheets/{Humanoid,items,weapons} | Combat sprites |
| Guns_Animation | Duel gun FX (keep rifle_sniper — has unique SCOPE sheets) |
| UI/{HUD,Event_bg} | HUD + menu parallax |
| VFX/BLOOD VFX | Combat blood (trimmed pad frames) |
| _shelf | Unused but preserved |

## Follow-up completed

- Rebuilt MacroTileSet → **420** tiles (0 duplicate paths, 0 missing).
- Set `BLOOD_FRAME_COUNT := 29` in `CombatLaneHUD.gd`.
- Added `Asset/_shelf/.gdignore` so shelved art is not imported.
