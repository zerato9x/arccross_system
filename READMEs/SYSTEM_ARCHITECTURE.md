# ARCCROSS System Architecture

Canonical terminology is defined in [GLOSSARY.md](GLOSSARY.md). Phase 2 systems
foundations are closed; historical detail lives in
[phase_2_execution_plan.md](phase_2_execution_plan.md). Active Act 1 delivery
belongs in
[design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).
The closed Phase 1 record remains in
[phase_1_execution_plan.md](phase_1_execution_plan.md).

## Core Invariants

1. Each domain owns and validates its rules and mutable state.
2. Cross-system communication uses `GameEnums` values, stable IDs, engine
   primitives, neutral dictionaries or arrays, and signals.
3. Static definitions are immutable. Runtime objects are unique records with
   stable IDs.
4. Presentation receives snapshots and emits intent. It never calculates
   legality, resolves outcomes, or mutates authoritative state.
5. Destroying a node or UI projection must not destroy the record it represents.

`GameEnums` contains only closed categories that multiple domains must
interpret, plus the universal Base-12 constants. It is not a glossary, content
database, stat registry, or rule table.

## Domain Ownership

### SystemCore

- Owns orchestration, factories, and authoritative runtime records.
- `RuntimeStateStore` owns player, entity, hex, world-time, and ground-item
  records, pairwise relationships, node snapshots, combat handoffs, applied
  encounter history, and the validated save/load facade. `RuntimeSaveFileRepository`
  owns JSON/file replacement mechanics and `RuntimeSaveMigrationService` owns
  detached legacy-payload migration; neither may mutate live runtime authority.
  `player_record.coords` is canonical; `player_coords` is a compatibility
  accessor only.
- `GameTimeRules` owns shared action durations and clock conversion.
- `WorldActionApplicationService` owns the single world-action reconciliation
  snapshot, commit ordering, world-time/signal fanout, reservation/receipt
  identity, integrity gate, and rollback. `WorldActionReceiptValidationService`
  owns generic and semantic receipt validation;
  `WorldActionActorStagingService` dispatches detached actor/Hex proposals.
  Small transaction services stage inventory, POI-selection, CAMP, movement,
  SEARCH, NPC-work, negotiation, macro-event, and trade semantics from canonical
  records; none commits a
  competing partial world.
- `LootCatalog` translates ItemCore resources into neutral descriptors and
  runtime item records.
- `GameDirector` coordinates WorldCore and CombatCore through signals and
  records. It validates and forwards the roster assembled by WorldCore; it does
  not rediscover participants or apply combat-domain results itself.

### WorldCore

- Owns hex generation, movement, macro presentation, proximity loading, POI
  resolution, and macro interaction rules.
- Renders local zones dynamically through `HexMapVisualizer` and
  `MacroTileCatalog`; baselines may come from seeded generation or baked
  `AuthoredWorldMap` resources rather than thousands of live authored nodes.
- `WorldMapEditor` owns the paint workflow, `AuthoredWorldMapBaker` converts
  editor layers to neutral records, and `HexMapSocket` stores placement hooks
  without spawning gameplay content in the editor scene.
- Selects Loot Profile IDs from biome and POI state without exposing ItemCore
  resources to UI.
- Creates encounter records deterministically from world seed and coordinates.
- Treats tokens as projections; loading or unloading never changes entity life
  state.
- `MacroZoneGenerator` produces deterministic detached `HexRecord` baselines;
  generation cannot write run state. `HexWorldGenerator` is the live projection
  and legacy authored-map facade, never a second directional-node authority.
- `MacroGameManager` is the WorldCore facade for input and orchestration.
  `MacroPlayerMovementCoordinator` owns route/tween/arrival lifecycle and its
  receipt boundary; `MacroWorkSurfaceCoordinator` owns fullscreen Node Map,
  inventory, and medical-surface arbitration; `MacroDebugConsole` owns debug
  hub presentation and actions. Medical treatment, inventory, POI gear/traps,
  movement, visibility, SEARCH, CAMP, NPC work, signals, and elapsed survival
  time commit through revision-validated store transactions. The facade and
  coordinators may build intent and reproject committed state; they may not
  submit a live actor/Hex snapshot as new authority.
