# ARCCROSS Real-Time Duel UI Specification

The combat UI projects `RealtimeDuelRuntime` snapshots and emits `DuelIntent`.
It does not calculate AP, legality, hit timing, defense, targets, or outcomes.

## Always Visible

- Twelve-slot lane with player, enemy, terrain, cover, territory, and armed
  trap readability.
- Both combatants' Paper Dolls, seven-region wound/Trauma state, Blood, AP,
  effective regeneration per second, Stance, Kinetic Tier, current action,
  weapon readiness, ammunition, and cycling state.
- Aim progress, combo step, push-follow window, and short authoritative
  feedback only while relevant.
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
