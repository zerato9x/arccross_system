# ARCCROSS Changelog

## June 12, 2026

### Stance And Recovery

- Prevented ordinary Stance Damage from reducing a combatant below `1`.
  Explicit takedown effects may still Fell a target.
- Restricted BREAK knockdowns to targets that are already Stumbling.
- Replaced automatic Felled turn skipping with an explicit GET UP action that
  consumes all current AP, restores `6` Stance, and applies Recovery Guard.
- Changed TAKE COVER to restore `2` Stance and exposed the current Stance State
  in combat presentation.

### Weapon Data And Ballistics

- Expanded item definitions with inventory, unloaded, and equipped sprite
  paths; accuracy, effective and optimal range, distance falloff, exact
  ammunition and magazine IDs, loading aids, cycling rules, and attachment
  compatibility.
- Added Shotgun as a Weapon Class and Ammunition as an Item Type.
- Changed ballistic hits to deal `0` Stance Damage and apply the weapon's
  authored Flesh Damage directly to one resolved Limb Region.
- Removed the hidden ballistic damage multiplier. Out-of-range shots are now
  rejected before ammunition is consumed.
- Combined shooter Finesse, weapon Accuracy Rating, distance, environment, and
  aimed-fire bonuses in ranged hit resolution.

### Firearm Handling

- Enforced exact magazine and loose-ammunition compatibility for magazine-fed
  pistols and rifles.
- Added six-round revolver handling: CYCLE hand-loads one pistol round, while a
  compatible speedloader enables RELOAD.
- Added five-round service-rifle handling with single-round CYCLE loading or
  clip-assisted RELOAD.
- Required the service rifle and shotgun to CYCLE after firing.
- Added shell-by-shell shotgun loading. Shotgun damage remains full through two
  lane tiles, falls to `35%` by tile four, and cannot hit beyond tile four.
- Added rounds, capacity, effective range, and cycling state to combat weapon
  snapshots and HUD output.

### Content And Verification

- Added authored carbon and service pistols, revolver, carbon rifle, AK-47,
  service rifle, shotgun, compatible feeds, loading aids, service-rifle scope,
  and sharp-melee resources linked to Innawoods inventory and equipment
  sprites.
- Refined blunt and sharp melee data around one-handed versus two-handed
  accuracy, Weight, and Bulk tradeoffs.
- Updated player, Arcborn, and generated ranged-enemy loadouts with compatible
  weapons and ammunition support.
- Kept Duel Scene animation as placeholder content. Shield-specific BLOCK
  coverage and mitigation remain outside this weapon-data pass.
- Added `WeaponDataSmoke.gd` coverage for the firearm roster, exact feeds,
  zero-Stance ballistic limb damage, manual loading, shotgun falloff, scope
  metadata, and runtime serialization.
- Passed the new weapon smoke test, Base-12 scale, runtime state, save/load,
  combat lane HUD, combat interface, and a headless editor import check on
  Godot `4.6.3`.

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
