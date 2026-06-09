# ARCCROSS System Architecture

Canonical terminology is defined in [GLOSSARY.md](GLOSSARY.md). Delivery status
belongs in [PHASE_1_EXECUTION_PLAN.md](PHASE_1_EXECUTION_PLAN.md).

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
  records.
- `GameTimeRules` owns shared action durations and clock conversion.
- `LootCatalog` translates ItemCore resources into neutral descriptors and
  runtime item records.
- `GameDirector` coordinates WorldCore and CombatCore through signals and
  records.

### WorldCore

- Owns hex generation, movement, macro presentation, proximity loading, POI
  resolution, and macro interaction rules.
- Selects Loot Profile IDs from biome and POI state without exposing ItemCore
  resources to UI.
- Creates encounter records deterministically from world seed and coordinates.
- Treats tokens as projections; loading or unloading never changes entity life
  state.

### CombatCore

- Owns encounter flow, lanes, turns, AI, AP costs, action legality, reactions,
  and combat resolution.
- `CombatRules` contains combat-private categories and tuning tables.
- `CombatCommandAdapter` translates neutral player intent into owner-validated
  calls.
- Returns only `GameEnums.CombatOutcome` and neutral runtime snapshots across
  the system boundary.

### BiologicalCore

- Owns anatomy, vitals, Morale, Stance, Trauma, and biological snapshots.
- Composes ItemCore through `InventorySystem`.
- Supplies biological equipment restrictions to ItemCore through callbacks.

### ItemCore

- Owns item definitions, Runtime Item Instances, loadouts, inventory rules, and
  equipment calculations.
- Keeps authored `.tres` resources immutable.
- Stores mutable firearm and consumable state on unique runtime instances.
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

- `CombatPanel` receives a neutral combat snapshot and legal-action descriptors.
- Player commands contain an `ActionType` plus only the target or item IDs
  required by that action.
- `CombatCommandAdapter` revalidates commands before routing them to turn, lane,
  inventory, biological, or resolution owners.
- Passing may preserve unused AP as Reserved AP. An unresolved Reaction Window
  blocks turn advancement.
- CombatCore emits outcomes and runtime snapshots. SystemCore applies those
  results to persistent world records.
- Combat presentation never changes macro tokens, entity life state, AP costs,
  or action legality directly.

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
