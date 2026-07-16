# ARCCROSS Documentation

Each topic has one authoritative document. Other files should link to it instead
of restating it.

## Current Contracts

- [Project Glossary](GLOSSARY.md): canonical terms and distinctions.
- [System Architecture](SYSTEM_ARCHITECTURE.md): ownership, dependencies,
  records, and presentation boundaries.
- [Humanoid Token Pipeline](HUMANOID_TOKEN_PIPELINE.md): layered sprite
  contract, current visual coverage, and runtime asset preparation.
- [Phase 1 Execution Plan](phase_1_execution_plan.md): closed vertical-slice
  scope, acceptance criteria, and historical verification.
- [Phase 2 Execution Plan](phase_2_execution_plan.md): active game-dev phase,
  completed workstreams, and remaining goals.
- [Changelog](CHANGELOG.md): dated implementation and verification notes.

## Current Implementation

Status updated on **July 17, 2026**:

### Playable Loop

- Entry scene: `UI/MainMenu.tscn` → `SystemCore/game_director.tscn` →
  `WorldCore/main_world.tscn`.
- New Game seeds `DEMO_WASTELAND_01` and restores the player from persistent
  records. Continue loads one of three JSON save slots with day and timestamp
  metadata.
- Macro play covers hex movement, fog of war, proximity loading, SEARCH/CAMP,
  TALK/AMBUSH, inventory, and world-time biology.
- Macro zones use center-plus-12-ring geometry and directional boundary travel
  through a 22-node four-arm web. Permanent Meta nodes survive characters;
  seeded random nodes and ordinary runtime state do not.
- Hostile entity collision suspends macro input and opens `CombatCore/MainDuelScene`.
- Combat outcomes return to the macro map with persistent injury, ammunition,
  loot, and entity life state intact.
- Defeat shows `DefeatPanel` with new-run and load-save actions.

### Phase Status

- **Phase 1** remains closed and verified. Do not expand the vertical-slice
  acceptance set silently; track new gameplay as phase work.
- **Phase 2 combat HUD** (P2-01 through P2-04) is **complete** as of June 29,
  2026. The bottom command deck, grouped legal actions, weapon cards, visible
  AIMED SHOT limb choices, and `GunAnimationCatalog` effects are implemented
  and covered by `CombatLaneHUDSmoke.gd`.
- Remaining Phase 2 focus: token art coverage, presentation polish, and
  authored content expansion — not combat HUD layout. Shield-specific BLOCK
  rules are complete.

### Systems Snapshot

- Layered Humanoid Tokens mirror supported equipped Innawoods visuals in the
  macro world, combat lane, and inventory Paper Doll.
- Token runtime animation uses seventeen gameplay-relevant sheets; moving-attack
  variants remain source-only.
- The revised Stance loop prevents routine pressure knockdowns and gives Felled
  combatants an explicit all-AP GET UP turn.
- Weapon definitions author handling, accuracy, range, distance falloff, exact
  ammunition feeds, cycling, loading aids, inventory and equipment sprites, and
  attachment compatibility.
- Ballistic attacks deal localized Flesh Damage with zero Stance Damage.
- Exact pistol magazines, revolver speedloading and hand-loading, rifle feeds,
  manual cycling, and shell-by-shell shotgun behavior are covered by automated
  checks.
- The static Innawoods inventory set supplies **167** categorized item Resources.
  Loadouts, loot, enemy generation, persistence, and inventory tests use those
  IDs.
- `LootCatalog` is the single runtime registry. The offline catalog builder
  adds missing definitions without overwriting later Inspector edits.
- Macro node zones retain deterministic seeded generation as a fallback, while
  the authored pipeline stores painted terrain, water, gameplay layers,
  decorations, and placement sockets in `AuthoredWorldMap` resources.
- `WorldCore/plains_zone_template.tscn` is the canonical radius-12 authoring
  example: 469 terrain cells, eight directional arrival/exit pairs, and POI,
  encounter, and quest-object socket examples.
- Macro NPC projection is sparse and purpose-driven; the HUD surfaces nearby NPC
  intent.
- `AudioConductor` handles macro day/night music, combat, and game-over scenes
  plus categorized SFX through `GameEventBus`.
- Core state is decoupled into `BodyState`, `HumanoidState`, `InventoryState`,
  `EntityRecord`, and `HexRecord`.
- Automated smoke scripts cover the vertical slice and focused system contracts.
  The current broad HUD/interface runners still contain teardown and timing
  failures recorded during the July 13 gameplay-loop audit.

### Known Gaps

- Service-rifle scope data is present, but macro **SNIPE** remains unimplemented.
- **EXECUTE** is disabled pending a trait-unlock system.
- Shield items now author BLOCK damage-type coverage, protected Limb Regions,
  and distinct mitigation values.
- Token art coverage remains incomplete for rigs, face and eye equipment, several
  armor regions, and unsupported weapons.
- Squad combat, full narrative dialogue, and balance tuning beyond deadlock
  prevention remain out of scope.
- Hand-painted preset coverage is still incomplete. The authoring contract is
  implemented; assigning finished presets across campaign profiles is content
  work rather than secretly completed by the template scene.

See the [June 29 changelog](CHANGELOG.md#june-29-2026) for the combat HUD
completion record and [Phase 2 Execution Plan](phase_2_execution_plan.md) for
remaining workstreams.

## Design Direction

- [Visual Direction](design/VISUAL_DIRECTION.md): shared presentation language
  and screen-level goals.
- [Combat UI Specification](design/COMBAT_UI_SPECIFICATION.md): combat-specific
  layout and feedback.
- [Combat HUD Asset Map](design/COMBAT_HUD_ASSET_MAP.md): wired HUD atlas regions.
- [Mockup Images](design/mockups/): visual references, not implementation
  contracts.

## Maintenance Rule

Definitions belong in the glossary, system behavior belongs in architecture,
delivery status belongs in the execution plan, and presentation intent belongs
in design documents. Dated implementation notes belong in the changelog.
Remove obsolete claims instead of archiving duplicate copies inside the
repository.
