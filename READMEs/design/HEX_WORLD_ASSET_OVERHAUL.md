# Hex World Asset Overhaul

**Status:** Official asset-pool and biome-dialect contract.
**Locks:** [World Timeline Codex](../WORLD_TIMELINE_CODEX.md) chronology ·  
[Macro World Overhaul](MACRO_WORLD_OVERHAUL.md) Node Web ·  
[Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md) FRAME/CORE ·  
[Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md) campaign/alpha boundary ·
[Hex World Generator V2](HEX_WORLD_GENERATOR_V2.md) local-zone composition,
roads, and settlement uniqueness.

Where this file conflicts with older S:→biome sort tables (including the asset
pipeline table previously embedded in Central Core Campaign Overhaul), **this
file wins for asset identity and generator dialect**.

---

## Goal

Make the Directional Node Web and radius-12 hex generator produce an Era 9
**Glitch** world from real packs:

1. **Theme packs** define Arm ecological + institutional identity.
2. **Golbanc** is the **Era 8 default vernacular** (homesteads / ordinary
   settlement), not an Arm theme.
3. **Alpha journey:** nodes next to Central = homestead starters; theme weight
   ramps toward each Arm Core (e.g. North = snow overtaking plains).

---

## Locked pack roles

| Source on `S:\Asset\_Asset` | Role | `pool_id` / dialect | Notes |
| --- | --- | --- | --- |
| Brutalist Metropole + `central_core*` | Theme — **Central** | `central` | Already in `biome_centralcore` |
| Archology South | Theme — **South** | `south` | Dock / logistics city |
| Arid Badlands | Theme — **West basin** | `west_basin` | Surface extraction |
| Exo-Lunar Desolation | Theme — **West deep / Man-Eater** | `west_deep` | Sealed Arc-plant / Gap oxide; not “space” |
| `_BIOMES\biomes_snow` | Theme — **North** | `north` | Gallian pack folder is empty — use this |
| Hercynian Lowlands | Theme — **East wet lowlands** | `east` | Mud / wetland pressure |
| **Golbanc Homestead** | **Default Era 8 structures** | `default_era8` | Shared across all arms |
| Gloria Station | Shared props (crates) / shelf halls | `shared_props` | Crates now; halls later |
| Starlight Menagerie | Shared props / later AI / shelf mechs | `shared_props` / `_shelf` | Vehicles + barricades now |
| `HEXIFY/` | Prefer hex-ready dupes when present | — | Archive junk separately later |

### Ecological extremes (readable Arm outdoor language)

| Arm | Extreme | Theme terrain |
| --- | --- | --- |
| Central | Urban concrete / density | Brutalist |
| North | Ice / arctic | snow biome |
| West | Desert basin + sealed mountain | Arid + Exo |
| East | Wet lowlands / mud | Hercynian |
| South | Coastal / archology density | Archology |

---

## Alpha release — visual journey rule

```text
[Arm Core]     theme dominant
     ↑
[mid nodes]    mix theme + Golbanc
     ↑
[*_random_1]   Golbanc homestead starter (~80–100% default)
     ↑
[CENTRAL]      Brutalist hub (authored)
```

| Node depth | `default_era8` (Golbanc) | Arm theme | Intent |
| --- | --- | --- | --- |
| `central_core` | rare | `central` 100% authored | Eviction seat / hub stamp |
| `*_random_1` (next to Central) | 100% | 0% terrain; dressing hint only | **Starter areas** — shared tutorial grammar |
| mid (`*_random_2..3` / approaches) | ~50% | ~50% | Player feels the Arm waking up |
| `*_gateway` | ~20% | ~80% | Theme readable |
| `*_core` | low | theme + Core landmark | Destination identity |

**North example:** Route 1 is Central's cold fringe: muddy/plains terrain,
Golbanc structures, dead vegetation, and only isolated frost-covered props.
Snow terrain begins at Route 2, then ramps toward the North Core. Structures
stay Golbanc longer than terrain (sheds in snow = Era 9).

All four Route 1 nodes use the same starter **ecology and logistics grammar**,
not four copies of the same inhabited POI. Each has a fixed paved arterial from
its Central-facing rim to its outward arm exit, plus a short dirt service spur.
Exactly one inhabited starter settlement exists across the ring. The alpha
locks that settlement and its only wayfinder to `north_random_1`; East, South,
and West contain no settlement stamp, resident wayfinder, or substitute
inhabited POI. Seeded terrain, forests, rocks, rubble, and dressing vary around
the fixed logistics skeleton. The complete contract lives in
[Hex World Generator V2](HEX_WORLD_GENERATOR_V2.md).

