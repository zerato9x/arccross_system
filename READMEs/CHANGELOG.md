# ARCCROSS Changelog

## July 23, 2026

### Official Turn-Based Combat Overhaul

- Made turn-based combat the official/default Settings mode; retained real-time
  as an optional independently balanced authority over the same canonical item,
  entity, wound, ammunition, condition, and persistence state.
- Added transactional action resolution so AP exhaustion cannot advance the
  turn before rules and queued presentation finish.
- Reworked turn AI to await attacks, prevent overlapping decision loops, cap
  actions, reserve reaction AP, and stop treating AIMED SHOT as an automatic
  score winner.
- Added turn-owned action duration/cue profiles and synchronized actor windup,
  projectile/impact presentation, and firearm-card sheet playback.
- Traced the dim combat stage in live Godot to the naturally dark plains plate,
  not an active shader or overlay; added a combat-local readability tint while
  preserving a softer Melee Lock focus grade.
- Fixed fractional firearm-card atlas row sampling, shortened the post-movement
  ready-weapon recovery, and added live/debug frame reporting.
- Standardized the turn HUD on `HUDAssetLibrary` colors and typography, restored
  the missing top panel/weapon-card frames, and made the 1280-wide command deck
  keep its action controls and combat log in separate regions.
- Added capped viewport-density scaling so the turn HUD remains readable at the
  live 2860x1734 Steam window without double-scaling weapon cards or overlapping
  the battlefield and command regions.
- Reclaimed projectile trails, bullets, and blood sprites when their authored
  presentation ends instead of retaining hidden VFX nodes for the rest of the
  duel.
- Restored the authored BLOCK tags, coverage, and bleed-through values that the
  July 20 bulk item rewrite accidentally stripped from both shield resources.
- Corrected combat portrait anchors so repeated HUD refreshes no longer flood
  Godot's runtime log with invalid size/anchor warnings.
- Removed the dead `RevampedHUDAtlas` script left behind after the retired
  `Asset/UI/revampedHUD` purge.
- Live Godot 4.7.1 MCP validation observed a 10-frame revolver action, locked
  resolution through queue drain, a clean three-decision AI turn, and a real
  hit transitioning from two active projectile nodes to zero after impact.
- The larger AI behavior overhaul is explicitly deferred; the current pass is
  presentation, animation, and interface polish only.
- Marked Central Core campaign implementation paused until the complete
  categorized asset folder is available.

### Documentation Sync And Central Core Master Spec

- Authored `READMEs/design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md` as the active Act 1
  build bible: eviction → North Pointer Tutorial, hard E/S/W seals, systems file
  map, `S:\Asset\_Asset` → biome sort contract, hex structure rules, and phased
  IDE checklist 0–9.
- Synced root `README.md` and `READMEs/README.md` to July 23: Phase 2 systems
  foundations closed/shipped; Central Core is the only active delivery track.
- Pointed `MACRO_WORLD_OVERHAUL.md`, glossary, architecture, and hex dressing
  docs at the Central Core MD; removed Act 1 “thin E/S/W wander” soft language.
- Deleted finished/stale repo plans: Macro HUD remake/repair, entity collision
  overhaul, Phase 2 macro focus, and the HUD/world-log/camera standardization
  plan (not the next queue).
- Replaced Visual Direction “Medical Monitor” with live `FieldHealthHUD`.
- Recorded July 20 realities not previously status-synced: Godot 4.7, Identity /
  Flaw catalog wiring, and HUD anim assets under `Asset/UI/HUD/anim/`.

## July 21, 2026

### Canonical World Spec And Macro Overhaul Docs

- Restored `READMEs/CANONICAL_WORLD_SPECIFICATION.md` as the world bible,
  including the Era 9 **eviction** contract: Central at capacity casts the
  player out; Central stays locked until all four regional Cores are restored
  (endgame systems deferred).
- Added `READMEs/design/MACRO_WORLD_OVERHAUL.md` for Act 1 Central + North spine
  shipping scope, soft local wander, sealed E/S/W arms, and composition plan.
- Added `READMEs/design/HEX_DRESSING_TEMPLATES.md` for fixed-frame / swap-core
  hex visual generation across radius-12 (469-cell) zones.
- Linked the new contracts from `READMEs/README.md` and extended `GLOSSARY.md`
  (Eviction, North Spine, Zone Composition Plan, Hex Dressing Template,
  Regional Dialect, Core Restore).

## July 19, 2026

### Inventory Overhaul And Identical Cross-Mode Item Mechanics

- Added one ItemCore condition resolver used by both production real-time combat
  and the supported future turn-based route. Identical starting records and
  rolls now yield identical wear, fault, breakage, ammunition, malfunction,
  armor, and shield outcomes; only scheduling remains mode-specific.
