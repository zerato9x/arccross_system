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

- Combat uses a twelve-slot lane, localized Limb Region damage, and
  encounter-local Stance.
- Ordinary Stance pressure cannot directly Fell a combatant. Explicit
  takedowns and BREAK against an already-Stumbling target can; GET UP then
  consumes the active turn and restores protected footing.
- Ballistic hits deal no Stance Damage. A successful shot applies the weapon's
  authored Flesh Damage directly to one Limb Region.
- Firearms enforce authored range, accuracy, ammunition, magazine or loading
  aid, capacity, and cycling rules. The current roster includes pistols,
  revolvers, rifles, and a distance-sensitive shotgun.
- The service-rifle scope carries compatibility and future macro-SNIPE
  metadata. The SNIPE world action is not implemented yet.
- The static Innawoods inventory set is mapped into a 163-definition Resource
  catalog. Paper Doll layers are authored as data, while Duel Scene animation
  remains intentionally excluded.
- Item definitions are shared Resources loaded once by `LootCatalog`; items do
  not require individual scripts or scene nodes.

## Item Authoring

Run `Tools/Build-StaticItemCatalog.ps1` after adding static Innawoods assets.
The default mode creates only missing definitions and preserves Inspector
edits. Use `-Rebuild` only when intentionally replacing the generated catalog.

## Documentation

- [Documentation index](READMEs/README.md)
- [Project glossary](READMEs/GLOSSARY.md)
- [System architecture](READMEs/SYSTEM_ARCHITECTURE.md)
- [Phase 1 execution plan](READMEs/PHASE_1_EXECUTION_PLAN.md)
- [Changelog](READMEs/CHANGELOG.md)
