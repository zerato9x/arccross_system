# ARCCROSS Changelog

## June 28, 2026

### Combat Flow Refactor

- Simplified Melee Lock into direct `PUSH`, `PULL`, `BREAK STANCE`, `GRAPPLE`,
  and `STRIKE` choices. Deprecated `PUSH_FOLLOW`, `PULL_STAY`, and `DISENGAGE`
  remain backend compatibility values only.
- Replaced player-facing pass/reserve wording with `GUARD`, which ends the
  active turn and banks remaining AP for eligible reactions.
- Added combat-turn bleeding pressure, visible bleed log entries, immediate body
  panel refreshes, and death checks through existing vital failure.
- Tuned close-range firearm dodge penalties and Felled grounded strike payoff so
  push-then-shoot and grapple-then-strike loops feel lethal without becoming
  invisible dice soup.
- Lowered craven thrall durability fixtures so their threat is rushing Melee
  Lock, not surviving clean hits like budget mythology.

### Phase 2 Documentation And Combat HUD Plan

- Marked ARCCROSS as Phase 2 in the canonical README set while preserving the
  closed Phase 1 execution plan as historical verification.
- Added `READMEs/phase_2_execution_plan.md` as the active planning document.
- Recorded the Phase 2 combat HUD implementation plan: bottom command deck,
  grouped action selection, visible aimed-shot target choices, weapon cards, and
  a cataloged path into `Asset/Guns_Animation/` for ranged weapon feedback.
- Updated the combat UI specification, architecture notes, glossary, and HUD
  asset README so the new plan has one place to live instead of reproducing
  itself like a bug report with ambition.
- Corrected README links to the actual lowercase phase-plan filenames.

## June 19, 2026 - Systems Refactor

### Combat Interface Revamp

- Replaced the monolithic `CombatPanel` with a modular UI architecture under `CombatCore/DuelUI/`.
- Introduced specialized presentation components: `CombatActionButton`, `CombatActorFloatHUD`, `CombatContextBoard`, `CombatGridHoverCard`, and `CombatGridSlot`.
- Refactored `CombatLaneHUD` and `CombatLaneView` to integrate with the new modular UI framework.
- Updated `MainDuelScene` to support the revamped combat lane interface.

### Audio Conductor System

- Implemented `audio_conductor.gd` and `sfx_conductor.gd` to manage music and dynamic sound effects playback.
- Integrated a comprehensive new sound library covering environment, footsteps, combat interactions, firearms, and destruction events.
- Created `audio_conductor_editor_bridge.gd` for tooling and timeline support.
- Refactored project-wide audio imports to stabilize the newly integrated assets.

### Macro Map Integration and Generation

- Removed the monolithic static `game_director.tscn` map which previously stored thousands of nodes.
- Shifted the world map to a dynamic, procedural generation and loading model utilizing the newly added `HexRecord`.
- Established `MacroTileCatalog` for a data-driven approach to hex tile definitions.
- Introduced Python automation scripts (`slice_hex.py`, `update_tscn.py`) to handle tile slicing and map data generation.
- Re-architected `HexWorldGenerator` and `HexMapVisualizer` to utilize the dynamic loading system.

### Core Systems Refactoring

- Decoupled state management from logic nodes by extracting dedicated resource classes: `BodyState`, `HumanoidState`, `InventoryState`, `EntityRecord`, and `HexRecord`.
- Refactored `HumanoidBody`, `HumanoidCore`, `RuntimeStateStore`, and `MacroGameManager` to align with the new decoupled state definitions.
- Refined `GameEnums` definitions to clean up redundant configurations.
- Cleaned up obsolete static test runners, replacing them with dynamic validation.

## June 19, 2026 - Entity Projections

### Entity Projections

- Added `EntityProjectionAssets` as the shared texture cache for humanoid
  presentation. Macro/combat token sheets, Innawoods Paper Doll textures, and
  generated grip-mask textures now reuse cached resources.
- Converted `PaperDollModel.tscn` from an empty scripted root into an authored
  static layer stack. `PaperDollModel.gd` now binds those nodes and only updates
  their texture state.
- Adopted **Entity Projection** as the shared term for macro-world tokens,
  combat-lane tokens, and the Innawoods Paper Doll.

## June 15, 2026

### Humanoid Token Animation Contract

