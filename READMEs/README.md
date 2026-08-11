# ARCCROSS Documentation

Each topic has one authoritative document. Other files should link to it instead
of restating it.

## Current Contracts

- [Project Glossary](GLOSSARY.md): canonical terms and distinctions.
- [Canonical World Specification](CANONICAL_WORLD_SPECIFICATION.md):
  authoritative setting, factions, Era 9 eviction framing, and narrative
  design principles (not player-facing exposition).
- [World Timeline Codex](WORLD_TIMELINE_CODEX.md): **official** era chronology
  (Pre → Era 9 Glitch). Supersedes older Alpha/README era lists. Not
  player-facing.
- [System Architecture](SYSTEM_ARCHITECTURE.md): ownership, dependencies,
  records, and presentation boundaries.
- [Humanoid Token Pipeline](HUMANOID_TOKEN_PIPELINE.md): layered sprite
  contract, current visual coverage, and runtime asset preparation.
- [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md):
  campaign build bible — eviction, four-Arm non-linear canon, current alpha
  content locks, hub stamp, hex taxonomy / sort SOP, phased checklist (0–9).
- [Hex World Asset Overhaul](design/HEX_WORLD_ASSET_OVERHAUL.md): official
  S:→biome pool roles, Golbanc Era 8 default, alpha homestead→theme ramp,
  dialect profiles, promote phases.
- [Hex World Generator V2](design/HEX_WORLD_GENERATOR_V2.md): authoritative
  469-cell composition, fixed four-arm logistics, one-of-four settlement rule,
  paved/dirt road masks, seeded surroundings, persistence, and acceptance tests.
- [Official Turn-Based Combat Overhaul](design/TURN_BASED_COMBAT_OVERHAUL.md):
  **active combat contract** — official default, transaction lifecycle, AI,
  impact cues, firearm-card playback, and independent mode balance.
- [Macro World Overhaul](design/MACRO_WORLD_OVERHAUL.md): supporting Node Web
  lore alignment, Core simulation layers, and alpha/canon boundary.
- [Phase 1 Execution Plan](phase_1_execution_plan.md): closed vertical-slice
  acceptance record.
- [Phase 2 Execution Plan](phase_2_execution_plan.md): closed systems
  foundations record; residual Known Gaps only.
- [Changelog](CHANGELOG.md): dated implementation and verification notes.

## Current Implementation

Status updated on **July 29, 2026**:

### Playable Loop

- Entry scene: `UI/MainMenu.tscn` → `SystemCore/game_director.tscn` →
  `WorldCore/main_world.tscn` (Godot **4.7**).
- New Game seeds `DEMO_WASTELAND_01` and restores the player from persistent
  records. Continue loads one of three JSON save slots with day and timestamp
  metadata.
- Macro play covers hex movement, fog of war, proximity loading, SEARCH/CAMP
  via `MacroExplorationWindow`, TALK/AMBUSH via the shared exploration/event
  stage, inventory, Field Health treatment, and world-time biology.
- Macro zones use radius-12 geometry on the Directional Node Web. The open
  starter ring contains four Route 1 nodes with fixed Central-to-outward roads;
  only North owns the alpha settlement and wayfinder. Deeper East/South/West
  routes remain locked. See
  [Hex World Generator V2](design/HEX_WORLD_GENERATOR_V2.md).
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
  The turn command deck is again the official combat UI; `RealtimeDuelHUD`
  remains the optional mode.
- **Active world track:** [Hex World Generator V2](design/HEX_WORLD_GENERATOR_V2.md).
- **Campaign framing:** [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).

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
- Starter Route 1 zones use Generator V2: exactly 469 cells, all approved
  seamless plains variants, seed-varying ecology and rubble, fixed paved/dirt
  logistics, and one North-only alpha settlement. Authored maps remain
  available for permanent/special nodes.
- `WorldCore/plains_zone_template.tscn` is the canonical radius-12 authoring
  example.
- Identity catalog wiring includes occupations, traits, and flaws
  (`IdentityCatalog`, `FlawDefinition`).
- `AudioConductor` handles macro day/night music, combat, and game-over scenes
  plus categorized SFX through `GameEventBus`.
- Core state is decoupled into `BodyState`, `HumanoidState`, `InventoryState`,
  `EntityRecord`, and `HexRecord`.
- Automated smoke scripts cover the vertical slice and focused system contracts.

### Known Gaps

- Service-rifle scope data is present, but macro **SNIPE** remains unimplemented.
- **EXECUTE** is disabled pending a trait-unlock system.
- Token art coverage remains incomplete for rigs, face and eye equipment, several
  armor regions, and unsupported weapons.
- TRADE after Ceasefire is a placeholder pending economy work.
- Squad combat and deep narrative dialogue remain out of current scope.
- Turn-based archetype simulations and mode-local balance tuning remain active.
- Hand-painted preset coverage across all campaign nodes is still incomplete.
- Pocket Map / full pocket-device chrome is deferred (Phase 2.5).

## Remaining Work

**Active world delivery track:**
[Hex World Generator V2](design/HEX_WORLD_GENERATOR_V2.md)

1. Maintain fixed four-arm starter logistics and the North-only alpha
   settlement contract.
2. Expand event-driven traces and persistent world changes.
3. Promote later-arm terrain only after seam and asset validation.
4. Add pipe/power overlay families without altering the shipped paved/dirt
   road sockets.
5. Seed-select the sole settlement arm only when the campaign is ready to
   remove the alpha North lock.

## Design Direction

- [Visual Direction](design/VISUAL_DIRECTION.md): shared presentation language
  and screen-level goals.
- [Hex Dressing Templates](design/HEX_DRESSING_TEMPLATES.md): fixed-frame hex
  props with swappable cores for coherent radius-12 zones.
- [Combat UI Specification](design/COMBAT_UI_SPECIFICATION.md): combat-specific
  layout and feedback.
- [Combat HUD Asset Map](design/COMBAT_HUD_ASSET_MAP.md): wired HUD atlas regions.
- [Mockup Images](Mockup/): current visual references (screenshots).
- [Legacy Mockup Plates](design/mockups/): historical sketches only — do not
  drive new HUD work from these.

## Maintenance Rule

Definitions belong in the glossary, system behavior belongs in architecture,
delivery status belongs in the active Central Core overhaul (or closed phase
records), and presentation intent belongs in design documents. Dated
implementation notes belong in the changelog. Remove obsolete claims instead of
archiving duplicate copies inside the repository.
