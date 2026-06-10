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

## Current Status

Status recorded on **June 10, 2026**:

- **Ready to verify:** The implementation exists, but the complete acceptance
  sequence has not been recorded as passing.
- **Partial:** Some required behavior or coverage is still missing.
- **Missing:** The required feature is not implemented.

| Item | Status | Remaining proof or work |
| --- | --- | --- |
| P1-01 Startup | Ready to verify | Run from clean user data. |
| P1-02 Movement | Ready to verify | Include in the integrated demonstration. |
| P1-03 Runtime state | Ready to verify | Include combat and reload transitions. |
| P1-04 Proximity loading | Ready to verify | Existing 100-step smoke coverage must remain green. |
| P1-05 Combat | Ready to verify | Include player-issued victory, defeat, and escape. |
| P1-06 Outcomes | Partial | Add defeat/recovery presentation and enemy-escape automation. |
| P1-07 Inventory | Ready to verify | Include transfer, use, equipment, and spill behavior. |
| P1-08 SEARCH | Ready to verify | Include depletion and persistent ground loot. |
| P1-09 CAMP | Ready to verify | Include safety, installed gear, time, and biology. |
| P1-10 Save/load | Missing | Implement versioned disk persistence and restoration. |
| P1-11 Regression | Partial | Add defeat, enemy escape, and save/load coverage. |

Existing smoke coverage includes runtime-state persistence, proximity loading,
world time, weighted loot, macro interactions, inventory commands, combat
commands, Reaction Windows, victory, and player escape.

## Remaining Order

1. Complete defeat/recovery presentation and enemy-escape routing.
2. Implement versioned save/load.
3. Add the missing outcome and save/load regression coverage.
4. Run the required demonstration from clean user data.

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

## Out Of Scope

- Final art, animation, sound, and UI styling.
- Full narrative or dialogue systems.
- Every declared combat action and reaction.
- Squad combat beyond the one-versus-one slice.
- Advanced faction simulation or strategic world AI.
- Multiple save slots, cloud saves, or migration from unreleased formats.
- Balance tuning beyond preventing deadlocks and obvious dominant behavior.