- `WorldMutationStore` is restricted to the legacy non-directional authored-map
  bridge. Directional nodes accept permanent structural patches only from
  `MetaProgressionStore`.

### CombatCore

- Owns the sole production combat scene,
  `CombatCore/Tactical/TacticalCombatScene.tscn`: encounter flow, the
  `squad_7x5` board, turns, AI, one AP pool, catalog actions, quotes, resolution,
  and presentation sequencing.
- `RuntimeStateStore` rejects any non-production topology at handoff. An assembled encounter has one
  directly controlled player, up to five autonomous NPCs, pairwise relations,
  a participant cap of six, and no late reinforcement.
- `CombatActionCatalog` owns action policy. Weapon classes derive canonical
  `strike` or `fire`; `ItemData.specialized_action_ids` projects additional
  catalog-validated attacks without controller/HUD ID lists.
- `CombatActionQuoteService`, `CombatForecastService`, and
  `CombatResolutionEngine` consume explicit melee/ranged action-family metadata.
  They validate readiness and range before mutation and resolve hits against one
  Limb Region.
- Combat defense uses only wounds, Stance, equipment, geometry cover, range,
  and observable conditions. Persistent facing, posture, rear/flank arcs,
  reaction AP, Block, Dodge, and opportunity attacks are not live authority.
- `TacticalTurnManager` owns the discrete AP transaction. A pending action cost
  may be held until commit, but there is no spendable AP reservation or reaction
  window.
- `TacticalCombatAI` acts only for autonomous actors. A shove out of hostile
  Engagement can queue one post-presentation AI replan without granting AP,
  changing turn order, or opening player input.
- `TacticalPresentationPlayer` and `TacticalArenaView` consume committed
  sequences. Marker, body-animation, map-weapon-sheet, release-marker, and
  static-card pulse clocks remain independent.
- `CombatItemCard` projects weapon state and a fixed pulse; it does not become a
  source-sheet player or reinterpret condition, ammunition, or readiness.
- `CombatModeComparison.tscn` is a non-persistent topology Lab. `duel_12x1`,
  and `skirmish_6x3` remain compatibility/reference topology paths. Former
  real-time and duel-lane surfaces are historical material, never parallel
  production authorities.
- Incapacitated actors leave active occupancy but remain addressable through the
  neutral handoff layer. `Strip` and `Execute` may use that projected sector;
  `mark_body()` moves an executed actor into the persistent body layer.
- Returns only `GameEnums.CombatOutcome` and neutral runtime snapshots across
  the system boundary.

### BiologicalCore

- Owns anatomy, systemic vitals, Morale, combat-local Stance, persistent Wounds,
  and biological snapshots through explicit `Wound`, `BodyState`, and
  `HumanoidState` resources.
- Limb HP represents structural integrity. Per-limb Wounds represent injury
  type, severity, pain, bleeding, contamination, and treatment. Blood loss and
  motor penalties are derived from those records; `TraumaType` is only a compact
  compatibility summary for older consumers.
- Composes ItemCore through `InventorySystem`.
- Supplies biological equipment restrictions to ItemCore through callbacks.
- Persists destroyed-limb identity in `BodyState`; detached reconstruction must
  preserve destroyed anatomy and reconcile destroyed vital regions to terminal
  actor state before canonical capture.

### ItemCore

- Owns item definitions, Runtime Item Instances, loadouts, inventory rules, and
  equipment calculations.
- Aggregates Weight, Bulk, Threat, Insulation, and damage-type protection for
  neutral presentation snapshots. Protection is filtered by the struck body
  region; Bulk contributes to encumbrance rather than damage resistance.
- Keeps authored `.tres` resources immutable.
- Stores mutable firearm and consumable state on unique runtime instances.
- Owns grade-scaled condition wear, malfunction state, stable per-item protection
  resolution, active-function disabling at condition zero, and tool/material
  repair recipes. These rules do not import either combat scheduler.
- Authors weapon handling, damage, accuracy, range and falloff, exact
  ammunition feeds, loading aids, cycling, inventory/unloaded/equipped sprite
  paths, and attachment compatibility.
