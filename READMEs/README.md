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
- [System / Integration Reconciliation Audit](design/SYSTEM_INTEGRATION_RECONCILIATION_AUDIT.md):
  authority winners, rejected conflicts, migration bridges, deferred work, and
  verification evidence for the v14 runtime-state boundary.
- [World State / Simulation Reconciliation Audit](design/WORLD_STATE_RECONCILIATION_AUDIT.md):
  disposable-world authority, atomic action/node contracts, save-v14 migration,
  rejected conflicts, compatibility paths, and verification evidence.
- [World Action Transaction Checkpoint Audit](design/WORLD_ACTION_TRANSACTION_CHECKPOINT_AUDIT.md):
  August 25 medical, inventory, POI, CAMP, movement, SEARCH, NPC-work, terminal
  biology, verification, residual-risk, and next-step record.
- [Architecture Index](ARCHITECTURE_INDEX.md): generated code/resource/test
  inventory for orientation; it is not a behavioral authority.
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
- [Combat UI Specification](design/COMBAT_UI_SPECIFICATION.md): active tactical
  HUD composition, inspection, context-menu, item-projection, timeline, and
  audio-presentation contract.
- [Combat HUD Asset Map](design/COMBAT_HUD_ASSET_MAP.md): current HUD asset
  ownership and semantic asset roles.
- [Combat Reconciliation Audit](design/COMBAT_RECONCILIATION_AUDIT.md): dated
  migration evidence, compatibility disposition, and the latest completion
  records. Its pre-implementation sections are historical, not live guidance.
- [Macro World Overhaul](design/MACRO_WORLD_OVERHAUL.md): supporting Node Web
  lore alignment, Core simulation layers, and alpha/canon boundary.
- [Phase 1 Execution Plan](phase_1_execution_plan.md): closed vertical-slice
  acceptance record.
- [Phase 2 Execution Plan](phase_2_execution_plan.md): closed systems
  foundations record; residual Known Gaps only.
- [Changelog](CHANGELOG.md): dated implementation and verification notes.

## Current Implementation

Status updated on **August 25, 2026**:

### Playable Loop

- Entry scene: `UI/MainMenu.tscn` → `SystemCore/game_director.tscn` →
  `WorldCore/main_world.tscn` (Godot **4.7.1**).
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
  Ask / Trade placeholder). Production combat entry is assembled by
  `GameDirector` and loads `CombatCore/Tactical/TacticalCombatScene.tscn` with
  the `squad_7x5` topology.
- Combat outcomes return to the macro map with persistent injury, ammunition,
  loot, and entity life state intact.
- Defeat shows `DefeatPanel` with new-run and load-save actions.

### Phase Status

- **Phase 1** remains closed and verified.
- **Phase 2 systems foundations are closed/shipped:** inventory/condition
  (P2-11), Node Web, exploration/collision HUD (P2-10), Field Health,
  authored-zone tooling (P2-08), and the earlier shield/item work (P2-06).
  Historical detail lives in [phase_2_execution_plan.md](phase_2_execution_plan.md).
- **August 17 combat reconciliation closeout:** production combat is the
  `squad_7x5` tactical scene with a frozen six-actor cap, one direct player,
  pairwise relationships, geometry-only cover, catalog-owned weapon actions,
  independent presentation clocks, and the corrected incapacitated-body
  handoff. The `duel_12x1` and `skirmish_6x3` resources remain Lab/compatibility
  fixtures only; former real-time/duel-lane material is historical reference.
- **August 25 world-action checkpoint:** medical treatment, inventory, POI gear,
  CAMP, movement, player SEARCH, NPC work, and negotiation now stage semantic mutations from
  canonical records inside the atomic receipt boundary. Completed NPC SEARCH
  now commits depletion, disturbance trace, deterministic salvage ownership,
  knowledge, revisions, time, and reservation release as one receipt. Destroyed
  vital limbs persist and reconcile terminal death. See the
  [checkpoint audit](design/WORLD_ACTION_TRANSACTION_CHECKPOINT_AUDIT.md) for
  verified scope and remaining live-acceptance boundary.
- **Active world track:** [Hex World Generator V2](design/HEX_WORLD_GENERATOR_V2.md).
- **Campaign framing:** [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).

### Systems Snapshot

- Layered Humanoid Tokens mirror supported equipped Innawoods visuals in the
  macro world, tactical arena, and inventory Paper Doll.
- `GameDirector` assembles the production combat handoff; `CombatActionCatalog`
  owns action policy, while `ItemData.specialized_action_ids` supplies
  catalog-validated weapon extensions. Unknown weapon action IDs are rejected.
- `Incapacitate` moves an actor into the neutral handoff layer; `Strip` and
  `Execute` resolve against that projected sector, and executed bodies persist
  through the combat result. This is distinct from active occupancy.
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
  The current Godot 4.7.1 SceneTree gate passes `141/141`.

### Known Gaps

- `MacroGameManager` remains a concentration point. Further extraction must
  preserve explicit authority boundaries instead of breeding smaller god
  objects with matching hats.
- Health/inventory presentation and physical input friction have not yet had a
  dedicated live player-facing acceptance pass after the authority changes.
- Service-rifle scope data is present, but macro **SNIPE** remains unimplemented.
- Token art coverage remains incomplete for rigs, face and eye equipment, several
  armor regions, and unsupported weapons.
- TRADE after Ceasefire is a placeholder pending economy work.
- Larger or dynamically reinforced encounters remain out of current scope;
  production squad assembly is already shipped with a six-actor cap and no late
  entry.
- Combat balance tuning and deeper AI/content expansion remain active in Lab and
  authoring work; they do not define an alternative production mode.
- Hand-painted preset coverage across all campaign nodes is still incomplete.
- Pocket Map / full pocket-device chrome is deferred (Phase 2.5).

### Verification boundary

The latest completed full reconciliation sweep passed `109/109` executable
capital-`Tests` SceneTree scripts with `FAILED=0` under Godot
`4.7.1.stable.official.a13da4feb`; that result predates the August 25 transaction
checkpoint. The current tree contains 139 executable SceneTree scripts and two
`Control` previews, so a new full-sweep claim requires running all 139. The
focused checkpoint suite is recorded in the
[transaction audit](design/WORLD_ACTION_TRANSACTION_CHECKPOINT_AUDIT.md) and
passed `21/21` with editor import exit `0`. Full
sweeps prepare the ignored workspace-local
`.godot/test-appdata`, `.godot/test-localappdata`, and `.godot/test-logs`
directories before execution. The remediation record separately documents live
editor/screenshot evidence. Physical Windows pointer input and subjective
weapon/audio acceptance remain distinct claims.

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
