# ARCCROSS System Architecture

## Core Rule

`GameEnums` is the shared semantic vocabulary. Domain cores must not exchange
ownership of their internal nodes or static resources.

`GameEnums` contains only stable concepts that cross a system boundary or appear
in neutral runtime records. A domain may define private enums and rule tables
when no other core needs to interpret them.

Cross-system communication uses:

- Values defined by `GameEnums`
- Stable string IDs
- Engine primitives such as `Vector2i`
- Neutral dictionaries and arrays
- Signals
- SystemCore orchestration services

## Ownership

### SystemCore

- Owns orchestration, factories, and authoritative runtime records.
- May coordinate domain cores but must not move domain implementation into them.
- `RuntimeStateStore` owns world, entity, hex, player, and ground-item records.
- `GameDirector` translates signals between WorldCore and CombatCore.

### WorldCore

- Owns hex generation, map presentation, movement, and token projection.
- Enemy tokens contain an entity ID and presentation state only.
- Deleting a token must never delete its entity record.
- WorldCore owns macro interaction presentation and deterministic POI resolution.
- WorldCore requests combat with a neutral setup dictionary containing IDs,
  coordinates, `EncounterContext`, collider identity, and ambush position.
- Encounter records are generated once using the world seed and axial coordinate.
- Tokens load inside the active radius and unload outside a wider hysteresis
  radius. Neither operation changes entity lifecycle state.

### CombatCore

- Owns encounter flow, lanes, turns, AI, and resolution.
- `CombatRules` owns combat-private AP categories, action-legality groups, lane
  terrain/object enums, and AI weighting tables.
- It may construct temporary biological combatants from neutral records.
- It translates encounter context into lane placement and collider identity into
  opening initiative.
- It returns `GameEnums.CombatOutcome` and neutral runtime snapshots.
- It does not mutate WorldCore tokens or world dictionaries directly.

### BiologicalCore

- Owns anatomy, vitals, morale, stance, and biological runtime snapshots.
- It may compose ItemCore through `InventorySystem`.
- Biological equipment restrictions are supplied to ItemCore as a callback.

### ItemCore

- Owns item definitions, runtime item instances, loadouts, and inventory rules.
- Static `.tres` files are immutable definitions.
- Carried and equipped items are unique runtime copies with stable IDs.
- Interaction tools expose data-only SEARCH and CAMP modifiers.
- ItemCore does not import BiologicalCore, CombatCore, or WorldCore types.

## Runtime Record Contracts

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

- POI SEARCH uses `loot`, `safety`, and `sneak` metrics.
- CAMP uses `sleep`, `shelter`, `healing`, `concealment`, and `alertness`.
- The UI submits stable item-instance IDs. WorldCore validates those IDs against
  the authoritative inventory before resolving an action.
- CAMP gear is moved out of the player inventory and stored as item runtime
  records on the hex. It is not duplicated.
- TALK resolves to a `NegotiationOutcome`. Failure requests ordinary combat
  deployment; success changes persistent `EntityWorldStatus`.
- AMBUSH submits only `AmbushPosition`. CombatCore owns the actual lane indices.
- The entity identified as the collider is placed first in the combat turn
  ledger and receives opening initiative.

## Dependency Direction

```text
GameEnums
   ^
   |
ItemCore <- BiologicalCore <- CombatCore
                  ^
                  |
               WorldCore

SystemCore coordinates every domain through neutral records and signals.
```

Dependencies must remain one-directional. A lower-level core must not import a
higher-level core to inspect its state. Owner-specific policy is injected through
callbacks or handled by SystemCore.

## Enum And Stat Policy

- Use `GameEnums` for closed categories shared between cores, such as
  `ActionType`, `CombatOutcome`, `Faction`, and `EncounterContext`.
- Keep domain-private categories beside their owning system. Other cores must not
  depend on `CombatRules`.
- Store measurable properties such as threat, weight, bulk, insulation, vision,
  and protection as numeric data or derived calculations, not enum members.
- Store extensible content such as occupations, traits, flaws, recipes, and POIs
  as stable IDs or resources rather than expanding `GameEnums`.
- The immutable genetic axes are represented by `GameEnums.Pillar`.

## Current Boundary

The Phase 1 architecture now enforces neutral records at the WorldCore-to-
CombatCore boundary and removes the ItemCore-to-BiologicalCore dependency.
Existing composition references inside combat and the macro player remain
intentional until narrower interfaces replace them.