- Authors Loot Profiles and data-only SEARCH or CAMP item modifiers.
- Does not import BiologicalCore, CombatCore, or WorldCore types.

## Runtime Record Contracts

Records may gain fields, but their ownership and neutral-data requirement must
remain stable.

### Entity Record

```text
entity_id: String
kind: GameEnums.RuntimeEntityKind
life_state: GameEnums.EntityLifeState
world_status: GameEnums.EntityWorldStatus
coords: Vector2i
definition: Dictionary
runtime: Dictionary
```

### Item Runtime Record

```text
instance_id: String
template_path: String
current_magazine: int
needs_cycling: bool
current_condition: float
is_jammed: bool
definition: Dictionary
```

### Hex Record

```text
revision: int
biome: GameEnums.GridBiome
terrain_tile: GameEnums.MacroTerrainTile
flora_layer: GameEnums.MacroFloraLayer
rock_layer: GameEnums.MacroRockLayer
water_layer: GameEnums.MacroWaterLayer
structure_layer: GameEnums.MacroStructureLayer
water_sprite_path: String
is_poi: bool
poi_id: String
poi_name: String
is_explored: bool
hazard_level: float
encounter_evaluated: bool
encounter_entity_id: String
search_count: int
camp_item_states: Array
camp_rest_count: int
```

### Combat Setup Record

```text
enemy_id: String
coords: Vector2i
context: GameEnums.EncounterContext
initiator_id: String
ambush_position: GameEnums.AmbushPosition
```

## Macro Interaction Boundary

- WorldCore produces SEARCH, CAMP, TALK, AMBUSH, health, and inventory snapshots.
- Macro presentation hosts are `MacroHudController` with corner panels,
  `MacroExplorationStage` (events, entity-collision sessions, travel beats),
  and `MacroExplorationWindow` (SEARCH/CAMP). They display snapshots and emit
  stable command IDs, shared enum values, and Runtime Item Instance IDs.
- `FieldHealthHUD` renders `HealthHUDProfile`-authored metrics from neutral
  health snapshots only; it never reaches live `HumanoidBody` or
  `InventorySystem` objects.
- WorldCore revalidates every command against the authoritative player,
  coordinate, inventory, hex, and encounter state.
- `RuntimeStateStore` performs atomic record changes. BiologicalCore and
  ItemCore apply their own effects and restrictions.
- `WorldActionReservationRecord` owns a node-scoped work session. Each attempt
  has a unique `receipt_id`; `WorldActionApplicationService` validates actor,
  target, object, Hex, node, and reservation revisions before committing or
  restoring the complete pre-action snapshot.
- Biological and inventory presentation capture is owned by
  `BiologicalSnapshotService` and `InventorySnapshotService`. WorldCore composes
  their neutral dictionaries and never loads wound-treatment resources.
- Movement, SEARCH, CAMP, and completed combat advance one authoritative clock;
  BiologicalCore processes the same elapsed duration.
- SEARCH selects a Loot Profile and places generated Runtime Item Instances in
  persistent ground inventory. Completed NPC SEARCH instead creates one
  receipt-deterministic salvage instance in the NPC inventory while resource
  depletion, trace, knowledge, ownership, revisions, time, and reservation
  release share the same atomic commit.
- CAMP moves installed gear from player inventory to the Hex Record; it never
  duplicates items. Camp traps persist on the Hex and can feed combat setup.
- TALK resolves Threat / Ceasefire (and Ask / Trade placeholder) only after
  owner-side resolution via `MacroEntityCollisionResolver` and related
  resolvers. ROB is not part of the live tree.
- AMBUSH submits encounter/deployment context. CombatCore chooses actual
  `squad_7x5` deployment sectors.
- The collider receives opening initiative.

## Combat Interaction Boundary

- `TacticalCombatHUD` consumes combat-owned snapshot presenters and emits typed
  intent through `TacticalCombatInteractionCoordinator`; it never spends AP or
  resolves a hit.