Current alpha shipping locks unfinished **deep E/S/W** routes while all four
Route 1 starts and inner-ring links remain playable
([Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)). This is a
content boundary, not a mandatory North-first campaign rule.

Before Core stabilization, shared pools may intentionally make Arms read as
ambiguous Glitch-corrupted post-apocalypse. Restoration selects historically
legible regional ruin dialects; it does not time-travel or rebuild pristine
landscapes.

---

## Architecture — Node Map → zone → tiles

```mermaid
flowchart TD
  nodeMap[NodeMap_node_id]
  profile[NodeDialectProfile]
  zoneGen[MacroZoneGenerator]
  catalog[MacroTileCatalog_pools]
  visual[HexMapVisualizer]

  nodeMap --> profile
  profile -->|"ecology theme_weight default_mix"| zoneGen
  zoneGen -->|"hex.biome_pack + layers"| visual
  catalog --> visual
```

### NodeDialectProfile (data contract)

Per node (or per arm × depth band):

| Field | Purpose |
| --- | --- |
| `arm` | `central` \| `north` \| `east` \| `south` \| `west` |
| `ecology` | `urban` \| `ice` \| `desert` \| `wet_lowland` \| `coastal` \| `west_deep` |
| `theme_pool` | pack id for terrain + theme structures |
| `default_pool` | always `default_era8` except pure Central hub / west_deep |
| `theme_weight` | 0.0–1.0 from alpha table above |
| `glitch_rate` | rare wrong-pack scraps (Era 9) |
| `landmark_pool` | POI / CORE stamps for that band |

Generator must **not** hardcode “everything is plains.”  
`hex.biome_pack` (or split `terrain_pack` + `structure_pack`) must follow the
profile.

### Catalog pools (expand beyond `plains` / `centralcore`)

| Pool id | Feeds |
| --- | --- |
| `central` | terrain + Brutalist structures |
| `north` | snow HEX + northern scraps |
| `east` | Hercynian mud/wet + wet structures |
| `south` | Archology terrain/structures |
| `west_basin` | Arid terrain/rocks/structures |
| `west_deep` | Exo (Man-Eater / Gap nodes later) |
| `default_era8` | Golbanc structures (and mild grass if needed) |
| `shared_props` | Gloria crates, Menagerie barricades/vehicles |

`Tools/Build-HexTileSet.gd` path heuristics and `GameEnums.BIOME_PACK_*` must
grow to match. Structure resolution: if roll = vernacular → sample
`default_era8` even when terrain pack is `north`.

---

## Project folder taxonomy

Under `res://Asset/HexTiles/_BIOMES/`:

```text
biome_centralcore/     # exists
biome_north/           # from biomes_snow (+ curated)
biome_east/            # Hercynian
biome_south/           # Archology
biome_west_basin/      # Arid
biome_west_deep/       # Exo (later)
default_era8/          # Golbanc — structures primary
shared_props/          # crates, barricades, vehicles
_shelf/                # Gloria halls, mechs, unused
```

Per biome / pool:

- `HEX/` — terrain-only bases (512² preferred)
- `Infrastructure/` — OVERLAY / FRAME (roads, tanks, poles)
- `Structures/` — CORE footprints
- `flora/`, `Rocks/`, `remnants/`, `water_*` as needed

**Do not** bake roads into terrain HEX. Generator V2 ships complete transparent
six-edge overlay families: 64 paved masks and 64 dirt masks at 512×512. Pipes
and power remain later infrastructure work.

---

## Sort SOP (S: → project)

1. Classify each PNG: terrain / structure / overlay / prop / shelf / discard  
2. Prefer HEXIFY when duplicate exists  
3. Copy into pool folder with stable `snake_case` names  
4. Tag dressing pools (CORE / FRAME / ACCENT / OVERLAY)  
5. Rebuild TileSet + `MacroTileCatalog`  
6. Smoke: same `zone_seed` → same placement  

Promote order for alpha:

1. `central` (done / harden)  
2. `default_era8` (Golbanc structures)  
3. `north` (snow)  
4. `shared_props` (crates, barricades)  
5. east / south / west_basin when arms unlock  
6. `west_deep` with Man-Eater nodes  

