# ARCCROSS Combat UI Specification

The combat UI presents CombatCore snapshots and emits player intent. It does not
calculate AP costs, legal actions, targets, reactions, or outcomes.

## Tactical Lane

- Render the twelve-slot lane as a receding monospace wireframe corridor.
- Keep player, enemy, terrain, and cover markers distinguishable by both glyph
  and color.
- Preserve exact lane positions even when perspective compresses distant slots.
- Show the active combatant, AP, Reserved AP, Stance, and immediate biological
  danger without covering the lane. Label the current Stance State instead of
  relying on the numeric value alone.
- Show every Limb Region's current and maximum Structural Integrity separately
  from systemic Blood Level. Mark active Trauma without treating Blood as total
  HP.
- Mark Recovery Guard while its temporary anti-knockdown floor is active.
- For the equipped ranged weapon, show current rounds, capacity, effective
  range, and whether CYCLE is required before another shot.

## Melee Lock

![Melee lock reference](mockups/melee_lock.png)

When hostile combatants share a lane slot, replace the corridor center with a
front-view lock overlay. Keep legal actions and AP visible. Restore the corridor
when the lock ends.

## Controls

- Anchor the combat command surface at the bottom of the screen.
- Display only owner-validated legal actions and their exact AP costs.
- Group legal actions into readable command types:
  - Firearm: SHOOT, AIMED SHOT, RELOAD, CYCLE.
  - Movement: GET UP, ADVANCE, RETREAT, BEGIN ESCAPE, CHARGE.
  - Melee: STRIKE, GRAPPLE, BREAK STANCE, PUSH, PULL, EXECUTE.
  - Field: TAKE COVER and GUARD.
  - Items: legal combat consumables.
  - Reaction: legal off-turn responses.
- Support both pointer input and visible keyboard shortcuts: `Q` / `E` for group
  cycling, `1-6` for actions in the active group, and `0` for GUARD or reaction
  decline.
- Request target limbs or Runtime Item Instance IDs only after an action requires
  them.
- Present AIMED SHOT limb selection as visible target choices. Right-click
  cycling may remain a fallback, but hidden limb roulette is not the main
  interaction unless the goal is to make the player file a complaint.
- Disable input while a command is awaiting authoritative resolution.

## Phase 2 Bottom Command Deck

Implemented June 29, 2026. The bottom command deck replaces the narrow flat
action list. It has three responsibilities:

- Current weapon card: weapon sprite, name, rounds, capacity, optimal and
  effective range, READY, EMPTY, RELOAD, and CYCLE state.
- Grouped action selector: tabs or slots for legal action groups, with only the
  selected group's actions expanded.
- Context strip: target limb choices, reaction prompts, feedback, or short
  explanation of why the current weapon state matters.

The weapon card uses ItemCore's `inventory_sprite_path` and
`unloaded_sprite_path` for stable static presentation. Ranged weapon actions
use `Asset/Guns_Animation/` through `GunAnimationCatalog` for shoot, reload,
empty, cycle, casing, shell, and muzzle-flash effects. `CombatLaneHUD`
consumes resolved presentation descriptors; it does not parse raw filenames.

Keyboard mapping: `Q` / `E` for group cycling, `1-6` for actions in the active
group, and `0` for GUARD or reaction decline.

## Combat Flow

- `PUSH` maps to backend `PUSH_STAY`: perform the leverage check, shove the
  target away, keep the initiator in place, break Melee Lock, and restore normal
  non-lock actions if AP and lane rules still allow them.
- `PULL` maps to backend `PULL_FOLLOW`: perform the leverage check, drag both
  combatants together, and preserve Melee Lock.
- `BREAK STANCE` is low-cost stance pressure. Ordinary stance damage floors at
  `1`; explicit takedowns such as `GRAPPLE` create Felled openings.
- `GUARD` is the visible form of pass/reserve: end the active turn and bank the
  remaining AP for eligible reactions.
- Deprecated backend values `PUSH_FOLLOW`, `PULL_STAY`, and `DISENGAGE` remain
  compatibility names only and must not appear in player-facing legal actions.

## Impact Feedback

- Flash the struck anatomical region and update its value immediately.
- Use brief camera or panel shake for meaningful impacts, not every log entry.
- Distinguish Flesh Damage, Stance Damage, collapse, and death visually.
- Do not present ballistic impact as Stance loss; firearm hits update the
  resolved Limb Region.
- Surface combat bleeding as turn-flow pressure: active bleeding wounds drain
  Blood during combat turns, emit visible log entries, update body panels, and
  can kill through existing vital failure.
- Grounded armed strikes against Felled targets should read as severe payoff:
  priority target region, no dodge, stronger weapon damage, and clear trauma
  feedback. Unarmed grounded strikes stay weaker.
- Keep the combat log readable after effects finish.

## Reaction Window

When CombatCore exposes a reaction:

```text
[!] REACTION WINDOW - INCOMING ATTACK [!]
[ DODGE (AP) ]  [ BLOCK (AP) ]  [ DECLINE ]
```

- Dim normal controls and pause turn advancement.
- Show only legal reactions with authoritative costs.
- Explain that reactions spend Guarded / Reserved AP.
- Close the overlay only after the selected response resolves.
- Never spend AP or infer reaction availability inside the UI.