- Added Base-12 condition bands, grade-scaled wear, firearm jams and contextual
  clearing (`2.2s` real-time, Quick `1/2/3 AP` turn-based), mutating stable-slot
  armor resolution, broken-item legality, and legacy save migration.
- Rebalanced all **168** item Resources with grades, repair domains, concise
  grounded field notes, differentiated authoring values, and stricter
  Service/Carbon/Unique distribution through loadouts and Loot Profiles.
- Added field and CAMP tool-plus-material repair through `MACRO_INV_REPAIR`.
  Repairs consume one material, advance 30 minutes, wear the tool, and are not
  exposed during combat.
- Replaced the runtime-assembled inventory shell with an editor-authored,
  responsive paper-doll/items/inspector layout. Added persistent comparison,
  seven filters, hovered-pane scrolling, keyboard region navigation, preserved
  focus/scroll/selection, context actions, and confirmation for destructive use.
- Rebuilt the equipment region around a readable Innawoods body projection and
  two authored anatomy/carry slot rails. All 15 equipment slots now remain
  visible, expose per-item condition and malfunction state, and drive the same
  layered clothing, armor, weapon, and wound projection used by the inspector.
- Removed the obsolete macro corner-expansion route that embedded InventoryUI
  into an 880x620 host and deliberately hid its paper doll and inspector. PACK,
  the health-HUD shortcut, and keyboard inventory controls now open the same
  high-layer fullscreen surface; live snapshot refreshes preserve that mode,
  and the three regions scale proportionally through ultrawide resolutions.
- Added one shared `CombatItemCard.tscn` to both combat HUDs plus focused catalog,
  parity, persistence, repair, real-time, and turn-mode smoke coverage.

### Documentation Hygiene And Working Agreement

- Synced root and `READMEs/` status to July 19: Field Health HUD, wound
  records, exploration window, entity-collision Event HUD path, item count
  **168**, and deferred Pocket Map / TRADE economy.
- Updated glossary macro interaction terms (Threat / Ceasefire / Ask; ROB
  retired) and documented live hosts `MacroExplorationStage` /
  `MacroExplorationWindow` / `FieldHealthHUD`.
- Recorded Phase 2 workstream **P2-10** for shipped exploration/collision HUD
  work; marked conflicting Macro HUD remake/repair plans as stale.
- Confirmed working agreement: continue features on live foundations; do not
  pause for a total architecture rewrite.

### Authored Field Health HUD And Boundary Cleanup

- Replaced the macro health corner's legacy `MacroStatusPanel` and scripted
  `MedicalMonitor` route with a new `FieldHealthHUD`. The compact view uses six
  large icon-and-bar vital tiles plus an explicit condition banner; the detailed
  view adds seven systemic readouts and seven regional wound cards with limb,
  trauma, integrity, bleeding, and treatment visuals.
- Rearranged the detailed regions into an anatomical paper doll: head above the
  torso, arms flanking the upper torso, and legs below. Region hotspots expose a
  full wound inspector on hover and open a carried-item treatment tray on right
  click while retaining medical-item drag and drop.
- Added an authored six-wound treatment profile. Neutral health snapshots now
  include care instructions, required effects, recommended item IDs, and carried
  medical-item descriptors. Unsupported care such as splinting a fracture is
  identified honestly instead of presenting a button that can never succeed.
- Added a data-authored `HealthHUDProfile` with metric thresholds, transforms,
  icon paths, and body-region definitions. Presentation consumes only the
  neutral `MacroSnapshotBuilder` dictionary and cannot reach live
  `HumanoidBody`, `InventorySystem`, or WorldCore state.
- Routed the campaign node-map medical surface through the same detailed health
  HUD, so the old monitor is no longer a hidden second implementation.
- Added `FieldHealthHUDSmoke.gd` for live metric/region/icon coverage and
  `HealthItemArchitectureSmoke.gd` for cutover, snapshot, profile, and authored
  item-stat contracts.
- Removed the remaining static domain-boundary violations by moving combat and
  menu scene paths plus the debug HUD theme into `PresentationSceneRegistry`.
  `DomainBoundarySmoke.gd` once again validates SystemCore, WorldCore,
  CombatCore, UI, and ItemCore imports.

## July 18, 2026

### Wound, Health, And Item-Stat Overhaul

- Replaced the one-value-per-limb bleeding flag with persistent per-limb Wound
  records: bruise, laceration, puncture, gunshot, fracture, and burn. Each wound
  carries severity, pain, bleeding rate, contamination, and treatment state and
  survives runtime snapshot/save round trips.
