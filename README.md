# ARCCROSS

ARCCROSS is a lethal survival game built around immutable bodies, systemic
injury, equipment-driven progression, persistent hex exploration, and tactical
combat.

Its abstract mechanical language is anchored to twelve: Pillars use `1` to `12`,
while systemic reserves such as Blood and combat-local equilibrium such as
Stance use `0` to `12`. Wounds persist as typed per-limb injuries with severity,
pain, bleeding, contamination, and treatment state. Physical measurements
retain meaningful units.

## Design Pillars

- **Make do:** Each run begins with a body the player must adapt to, not level
  into an ideal build.
- **Gear is progression:** Equipment compensates for physical weaknesses and
  expands practical options.
- **Consequences persist:** Injury, ammunition, inventory, enemies, and world
  changes survive transitions between exploration and combat.
- **Systems own their rules:** Presentation emits intent; domain cores validate
  and mutate authoritative state.

## Current Prototype

Status updated on **July 29, 2026**.

### Playable Today

Launch from `UI/MainMenu.tscn` into a persistent macro run (Godot **4.7**):

1. Start a new world or continue from one of three save slots.
2. Explore seeded radius-12 local zones with fog of war, landmark POIs, and
   purpose-driven NPC activity.
3. Open SEARCH/CAMP through `MacroExplorationWindow` (Act at landmarks; no
   auto-open on step).
4. Resolve entity collisions through the shared exploration/event stage:
   TALK (Threat / Ceasefire → Ask / Trade placeholder) or AMBUSH with opponent
   summary and combat-grid preview.
5. Fight persistent enemies in readable, lethal turn-based 1v1 lane duels.
   Real-time combat is an optional Settings mode.
6. Manage equipment through the authored three-region Inventory HUD: its
   Innawoods body projection, anatomy/carry slot rails, condition states,
   comparisons, firearm readiness, grounded field notes, and tool-plus-material
   repair; treat wounds through the Field Health HUD.
7. Save and reload with `F5` / `F9` or the main-menu and in-game slot UI.
8. Cross radius-12 local zones through directional rims and the Node Web. The
   four Route 1 nodes form the open starter ring; deeper North is open while
   deeper East/South/West remain sealed.

Characters and their run-local worlds are disposable. Permanent Meta nodes,
completed Meta Events, gateway state, structural mutations, and arm-core
reconstruction persist for later characters through the separate Meta Progress
profile.

### Phase Status

- **Phase 1** is closed and verified. The persistent vertical slice remains the
  regression baseline.
- **Phase 2 systems foundations are closed/shipped:** the tactical combat authority,
  inventory/condition/repair, directional Node Web, exploration window + trap
  loop, persistent wounds, Field Health HUD, entity-collision Event HUD path,
  authored-zone tooling.
- Official combat runs through `CombatCore/Tactical/TacticalCombatScene.tscn`.
  Production encounters use a concise `12 x 1` duel topology with the current
  AP, forecast, health, wound, inventory, and action rules. `6 x 3` and `7 x 5`
  profiles remain laboratory scaffolding rather than player settings.
- **Active world track:** [Hex World Generator V2](READMEs/design/HEX_WORLD_GENERATOR_V2.md).
- **Campaign framing:** [Central Core Campaign Overhaul](READMEs/design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).

### Core Systems

- Combat uses a twelve-slot lane, localized Limb Region damage, and
  encounter-local Stance. Each turn grants a discrete 12 AP pool and can bank
  leftover AP for reactions. Occupied cells enforce linear no-passing and
  adjacent same-squad enemies can enter as a supported 1v2 encounter.
- Ballistic hits deal no Stance Damage. A successful shot applies the weapon's
  authored Flesh Damage directly to one Limb Region.
- Firearms enforce authored range, accuracy, ammunition, magazine or loading
  aid, capacity, and cycling rules.
- Persistent per-limb Wound records drive hemorrhage, pain, and treatment.
  Macro survival UI is `FieldHealthHUD` driven by `HealthHUDProfile` snapshots.
- The static Innawoods inventory set maps into **168** rebalanced Resources with
  authored grade, repair domain, condition participation, grounded field note,
  and differentiated stats. Supported equipped visuals drive layered Humanoid
  Tokens in the macro world and combat lane.
- Runtime items persist condition (`0-12`) and firearm malfunctions. SEARCH,
  CAMP, firearm attempts, melee impacts, armor, and shields resolve wear and
  typed faults through one combat-independent ItemCore contract. Broken gear
  keeps its physical burden and storage while losing active functionality.
