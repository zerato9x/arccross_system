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
  - Movement: GET UP, ADVANCE, RETREAT, BEGIN ESCAPE, CHARGE, DISENGAGE.
  - Melee: STRIKE, GRAPPLE, BREAK, PUSH, PULL, EXECUTE.
  - Field: TAKE COVER and PASS / RESERVE.
  - Items: legal combat consumables.
  - Reaction: legal off-turn responses.
- Support both pointer input and visible keyboard shortcuts. Suggested Phase 2
  mapping is `Q` / `E` for group cycling, `1-6` for actions in the active
  group, and `0` for pass or decline.
- Request target limbs or Runtime Item Instance IDs only after an action requires
  them.
- Present AIMED SHOT limb selection as visible target choices. Right-click
  cycling may remain a fallback, but hidden limb roulette is not the main
  interaction unless the goal is to make the player file a complaint.
- Disable input while a command is awaiting authoritative resolution.

## Phase 2 Bottom Command Deck

The next combat HUD pass replaces the narrow flat action list with a bottom
command deck. The deck has three responsibilities:

- Current weapon card: weapon sprite, name, rounds, capacity, optimal and
  effective range, READY, EMPTY, RELOAD, and CYCLE state.
- Grouped action selector: tabs or slots for legal action groups, with only the
  selected group's actions expanded.
- Context strip: target limb choices, reaction prompts, feedback, or short
  explanation of why the current weapon state matters.

The weapon card should use ItemCore's `inventory_sprite_path` and
`unloaded_sprite_path` for stable static presentation. Ranged weapon actions may
use `Asset/Guns_Animation/` through a small catalog for shoot, reload, empty,
cycle, casing, shell, and muzzle-flash effects. File-name parsing does not
belong in `CombatLaneHUD`; the HUD consumes a resolved presentation descriptor.

The first implementation milestone is static: bottom deck, grouped actions,
weapon sprite, ammo, range, and state. The second milestone adds the animated
gun feedback layer.

## Impact Feedback

- Flash the struck anatomical region and update its value immediately.
- Use brief camera or panel shake for meaningful impacts, not every log entry.
- Distinguish Flesh Damage, Stance Damage, collapse, and death visually.
- Do not present ballistic impact as Stance loss; firearm hits update the
  resolved Limb Region.
- Keep the combat log readable after effects finish.

## Reaction Window

When CombatCore exposes a reaction:

```text
[!] REACTION WINDOW - INCOMING ATTACK [!]
[ DODGE (AP) ]  [ BLOCK (AP) ]  [ PASS ]
```

- Dim normal controls and pause turn advancement.
- Show only legal reactions with authoritative costs.
- Close the overlay only after the selected response resolves.
- Never spend AP or infer reaction availability inside the UI.