- Made active wounds authoritative for blood loss. Combat and macro biological
  ticks now drain Blood from summed hemorrhage rates, while accumulated pain,
  damaged legs, and low Blood reduce motor efficiency and Kinetic Burden.
- Changed bleeding treatment from clearing an entire limb flag to treating the
  worst active wound with the item's authored potency. Old saves and debug
  fixtures containing only `TraumaType.BLEEDING` migrate into wound records.
- Removed encounter-local Stance from the macro survival readout. The interim
  compact health HUD and Medical Monitor exposed Pain, active bleed rate, wound
  counts, wound types, severity, and treatment state; Stance remains a
  combat-only equilibrium resource. That interim presentation was superseded
  by the authored Field Health HUD on July 19.
- Made armor protection body-region-aware. Torso clothing no longer protects
  the head or limbs, and Bulk no longer acts as invisible bonus armor; equipped
  Bulk instead contributes to movement burden. Rebalanced the burden formula so
  ordinary starter equipment is Labored rather than Agonizing; high capacity
  use, heavy gear, and high Bulk still compound into the severe tier.
- Added always-visible loadout totals for Weight, Bulk, Threat, Insulation,
  blunt/sharp/ballistic protection, and Kinetic tier. Inventory examine cards
  now expose these values plus weapon damage and penetration directly.
- Added `WoundItemOverhaulSmoke.gd` covering wound creation, hemorrhage,
  treatment, fractures, persistence, local armor coverage, and visible item
  stats.

## July 17, 2026

### Duel Readability And Turn-Based Comparison

- Replaced the prototype's global `1.6x` timer multiplier with authored action
  profiles: movement is `1.2s`, light strikes are approximately `1.45-1.65s`,
  heavy strikes are approximately `2.4-2.65s`, and finishers are `2.9s`.
  Humanoid sprite sheets now distribute their actual visible frames across the
  matching action duration instead of finishing early and idling through the
  resolver wind-up. AP ticks every `0.5s` and regenerates at only `25%` while
  committed, so action animation no longer doubles as a free refill break.
- Rebuilt the real-time HUD around permanent player and opponent Paper Dolls,
  seven-region wound/Trauma projection, labelled Blood/AP/Stance rails, current
  action and recovery state, terrain context, an impact-marked duel timeline,
  contextual controls, and animated weapon cards for both combatants.
- Preserved layered `GunAnimationCatalog` playback for shoot, reload, and cycle
  effects. Projectiles now begin from the action timeline and arrive on the
  resolver's impact marker instead of damage appearing before the bullet.
- Removed ordinary-action threat zooms and light-hit camera spasms. The camera
  now uses one stable approach profile and one stable Melee Lock profile, with
  restrained displacement reserved for parry, heavy, and finisher impacts.
- `DuelReadabilityEffects` remains responsible for parry, block, feint, trip,
  and damage popups; the permanent central timeline owns enemy intent and the
  explicit telegraph/impact/recovery phases.
- Restored the original turn-based stack as the independent
  `TurnBasedDuelScene`, retaining its turn manager, resolver, adapter, AI, and
  command HUD without leaking turn scheduling into production real-time combat.
- Added `CombatModeComparison.tscn` (`F1` real-time, `F2` turn-based) to run
  both systems from identical standalone records.

### Real-Time Duel Combat Overhaul

- Replaced the production turn manager, Reserved AP reactions, command adapter,
  turn AI, and grouped command deck with a separate fixed-step real-time duel
  runtime. The old stack is no longer wearing a fake moustache and calling
  itself action combat.
- Kept the twelve-slot lane, no-crossing rule, Melee Lock, terrain, cover,
  owner-aware pre-combat traps, Limb trauma, armor, Stance, firearm state,
  encounter handoff, loot, outcomes, humanoid layers, and cinematic camera.
- Added Kinetic Burden plus Stance AP regeneration, fixed action prices,
  animation-timed impacts, automatic Felled recovery, weapon combo profiles,
  cancellable heavy windups, timed guard/parry, push/follow, blind fire, held
  aimed fire, cycling, and reload.
- Added `RealtimeDuelAI` on the same intent surface as the player and a
  full-state `RealtimeDuelHUD` with Paper Dolls, wounds, vitals, weapon-sheet
  animation, action phases, aim, combo, follow, terrain, and feedback.
- Added `RealtimeDuelSmoke.gd`; live editor evaluation verified AP matrices,
  fixed-cost grid movement, melee/combo impact, heavy feint cost, parry stagger,
  partial aimed fire, hostile-only traps, push, and follow. The standalone
  SceneTree runner still encounters the checkout's known Godot `signal 11`.

### Authored Local-Zone Pipeline And Generator Cleanup

- Removed the abandoned procedural river pass, polygon connector bandages,
  random oversized-boulder/tree expansion, and unused generator compatibility
  fields from the in-progress macro-world changes.
