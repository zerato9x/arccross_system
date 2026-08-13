# ARCCROSS Combat UI Specification

Status updated on **August 13, 2026**.

The official production route is the tactical scene:
`CombatCore/Tactical/TacticalCombatScene.tscn` with
`CombatCore/Tactical/TacticalCombatHUD.tscn`. The HUD projects authoritative
snapshots and emits intent; it does not calculate AP, legality, hit timing,
defense, targets, or outcomes. The former lane wording below remains useful
for authored action timing, but is not a second runtime owner.

## Coherent tactical composition

- The player status card is persistent in the top-left. It uses the authored
  `PaperDollModel`, equipment layers, limb condition, Blood, Consciousness,
  relevant Pain/Shock warnings, weapon readiness/ammunition, and urgent wound
  selection.
- The bottom-center command dock owns the local turn loop: dominant AP with
  twelve exact pips, stance and posture, Kinetic Burden tier plus numeric value,
  CP with its own pip counter, current actor/initiative context, contextual
  actions, quote forecasts, confirmation, and End Turn.
- A selected non-player entity occupies the bottom-right relationship-neutral
  card. Player selection returns focus to the top-left card. A selected empty
  sector uses the top-right sector-context card; ground items remain sector
  context rather than global inventory.
- Hands/Quick inventory is an icon drawer attached to the command dock. Item
  selection retains the authoritative stable instance ID and follows the
  treatment flow: item icon, player limb, wound, quote, confirmation.
- The HUD consumes `CombatActorPresentationProjection` keyed by actor ID.
  Self and friendly views may retain exact authored state. Neutral/hostile
  views expose qualitative observable body condition, visible wound evidence,
  posture/stance bands, intent, relation, and weapon readiness without carried
  inventory, exact hidden condition, exact ammunition, or exact injury values.
- `CombatBodyTargetView` renders qualitative limb bands for observable actors;
  it never manufactures a gameplay result from those bands. AI traces and
  scoring remain non-UI diagnostics and are not rendered as tactical prose.
- `HudMotion` owns kill-safe 160–220 ms drawer/entity transitions, 280 ms meter
  easing, short resource flashes, and unresolved critical-state breathing.
  Snapshot refresh preserves selection and staged interaction state while the
  presentation barrier is active.

Supported layout evidence covers 1152x648, 1280x720, 1600x900, 1920x1080,
2560x1080, and 2560x1440. The production duel remains `duel_12x1`; `skirmish_6x3`
and `squad_7x5` are data-driven laboratory handoff profiles pending wider
encounter, topology, and battlefield presentation approval.

## Official turn-based interface

- `TacticalCombatHUD` projects `TacticalCombatSnapshotPresenter` output and
  emits typed turn intent through `TacticalCombatInteractionCoordinator`.
- The grouped command deck, reaction prompt, twelve-slot lane, Paper Dolls,
  wounds, Blood, Stance, AP, weapon readiness, ammunition, and combat log remain
  visible.
- An accepted action holds the turn transaction until its complete presentation
  queue drains.
- `TurnBasedCombatBalance` supplies action duration and cue fraction. Actor
  windup and weapon-card sheet playback use that profile; projectile or melee
  impact presentation begins at the cue.
- Firearm card playback must traverse the full source sheet over the authored
  duration. A static first frame pretending to be animation fails acceptance.
- Firearm atlas rows and columns use integer frame coordinates; fractional
  texture regions fail acceptance.
- Top status and weapon summaries use visible panel/card frames rather than
  unsupported text floating over the battlefield.
- At 1280-wide and narrower layouts, the combat log leaves the bottom command
  deck so two action columns remain unobstructed.
- Above the 1920x1080 reference, authored HUD content and spacing scale with the
  viewport up to `1.45x`; logical weapon-card coordinates must not be scaled
  twice.
- Combat colors, borders, labels, buttons, item cards, and condition bars use
  `HUDAssetLibrary` semantic roles. Mode-specific layout does not justify a
  second unrelated palette.
- Projectile, trail, and blood presentation nodes must be removed from both the
  scene and the active VFX registry when their animation completes.
- Stage readability is corrected locally at the battlefield texture. Global
  post-processing and briefing shades must not be used to compensate for a
  dark source plate.
- The macro world's CanvasLayers, including its vision vignette and interaction
  surfaces, are suspended for the complete combat lifetime and restored only
  after combat teardown. A hidden macro Node2D is not sufficient because
  CanvasLayer visibility and GUI interception are independent.

## Optional real-time interface

`RealtimeDuelHUD` projects `RealtimeDuelRuntime` snapshots and emits
`DuelIntent`.

## Always Visible

- The tactical arena remains the world-facing surface with player, enemy,
  terrain, cover, territory, and armed-trap readability.
- The player's Paper Doll, seven-region wound/Trauma state, Blood,
  Consciousness, AP, Stance, Kinetic Tier, current action, weapon readiness,
  ammunition, and cycling state remain available through the persistent status
  card and command dock.
- A selected non-player entity gets a relationship-neutral identity, intent,
  posture, stance/balance band, critical condition, weapon, and qualitative
  body/wound view. Exact systemic values are only shown where the projection's
  knowledge level authorizes them.
- Aim progress, forecast, confirmation, and short authoritative feedback only
  appear while relevant.
- During Melee Lock, an enemy action telegraph names the committed motion,
  counts down to its impact marker, and gives a terse reaction hint. Telegraphs
  expose the timeline; they do not reveal randomized hit outcomes.
- Limb trauma is always projected through the Paper Dolls plus a compact wound
  summary. The HUD does not hide the game's defining injury system just because
  a programmer discovered minimalism.

## Controls

| Input | Outside Melee Lock | In Melee Lock |
|---|---|---|
| `A` | Step away; hold repeats | No free disengage; may cancel early heavy |
| `D` | Step toward enemy | Push; during follow window, follow |
| Left mouse | Blind fire | Light strike |
| Hold right mouse | Build aimed-fire accuracy | Heavy strike on press |
| Left mouse while aiming | Fire current partial/full aim | — |
| `Space` | Timed guard | Timed block/parry |
| `R` | Cycle first, otherwise reload | Same when legal |

Actions remain fixed-price. Kinetic Burden and Stance affect regeneration only.
Movement stays discrete even though time is continuous.

## Timeline Contract

- Every accepted action emits one timeline ID with duration, impact marker,
  animation key, and contextual data.
- Damage, ammo use, lane occupancy, animation, camera, VFX, and audio use the
  same timeline. Presentation completion never decides whether gameplay hit.
- Light attacks commit immediately. Heavy and combo-finisher windups may cancel
  before their authored commit marker for a `1 AP` feint fee.
- Space opens one `1.1s` guard event. Impact at approximately `0.10-0.42s`
  after guard start parries; later overlap blocks. Ballistics require a
  covering shield and cannot be parried.
- Ordinary actions never pause the duel clock. A confirmed lethal finisher may
  halt simulation for its camera/death/result sequence.

## Camera and Feedback

- Stable wide profile for approach and stable close profile for Melee Lock.
  Enemy wind-up is communicated by animation and the duel timeline, not by
  repeatedly zooming the camera into every punch like a parody trailer.
- Flash or animate the actually resolved target; distinguish miss, cover,
  block, parry, Flesh damage, Stance damage, collapse, and death.
- Projectile trails end at impact/blood start. Result UI waits for the lethal
  presentation rather than ambushing the corpse halfway through its animation.