- Field and CAMP repairs consume an authored material, take 30 world minutes,
  wear the selected tool, and remain unavailable in either combat mode.
- Item definitions are shared Resources loaded once by `LootCatalog`; items do
  not require individual scripts or scene nodes.
- Route 1 local zones use Generator V2: fixed seed-invariant paved/dirt
  logistics, seed-varying terrain and ecology, poor exhaustible rubble, and one
  North-only alpha settlement across the four-node starter ring.
- `AuthoredWorldMap`, `WorldMapEditor`, and `AuthoredWorldMapBaker` remain the
  hand-painted preset pipeline for permanent and special nodes.
- The reusable `plains_zone_template.tscn` contains the complete 469-cell
  footprint, eight arrival sockets, eight exit sockets, and examples for fixed
  POIs, variable POIs, encounters, quest objects, water, and freeform props.
- Macro NPC projection is capped for readability and surfaces purpose signals
  through the world HUD.
- Identity catalog wiring includes occupations, traits, and flaws.
- An integrated Audio Conductor handles synchronized music and categorized SFX.
- Core biological and system states live in explicit resource classes
  (`BodyState`, `HumanoidState`, `InventoryState`, `EntityRecord`,
  `HexRecord`).
- `CombatCore/CombatModeComparison.tscn` is the topology lab (`F1` production
  `12 x 1`, `F2` future `7 x 5`) and never saves laboratory state.
- Automated smoke scripts cover the vertical slice and focused system contracts.

### Known Gaps

- Macro **SNIPE** remains unimplemented; service-rifle scope data is metadata
  only.
- **EXECUTE** is gated off (`CombatRules.EXECUTE_ENABLED = false`).
- Ballistic defense still requires shield-authored damage-type and Limb Region
  coverage; ordinary melee guard/parry does not magically stop bullets.
- Humanoid token art coverage remains incomplete for several rigs, face/eye
  equipment, and unsupported weapons.
- Production supports 1v1 and 1v2. Larger squads and the `6 x 3` / `7 x 5`
  topologies are not player-facing.
- TRADE after Ceasefire is a placeholder pending an economy pass.
- The authored-zone toolchain is complete, but campaign profiles still need a
  real library of hand-painted presets; unassigned random nodes retain the
  seeded procedural fallback.
- Pocket Map / full pocket-device HUD chrome remains deferred (Phase 2.5).

## Working Agreement (July 29)

Phase 2 foundations stay live. Generator V2 is the active world-delivery track:
fixed logistics are authored truth, seeded surroundings provide run variation,
and the starter ring contains only one inhabited settlement. Do not restore the
legacy arrival-driven road behavior or four-settlement starter contract.

## Item Authoring

Run `Tools/Build-StaticItemCatalog.ps1` after adding static Innawoods assets.
The default mode creates only missing definitions and preserves Inspector
edits. Use `-Rebuild` only when intentionally replacing the generated catalog.

## Macro Zone Authoring

Duplicate `WorldCore/plains_zone_template.tscn`, paint the TileMap layers, place
`HexDecorProp`, `HexMapMarker`, and `HexMapSocket` children, then set a unique
`map_id` and `output_path` on `AuthoredWorldMapBaker`. Toggle `bake_now` to emit
the runtime `.tres`. Keep all directional rim corridors traversable; the baker
records authored data but does not rescue a beautifully painted dead end.

## Documentation

- [Documentation index](READMEs/README.md)
- [Official Turn-Based Combat Overhaul](READMEs/design/TURN_BASED_COMBAT_OVERHAUL.md)
- [Central Core Campaign Overhaul](READMEs/design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
- [Hex World Asset Overhaul](READMEs/design/HEX_WORLD_ASSET_OVERHAUL.md)
- [Hex World Generator V2](READMEs/design/HEX_WORLD_GENERATOR_V2.md)
- [Project glossary](READMEs/GLOSSARY.md)
- [Canonical world specification](READMEs/CANONICAL_WORLD_SPECIFICATION.md)
- [World Timeline Codex](READMEs/WORLD_TIMELINE_CODEX.md) (official era chronology)
- [Macro world overhaul](READMEs/design/MACRO_WORLD_OVERHAUL.md)
- [System architecture](READMEs/SYSTEM_ARCHITECTURE.md)
- [Phase 1 execution plan](READMEs/phase_1_execution_plan.md)
- [Phase 2 execution plan](READMEs/phase_2_execution_plan.md)
- [Humanoid token pipeline](READMEs/HUMANOID_TOKEN_PIPELINE.md)
- [Changelog](READMEs/CHANGELOG.md)
