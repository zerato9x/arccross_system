# ARCCROSS System Architecture

Canonical terminology is defined in [GLOSSARY.md](GLOSSARY.md). Delivery status
belongs in [phase_2_execution_plan.md](phase_2_execution_plan.md) (Phase 2
combat HUD and shield rules complete; token coverage remains open). The closed
Phase 1 record remains in [phase_1_execution_plan.md](phase_1_execution_plan.md).

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
- Generates the world map dynamically using `HexMapVisualizer` and `MacroTileCatalog` rather than a static scene.
- Selects Loot Profile IDs from biome and POI state without exposing ItemCore
  resources to UI.
- Creates encounter records deterministically from world seed and coordinates.
- Treats tokens as projections; loading or unloading never changes entity life
  state.

### CombatCore

- Owns encounter flow, lanes, turns, AI, AP costs, action legality, reactions,
  and combat resolution.
- Validates firearm range and readiness before consuming ammunition, combines
  actor and weapon accuracy, and resolves successful shots against one Limb
  Region.
- Applies ballistic Flesh Damage without Stance Damage. Ordinary Stance
  pressure floors at `1`; only explicit takedown-capable resolution may Fell.
- `CombatRules` contains combat-private categories and tuning tables.
- `CombatCommandAdapter` translates neutral player intent into owner-validated
  calls.
- Returns only `GameEnums.CombatOutcome` and neutral runtime snapshots across
  the system boundary.

### BiologicalCore

- Owns anatomy, vitals, Morale, Stance, Trauma, and biological snapshots through explicit `BodyState` and `HumanoidState` resources.
- Composes ItemCore through `InventorySystem`.
- Supplies biological equipment restrictions to ItemCore through callbacks.

### ItemCore

- Owns item definitions, Runtime Item Instances, loadouts, inventory rules, and
  equipment calculations.
- Keeps authored `.tres` resources immutable.
- Stores mutable firearm and consumable state on unique runtime instances.
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
definition: Dictionary
```

### Hex Record

```text
biome: GameEnums.GridBiome
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

- WorldCore produces SEARCH, CAMP, TALK, AMBUSH, and inventory snapshots.
- Macro HUDs display those snapshots and emit stable command IDs, shared enum
  values, and Runtime Item Instance IDs.
- WorldCore revalidates every command against the authoritative player,
  coordinate, inventory, hex, and encounter state.
- `RuntimeStateStore` performs atomic record changes. BiologicalCore and
  ItemCore apply their own effects and restrictions.
- Movement, SEARCH, CAMP, and completed combat advance one authoritative clock;
  BiologicalCore processes the same elapsed duration.
- SEARCH selects a Loot Profile and places generated Runtime Item Instances in
  persistent ground inventory.
- CAMP moves installed gear from player inventory to the Hex Record; it never
  duplicates items.
- TALK changes persistent relationship or world status only after owner-side
  resolution.
- AMBUSH submits a deployment band. CombatCore chooses actual lane indices.
- The collider receives opening initiative.

## Combat Interaction Boundary

- `CombatLaneHUD` and `CombatLaneView` use a modular architecture composed of
  `DuelUI` presentation elements, receiving neutral combat snapshots and
  legal-action descriptors.
- Combat presentation groups legal-action descriptors into player-facing command
  groups: firearm, movement, melee, field, items, and reaction. The groups
  organize owner-produced legality; they do not create legality.
- The bottom command deck owns visual selection state, current group focus,
  weapon cards, and short-lived weapon presentation effects resolved through
  `GunAnimationCatalog`. CombatCore still owns AP, target, readiness, and
  outcome validation.
- Player commands contain an `ActionType` plus only the target or item IDs
  required by that action.
- `CombatCommandAdapter` revalidates commands before routing them to turn, lane,
  inventory, biological, or resolution owners.
- Combat snapshots expose weapon rounds, capacity, effective range, and cycle
  state; presentation does not infer firearm readiness. Static weapon sprites
  come from ItemCore item presentation paths, while `Asset/Guns_Animation/`
  may be resolved through a catalog for short-lived shoot, reload, empty, and
  cycle effects.
- GET UP is an explicit all-AP command for Felled combatants. TAKE COVER applies
  its owner-resolved Stance recovery through normal command routing.
- GUARD ends the active turn and preserves unused AP as Reserved AP for eligible
  reactions. An unresolved Reaction Window blocks turn advancement.
- CombatCore emits outcomes and runtime snapshots. SystemCore applies those
  results to persistent world records.
- Combat presentation never changes macro tokens, entity life state, AP costs,
  or action legality directly.

## Persistence Boundary

- `RuntimeStateStore` writes one versioned JSON save containing the world seed,
  time, player record, entity records, Hex records, and ground-item records.
- Godot-specific values such as `Vector2i` are explicitly tagged in JSON rather
  than restored through executable Variant text.
- A successful load sets a one-shot startup flag. WorldCore consumes that flag
  and restores records before rendering Hexes or generating proximity content.
- Normal game startup loads the default save when present. Scripted smoke tests
  opt into their own isolated save paths.
- `GameDirector` synchronizes cached player and Hex state before saving. `F5`
  saves and `F9` loads the current run. `SaveLoadMenu` exposes three named slots
  with day and timestamp metadata from the main menu and defeat flow.

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
- **Item runtime dict** — `instance_id`, `template_path`, `current_magazine`,
  `needs_cycling`, `definition` (neutral descriptor subset).
- **`GameEnums` macro inventory command IDs** — `MACRO_INV_TAKE`, `MACRO_INV_DROP`,
  `MACRO_INV_EQUIP`, `MACRO_INV_UNEQUIP`, `MACRO_INV_CONSUME`, `MACRO_INV_MOVE`,
  `MACRO_INV_LOAD_MAGAZINE`, `MACRO_INV_INTERACT`.
- **`GameEnums` macro hex command IDs** — `MACRO_HEX_SCAN`, `MACRO_HEX_TRAVEL`,
  `MACRO_HEX_ACT`.
- **`GameEnums` NPC macro purpose strings** — `NPC_PURPOSE_SCAVENGE`, `PATROL`,
  `HUNT`, `ROAM`.
- **`MacroSnapshotBuilder`** — `build_inventory_snapshot()`, `build_limb_snapshot()`,
  `build_world_hud_snapshot()`, `build_hex_descriptor()`, `build_macro_activity_snapshot()`,
  `item_inventory_descriptor()` for neutral UI snapshots.
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
- **Combat boundary** — neutral snapshots and command payloads from
  `CombatCommandAdapter`; outcomes as `GameEnums.CombatOutcome` plus runtime
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
