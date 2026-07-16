# ARCCROSS

ARCCROSS is a lethal survival game built around immutable bodies, systemic
injury, equipment-driven progression, persistent hex exploration, and tactical
combat.

Its abstract mechanical language is anchored to twelve: Pillars use `1` to `12`,
while depletable conditions such as Blood and Stance use `0` to `12`. Physical
measurements retain meaningful units.

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

Status updated on **July 17, 2026**.

### Playable Today

Launch from `UI/MainMenu.tscn` into a persistent macro run:

1. Start a new world or continue from one of three save slots.
2. Explore seeded radius-12 local zones with fog of war, POIs, and
   purpose-driven NPC activity.
3. Fight persistent enemies in 1v1 lane combat when colliding on the macro map.
4. Manage inventory, equipment, firearm loading, SEARCH, and CAMP.
5. Save and reload with `F5` / `F9` or the main-menu and in-game slot UI.
6. Cross radius-12 local zones through directional rims and choose only
   graph-connected destinations in the eight-sector, four-arm Node Web. Hover
   the non-playable radius-13 route band to inspect the destination first.

Characters and their run-local worlds are disposable. Permanent Meta nodes,
completed Meta Events, gateway state, structural mutations, and arm-core
reconstruction persist for later characters through the separate Meta Progress
profile.

### Phase Status

- **Phase 1** is closed and verified. The persistent vertical slice — macro
  movement, combat, inventory, SEARCH/CAMP, and JSON persistence — remains the
  regression baseline.
- **Phase 2** combat HUD work (P2-01 through P2-04) is **complete**. The bottom
  command deck, grouped actions, weapon cards, visible AIMED SHOT targets, and
  `GunAnimationCatalog` feedback are live in `CombatLaneHUD`.
- Active Phase 2 follow-up work now targets content coverage, presentation
  polish, and deferred non-goals such as macro SNIPE. Shield-specific BLOCK
  rules are complete. See [Phase 2 Execution Plan](READMEs/phase_2_execution_plan.md).

### Core Systems

- Combat uses a twelve-slot lane, localized Limb Region damage, and
  encounter-local Stance. Ordinary Stance pressure cannot directly Fell a
  combatant; explicit takedowns and BREAK against an already-Stumbling target
  can. GET UP consumes the active turn and restores protected footing.
- Ballistic hits deal no Stance Damage. A successful shot applies the weapon's
  authored Flesh Damage directly to one Limb Region.
- Firearms enforce authored range, accuracy, ammunition, magazine or loading
  aid, capacity, and cycling rules. The current roster includes pistols,
  revolvers, rifles, and a distance-sensitive shotgun.
- The static Innawoods inventory set maps into **167** categorized item
  Resources. Supported equipped visuals drive layered Humanoid Tokens in the
  macro world and combat lane.
- Item definitions are shared Resources loaded once by `LootCatalog`; items do
  not require individual scripts or scene nodes.
- Macro local zones use seeded generation as a fallback, while
  `AuthoredWorldMap`, `WorldMapEditor`, and `AuthoredWorldMapBaker` provide a
  hand-painted preset pipeline for terrain, water, blockers, decorations, and
  runtime content sockets.
- The reusable `plains_zone_template.tscn` contains the complete 469-cell
  footprint, eight arrival sockets, eight exit sockets, and examples for fixed
  POIs, variable POIs, encounters, quest objects, water, and freeform props.
- Macro NPC projection is capped for readability and surfaces purpose signals
  through the world HUD.
- An integrated Audio Conductor handles synchronized music and categorized SFX.
- Core biological and system states live in explicit resource classes
  (`BodyState`, `HumanoidState`, `InventoryState`, `EntityRecord`,
  `HexRecord`).
- Automated smoke scripts cover the vertical slice, combat HUD, weapon data,
  inventory, save/load, macro interactions, and shield BLOCK rules.

### Known Gaps

- Macro **SNIPE** remains unimplemented; service-rifle scope data is metadata
  only.
- **EXECUTE** is gated off (`CombatRules.EXECUTE_ENABLED = false`).
- Shield BLOCK uses item-authored damage-type and Limb Region coverage with
  distinct ballistic and makeshift mitigation.
- Humanoid token art coverage remains incomplete for several rigs, face/eye
  equipment, and unsupported weapons.
- Gameplay remains 1v1; squad combat infrastructure is not player-facing.
- The authored-zone toolchain is complete, but campaign profiles still need a
  real library of hand-painted presets; unassigned random nodes retain the
  seeded procedural fallback.

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
- [Project glossary](READMEs/GLOSSARY.md)
- [System architecture](READMEs/SYSTEM_ARCHITECTURE.md)
- [Phase 1 execution plan](READMEs/phase_1_execution_plan.md)
- [Phase 2 execution plan](READMEs/phase_2_execution_plan.md)
- [Humanoid token pipeline](READMEs/HUMANOID_TOKEN_PIPELINE.md)
- [Changelog](READMEs/CHANGELOG.md)