- Expanded the layered token runtime contract from six animations to seventeen:
  three disposition idles, macro walking, combat forward/backward running,
  impaired crouch movement, four attacks, two cover strafes, damage, contextual
  interaction/aiming, and death.
- Added combat presentation events shared by player and AI actions. Firearms use
  `Attack1`; Grapple and Break use `Attack2`; melee strikes alternate
  `Attack3`/`Attack4`; Take Cover and Dodge use retained Strafe animations.
- Added combat movement sequencing: forward `Run`, retreat `RunBackwards`,
  firearm `Taunt` aim recovery, then aggressive `Idle2`.
- Added `CrouchIdle` and `CrouchRun` for Stance `0-6` or two disabled legs.
- Added macro disposition presentation: neutral player `Idle`, hostile NPC
  `Idle2`, passive NPC `Idle3`, with `Taunt` queued after movement for POI and
  pre-combat interactions.
- Kept only the four simultaneous moving-attack variants outside the runtime
  contract: `RunAttack`, `RunBackwardsAttack`, `StrafeLeftAttack`, and
  `StrafeRightAttack`.

### Humanoid Token Movement

- Corrected the eight-direction sprite-row mapping. Sheet rows now resolve
  clockwise from right through down, left, and up instead of mirroring every
  horizontal direction.
- Corrected combat presentation so player and enemy tokens face each other.
- Extended macro movement long enough to display several `Walk` frames.
- Added tweened `Walk` presentation when combatants change lane slots.
- Added direction-aware backpack depth: packs remain behind torso clothing when
  facing the camera and move above torso and armor layers when facing away.
- Added smoke coverage for facing rows, frame advancement, lane translation,
  backpack depth, and returning to the idle pose after movement.

## June 14, 2026

### Humanoid Tokens

- Added a shared layered Humanoid Token renderer for macro-world and combat-lane
  presentation.
- Authored the token as a reusable Godot scene with twelve pooled `Sprite2D`
  layer nodes. Macro actors and the combat lane now instance that scene instead
  of constructing presentation nodes from scripts.
- Derived player appearance from the authoritative equipped inventory and enemy
  appearance from persistent runtime equipment or authored spawn loadouts.
- Replaced full-character faction tinting with macro token ground rings so
  equipped colors remain faithful to their visual layers.
- Added shared visual aliases for definitions that intentionally use the same
  Innawoods appearance, including jeans, generic pistols, and bat variants.
- Limited runtime animation loading to `Idle`, `Walk`, `CrouchIdle`, `Attack1`,
  `TakeDamage`, and `Die`. Strafe and backwards movement variants remain source
  assets but are not runtime behavior.
- Preserved the old macro sprites as hidden scene fallbacks so inherited scene
  overrides remain valid during migration.
- Added token assertions to persistent-player and combat-lane HUD smoke tests.
- Verified the authored node hierarchy and live macro rendering through the
  Godot AI editor, runtime-tree, and game-capture tools.
- Added a pipeline contract covering missing visual categories, source/runtime
  separation, manifest preparation, shared cropping, import settings, and
  benchmark targets.

### Verification

- Passed the headless editor import on Godot `4.6.3`.
- Passed `PersistentPlayerSmoke.gd` with macro token, equipment layer, enemy
  projection, movement animation, and macro-to-combat persistence checks.
- Passed `CombatLaneHUDSmoke.gd` with layered lane tokens and Felled pose
  checks while retaining the existing combat and Melee Lock contract.

## June 12, 2026

### Static Item Catalog

- Replaced the prototype item set with 163 categorized Resource definitions
  generated from the static Innawoods Items, Equipment, and Weapons assets.
- Migrated player and enemy loadouts, loot profiles, spawners, combat fixtures,
  and persistence tests to the new stable item IDs.
- Added multi-layer Paper Doll paths while retaining singular equipped-sprite
  compatibility. Duel Scene animation assets are deliberately excluded.
- Made `LootCatalog` the single runtime item registry and removed duplicate
  item loading from `MobSpawner`.
- Added a non-runtime PowerShell catalog builder. Normal runs preserve existing
  Inspector edits; `-Rebuild` explicitly replaces generated definitions.
- Added catalog validation for IDs, static asset paths, required Phase 1
  entries, and accidental Duel Scene references.

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
- Exposed the earlier Pull / Follow and Disengage prototype, now superseded by
  the June 28 `PUSH` / `PULL` / `GUARD` combat-flow refactor.
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
