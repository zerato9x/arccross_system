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
  records plus their versioned disk representation, decoupled into explicit resource objects (`EntityRecord`, `HexRecord`, etc.).
- `GameTimeRules` owns shared action durations and clock conversion.
- `LootCatalog` translates ItemCore resources into neutral descriptors and
  runtime item records.
- `GameDirector` coordinates WorldCore and CombatCore through signals and
  records.

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

### CombatCore

- Owns encounter flow, lanes, the fixed-step real-time duel clock, AI, AP
  regeneration, fixed action costs, animation timelines, defense timing, and
  combat resolution.
- Validates firearm range and readiness before consuming ammunition, combines
  actor and weapon accuracy, and resolves successful shots against one Limb
  Region.
- Applies ballistic Flesh Damage without Stance Damage. Ordinary Stance
  pressure floors at `1`; only explicit takedown-capable resolution may Fell.
- `RealtimeDuelRuntime` accepts neutral `DuelIntent` values and owns the
  authoritative windup, impact, recovery, AP, combo, aim, guard, and Felled
  timelines.
- `RealtimeDamageResolver` applies body, armor, Stance, shield, melee, and
  firearm results without turn or presentation dependencies.
- `RealtimeLaneController` commits timed movement, push, and follow operations
  through `CombatLaneManager` without weakening its no-crossing invariant.
- `DuelWeaponProfile` resources author fixed costs and timing markers; ItemCore
  selects them through the neutral `realtime_profile_id` field.
- `RealtimeDuelHUD` owns the permanent impact-marked intent timeline;
  `DuelReadabilityEffects` owns short parry, block, feint, trip, and damage
  popups. Neither resolves defense timing or alters outcomes.
- The historical turn-based authority is preserved independently under
  `CombatCore/TurnBased/TurnBasedDuelScene.tscn`, with its own
  `CombatTurnManager`, `CombatResolutionEngine`, `CombatCommandAdapter`, AI,
  and `CombatLaneHUD`. Production `MainDuelScene` does not run both authorities.
- Both combat authorities consume the same ItemCore resolver at firearm attempt,
  melee impact, armor contribution, and shield block. A shared neutral outcome
  controls wear, typed faults, contribution, breakage, and firearm malfunction;
  mode-specific attack modifiers may be applied only afterward.
- Both HUDs host `UI/Inventory/CombatItemCard.tscn` without independently
  reinterpreting condition, fault chance, ammunition, readiness, or malfunction.
- `CombatModeComparison.tscn` is a non-persistent laboratory launcher that feeds
  identical records into either scene for direct comparison.
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
- Movement, SEARCH, CAMP, and completed combat advance one authoritative clock;
  BiologicalCore processes the same elapsed duration.
- SEARCH selects a Loot Profile and places generated Runtime Item Instances in
  persistent ground inventory.
- CAMP moves installed gear from player inventory to the Hex Record; it never
  duplicates items. Camp traps persist on the Hex and can feed combat setup.
- TALK resolves Threat / Ceasefire (and Ask / Trade placeholder) only after
  owner-side resolution via `MacroEntityCollisionResolver` and related
  resolvers. ROB is not part of the live tree.
- AMBUSH submits a deployment band. CombatCore chooses actual lane indices.
- The collider receives opening initiative.

## Combat Interaction Boundary

- `RealtimeDuelHUD` translates A/D, mouse buttons, Space, and R into
  `DuelIntent`; it never spends AP or resolves a hit.
- `RealtimeDuelRuntime` revalidates every intent and emits neutral snapshots
  plus timeline events. Each event carries the same duration and impact marker
  consumed by animation, camera, audio, VFX, and damage resolution.
- `CombatLaneView` remains the twelve-slot and layered-humanoid projection.
  `RealtimeDuelHUD` supplies cached Paper Dolls and wound layers, complete
  Blood/AP/Stance rails, current action phases, terrain, aim, combo, follow,
  ammo, animated weapon cards, and feedback around it.
- Combat snapshots expose weapon rounds, capacity, effective range, and cycle
  state; presentation does not infer firearm readiness. Static weapon sprites
  come from ItemCore item presentation paths, while `Asset/Guns_Animation/`
  may be resolved through a catalog for short-lived shoot, reload, empty, and
  cycle effects.
- Felled recovery starts automatically at `4 AP`, remains interruptible until
  its timeline completes, and grants a short anti-refell guard on success.
- Space creates a timed defense event. The impact offset distinguishes parry
  from block; no reaction popup or Reserved AP pool exists.
- CombatCore emits outcomes and runtime snapshots. SystemCore applies those
  results to persistent world records.
- Combat presentation never changes macro tokens, entity life state, AP costs,
  or action legality directly.

## Persistence Boundary

- `RuntimeStateStore` writes the disposable run save: world seed, time, player,
  graph discovery/traversal, node-keyed runtime snapshots, entities, Hexes, fog,
  and ground items. Character death/new-run creation discards this state.
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
- **Combat boundary** — neutral snapshots and `DuelIntent` payloads through
  `RealtimeDuelRuntime`; outcomes remain `GameEnums.CombatOutcome` plus runtime
  dicts.
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
