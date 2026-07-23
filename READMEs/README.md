# ARCCROSS Documentation

Each topic has one authoritative document. Other files should link to it instead
of restating it.

## Current Contracts

- [Project Glossary](GLOSSARY.md): canonical terms and distinctions.
- [Canonical World Specification](CANONICAL_WORLD_SPECIFICATION.md):
  authoritative setting, eras, factions, Era 9 eviction framing, and narrative
  design principles (not player-facing exposition).
- [System Architecture](SYSTEM_ARCHITECTURE.md): ownership, dependencies,
  records, and presentation boundaries.
- [Humanoid Token Pipeline](HUMANOID_TOKEN_PIPELINE.md): layered sprite
  contract, current visual coverage, and runtime asset preparation.
- [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md):
  **active Act 1 build bible** — eviction → North tutorial, travel seals,
  `S:\Asset\_Asset` sort, hex rules, phased IDE checklist.
- [Macro World Overhaul](design/MACRO_WORLD_OVERHAUL.md): supporting Node Web
  lore alignment; defers to Central Core MD where Act 1 seals conflict.
- [Phase 1 Execution Plan](phase_1_execution_plan.md): closed vertical-slice
  acceptance record.
- [Phase 2 Execution Plan](phase_2_execution_plan.md): closed systems
  foundations record; residual Known Gaps only.
- [Changelog](CHANGELOG.md): dated implementation and verification notes.

## Current Implementation

Status updated on **July 23, 2026**:

### Playable Loop

- Entry scene: `UI/MainMenu.tscn` → `SystemCore/game_director.tscn` →
  `WorldCore/main_world.tscn` (Godot **4.7**).
- New Game seeds `DEMO_WASTELAND_01` and restores the player from persistent
  records. Continue loads one of three JSON save slots with day and timestamp
  metadata.
- Macro play covers hex movement, fog of war, proximity loading, SEARCH/CAMP
  via `MacroExplorationWindow`, TALK/AMBUSH via the shared exploration/event
  stage, inventory, Field Health treatment, and world-time biology.
- Macro zones use radius-12 geometry on the Directional Node Web. Permanent Meta
  nodes survive characters; seeded random nodes and ordinary runtime state do
  not. **Act 1 content contract** opens North only after eviction — see
  [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).
- Entity collision opens the exploration/event stage first (Talk / Ambush /
  Ask / Trade placeholder). Combat entry loads `CombatCore/MainDuelScene`.
- Combat outcomes return to the macro map with persistent injury, ammunition,
  loot, and entity life state intact.
- Defeat shows `DefeatPanel` with new-run and load-save actions.

### Phase Status

- **Phase 1** remains closed and verified.
- **Phase 2 systems foundations are closed/shipped:** realtime duel (P2-09),
  inventory/condition (P2-11), Node Web, exploration/collision HUD (P2-10),
  Field Health, authored-zone tooling (P2-08), shields (P2-06). Historical
  detail lives in [phase_2_execution_plan.md](phase_2_execution_plan.md).
  P2-01–04 command-deck text is historical (turn-based / pre–realtime); production
  combat UI is `RealtimeDuelHUD`.
- **Active next:** [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
  Phase 0 docs landed; Phases 1–9 are the build queue. Do not reopen finished
  Macro HUD remake/repair or entity-collision plans.

### Systems Snapshot

- Layered Humanoid Tokens mirror supported equipped Innawoods visuals in the
  macro world, combat lane, and inventory Paper Doll.
- Persistent Wound records own hemorrhage and treatment; Stance stays
  combat-local. Macro health presentation is `FieldHealthHUD` +
  `HealthHUDProfile`.
- Weapon definitions author handling, accuracy, range, distance falloff, exact
  ammunition feeds, cycling, loading aids, inventory and equipment sprites, and
  attachment compatibility.
- The static Innawoods inventory set supplies **168** rebalanced, graded item
  Resources with grounded field notes and repair domains. `LootCatalog` is the
  single runtime registry. `ItemConditionRules` owns Base-12 condition wear and
  malfunctions for both combat modes.
- Macro node zones retain deterministic seeded generation as a fallback, while
  the authored pipeline stores painted terrain, water, gameplay layers,
  decorations, and placement sockets in `AuthoredWorldMap` resources.
- `WorldCore/plains_zone_template.tscn` is the canonical radius-12 authoring
  example.
- Identity catalog wiring includes occupations, traits, and flaws
  (`IdentityCatalog`, `FlawDefinition`).
- `AudioConductor` handles macro day/night music, combat, and game-over scenes
  plus categorized SFX through `GameEventBus`.
- Core state is decoupled into `BodyState`, `HumanoidState`, `InventoryState`,
  `EntityRecord`, and `HexRecord`.
- Automated smoke scripts cover the vertical slice and focused system contracts.

### Known Gaps (deferred — not the active queue)

- Service-rifle scope data is present, but macro **SNIPE** remains unimplemented.
- **EXECUTE** is disabled pending a trait-unlock system.
- Token art coverage remains incomplete for rigs, face and eye equipment, several
  armor regions, and unsupported weapons.
- TRADE after Ceasefire is a placeholder pending economy work.
- Squad combat, deep narrative dialogue, and balance tuning remain out of Act 1
  scope.
- Hand-painted preset coverage across all campaign nodes is still incomplete.
- Pocket Map / full pocket-device chrome is deferred (Phase 2.5).

## Remaining Work

**Only active delivery track:**
[Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)

1. Asset sort (Central + plains from S:/HEXIFY; hub PNG)
2. Act 1 travel seals (E/S/W grey; Central lock)
3. Eviction + occupation flavor (scavenger first)
4. North Pointer Tutorial + Node Map highlight
5. Central look / dressing runtime / North spine content
6. Roads/pipes/power overlays; later E/S/W chapters

## Design Direction

- [Visual Direction](design/VISUAL_DIRECTION.md): shared presentation language
  and screen-level goals.
- [Hex Dressing Templates](design/HEX_DRESSING_TEMPLATES.md): fixed-frame hex
  props with swappable cores for coherent radius-12 zones.
- [Combat UI Specification](design/COMBAT_UI_SPECIFICATION.md): combat-specific
  layout and feedback.
- [Combat HUD Asset Map](design/COMBAT_HUD_ASSET_MAP.md): wired HUD atlas regions.
- [Mockup Images](design/mockups/): visual references, not implementation
  contracts.

## Maintenance Rule

Definitions belong in the glossary, system behavior belongs in architecture,
delivery status belongs in the active Central Core overhaul (or closed phase
records), and presentation intent belongs in design documents. Dated
implementation notes belong in the changelog. Remove obsolete claims instead of
archiving duplicate copies inside the repository.