- `TacticalArenaView` projects the `squad_7x5` board and layered humanoids. LMB
  emits inspect intent. RMB emits context intent with a global pointer anchor;
  the HUD positions and clamps the menu, while pointerless keyboard/synthetic
  requests fall back to the command dock.
- Snapshot projection retains exact self/authorized-friendly data and redacts
  private neutral/hostile vitals, wounds, ammunition, condition, inventory, and
  AI trace details. Hands/Quick, observable target, and ground item rows use
  projected icon paths and stable instance IDs.
- Combat snapshots expose weapon action IDs, rounds, capacity, range, cycle,
  condition, and readiness; presentation does not infer them. Static sprites
  come from ItemCore paths, while `Asset/Guns_Animation/` is catalog-resolved
  only for map shoot/reload/cycle overlays.
- Presentation action/contact audio carries typed encounter/action/actor/target/
  item/weapon/result identity. Only `HumanoidBody` wound creation emits
  `HumanInjured`; presentation never emits a second injury vocal.
- CombatCore emits outcomes and runtime snapshots. SystemCore applies those
  results exactly once through `CombatResultApplicationService`, validating the
  active encounter, exact actor IDs, participant revisions, location records,
  relationships, and item ownership before committing.
- Combat presentation never changes macro tokens, entity life state, AP costs,
  or action legality directly.

## Persistence Boundary

- `RuntimeStateStore` validates and reconstructs the disposable run save: world seed, time, player,
  graph discovery/traversal, node-keyed runtime snapshots, entities, Hexes, fog,
  ground items, pairwise relationships, and a bounded applied-encounter history.
  Save format 15 migrates formats 12 through 14, initializes Hex revisions and
  typed active actions, strips obsolete caller-owned actor snapshots from world
  receipts, and persists a bounded 256-entry applied-world-receipt history.
  `RuntimeSaveMigrationService` transforms detached payloads and
  `RuntimeSaveFileRepository` performs temporary-file replacement only after
  the store accepts the candidate. Reconstructed candidates are
  integrity-validated before load, so invalid state cannot overwrite the last
  valid save.
- `MetaProgressionStore` writes a separate cross-run profile containing only
  permanent-node structural patches, completed Meta Events, gateway state,
  node-profile mutations, and arm-core reconstruction.
- Permanent Hex patches are keyed by stable node ID and coordinate. An unscoped
  `(0,0)` patch must never leak into another node's `(0,0)`.
- Godot-specific values such as `Vector2i` are explicitly tagged in JSON rather
  than restored through executable Variant text.
- A successful load sets a one-shot startup flag. WorldCore consumes that flag
  and restores records before rendering Hexes or generating proximity content.
- Normal game startup loads the default save when present. Scripted smoke tests
  opt into their own isolated save paths.
- `GameDirector` synchronizes cached player and Hex state before saving. `F5`
  saves and `F9` loads the current run. `SaveLoadMenu` exposes three named slots
  with day and timestamp metadata from the main menu and defeat flow.

### Directional Node Web

- Each local node zone is a true axial radius-12 footprint: 469 cells, with 72
  cells on the outer ring.
- Travel classification uses eight visual sectors. This avoids pretending axial
  north-west and south-east neighbor steps are screen-space north and south.
- A non-playable 78-cell radius-13 preview band displays eligible destination
  nodes on hover without contaminating world generation or runtime snapshots.
- `MacroMapGraph` edges carry source exit direction, destination arrival
  direction, visibility, and optional Meta unlock flag.
- The Node Map is inspectable anywhere; travel intent is accepted only after an
  outward rim step and only for eligible adjacent directional edges.
- `RuntimeStateStore` snapshots visited nodes within one run so backtracking
  cannot reset enemies, loot, fog, or quest objects.
- Directional travel is one store transaction: capture the source, build the
  destination from its saved snapshot or detached baseline plus permanent
  patches, validate indexes and ownership, then swap node, graph, player, Hex,
  action, and signal state. A failed candidate leaves the source untouched.
- Generator V2 starter zones separate fixed logistics from seeded environment.
  `StarterZonePlanner` rotates one canonical Central-facing-to-outward arterial
  for each arm; neither world seed nor player arrival may reroute it.
