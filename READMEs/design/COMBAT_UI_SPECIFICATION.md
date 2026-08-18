# ARCCROSS Combat UI Specification

Status updated on **August 17, 2026**.

The production interface is
`CombatCore/Tactical/TacticalCombatHUD.tscn` inside
`CombatCore/Tactical/TacticalCombatScene.tscn`. It renders combat-owned
snapshots and emits typed intent through
`TacticalCombatInteractionCoordinator`; it does not calculate AP, legality,
defense, target outcomes, or AI decisions.

## Stable composition

- The `squad_7x5` arena is the primary world-facing surface. It must keep up to
  six actors, terrain, threatened cover edges, hazards, objects, projectiles,
  blood effects, and selected routes readable.
- The persistent top-left player card keeps Blood, Consciousness, AP, CP,
  Burden tier/value, Stance, intent, equipment, seven-region body state, urgent
  wounds, weapon readiness, and ammunition available without opening a modal.
- The bottom-center command dock owns local actions, exact AP/CP pips, quote
  forecast, confirmation, feedback, and the single visible End Turn control.
- A selected non-player uses the relationship-neutral entity card. A selected
  empty sector uses the sector card. Player selection returns focus to the
  persistent player card.
- The Hands/Quick drawer, observable target items, and ground-item rows render
  owner-projected icon paths while retaining stable item instance IDs.

## Knowledge and inspection

`CombatActorPresentationProjection` is keyed by actor ID. Self and authorized
friendly projections may expose exact body, wound, inventory, ammunition, and
condition state. Neutral and hostile projections expose only relationship,
coarse public intent, qualitative body/stance/burden bands, visible wound
evidence, and observable weapon readiness. They do not expose exact private
vitals, wound values, carried inventory, ammunition, or AI scoring traces.

`CombatBodyTargetView` visualizes the projection it receives. Its limb bands do
not create targeting rules or resolve outcomes. Ordinary attacks do not select
a body region; only a catalog action with an authored targeting interaction may
do so.

## Input and context menu

- Physical LMB inspects the actor or sector under the pointer and never opens an
  action menu by itself.
- Physical RMB performs the same inspection, then opens the root context menu.
  `TacticalArenaView` forwards the global pointer anchor with that intent.
- The menu opens next to the pointer, flips to its opposite side near the right
  edge, and clamps between the top status band and command dock. Keyboard and
  synthetic requests without a pointer retain the command-dock fallback.
- Visible number and mnemonic shortcuts activate the same action buttons. They
  are not a second command model.
- Cancellation moves back one interaction phase. Passive snapshot or quote
  refresh must preserve selection, menu state, and an in-progress staged action.
- Accepted actions lock input until their full queued presentation completes.

## Action and defense presentation

- Action rows come from `CombatActionCatalog` plus owner-generated legal quotes.
  The HUD does not reconstruct melee/ranged ID lists.
- There is no Reaction panel, posture chip, facing selector, Block, Dodge,
  Opportunity Strike, aimed default attack, or reserved-AP display.
- The forecast may describe wounds, Stance, equipment/armor, range, conditions,
  line of sight, and geometry cover. It must not imply hidden defense systems.
- `LEAVE BATTLE` remains neutral and appears only when the owner quote says the
  player has no living hostile relationship.

## Items and animation clocks

- `CombatItemCard` displays the active weapon's static authored sprite,
  ammunition, condition, range, and readiness. Action feedback is one explicit
  `0.18s` pulse; the card never consumes sequence or source-sheet duration.
- `TacticalArenaView` owns map animation. Ranged cues use the weapon
  presentation catalog's authored firearm sheets; melee cues animate the
  existing static equipped-item sprite.
- One action sequence carries separate marker time, authored body-animation
  duration, map-weapon animation duration, and release/impact marker times.
  None is silently derived from another clock.
- The marker vocabulary is `focus_in`, `anticipation`, `release_contact`,
  `travel`, `impact`, `response`, `recovery`, and `focus_out`. `response` is
  target presentation timing, not a gameplay reaction window.
- Projectile, trail, blood, and transient overlay nodes are removed from the
  scene and active registries when complete.

## Audio presentation

The release cue emits action audio. A resolved impact may emit contact audio.
Neither emits an injury vocal. `HumanoidBody` emits the one `HumanInjured` event
when it creates the wound. All combat-specific payloads retain encounter,
action-event, action, attacker, victim, body-region, source-item, weapon, and
result identity.

## Layout and acceptance

Automated layout coverage is required at `1152x648`, `1280x720`, `1600x900`,
`1920x1080`, `2560x1080`, and `2560x1440`, including pointer-anchor clamping at
all four viewport corners and pointerless fallback. Physical LMB/RMB, visual
legibility, map-weapon animation, and audible playback remain separate live
acceptance items.

Colors, borders, labels, controls, item rows, and meters use
`HUDAssetLibrary` semantic roles. Compact widths must preserve the command deck;
large widths may scale authored density up to the existing cap without scaling
logical weapon-sheet coordinates twice.
