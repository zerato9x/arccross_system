# ARCCROSS Documentation

Each topic has one authoritative document. Other files should link to it instead
of restating it.

## Current Contracts

- [Project Glossary](GLOSSARY.md): canonical terms and distinctions.
- [System Architecture](SYSTEM_ARCHITECTURE.md): ownership, dependencies,
  records, and presentation boundaries.
- [Humanoid Token Pipeline](HUMANOID_TOKEN_PIPELINE.md): layered sprite
  contract, current visual coverage, and runtime asset preparation.
- [Phase 1 Execution Plan](PHASE_1_EXECUTION_PLAN.md): scope, acceptance
  criteria, current status, and remaining work.
- [Changelog](CHANGELOG.md): dated implementation and verification notes.

## Current Implementation

Status updated on **June 14, 2026**:

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
- Duel Scene animation remains placeholder, and the existing BLOCK rules have
  not yet been replaced by shield-specific coverage and mitigation.
- The static Innawoods inventory set now supplies 163 categorized item
  Resources. Loadouts, loot, enemy generation, persistence, and inventory
  tests use the new IDs instead of the removed prototype entries.
- `LootCatalog` is the single runtime registry. The offline catalog builder
  adds missing definitions without overwriting later Inspector edits.
- Token art coverage remains incomplete for rigs, face and eye equipment,
  several armor regions, and unsupported weapons. The existing BLOCK rules
  have not yet been replaced by shield-specific coverage and mitigation.

See the [June 14 changelog](CHANGELOG.md#june-14-2026) for implementation and
verification detail.

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