---

## Generator work (code owners)

| Area | Job |
| --- | --- |
| Profile table / resource | Map `node_id` → `NodeDialectProfile` |
| `MacroZoneGenerator` | Use profile for terrain + structure_mix; stop all-plains default |
| `HexMapVisualizer` / catalog | Resolve theme terrain + `default_era8` structures |
| `Build-HexTileSet.gd` | Multi-pack path → pool ids |
| `GameEnums` | New `BIOME_PACK_*` / pool constants |
| Dressing templates | Roles tagged `central`, `north`, `default_era8`, … |
| Composition plan | Ring budgets; starter nodes homestead-heavy |

Presentation emits visuals only. Travel seals / Meta flags stay WorldCore /
SystemCore ([Central Core](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)).

---

## Phased build order

### Phase A — Docs lock (this file)

- Point Central Core asset table here; link from docs index  
- **Done when:** agents use this file for pack identity  

## Phase B — Alpha pools on disk (Central + plains homestead + north snow)

- Sort Golbanc → `default_era8/` (homestead structures from plains)  
- Sort snow → `biome_north/` (`HEX/snow_tiles`, Rocks, Structures)  
- Harden `biome_centralcore/` taxonomy  
- Rebuild catalog via `Tools/Build-HexTileSet.gd`  
- **Done when:** Godot loads central + plains + default_era8 + north sources  

### Phase C — Dialect profiles + generator mix

- `WorldCore/NodeDialectProfile.gd` — adjacent ring homestead; North snow ramp  
- `MacroZoneGenerator` applies theme_weight → `SNOW_TRANSITION` / pack ids  
- Stub E/S/W as plains homestead until those packs ship (`future_theme_pool`)
- `structure_pack` on hex records; catalog resolves vernacular structures
- `HexWorldGenerator` facade: legacy hub/wedge off by default
- **Done when:** North approach reads Golbanc→snow ramp at fixed seed  
- **Status (2026-07-28):** Done — `MacroZoneDialectSmoke` snow_r1=0 vs snow_core=434

### Phase D — Dressing templates

- 6–8 templates: Central hub + north homestead + north cold mid  
- FRAME fixed; CORE from `default_era8` / `north` pools  
- **Done when:** same seed stable FRAME; CORE varies by weight  

### Phase E — Arm expansion (post–Core meta / seal lift)

- Promote east / south / west_basin  
- Same depth mix curve as North  
- `west_deep` only on Man-Eater / Gap special nodes  
- **Done when:** each Arm Core has readable extreme  

### Phase F — Infrastructure overlays

- **Road status (2026-07-29): Done** — 64 paved and 64 dirt masks, exact shared
  sockets, stable IDs, surface-aware rendering, and fixed four-arm logistics.
- Pipes and power remain future overlay families.
- **Road acceptance:** reciprocal sockets, all masks present, both rims
  connected, no road geometry baked into terrain HEX files.

---

## Non-goals

- Mass-renaming all of `S:\Asset\_Asset` before Phase B promote  
- Treating Golbanc as “East theme”  
- Using empty Gallian Ice Field pack SKU (use `_BIOMES\biomes_snow`)  
- Exo as orbital tourism biome  
- Mechs / Gloria halls in alpha  
- Four full arms playable in Act 1 if travel seals remain locked  

---

## Success criteria

- Node next to Central = homestead starter language (Golbanc)  
- Arm Core approach = that Arm’s ecological theme readable  
- Golbanc appears on multiple arms as Era 8 default, not one faction  
- Catalog + generator speak in pool ids aligned to this doc  
- Act 1 can ship Central + North ramp without waiting for all packs  
- Props never author blockers / travel / POI authority  
- Exactly one inhabited starter settlement exists across the four Route 1
  nodes; alpha ownership is North.
- Road geometry is invariant across seeds and discovery direction while the
  surrounding ecology materially changes with the seed.

---

## Cross-links

- Chronology: [World Timeline Codex](../WORLD_TIMELINE_CODEX.md)  
- Campaign availability / eviction: [Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
- Node Web: [Macro World Overhaul](MACRO_WORLD_OVERHAUL.md)  
- Dressing schema: [Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md)  
- Generator contract: [Hex World Generator V2](HEX_WORLD_GENERATOR_V2.md)
- Builder: [`Tools/Build-HexTileSet.gd`](../../Tools/Build-HexTileSet.gd)  
