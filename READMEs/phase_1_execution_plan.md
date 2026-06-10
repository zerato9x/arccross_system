# ARCCROSS Phase 1 Execution Plan

Phase 1 is one playable, persistent vertical slice. A feature is complete only
when its acceptance criteria pass from the configured main scene against clean
local user data. Standalone helpers and completion percentages are not proof.

## Required Player Flow

1. Launch into the macro world.
2. Move through deterministic hexes.
3. Discover and engage a persistent enemy.
4. Control the player while the enemy uses AI.
5. Resolve victory, defeat, or escape.
6. Loot and manage carried or equipped items.
7. SEARCH or CAMP with world-time and biological consequences.
8. Save, exit, reload, and recover the same meaningful state.

## Acceptance Criteria

### P1-01: Clean Startup

- The configured main scene launches without script errors.
- The macro map, player, and required managers initialize.
- A valid enemy can be generated without scene-specific gameplay wiring.

### P1-02: Macro Movement

- Movement is limited to the six adjacent hexes.
- Authoritative coordinates update before dependent systems run.
- Seeded biome, POI, and initial encounter generation is deterministic.
- Revisiting a Hex does not duplicate its marker or record.

### P1-03: Persistent Runtime State

- Player biology, inventory, equipment, position, and identity have one
  authoritative runtime state.
- Combat transitions do not recreate or reset persistent player state.
  Encounter-local Stance and escape intent clear at combat boundaries.
- Enemy and Hex records exist independently from rendered nodes.
- Unloading a token does not erase damage, inventory, or death.

### P1-04: Proximity Loading

- Entity projections load inside the active radius and unload outside the wider
  unload radius.
- Returning restores the same living entity or preserves its death.
- At least 100 Hex steps do not cause unbounded token, tile, or POI growth.

### P1-05: Integrated Combat

- Entering a hostile occupied Hex suspends macro input and opens combat.
- Player commands use the combat interface; only enemies use combat AI.
- Existing player and enemy runtime state enters the encounter.
- Victory, defeat, and escape terminate the turn loop.

### P1-06: Outcome Resolution

- Victory persists enemy death and valid loot.
- Defeat does not restore ordinary exploration with a healthy player.
- Enemy escape preserves the enemy as alive.
- Player escape preserves both entities and returns to a valid coordinate.
- Damage, ammunition, consumables, and equipment survive the transition.

### P1-07: Loot And Inventory

- The interface shows equipment, backpack, Capacity, and ground items.
- Items can be taken, dropped, equipped, unequipped, and consumed.
- Capacity overflow creates ground records instead of deleting items.
- Firearm state belongs to Runtime Item Instances.

### P1-08: SEARCH

- SEARCH is available through the macro interaction interface.
- It advances World Time and applies biological costs.
- Biome or POI state selects a data-driven Loot Profile.
- Results enter persistent ground inventory.
- Depletion prevents unlimited loot unless explicitly configured otherwise.

### P1-09: CAMP

- Owner-side safety rules determine availability.
- CAMP advances World Time and applies survival consequences.
- Rest and healing follow explicit Phase 1 rules.
- Installed gear persists on the Hex without duplication.
- Inventory remains accessible while camped.

### P1-10: Save And Load

- The save format has an explicit version.
- Saving captures seed, time, player state, Hex changes, enemies, interactions,
  and ground items.
- Loading restores equivalent position, biology, inventory, enemies, and loot.
- Loading does not duplicate generated content.

### P1-11: Regression Verification

- Automated coverage includes inventory transfer and overflow.
- Automated coverage includes deterministic generation and SEARCH depletion.
- Automated coverage includes entity unload/reload persistence.
- Automated coverage includes victory, defeat, and both escape paths.
- A scripted smoke test performs a save/load round trip.

## Verification Status

Status recorded on **June 10, 2026**:

- **Verified:** The acceptance behavior passed from the configured main scene
  under automated clean-state or isolated-save conditions.

| Item | Status | Recorded evidence |
| --- | --- | --- |
| P1-01 Startup | Verified | Main-scene startup is exercised by all integrated smoke scripts. |
| P1-02 Movement | Verified | The vertical slice crosses five adjacent Hexes before combat. |
| P1-03 Runtime state | Verified | Player and enemy state survive combat reconstruction and disk reload. |
| P1-04 Proximity loading | Verified | The 100-step bounded-loading smoke remains green. |
| P1-05 Combat | Verified | Player commands, enemy AI, victory, defeat, and escape terminate correctly. |
| P1-06 Outcomes | Verified | Enemy inventory drops, defeat presentation, and both escape routes are covered. |
| P1-07 Inventory | Verified | Transfer, use, equipment, overflow, and runtime firearm state pass. |
| P1-08 SEARCH | Verified | Data-driven loot, depletion, ground state, and collection pass. |
| P1-09 CAMP | Verified | Safety, time, biology, installed gear, and inventory access pass. |
| P1-10 Save/load | Verified | Versioned JSON round trip restores all required meaningful state. |
| P1-11 Regression | Verified | Eleven automated smoke scripts pass together. |

All eleven smoke scripts passed on **June 10, 2026** using Godot `4.6.3`.
Automated coverage includes:

- Base-12 biology, items, and interaction metrics.
- Runtime Item Instance isolation, in-memory reconstruction, and disk reload.
- Persistent player identity and injury across macro-to-combat transitions.
- Bounded proximity loading across 100 Hex steps.
- Deterministic world time, Loot Profiles, and SEARCH depletion.
- SEARCH, CAMP, TALK failure, AMBUSH placement, and collider initiative.
- Inventory take, drop, equip, unequip, consume, overflow, CAMP safety, and
  inventory access during an active CAMP session.
- Combat commands, Reaction Windows, death loot, defeat presentation, and both
  escape routes.
- Twelve-slot HUD projection, limb readouts, Stance recovery safeguards,
  opposed Grapple, Execute gating, random melee targeting, and Pull / Follow.
- Versioned JSON persistence for player, enemy, Hex, world-time, and ground
  records without duplicate generation.
- One clean vertical slice covering five-Hex travel, player-issued victory,
  loot transfer, SEARCH collection, CAMP, save, teardown, and reload.

## Phase 1 Closure

No known Phase 1 acceptance item remains open. Future work should preserve the
eleven-script regression gate and treat any new gameplay feature as a separate
phase rather than silently expanding this slice.

## Required Demonstration

The final acceptance run must complete without editor intervention:

1. Start a new game and cross at least five hexes.
2. Encounter and defeat an enemy using player-issued actions.
3. Transfer dropped loot into the backpack.
4. SEARCH a valid location and collect its result.
5. CAMP and verify time and biological changes.
6. Save and exit.
7. Reload and verify position, injury, inventory, SEARCH state, enemy death, and
   remaining ground loot.

This sequence is automated by `Tests/Phase1VerticalSliceSmoke.gd` and passed on
**June 10, 2026**.

## Out Of Scope

- Final art, animation, sound, and UI styling.
- Full narrative or dialogue systems.
- Every declared combat action and reaction.
- Squad combat beyond the one-versus-one slice.
- Advanced faction simulation or strategic world AI.
- Multiple save slots, cloud saves, or migration from unreleased formats.
- Balance tuning beyond preventing deadlocks and obvious dominant behavior.
