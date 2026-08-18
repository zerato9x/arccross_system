# Hex World Generator V2

Authoritative implementation contract for generated radius-12 local zones.

**Status:** First starter-ring implementation shipped July 29, 2026; authority
reconciled August 18, 2026. The output contract remains Generator V2 while run
state preserves `world_generation_version = 3`.

This document owns local-zone composition, logistics, settlement uniqueness,
road overlays, seed boundaries, and Generator V2 validation. It defers campaign
node visibility and travel legality to
[Central Core Campaign Overhaul](CENTRAL_CORE_CAMPAIGN_OVERHAUL.md), biome pack
identity to [Hex World Asset Overhaul](HEX_WORLD_ASSET_OVERHAUL.md), and prop
placement language to [Hex Dressing Templates](HEX_DRESSING_TEMPLATES.md).

---

## Implemented starter-ring contract

The four Central-adjacent Route 1 nodes are generated as one coordinated
starter ring:

| Node | Fixed paved arterial | Dirt service spur | Inhabited settlement | Wayfinder |
| --- | --- | --- | --- | --- |
| `north_random_1` | Central-facing rim to outward rim | Yes | **Yes — alpha lock** | Exactly one |
| `east_random_1` | Central-facing rim to outward rim | Yes | No | None |
| `south_random_1` | Central-facing rim to outward rim | Yes | No | None |
| `west_random_1` | Central-facing rim to outward rim | Yes | No | None |

There is exactly **one** starter settlement across all four nodes. For the
alpha it is locked to North. A later campaign rule may choose one arm from the
world seed, but it must still select exactly one settlement rather than one per
arm.

Every Route 1 zone contains exactly **469 playable cells**. Central remains a
locked/authored campaign node and does not receive another procedural local-zone
generator.

## Determinism boundary

The logistics layer and the environmental layer intentionally use different
sources of truth.

| Fixed between seeds and discovery orders | Derived from the world/node seed |
| --- | --- |
| Central-facing road endpoint | Terrain variant assignment |
| Outward road endpoint | Elevation, moisture, drainage, and vegetation fields |
| Rotated arterial shape | Forest, scrub, rock, and rubble regions |
| Reciprocal six-edge road sockets | Searchable rubble budget and positions |
| Dirt service-spur geometry | Visual rubble and quiet-landscape dressing |
| North settlement stamp and anchor | Traces and non-authoritative accents |
| Settlement-bearing arm during alpha | Hidden/optional content owned by the Node Web |

Player arrival is a spawn concern only. It does not reroute the arterial. A
node entered from an inner-ring neighbor still retains its authored road from
the Central-facing rim to its outward arm exit. Roads therefore never appear
because of player movement or discovery order.

Local road overlays do not create or reveal Node Web edges. Hidden-node
topology remains a separate campaign-graph responsibility; when hidden content
uses seeded placement, it must attach to stable graph and content IDs.

`MacroZoneGenerator` returns detached baseline records and diagnostics. It does
not materialize, restore, or persist a node. `RuntimeStateStore` owns that
transition and validates the complete candidate before swapping active state.
`HexWorldGenerator` is rebuilt from store snapshots after transitions, loads,
and committed transactions; mutating its cached `MacroHexData` cannot mutate
the canonical `HexRecord`.

## Composition order

`MacroZoneGenerator` builds the environmental fields first, then applies the
transient `GeneratedZonePlan`:

1. Resolve node identity, arm, seed, actual player arrival, and fixed logistics
   directions.
2. Generate the 469-cell radius-12 terrain and ecology fields.
3. Select all approved green-plains terrain variants deterministically.
4. Rotate the canonical arterial from the Central-facing rim to the outward
   arm rim.
5. Apply the North settlement stamp when the node owns the sole settlement.
6. Add a short dirt service spur without occupying settlement cells.
7. Place poor searchable rubble and non-searchable visual remnants near causal
   terrain and road context.
8. Apply passability, travel cost, hazard, loot, trace, POI, and spawn
   authority to hex records.
