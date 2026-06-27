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
  current workstreams, and implementation plans.
- [Changelog](CHANGELOG.md): dated implementation and verification notes.

## Current Implementation

Status updated on **June 28, 2026**:

- The project is now in **Phase 2**. Phase 1 remains closed and verified; new
  work should be tracked as phase expansion instead of quietly stuffing more
  furniture into the vertical-slice closet.
- Layered Humanoid Tokens now mirror supported equipped Innawoods visuals in
  the macro world and combat lane.
- Token runtime animation is restricted to six gameplay-relevant sheets;
  strafe and other unreachable variants are excluded from runtime loading.
- The revised Stance loop prevents routine pressure from causing immediate
  knockdowns and gives Felled combatants an explicit all-AP GET UP turn.
- Weapon definitions now author handling, accuracy, range, distance falloff,
  exact ammunition feeds, cycling, loading aids, inventory and equipment
  sprites, and attachment compatibility.
- Ballistic attacks deal localized Flesh Damage with zero Stance Damage.
- Exact pistol magazines, revolver speedloading and hand-loading, rifle feeds,
  manual cycling, and shell-by-shell shotgun behavior are covered by automated
  checks.
- Service-rifle scope data is present, but the macro SNIPE action remains
  planned.
- The static Innawoods inventory set now supplies 163 categorized item
  Resources. Loadouts, loot, enemy generation, persistence, and inventory
  tests use the new IDs instead of the removed prototype entries.
- `LootCatalog` is the single runtime registry. The offline catalog builder
  adds missing definitions without overwriting later Inspector edits.
- The monolithic combat interface has been replaced with a modular `DuelUI`
  component architecture. The active Phase 2 combat HUD plan moves the action
  interface to a bottom command deck, groups legal actions by type, and makes
  weapon sprites, ammunition, range, reload, and cycle state central to ranged
  play.
- Macro world maps are dynamically loaded and procedurally generated using
  `HexRecord` and `MacroTileCatalog`, replacing the static world scene.
- Macro NPC projection is intentionally sparse and purpose-driven; the HUD now
  surfaces nearby NPC intent instead of filling the map with mystery meat.
- An integrated Audio Conductor System handles synchronized dynamic playback of
  music and categorized sound effects.
- Core biological and system states have been decoupled into explicit resource
  tracking classes (`BodyState`, `HumanoidState`, `InventoryState`,
  `EntityRecord`, `HexRecord`).
- Token art coverage remains incomplete for rigs, face and eye equipment,
  several armor regions, and unsupported weapons. The existing BLOCK rules
  have not yet been replaced by shield-specific coverage and mitigation.

See the [June 28 changelog](CHANGELOG.md#june-28-2026) and
[Phase 2 Execution Plan](phase_2_execution_plan.md) for the current combat HUD
workstream.

## Design Direction

- [Visual Direction](design/VISUAL_DIRECTION.md): shared presentation language
  and screen-level goals.
- [Combat UI Specification](design/COMBAT_UI_SPECIFICATION.md): combat-specific
  layout and feedback.
- [Mockup Images](design/mockups/): visual references, not implementation
  contracts.

## Maintenance Rule

Definitions belong in the glossary, system behavior belongs in architecture,
delivery status belongs in the execution plan, and presentation intent belongs
in design documents. Dated implementation notes belong in the changelog.
Remove obsolete claims instead of archiving duplicate copies inside the
repository.
