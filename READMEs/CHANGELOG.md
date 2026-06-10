# ARCCROSS Changelog

## June 10, 2026

### Combat Presentation

- Removed the legacy combat Debug UI and Debug Log.
- Added the twelve-slot tactical lane HUD and Melee Lock presentation.
- Added separate Limb Region structure readouts for both combatants. Blood
  remains a systemic vital rather than functioning as total HP.

### Combat Rules

- Reset encounter-local Stance and escape intent between combats without
  healing persistent injuries.
- Changed Strike to resolve a random non-head Limb Region instead of requesting
  a manual target.
- Changed Grapple from guaranteed success to an opposed base-12 check.
- Disabled Execute until the planned trait-unlock system exists.
- Exposed Pull / Follow and preserved Disengage as a separate break-away action.
- Added Recovery Guard after Felled recovery to prevent indefinite knockdown
  loops.
- Clarified that Stumbling receives a normal active turn and added passive
  Stance recovery at turn start.

### Combat Outcomes

- Defeated enemies now surrender all remaining equipped and carried Runtime
  Item Instances into persistent ground loot.
- Added a dedicated run-ended presentation with new-run and load-save actions.
- Preserved dead player state on defeat and living enemy runtime state on enemy
  escape.

### Persistence

- Added versioned JSON save/load for world seed, time, player, enemies, Hex
  changes, CAMP gear, and ground items.
- Added explicit encoding for Godot values such as `Vector2i`.
- Restored loaded records before map rendering and proximity generation.
- Added prototype `F5` save and `F9` load controls plus automatic default-save
  loading during normal game startup.

### Documentation And Verification

- Clarified the distinction between `GameEnums`, the project glossary, and
  domain-private rule data.
- Updated the combat UI specification and glossary for limb structure,
  Stance recovery, and current action behavior.
- Verified all eleven smoke scripts on Godot `4.6.3`:
  Base-12 scale, runtime state, persistent player, proximity loading, world
  time and loot, macro interactions, inventory interactions, combat interface,
  combat lane HUD, versioned save/load, and the clean Phase 1 vertical slice.