9. Resolve reciprocal six-bit road masks and surface-specific overlay IDs.
10. Fill deterministic dressing recipes and light decoration on quiet cells.
11. Validate cell count, settlement uniqueness, budgets, sockets, overflow,
    and required-cell reachability.

Independent structure and landmark scatter is not permitted. Decorative
variation remains allowed only within role, footprint, and quiet-cell budgets.

## Starter budgets

- Exactly 469 playable cells per node.
- Exactly one settlement, settlement POI, gameplay anchor, and stationary
  wayfinder across the complete four-node ring.
- Settlement footprint: 13–17 stamped cells.
- One paved rim-to-rim arterial per node and one short dirt service spur.
- Six to ten poor, singly exhaustible searchable rubble cells per node.
- Twelve to twenty additional visual rubble cells per node.
- At least 60% quiet landscape.
- At least 20 forest cells so plains do not read as empty.
- All 54 approved seamless green-plains variants appear in every starter zone.
- No snow terrain in any Route 1 starter node.
- No renewable starter loot, second inhabited POI, trader, medic, or outpost.

North's radius-3 truth view additionally requires 37 cells, at least seven road
cells, at least one dirt-spur cell, at least sixteen quiet cells, and at least
five forest cells around the settlement reference area.

## Settlement and NPC authority

`starter_settlement_v2` is a multi-hex stamp. Its road-compatible orientation,
gameplay anchor, tent groups, Golbanc structures, rubble perimeter, and fixed
dressing slots are composition data rather than independent scatter.

Only the North wayfinder is a simulated settlement resident in the alpha. The
wayfinder is persistent, stationary, and uses HOLD behavior. Tent lights,
smoke, repairs, and ambient sound may imply other inhabitants without creating
additional NPC records.

Each visited Route 1 node owns a separate persistent pair of Central Guards,
keyed by `central_guard_pair_<node_id>`. The pair holds the Central-facing road
rim; it must not wander and must not be reused across different starter nodes.

## Terrain and dressing

- Full-hex terrain uses only manifest-approved 512×512 HEX textures.
- Starter zones use the seamless green-plains family. Snow, redmist, baked
  crossroads, arbitrary-size backgrounds, and `mud.png` are excluded.
- Terrain is edge-to-edge. Edge shadows and black gutters are forbidden.
- Forests, shrubs, rocks, rubble, tents, structures, crates, barrels, tanks,
  posts, solar panels, and machinery are fitted `Sprite2D` dressing records,
  not TileMap terrain sources.
- Large props declare a footprint class and reserve neighboring cells.
- Rubble recipes use a large readable pile framed by smaller scrub.
- Tent cells use tent clusters plus utility details rather than one isolated
  tent.
- Rocks remain large enough to establish terrain mass; shrubs remain smaller
  and use off-center FRAME placements instead of clustering at hex centers.
- Vegetation avoids paved surfaces and settlement blockers. Rubble favors roads
  and former structures; rocks and trees follow the generated fields.

## Road asset contract

Roads are transparent overlays and never baked into terrain bases.

- Final overlay size: exactly 512×512 pixels.
- Six shared sockets use identical positions and widths on every asset.
- Every six-bit neighbor mask `0–63` exists for each supported surface.
- Current surface families: 64 paved masks and 64 dirt masks.
- Paved IDs: `overlay.road.paved.00` through `overlay.road.paved.63`.
- Dirt IDs: `overlay.road.dirt.00` through `overlay.road.dirt.63`.
- Legacy `overlay.road.XX` IDs continue to resolve to paved masks during the V2
  transition.
- Paved and dirt masks share geometry but use separate source material and
  weathering language.

`Tools/build_road_hex_overlays.py` renders at four-times resolution and
downsamples with LANCZOS to preserve the 512×512 target. Generated material
swatches live under `Asset/HexTiles/_SOURCE/roads`; runtime masks live under
`Asset/HexTiles/_OVERLAYS/roads`.

Posts and infrastructural details attach through dressing slots and do not
change road connectivity.

## Asset pipeline