- `GeneratedZonePlan` is transient composition authority for 469 cell roles,
  road masks, stamps, rubble, traces, and validation. Persisted `MacroHexData`
  and `HexRecord` state carries stable asset/template IDs and runtime mutations,
  not external source paths or the planner object.
- The four Route 1 nodes collectively own exactly one starter settlement. The
  alpha selects `north_random_1`; only that node receives the settlement stamp,
  gameplay anchor, POI, and stationary wayfinder.
- Every visited Route 1 node may own its own stationary Central Guard pair,
  keyed by node-specific squad ID and placed at the Central-facing road rim.
- Road connectivity is gameplay composition data expressed as reciprocal
  six-bit masks. `HexMapVisualizer` resolves those masks to paved or dirt
  512×512 overlays; presentation cannot add a road or change connectivity.
- `AuthoredWorldMap` stores painted hex entries, freeform decoration records,
  and socket records. The template supplies all eight arrival and exit anchors;
  authored presets must keep those corridors traversable.
- TileMap terrain and water remain full-hex gameplay layers. `HexDecorProp`
  remains visual-only; blockers, travel cost, POIs, and water authority come
  from the baked hex entry or marker metadata.
- Seeded procedural generation remains a fallback for campaign profiles without
  a finished authored preset. The template does not magically constitute a
  complete preset library, despite being much more organized than the old
  shrub lottery.

The complete composition, asset, and acceptance contract is
[Hex World Generator V2](design/HEX_WORLD_GENERATOR_V2.md).

## Dependency Direction

```text
GameEnums is interpreted by every domain.

ItemCore <- BiologicalCore <- CombatCore
				  ^
				  |
			   WorldCore

SystemCore coordinates domains through neutral records and signals.
```

Dependencies remain one-directional. Lower-level domains do not import
higher-level domains to inspect their state. Owner-specific policy is injected
through callbacks or coordinated by SystemCore.

## Allowed Dependency Matrix

| From | To | Allowed |
|---|---|---|
| Any domain | `GameEnums` | Yes — shared closed vocabulary |
| `BiologicalCore` | `ItemCore` | Yes — biology composes inventory |
| `WorldCore` | `BiologicalCore` | Yes — macro tokens project runtime actors |
| `CombatCore` | `BiologicalCore` | Yes — combat resolves on hydrated actors |
| `WorldCore` / `CombatCore` | `SystemCore` factories | Yes — via neutral dicts and `EntityRecord` |
| `WorldCore` | `CombatCore` | **No** — use `GameDirector` + signals |
| `CombatCore` | `WorldCore` | **No** — return outcome dicts to `GameDirector` |
| `ItemCore` | Any higher domain | **No** |
| Presentation (`UI/`) | Domain runtime types | **No** — snapshots and intent IDs only |
| `PresentationCore` | Shared HUD catalogs and scene path registry | Yes — presentation data only |
| `HumanoidVisualCatalog` | Appearance dicts from records/equipment snapshots | Yes — no live `InventorySystem` |
| Any domain | `CombatRules` / `WorldRules` | **No** — owner-private policy |

Cross-domain payloads must be `GameEnums` values, stable IDs, engine primitives,
neutral dictionaries or arrays, and signals. Live `HumanoidCore` nodes may exist
only inside the domain that hydrated them from a record.

## Modding Contract

Stable surfaces for content mods (no orchestration code changes required):

- **Entity records** — `EntityRecord` JSON fields (`entity_id`, `kind`,
  `life_state`, `world_status`, `coords`, `definition`, `runtime`).
- **Hex records** — `HexRecord` fields documented above.
- **Authored local zones** — `AuthoredWorldMap` entries, decorations, and
  `HexMapSocket` records baked from `WorldMapEditor` scenes.
- **Item runtime dict** — `instance_id`, `template_path`, `current_magazine`,
  `needs_cycling`, `definition` (neutral descriptor subset).
