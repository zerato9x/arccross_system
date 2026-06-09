# ARCCROSS Phase 1 Execution Plan

## Purpose

This document defines the objective completion criteria for Phase 1. A feature is
complete only when its acceptance test passes in the integrated main scene.
Standalone simulations, helper methods, and completion percentages are not proof
of completion.

## Phase 1 Goal

Deliver one playable, persistent vertical slice:

1. Launch into the macro hex world.
2. Move through procedurally generated hexes.
3. Discover and engage a persistent enemy.
4. Control the player during combat while the enemy uses AI.
5. Resolve victory, defeat, or escape correctly.
6. Loot the battlefield and manage equipped and carried items.
7. SEARCH or CAMP on the overworld with biological time costs.
8. Save, exit, reload, and recover the same meaningful world state.

## Definition Of Done

Phase 1 is complete only when all acceptance tests below pass consecutively from
the project main scene using a clean local user-data directory.

### P1-01: Clean Startup

- `project.godot` launches the configured main scene without script errors.
- The macro map, player token, and required managers initialize successfully.
- At least one valid enemy can be generated without hardcoded demo-only wiring.

### P1-02: Macro Movement

- The player can move only to one of the six adjacent hexes.
- Moving updates the authoritative player coordinate before dependent systems run.
- The same world seed produces the same biome and fixed encounter data for a
  coordinate.
- Revisiting a generated hex does not duplicate its POI marker or state.

### P1-03: Persistent Runtime State

- The player has one authoritative runtime state containing biology, inventory,
  equipment, position, and identity.
- Entering and leaving combat does not recreate or reset player state.
- Enemy and hex state exists independently from rendered token nodes.
- Removing an off-screen token does not erase its damage, inventory, or death
  state.

### P1-04: Proximity Loading

- Enemy tokens are instantiated only inside the configured active radius.
- Tokens outside the unload radius are freed without deleting their world records.
- Returning to a coordinate restores the same living enemy or preserves its death.
- Traversing at least 100 hex steps does not cause unbounded token or POI-node
  growth.

### P1-05: Integrated Combat

- Entering an occupied hostile hex suspends macro input and opens combat.
- The player is controlled through a minimal action interface.
- Only enemy combatants use `CombatAIEvaluator`.
- The combat scene receives the existing player and enemy runtime state.
- The duel can terminate through victory, defeat, or escape without continuing
  the turn loop afterward.

### P1-06: Outcome Resolution

- Player victory removes or marks the defeated enemy dead and creates valid loot.
- Player defeat does not delete the enemy or return an apparently healthy player
  to normal exploration.
- Enemy escape preserves the enemy as alive.
- Player escape preserves both combatants and returns the player to a valid macro
  coordinate.
- Damage, ammunition, consumables, and equipment changes survive the transition
  back to the macro world.

### P1-07: Loot And Inventory

- The player can view equipped gear, backpack contents, capacity, and ground loot.
- Items can be transferred between ground and backpack.
- Items can be equipped, unequipped, consumed, and manually dropped.
- Capacity overflow creates ground remnants rather than deleting items.
- Firearm magazine and cycling state belongs to an item instance, not a shared
  resource used by multiple entities.

### P1-08: SEARCH

- SEARCH is available through a minimal overworld action interface.
- It advances world time and applies biological costs.
- It resolves against a data-driven loot table selected by biome or POI.
- Generated loot is placed in the hex's persistent ground inventory.
- A searched location cannot produce unlimited loot unless explicitly configured
  as renewable.

### P1-09: CAMP

- CAMP is available only when the current hex satisfies its safety rules.
- It advances world time and applies hunger, thirst, temperature, and encounter
  consequences.
- It reduces fatigue and performs only the healing explicitly allowed by the
  Phase 1 rules.
- The player can access inventory while camped.

### P1-10: Save And Load

- The save format has an explicit version number.
- Saving captures the world seed, world time, player state, generated hex changes,
  enemy records, searched/camped flags, and ground remnants.
- Loading restores the player to the same coordinate with equivalent biology,
  inventory, enemy, and loot state.
- Loading does not duplicate generated enemies, POIs, or items.

### P1-11: Regression Verification

- Automated tests cover inventory transfer and overflow.
- Automated tests cover deterministic hex generation and search exhaustion.
- Automated tests cover enemy unload/reload persistence.
- Automated tests cover victory, defeat, and escape outcome routing.
- One automated or scripted smoke test performs a save/load round trip.

## Required Demonstration

The final Phase 1 demonstration must perform this sequence without editor
intervention:

1. Start a new game.
2. Move across at least five hexes.
3. Encounter and defeat an enemy using player-issued actions.
4. Transfer at least one dropped item into the player's backpack.
5. SEARCH a valid location and collect its result.
6. CAMP and verify that time and biological values change.
7. Save and exit.
8. Reload and verify position, injuries, inventory, searched state, enemy death,
   and remaining ground loot.