- Maintained external source library: `S:\Asset\_Asset\_BIOMES`.
- Candidate-only archive: `_archive\HEXIFY`; promotion is never automatic.
- Import contract: `Tools/world_asset_manifest.json`.
- Importer and validator: `Tools/import_world_assets.py`.
- Runtime root: `res://Asset/HexTiles`.
- TileSet/catalog builder: `Tools/Build-HexTileSet.gd`.
- Runtime manifest: `Asset/HexTiles/world_asset_runtime_manifest.json`.
- Git LFS status: [Hex World V2 Git LFS Audit](HEX_WORLD_LFS_AUDIT.md).

Builds never read the `S:` drive. Approved runtime assets remain inside the
Godot project.

## Runtime data contracts

| Contract | Responsibility |
| --- | --- |
| `WorldAssetManifest` | Stable asset ID, source metadata, layer kind, tags, dimensions, signatures, footprint, hash |
| `ZoneGenerationProfile` | Climate, terrain family, stamp requirement, road requirement, loot and density budgets |
| `HexStampTemplate` | Axial footprint, roles, road compatibility, anchors, blockers, slots, orientation |
| `GeneratedZonePlan` | Transient 469-cell roles, roads, masks, stamps, rubble, traces, validation report |
| `MacroHexData` / `HexRecord` | Persisted V2 asset IDs, overlays, role, stamp instance, road mask, gameplay state |

Generator V2 stores stable asset and template IDs rather than external
filesystem paths. Runtime mutations—depleted rubble, dropped items, deaths,
traps, camps, and changed structures—remain node-snapshot state. Re-entering or
reloading a node must not regenerate those consequences.

## Code ownership

| File | Job |
| --- | --- |
| `WorldCore/MacroZoneGenerator.gd` | Environmental fields, V2 integration, North settlement selection |
| `WorldCore/GenerationV2/StarterZonePlanner.gd` | Fixed logistics, stamp, rubble, traces, validation |
| `WorldCore/GenerationV2/ZoneGenerationProfile.gd` | Starter budgets and settlement/no-settlement profiles |
| `WorldCore/GenerationV2/GeneratedZonePlan.gd` | Transient plan and diagnostic report |
| `WorldCore/GenerationV2/HexStampTemplate.gd` | Settlement footprint and dressing slots |
| `WorldCore/MacroTileCatalog.gd` | Stable terrain and paved/dirt road-mask lookup |
| `WorldCore/HexMapVisualizer.gd` | Terrain, overlay, and fitted-dressing presentation |
| `WorldCore/MacroGameManager.gd` | North wayfinder and per-node Central Guard persistence |
| `Tools/GeneratorV2Preview.gd` | Radius-3/radius-12 inspection and diagnostic export |
| `Tools/build_road_hex_overlays.py` | Deterministic 128-mask road asset build |

Presentation resolves visuals from IDs but never owns passability, POIs, loot,
travel, blockers, NPC behavior, or persistence.

## Verification

The current starter implementation is covered by:

- `Tests/StarterNodeCompositionSmoke.gd`
- `Tests/HexAssetContractSmoke.gd`
- `Tests/HexVisualDeterminismSmoke.gd`
- `Tests/GeneratorV2PersistenceSmoke.gd`
- `Tests/ZoneVisualOverhaulSmoke.gd`

Acceptance requires all four nodes to contain 469 cells, fixed roads touching
both required rims, reciprocal road sockets, seed-invariant logistics,
seed-varying surroundings, exactly one North settlement, no settlement content
in the other three nodes, reachable rubble and anchors, all approved terrain
variants, and zero invalid assets or overflow violations.

## Remaining Generator V2 work

- Replace the alpha North lock with a one-of-four seed selection only when the
  campaign is ready to support it.
- Expand surface families beyond paved and dirt without changing socket
  geometry.
- Promote later-arm terrain families only after seam validation.
- Expand trace expiry and event-driven unloaded-node simulation.
- Finish full preview/report export workflows and manual visual comparison for
  every arm profile.
- Retire legacy generation and non-HEX TileSet paths only after all active
  campaign profiles use V2.
