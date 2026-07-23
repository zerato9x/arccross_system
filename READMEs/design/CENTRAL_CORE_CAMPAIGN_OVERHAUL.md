# Central Core Campaign Overhaul

Authoritative Act 1 implementation contract for Cursor/agents.
Docs-first build bible for eviction → North-tutorial play on the live
Directional Node Web.

**Where this conflicts with soft Act 1 language elsewhere, this file wins.**

> **Implementation status — paused / asset-blocked (July 23, 2026):**
> keep this document as the authoritative campaign contract, but do not begin
> campaign scene/profile implementation until the complete categorized asset
> folder is available to pull from. The active engineering track is the
> [Official Turn-Based Combat Overhaul](TURN_BASED_COMBAT_OVERHAUL.md).

| Owns | Defers to |
| --- | --- |
| Act 1 campaign flow, travel seals, tutorial beats, phased IDE checklist | — |
| `S:\Asset\_Asset` → biome pack sort + hex structure enforcement | — |
| Lore tone / eras / eviction framing | [Canonical World Specification](../CANONICAL_WORLD_SPECIFICATION.md) |
| Domain ownership / presentation boundaries | [System Architecture](../SYSTEM_ARCHITECTURE.md) |
| FRAME/CORE dressing schema detail | [Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md) |
| Supporting Node Web lore alignment | [Macro World Overhaul](MACRO_WORLD_OVERHAUL.md) |

No gameplay code is required to treat this file as the build queue. Implement
phases in order; do not reopen finished Phase 2 foundation plans.

---

## Non-goals

- Player-facing cosmic exposition (Marks, Primal Civilization, full Core purpose)
- Baking roads, pipes, or power lines into terrain-base hex PNGs
- Shipping four full arms in Act 1
- Treating Central as free midgame home after eviction
- Rewriting Node Web radius, Meta persistence, or domain ownership
- TRADE economy, SNIPE, EXECUTE, Pocket Map, squad combat (Known Gaps only)

---

## Locked Act 1 contract

```mermaid
flowchart TD
  newGame[NewGame_OccupationChoice]
  exile[EvictionSequence_OccupationFlavored]
  centralFringe[CentralFringe_PostEviction]
  pointer[NPC_or_Event_NorthPointer]
  nodeMapTut[NodeMap_Tutorial_HighlightNorth]
  northR1[Enter_north_random_1]
  northSpine[North_Route_1_to_3]
  northGate[North_Gateway_Meta]
  northCore[North_Core_Restore]
  endgame[FourCores_Unlock_Central]

  newGame --> exile --> centralFringe --> pointer
  pointer --> nodeMapTut --> northR1 --> northSpine --> northGate --> northCore
  northCore -.-> endgame
```

### Hard rules

- **Central hub art** (`Asset/HexTiles/_BIOMES/biome_centralcore/central_core_hub_main.png`)
  is the official Central Core city silhouette — visual authority, not a free
  midgame home.
- After eviction, **Central is locked** for that character until all four
  regional Cores are restored (endgame).
- Player starts on the **Central fringe / first exit**, not inside the locked hub.
- An **NPC or scripted event** (North Pointer Tutorial) points the player North,
  opens the Node Map, and **highlights the northern path with transition
  animation**.
- **E/S/W arms are greyed and non-traversable** for Act 1 (rim travel and Node
  Map both blocked). Inner-ring edges between `*_random_1` nodes do not open
  side-arm play.
- Occupation choice **flavors exile text / starting kit**, not which arm opens.
- Act 1 play begins at `north_random_1`; deeper north nodes unlock in order.
  Other `*_random_1` nodes stay visible-but-sealed teases.

### Eviction sequence (stub)

Tone: paperwork and scarcity, not destiny. Logs/NPCs talk rations, quotas,
sealed gates.

| Beat | Intent |
| --- | --- |
| Occupation select | Scavenger first; other occupations TBD stubs |
| Exile briefing | Occupation-flavored copy; triage language |
| Fringe spawn | Outside locked hub; Central re-entry refused |
| North pointer | Tutorial NPC/event; sets Meta tutorial flags |
| Node Map coach | One-shot open-map focus on `central_core → north_random_1` |

---

## Systems file map

