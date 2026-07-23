# ARCCROSS Phase 2 Execution Plan

Phase 2 **systems foundations are closed**. This file is the historical
implementation record for combat, inventory, Node Web, exploration/collision
  HUD, Field Health, and authored-zone tooling. Current combat direction lives in
  [design/TURN_BASED_COMBAT_OVERHAUL.md](design/TURN_BASED_COMBAT_OVERHAUL.md).

Phase 1 remains closed in
[phase_1_execution_plan.md](phase_1_execution_plan.md). Presentation emits
intent; domain cores validate and mutate authoritative state.

## Status

Status updated on **July 23, 2026**:

- Combat HUD workstreams **P2-01 through P2-04 are complete** and again form the
  official turn-based presentation foundation. See
  [June 29 changelog](CHANGELOG.md#june-29-2026).
- Shield-specific BLOCK workstream **P2-06 is complete**. See
  [July 13 changelog](CHANGELOG.md#july-13-2026).
- Directional Node Web / Meta world overhaul shipped **July 16**. See
  [July 16 changelog](CHANGELOG.md#july-16-2026).
- Authored local-zone tooling **P2-08 is complete**. See
  [July 17 changelog](CHANGELOG.md#july-17-2026).
- Real-time duel overhaul **P2-09 is implemented** and remains the optional
  Settings mode.
- Wound / item-stat overhaul and Field Health HUD shipped **July 18–19**.
- Inventory condition, catalog, repair, and authored-HUD overhaul **P2-11 is
  implemented**. Turn-based is the official/default route; real-time remains
  optional. Both consume the same ItemCore outcomes and persistent records,
  while scheduling and balance are intentionally not unified.
- Macro exploration window, trap-to-combat loop, and entity-collision Event HUD
  path (Threat / Ceasefire / Ask / Trade placeholder) are live; do not revive
  `MacroInteractionPanel`. Finished Macro HUD remake/repair plans were deleted.
- **Active next:** official turn-based combat overhaul. Central Core campaign
  implementation is paused until the complete categorized asset folder is
  available.

## Completed Workstreams

### P2-11: Identical Cross-Mode Item Mechanics — Implemented July 19, 2026

- `ItemConditionRules` owns Base-12 condition bands, grade-scaled wear, typed
  fault outcomes, firearm jams, and deterministic malfunction clearing.
- Real-time and turn-based combat call the shared resolver at the same semantic
  item events and persist the same condition, ammunition, and malfunction state.
  Their clocks, AP presentation, movement, attack selection, and AI remain
  independent by design.
- Armor resolves per item in stable equipment-slot order; broken equipment
  retains Weight, Bulk, Size, and Capacity but contributes no active function.
- All 168 current items now author grade, repair domain, grounded field notes,
  and differentiated stats. Loot/loadout distribution keeps Service uncommon,
  Carbon rare, and Unique tied to explicit sources.
- The editor-authored Inventory HUD provides an Innawoods layered body
  projection, 15 anatomy/carry equipment slots with condition state, grouped
  carried/ground items, a persistent inspector/comparison surface, filters,
  safe keyboard and pointer behavior, confirmation for destructive actions,
  and field/CAMP repair.
- `CombatItemCard.tscn` is hosted unchanged by both combat HUDs.
- Focused parity, catalog, inventory, real-time, and turn-mode smokes cover the
  shared contract without pretending seconds and discrete AP are equivalent.

P2-01 through P2-04 remain implementation records for the command deck and
turn/reaction surfaces. The complete official authority stays isolated under
`CombatCore/TurnBased/`; optional real-time remains independently selectable and
both can be inspected through `CombatModeComparison.tscn`.

### P2-09: Real-Time Duel Overhaul — Implemented July 17, 2026

- `RealtimeDuelRuntime` replaces turns with fixed-step AP regeneration and
  owner-validated action timelines.
- A/D moves through the existing twelve-slot lane; terrain, no-crossing,
  Melee Lock, territory, and hostile trap rules remain authoritative.
- Mouse and Space provide contextual melee, blind/aimed fire, timed guard,
  parry, push/follow, and heavy feint controls.
- `RealtimeDuelAI` uses the same intent and timing surface as the player.
- Default pacing is `1.6x` the original prototype timelines, with synchronized
  token playback and opponent wind-up telegraphs during Melee Lock.
- `RealtimeDuelHUD` replaces the grouped command deck with minimal live status,
  aim, combo, follow, weapon, and feedback rails.

### P2-01: Combat HUD Command Deck — Verified June 29, 2026

- Bottom-screen command deck replaces the old narrow floating action list.
- Legal actions remain owner-produced descriptors from `CombatCommandAdapter`
  with `group` metadata.
- Groups: firearm, movement, melee, field, items, and reaction.
- Group selection supports pointer input and keyboard shortcuts.
- Verified by `CombatLaneHUDSmoke.gd`.

### P2-02: Weapon-First Ranged HUD — Verified June 29, 2026

- Active weapon card shows loaded/unloaded sprite from ItemCore presentation
  paths.
- Card shows name, rounds, capacity, optimal/effective range, and READY, EMPTY,
  RELOAD, or CYCLE state.
- Firearm actions appear in the firearm group when legal.
- AIMED SHOT exposes visible Limb Region choices in the command deck.
- Verified by `CombatLaneHUDSmoke.gd`.

### P2-03: Gun Animation Feedback — Verified June 29, 2026

- `CombatCore/DuelUI/GunAnimationCatalog.gd` maps weapon IDs to shoot, reload,
  empty, cycle, casing, shell, and muzzle-flash textures under
  `Asset/Guns_Animation/`.
- `CombatLaneHUD` consumes resolved presentation descriptors.
- SHOOT, RELOAD, and CYCLE show short-lived weapon effects without changing
  CombatCore rules.
- Missing animation assets degrade to the static weapon card.
- Verified by `CombatLaneHUDSmoke.gd`.

### P2-04: Combat HUD Regression Coverage — Verified June 29, 2026

- `CombatLaneHUDSmoke.gd` covers bottom deck layout, grouped actions, weapon
  card sprites, ammo/range/state text, and aimed-shot target choices.
- `CombatInterfaceSmoke.gd` still covers command execution, reactions, outcomes,
  loot spill, defeat, and escape paths.
- `WeaponDataSmoke.gd` remains the firearm rules source of truth.

## Deferred / Residual (not active)

Token coverage (former P2-05), presentation chrome polish (former P2-07),
authored preset library fill, TRADE economy, SNIPE, EXECUTE, and Pocket Map
remain Known Gaps. Central Core implementation is asset-blocked; see
[Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).

### P2-06: Shield-Specific BLOCK Rules — Verified July 13, 2026

Goal: make ballistic shields mechanically distinct from generic BLOCK.

Acceptance criteria:

- Shield items such as `shield_ballistic` and `makeshift_shield` apply authored
  coverage and mitigation during BLOCK reactions.
- Rules remain in CombatCore; presentation only reflects owner-produced outcomes.
- Regression coverage extends `CombatInterfaceSmoke.gd` or a focused shield smoke.

Implementation record:

- `ItemData` authors shield damage-type coverage, protected Limb Regions, and
  flesh/Stance bleed-through multipliers that survive runtime serialization.
- Ballistic shields can offer BLOCK against SHOOT and AIMED SHOT; makeshift
  shields remain limited to authored blunt/sharp coverage.
- Uncovered Limb Regions continue through normal attack resolution instead of
  receiving magical full-body protection from a handheld rectangle.
- `ShieldBlockSmoke.gd` verifies reaction availability, coverage, mitigation,
  AIMED SHOT reaction parity, and serialization.

### P2-07: Presentation Polish — Deferred

Former goal: align macro and combat HUDs with authored asset packs on live
`MacroHudShell` + `FieldHealthHUD`. Stale remake/repair plans were deleted.
Not the active queue.

### P2-10: Macro Exploration Window And Collision HUD — Shipped July 16–19

Implementation record:

- `MacroExplorationWindow` hosts landmark SEARCH/CAMP with drag-drop and camp
  trap persistence; Act-to-enter pacing replaces auto-open on step.
- `MacroExplorationStage` hosts travel beats, narrative events, and entity
  collision sessions previously planned as a separate `MacroEventHud`.
- `MacroEntityCollisionResolver` builds Talk / Ambush / Ask / Trade-placeholder
  sessions; ROB is removed.
- Field Health cutover retired `MacroStatusPanel` / `MedicalMonitor` dual paths.

### P2-08: Authored Local-Zone Pipeline — Verified July 17, 2026

Goal: replace procedural decoration guesswork with a reusable hand-painted zone
contract while retaining seeded generation as a safe fallback.

Implementation record:

- `WorldMapEditor` exposes terrain, water, flora, rock, structure, props,
  decoration, marker, and socket authoring surfaces.
- `AuthoredWorldMapBaker` emits neutral 469-cell resources containing gameplay
  layers, freeform decoration records, fixed marker metadata, and runtime
  placement sockets.
- `plains_zone_template.tscn` demonstrates all eight arrival/exit directions
  plus fixed POI, variable POI, encounter, quest-object, water, blocker, and
  decoration placement.
- Live Godot evaluation verified 469 entries, three water cells, three
  decorations, eight arrivals, eight exits, and three content sockets.

Remaining content work (deferred to Central Core / later content passes — not
a competing Phase 2 track):

- Duplicate the template into finished biome/layout presets.
- Assign those baked resources to campaign node profiles.
- Keep seeded generation for profiles that do not yet have approved authored
  coverage.

## Implementation Record: Combat HUD (Completed)

The following plan shipped on **June 29, 2026**:

1. Moved action layout ownership inside `CombatLaneHUD.gd` with a bottom
   `_action_rect` command deck.
2. Enriched action descriptors in `CombatCommandAdapter.gd` with `group`
   metadata.
3. Replaced flat action rendering with group tabs and active-group buttons.
4. Made AIMED SHOT limb selection visible in the command deck.
5. Added weapon card presentation for sprite, ammo, range, and readiness.
6. Resolved static weapon sprites from ItemCore paths first.
7. Added `GunAnimationCatalog` for short-lived ranged weapon effects.
8. Validated with `CombatLaneHUDSmoke.gd`, `CombatInterfaceSmoke.gd`, and
   `WeaponDataSmoke.gd`.

## Current Non-Goals

- Squad or multi-lane combat beyond the strict duel.
- Reintroducing `CombatPanel`.
- Implementing macro SNIPE.
- Making every `Asset/Guns_Animation/` filename a permanent API.
- Replacing humanoid token animation with HUD gun effects.
- Squad combat beyond the current 1v1 slice.
