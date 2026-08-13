# Official Tactical Combat

Status updated on **August 1, 2026**.

ARCCROSS has one production combat rules authority:
`CombatCore/Tactical/TacticalCombatScene.tscn`. It consumes the canonical
entity, anatomy, wound, inventory, ammunition, condition, malfunction, armor,
shield, and persistence records. The former real-time and legacy turn-based
duel runtimes are presentation and migration references, not selectable rules
engines.

## Production contract

- `GameDirector` always launches the tactical scene with `duel_12x1`.
- The production board is one row of twelve unique cells. Occupants block the
  only route, so actors cannot pass through one another.
- Melee engagement is adjacency, not shared-cell overlap.
- Encounters support one player against one hostile, plus one adjacent living
  hostile with the same non-empty macro `squad_id`.
- `skirmish_6x3` and `squad_7x5` use the same board, action, resolution, AI, and
  presentation contracts. They remain topology-lab profiles until their wider
  encounter and cover design is approved.
- Every turn uses a discrete 12 AP pool. The authored action catalog, typed
  previews, confirmation requirements, reaction windows, and transaction
  barriers remain authoritative.
- Macro shooting and terrain cover are macro-world interactions. Only durable
  entity state such as wounds, blood, ammunition, item condition, and inventory
  crosses the combat boundary.

## HUD and presentation contract

- Pointer selection is primary. The persistent player card, bottom-center
  command dock, and relationship-neutral entity card remain stable while
  selected-sector context and actions update locally.
- Keyboard mirrors the same action buttons through visible numbers and
  mnemonics; it does not maintain a second command model.
- Movement is previewed and commits on confirmation or a second click.
  Consequential actions retain authored confirmation.
- Player anatomy, wounds, and systemic bars remain visible in the persistent
  top-left status card. Observable non-player cards use qualitative body bands
  and redact exact hidden vitals, carried inventory, ammunition, and injury
  values according to relationship/knowledge projection.
- The pack is a Hands/Quick icon drawer attached to the command dock. The
  active authored weapon sprite, ammunition, condition, range, and readiness
  remain visible in `CombatItemCard` for the player/friendly exact view.
- `TacticalArenaView` instances the layered `HumanoidToken` renderer and plays
  the existing authored animation IDs. Rules state is committed transactionally
  while the visible snapshot waits for the short presentation sequence.

## Acceptance evidence

- Godot **4.7.1 Steam** completed a headless editor import after the topology,
  encounter, HUD, and presentation changes.
- `Tests/CombatDuelTopologySmoke.gd` covers the three profile dimensions,
  production 1v2 deployment, clutter-free duel sectors, and linear no-passing.
- `Tests/CombatArenaOverhaulSmoke.gd` keeps deterministic `7 x 5` generation and
  persistent terrain mutation covered as a laboratory profile.
- `Tests/TacticalCombatRulesSmoke.gd` covers AP transactions, movement, posture,
  shove geometry, melee reach, forecasts, and the current action catalog.
- `Tests/TacticalHUDLayoutSmoke.gd` covers the tactical HUD scene contract.

## Remaining work

1. Perform a live editor/runtime usability pass at supported resolutions; the
   current automated evidence proves parsing and focused behavior, not final
   visual taste.
2. Complete the squad_7x5 battlefield/topology presentation handoff after the
   encounter deployment and cover language are approved.
3. Add cinematic camera/impact overrides only for finishers, aimed attacks, and
   severe wounds; ordinary actions should remain snappy.
4. Expand beyond 1v2 only with explicit encounter grouping and readable
   deployment rules. The presence of larger topology resources is not approval
   to ship squad soup.

## Campaign dependency

The Central Core campaign implementation remains dependent on its categorized
asset library. Combat topology work must not invent substitute campaign art or
conflate macro cover mechanics with the concise duel simulation.