## Out Of Scope For Phase 1

- Final art, animation, sound, and UI styling.
- Full narrative content or dialogue systems.
- Every declared combat action and reaction.
- Squad combat beyond the minimum one-versus-one vertical slice.
- Advanced faction simulation or strategic world AI.
- Multiple save slots, cloud saves, or migration from unreleased save formats.
- Balance tuning beyond preventing obvious deadlocks and dominant test-only
  behavior.

## Implementation Order

1. Repair integrated scene wiring and establish authoritative player state.
2. Introduce persistent world, enemy, hex, and item-instance records.
3. Correct combat ownership and outcome routing.
4. Add deterministic proximity loading.
5. Add biome/POI loot tables and world time.
6. Implement SEARCH and CAMP.
7. Build the minimum inventory and combat interfaces.
8. Add versioned save/load.
9. Automate the acceptance tests and run the required demonstration.

## Current Baseline

As of June 10, 2026, Phase 1 does not pass the definition of done:

- The main scene initializes the persistent player and its two demo enemies.
- The macro player now owns one authoritative `HumanoidCore` and inventory.
- Integrated combat reuses that player state and assigns AI only to the enemy.
- `RuntimeStateStore` now owns neutral player, enemy, hex, ground-item, and
  authoritative in-memory world-time state.
- Enemy tokens are projections keyed by stable IDs and can be unloaded/reloaded
  without deleting their records.
- Runtime item instances now have unique IDs and isolated firearm state.
- World-to-combat handoff uses enemy IDs, neutral snapshots, and
  `GameEnums.CombatOutcome`.
- Proximity loading now generates coordinate-stable encounter records, loads
  tokens within radius 4, and unloads them beyond radius 6.
- A 100-step traversal test verifies bounded enemy-token, tile, and POI-node
  growth, living-enemy restoration, and dead-enemy persistence.
- Entering the adjacent demo POI now opens an actual SEARCH/CAMP panel.
- SEARCH supports three data-driven tool slots and resolves persistent depletion,
  loot, injury, and hostile-attraction outcomes.
- Biomes and POIs select ItemCore-authored weighted loot profiles through stable
  IDs. Generated items are created as neutral runtime records in the hex's
  persistent ground inventory.
- CAMP supports three persistent gear slots and calculates sleep, shelter,
  healing, concealment, and alertness. Installed gear is removed from the
  backpack and stored on the hex without duplication.
- CAMP is gated by WorldCore-owned POI, hazard, and hostile-presence rules. The
  inventory interface is accessible from the POI and CAMP flow.
- Movement, SEARCH, CAMP, and completed combat advance one authoritative clock.
  SEARCH and CAMP process their full elapsed duration through BiologicalCore.
- The macro interaction HUD displays WorldCore-produced snapshots and emits
  intent only; it does not calculate metrics or resolve actions.
- A neutral inventory/ground-loot panel now supports take, drop, equip, unequip,
  consume, capacity display, and persistent overflow spills. It emits intent and
  never receives `ItemData` or an `InventorySystem` reference.
- Entity collision now presents TALK or AMBUSH. TALK offers THREAT, ROB, and
  CEASEFIRE; failed negotiation uses ordinary combat deployment.
- AMBUSH allows far, standard, or close player deployment.
- The collider receives opening initiative for both player- and enemy-initiated
  encounters.
- A neutral combat panel now displays lanes, vitals, AP, legal actions, target
  limbs, usable consumables, and Reaction Windows. `CombatCommandAdapter`
  revalidates intent and owns routing to turn, lane, and resolution systems.
- Player commands now cover the Phase 1 combat path: advance, retreat, charge,
  shooting and aimed targeting, reload/cycle, melee actions, consumables,
  pass/reserve, reactions, execution, and escape.
- Integrated smoke coverage verifies player-issued victory and player escape,
  including persistent enemy death/alive routing.
- Player defeat is distinguished and no longer returns control to normal macro
  exploration, but a defeat/recovery screen is not implemented.
- Versioned save/load is absent.
- Scripted smoke tests cover the macro-to-combat transition, item isolation,
  token unload/reload, hex cache reconstruction, enemy runtime restoration,
  persistent camp slots, search depletion, negotiation deployment, ambush
  placement, collider initiative, authoritative action time, weighted loot
  determinism, valid item IDs, loot-profile exhaustion, inventory transfer,
  equipment changes, consumable routing, capacity spills, CAMP safety, player
  combat commands, reserved-AP reactions, targeted execution, victory, and
  player escape. Defeat presentation, enemy-escape automation, and save/load
  coverage are still absent.
