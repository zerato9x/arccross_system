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

Status updated on **July 19, 2026**:

### Playable Loop

- Entry scene: `UI/MainMenu.tscn` → `SystemCore/game_director.tscn` →
  `WorldCore/main_world.tscn`.
- New Game seeds `DEMO_WASTELAND_01` and restores the player from persistent
  records. Continue loads one of three JSON save slots with day and timestamp
  metadata.
- Macro play covers hex movement, fog of war, proximity loading, SEARCH/CAMP
  via `MacroExplorationWindow`, TALK/AMBUSH via the shared exploration/event
  stage, inventory, Field Health treatment, and world-time biology.
- Macro zones use radius-12 geometry and directional boundary travel through a
  22-node four-arm web. Permanent Meta nodes survive characters; seeded random
  nodes and ordinary runtime state do not.
- Entity collision opens the exploration/event stage first (Talk / Ambush /
  Ask / Trade placeholder). Combat entry loads `CombatCore/MainDuelScene`.
- Combat outcomes return to the macro map with persistent injury, ammunition,
  loot, and entity life state intact.
- Defeat shows `DefeatPanel` with new-run and load-save actions.

### Phase Status

- **Phase 1** remains closed and verified. Do not expand the vertical-slice
  acceptance set silently; track new gameplay as phase work.
- **Phase 2 real-time duel overhaul** (P2-09) is production combat.
  Turn-based remains an independent comparison target at
  `CombatCore/TurnBased/TurnBasedDuelScene.tscn` via
  `CombatCore/CombatModeComparison.tscn`.
- **Macro exploration / Node Web / health / collision** pillars through July 19
  are shipped. See [Changelog](CHANGELOG.md) dated July 16–19.
- Remaining Phase 2 focus: balance, animation and token coverage, presentation
  polish, authored zone preset library, and content expansion **on the live
  foundations** (no total architecture rewrite pause).

### Systems Snapshot

- Layered Humanoid Tokens mirror supported equipped Innawoods visuals in the
  macro world, combat lane, and inventory Paper Doll.
- Token runtime animation uses seventeen gameplay-relevant sheets; moving-attack
  variants remain source-only.
- Persistent Wound records own hemorrhage and treatment; Stance stays
  combat-local. Macro health presentation is `FieldHealthHUD` +
  `HealthHUDProfile`.
- The revised Stance loop modifies AP regeneration, allows heavy/finisher
  knockdowns, and automatically begins interruptible recovery at `4 AP`.
- Weapon definitions author handling, accuracy, range, distance falloff, exact
  ammunition feeds, cycling, loading aids, inventory and equipment sprites, and
  attachment compatibility.
- Ballistic attacks deal localized Flesh Damage with zero Stance Damage.
- The static Innawoods inventory set supplies **168** categorized item
  Resources. `LootCatalog` is the single runtime registry.
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
- Automated smoke scripts cover the vertical slice and focused system contracts
  (including wounds, field health, exploration window, and domain boundaries).

### Known Gaps

- Service-rifle scope data is present, but macro **SNIPE** remains unimplemented.
- **EXECUTE** is disabled pending a trait-unlock system.
- Token art coverage remains incomplete for rigs, face and eye equipment, several
  armor regions, and unsupported weapons.
- TRADE after Ceasefire is a placeholder pending economy work.
- Squad combat, deep narrative dialogue, and balance tuning beyond deadlock
  prevention remain out of scope.
- Hand-painted preset coverage is still incomplete. The authoring contract is
  implemented; assigning finished presets across campaign profiles is content
  work.
- Pocket Map / full pocket-device chrome is deferred (Phase 2.5).

See [Changelog](CHANGELOG.md) for July 16–19 overhaul records and
[Phase 2 Execution Plan](phase_2_execution_plan.md) for remaining workstreams.

### Working Agreement

Finish inventory, hex exploration, and related features on the current
domain/presentation stack. Prefer incremental Resource conversion when a
feature needs it. Do not execute the stale conflicting Macro HUD remake/repair
plans without rewriting them against `MacroHudShell` + `FieldHealthHUD`.

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