| File | Job |
| --- | --- |
| [`WorldCore/MacroGraphGenerator.gd`](../../WorldCore/MacroGraphGenerator.gd) | Initial unlock: Central + North Route 1; E/S/W start locked/grey |
| [`WorldCore/MacroProgressController.gd`](../../WorldCore/MacroProgressController.gd) | Directional destination filter + Act 1 arm seal |
| [`SystemCore/MetaProgressionStore.gd`](../../SystemCore/MetaProgressionStore.gd) | Flags: `eviction_completed`, `central_locked`, `tutorial_north_pointed`, `act1_arm_seals` |
| [`WorldCore/MacroGameManager.gd`](../../WorldCore/MacroGameManager.gd) | Post-exile spawn; pointer POI; refuse Central re-entry |
| [`UI/NodeMap/NodeMapGraphView.gd`](../../UI/NodeMap/NodeMapGraphView.gd) | Grey locked nodes/edges; pulse highlight |
| [`UI/NodeMap/NodeMapSystem.gd`](../../UI/NodeMap/NodeMapSystem.gd) | Open-with-focus animation; tutorial coach |
| [`BiologicalCore/Identity/OccupationDefinition.gd`](../../BiologicalCore/Identity/OccupationDefinition.gd) | Occupation + exile copy hooks |
| [`WorldCore/MacroZoneGenerator.gd`](../../WorldCore/MacroZoneGenerator.gd) | Place `central_core_hub_main` as Central landmark CORE; dressing runtime |

Presentation emits intent only. Travel legality and Meta flags live in WorldCore
/ SystemCore owners.

---

## Asset pipeline — `S:\Asset\_Asset` → project biomes

Agents must follow this sort contract. Prefer HEXIFY variants when both raw and
HEXIFY exist.

| Source pack (S:) | Target biome pack | Dialect use |
| --- | --- | --- |
| Brutalist Metropole, Archology South, `central_core*` hubs | `biome_centralcore` | Central admin / dense hub |
| Hercynian Lowlands, Golbanc Homestead | `biome_plains` | North approaches / wastes |
| Gallian Ice Field | `biome_snow` (new pack) | Far-north / cold rim |
| Arid Badlands | `biome_arid` (new, later) | East/West tease stubs |
| Exo-Lunar Desolation, Gloria Station | special / scrap pools | West scrap / Meta sites later |
| Starlight Menagerie | vehicles/props (non-hex) | Combat/world props, not terrain hexes |
| `HEXIFY/*` | preferred hex-ready duplicates | Prefer over raw |
| `S:\Asset\_Asset\_BIOMES\*` | merge into matching `res://Asset/HexTiles/_BIOMES/` | Already-sorted staging |

### Folder taxonomy (enforced under each `biome_*`)

- `HEX/` — terrain-only base hexes (512² preferred; catalog via
  [`Tools/Build-HexTileSet.gd`](../../Tools/Build-HexTileSet.gd))
- `Infrastructure/` — roads, pipes, power lines, tanks, poles (OVERLAY / FRAME)
- `Structures/` — CORE building footprints
- `Colony Infrastructure/` — shared camp/colony props (or fold into Infrastructure)
- `flora/`, `Rocks/`, `remnants/`, `water_*` as applicable
- Hub specials at biome root only if multi-hex landmark stamps
  (e.g. `central_core_hub_main.png`)

### Sort SOP

1. Inventory S: pack → classify (terrain / overlay / structure / prop / discard)
2. Prefer HEXIFY variants
3. Copy into `res://Asset/HexTiles/_BIOMES/biome_<id>/...` with stable names
4. Tag for dressing pools (CORE / FRAME / ACCENT / OVERLAY)
5. Rebuild TileSet / catalog
6. Smoke: same seed → same placement

---

## Hex structure rules

Agent-checkable bullets (extends [Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md)):

- Base hex = **terrain only**; never bake roads/pipes into grass/concrete bases
- Roads / power / pipes = **OVERLAY** edge stubs + straight/corner pieces
  covering all iso axes before full use
- FRAME anchors fixed; CORE swaps; props have **no gameplay authority**
- Central ring recipe: multi-hex HUB stamp using official hub PNG + surrounding
  STRUCTURE / ADMIN cells
- Radius-12 composition order: terrain → rings/wedges → trails → roles →
  templates → light scatter
- Footprint classes: `1x1_center`, `tall`, `wide`, multi-hex hub stamps
- Majority of cells stay quiet so landmarks read

---

## Infrastructure generation backlog

Not Act 1 travel-seal blockers; schedule after seals and hub look:

- Road overlay set (plains + central)
- Power lines / pylons
- Pipe runs / tanks
- Light poles / crates families (partially present)
- Catalog + dressing pool wiring

---

## Phased IDE build order

### Phase 0 — Docs (this pass)

- **Files:** this MD; pointer edits in Macro World Overhaul, docs index, glossary
- **Done when:** agents can implement Act 1 from this file without hunting five
  competing plans
- **Acceptance:** linked from [READMEs/README.md](../README.md)

### Phase 1 — Asset sort pass

- **Files:** `Asset/HexTiles/_BIOMES/biome_centralcore/`, `biome_plains/`,
  `Tools/Build-HexTileSet.gd`, tile catalogs
- **Jobs:** Central + plains from S:/HEXIFY; wire hub PNG; rebuild catalog
- **Done when:** hub stamp path resolves; biome folders obey taxonomy
- **Acceptance:** visualizer loads hub CORE; catalog smoke / manual Godot check

### Phase 2 — Act 1 seals

- **Files:** `MacroGraphGenerator.gd`, `MacroProgressController.gd`,
  `MetaProgressionStore.gd`
- **Jobs:** unlock defaults Central+North Route 1; refuse E/S/W travel; Central
  lock flag after eviction
- **Done when:** rim + Node Map cannot enter E/S/W; Central re-entry refused when
  `central_locked`
- **Acceptance:** Node Map / travel smokes or live probe on sealed edges

### Phase 3 — Eviction + occupation flavor

- **Files:** `MacroGameManager.gd`, Occupation defs, Meta flags, exile copy
- **Jobs:** eviction sequence; scavenger-first flavor; set `eviction_completed`
  / `central_locked`
- **Done when:** new run always ends on fringe with Central locked
- **Acceptance:** New Game → fringe spawn; Central travel refused

### Phase 4 — North pointer tutorial

- **Files:** pointer POI/event, `NodeMapGraphView.gd`, `NodeMapSystem.gd`, Meta
  `tutorial_north_pointed`
- **Jobs:** NPC/event → open map → pulse `central_core → north_random_1`; grey
  locked arms
- **Done when:** one-shot coach works; flag prevents repeat spam
- **Acceptance:** live tutorial probe; flag persists across save/load

### Phase 5 — Central look

- **Files:** `MacroZoneGenerator.gd`, central zone profiles, hub stamp wiring
- **Jobs:** ring recipes / hub density using official art
- **Done when:** Central reads as overcrowded administrative seat; hub silhouette
  authoritative
- **Acceptance:** visual pass vs hub PNG; composition stable for same seed

### Phase 6 — Dressing runtime

- **Files:** `MacroZoneGenerator.gd`, dressing template resources, pools
- **Jobs:** composition planner + FRAME/CORE resolve per Hex Dressing Templates
- **Done when:** templated roles beat free scatter on landmark hexes
- **Acceptance:** same seed → same placement; no roads baked into terrain bases

### Phase 7 — North spine content

- **Files:** north zone profiles, SiteCatalog copy, Meta north restore loop
- **Jobs:** Route 1→3 activity; North Regulator restore polish; fetch on north
  spine (not sealed east)
- **Done when:** normal pathing sequence with local wander; gateway unseal works
- **Acceptance:** playthrough `north_random_1` → north core restore hook

### Phase 8 — Roads / pipes / power overlays

- **Files:** Infrastructure art, OVERLAY pools, catalog wiring
- **Jobs:** full iso-axis stub sets for plains + central
- **Done when:** overlays place without altering terrain bases
- **Acceptance:** dressing smoke / visual probe

### Phase 9 — Later acts

- **Jobs:** unseal E/S/W chapters; four-Core Central re-entry endgame
- **Done when:** out of Act 1 scope by definition
- **Acceptance:** separate chapter plans; do not start here

---

## Success criteria (Act 1)

- One agent can implement Act 1 without reading five other delivery plans first
- After eviction tutorial, E/S/W cannot be traversed
- North path is the only highlighted open route
- Assets from S: land in correct biome folders with hex rules obeyed
- Central hub reads as the official city and stays inaccessible post-eviction
- Same seed → stable zone composition / dressing

---

## Related deferred gaps (not this queue)

- TRADE economy after Ceasefire
- Macro SNIPE / EXECUTE unlock
- Humanoid token coverage gaps
- Pocket Map / pocket-device chrome (Phase 2.5)
- Authored preset library across all campaign nodes