- Kept water as authored gameplay data with persistence, passability, travel
  cost, fog-aware rendering, and exploration-HUD descriptions.
- Rebuilt `world_map_editor.tscn` as a clean authoring workspace and added
  `plains_zone_template.tscn` as a complete 469-cell radius-12 example.
- Added `HexMapSocket` records for variable POIs, encounters, quest items, and
  all eight arrival/exit directions. Sockets bake into `AuthoredWorldMap`
  instead of masquerading as decorative sprites with delusions of authority.
- Extended `AuthoredWorldMapBaker` to preserve water layers, freeform
  decorations, fixed marker metadata, and runtime placement sockets.
- Expanded selected-hex HUD descriptors with environment, movement,
  visibility, cover, resources, and water details.
- Verified the authoring scene through live Godot evaluation: 469 baked entries,
  three water examples, three decorations, and nineteen sockets. The standalone
  Godot 4.6.3 SceneTree runner still crashes with the known `signal 11` failure.

## July 16, 2026

### Directional Node Web and Meta World Overhaul

- Replaced the 12-by-12 axial rhombus with true radius-12 zones containing 469
  playable cells and 72 outer-ring cells.
- Rebuilt the campaign as a four-arm directional web with twelve seeded-random
  zones, four permanent gateways, four permanent arm cores, the Central Core,
  and a permanent Meta fetch branch.
- Added opposite-rim arrival, directional destination filtering, run-local node
  snapshots, and a separate `MetaProgressionStore` for cross-run structural and
  progression state.
- Added the North Core Regulator fetch chain: retrieve it from the east branch,
  return it to the Central Core, and permanently unseal the north gateway.
- Marked pre-overhaul run saves incompatible; selecting one now starts a fresh
  character with a clear warning while preserving the separate Meta profile.
- Replaced single tiny decoration rolls with deterministic multi-sprite shrub,
  tree, stone, and prop clusters plus spatially separated POI placement.
- Corrected overlay anchoring and removed arbitrary prop rotation, duplicate
  shrub rendering, full-hex rock clutter, and topology-free road/wall picks.
- Expanded rim travel to eight visual sectors and added a 78-cell, non-playable
  radius-13 hover band that previews eligible destination nodes.

## July 13, 2026

### Shield-Specific BLOCK Rules

- Completed Phase 2 workstream P2-06 with authored shield damage-type coverage,
  protected Limb Regions, and flesh/Stance bleed-through multipliers.
- Ballistic shields can BLOCK covered SHOOT and AIMED SHOT impacts; makeshift
  shields retain narrower blunt/sharp coverage and weaker mitigation.
- Restored DODGE reaction availability for AIMED SHOT, which had been omitted
  from the ranged reaction trigger list.
- Added `ShieldBlockSmoke.gd` coverage for reaction availability, mitigation,
  uncovered limbs, and runtime serialization.

## June 30, 2026

### Documentation Sync

- Updated all project READMEs to the June 30, 2026 implementation state.
- Recorded Phase 2 combat HUD workstreams P2-01 through P2-04 as complete.
- Corrected item catalog count to **167** definitions and smoke coverage to **23**
  scripts.
- Documented the current playable loop: main menu, three save slots, procedural
  macro world, 1v1 combat, and known remaining gaps (SNIPE, EXECUTE, shields,
  token art).
- Added remaining Phase 2 workstreams P2-05 through P2-07 for token coverage,
  shield BLOCK rules, and presentation polish.

## June 29, 2026

### Combat HUD Refactor Completed

- Completed the Phase 2 combat HUD redesign. Actions are now grouped (firearm, movement, melee, item) in a bottom-screen command deck.
- Integrated `GunAnimationCatalog` for dynamic weapon feedback (shoot, reload, cycle, empty) based on equipped weapon IDs.
- Removed legacy HUD frames and monolithic layout components.
- AIMED SHOT now exposes visible Limb Region choices directly in the command deck.

### Visual and Audio Polish

- Added a scrolling parallax background to the Main Menu using new apocalyptic environment assets.
- Updated Blood VFX for combat impacts.
- Added comprehensive new firearm sound effects (9mm, revolver, shotgun handling and firing) tied into the `AudioConductor`.
- Updated the Combat Camera to improve action framing in the tactical lane.

### Interface and Persistence

- Implemented `SaveLoadMenu` UI, allowing players to view and load from three persistent save slots with Day and Timestamp tracking.
- Refined `PaperDollModel` for the inventory UI to accurately reflect multi-layered token visuals.

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
  (expanded to **167** by June 2026) generated from the static Innawoods Items,
  Equipment, and Weapons assets.
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