- **`GameEnums` macro inventory command IDs** — `MACRO_INV_TAKE`, `MACRO_INV_DROP`,
  `MACRO_INV_EQUIP`, `MACRO_INV_UNEQUIP`, `MACRO_INV_CONSUME`, `MACRO_INV_MOVE`,
  `MACRO_INV_LOAD_MAGAZINE`, `MACRO_INV_INTERACT`, `MACRO_INV_REPAIR`. Repair
  intent uses a neutral payload containing target, tool, material, and context.
- **`GameEnums` macro hex command IDs** — `MACRO_HEX_SCAN`, `MACRO_HEX_TRAVEL`,
  `MACRO_HEX_ACT`.
- **`GameEnums` NPC macro purpose strings** — `NPC_PURPOSE_SCAVENGE`, `PATROL`,
  `HUNT`, `ROAM`.
- **`MacroSnapshotBuilder`** — `build_inventory_snapshot()`, `build_limb_snapshot()`,
  `build_world_hud_snapshot()`, `build_hex_descriptor()`, `build_macro_activity_snapshot()`,
  `item_inventory_descriptor()` for neutral UI snapshots.
- **`HealthHUDProfile`** — presentation-only Resources define visible systemic
  metrics, transforms, warning thresholds, icon paths, and the seven body-region
  cards. `FieldHealthHUD` renders these definitions from neutral snapshots and
  never receives live biological or inventory objects.
- **`WoundTreatmentProfile`** — BiologicalCore Resources map each wound type to
  care instructions, required consumable effect, recommended item IDs, and
  whether the current rules can resolve that treatment. WorldCore projects this
  as neutral wound metadata; the paper-doll HUD never invents medical rules.
- **`PresentationSceneRegistry`** — central presentation/combat scene and theme
  paths keep SystemCore and CombatCore from importing concrete UI paths.
- **`MacroPoiController`** — `build_session_snapshot()`, `preview_metrics()`,
  `resolve_search_outcome()`, `apply_camp_gear_selection()`, `get_camp_access()` for
  POI session data and neutral search/camp outcomes (applied by `MacroGameManager`).
- **`MacroNpcSimulator`** — `hex_distance()`, `ensure_npc_purpose()`,
  `initialize_npc_runtime()`, `evaluate_npc_step()`, `plan_macro_turn()`,
  `projection_candidates()`, `plan_encounter_refresh()` for neutral NPC macro AI
  and encounter roll planning (token projection stays in `MacroGameManager`).
- **`LootCatalog`** — `create_runtime_item_state(item_id)`,
  `get_profile_descriptor(profile_id)`, `get_item_descriptor(item_id)`,
  `has_item(item_id)`, `pick_loadout_surrender_runtime_item(loadout)`.
- **`MobSpawner`** — `generate_mob_record(coords, faction, difficulty_bias,
  deterministic_key)` returns `EntityRecord`.
- **`EntityFactory`** — `record_to_humanoid_core(record, parent, unit_name)`,
  `humanoid_core_to_record(core)` for record hydration at domain boundaries.
- **Combat boundary** — neutral encounter records enter `TacticalCombatScene`;
  combat-owned snapshots leave through presentation, typed action requests
  return through the coordinator, and terminal outcomes remain
  `GameEnums.CombatOutcome` plus runtime dicts.
- **Content assets** — `ItemCore/Items/*.tres`, `ItemCore/LootProfiles/*.tres`,
  `BiologicalCore/*_def.tres`, `ItemCore/Loadouts/*.tres`.

Mods must not require edits to `WorldCore` or `CombatCore` for new items,
loot profiles, or entity definitions.

## Enum And Data Policy

- Add a value to `GameEnums` only when the set is closed, categorical, and
  interpreted by multiple domains or stored in a neutral record.
- Keep domain-private categories beside their owner. Other domains must not
  depend on `CombatRules`.
- Store measurable properties such as Threat, Weight, Bulk, Insulation, vision,
  and protection as numeric data or derived values.
- Author abstract gameplay meters on `0` to `12`. Create normalized ratios only
  inside formulas that need them.
- Preserve meaningful physical units such as degrees Celsius.
- Store extensible occupations, traits, flaws, recipes, POIs, and similar
  content as stable IDs or resources.
- Keep the four immutable genetic axes in `GameEnums.Pillar`; derived stats do
  not become additional Pillars.
