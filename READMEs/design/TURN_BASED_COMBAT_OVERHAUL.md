# Official Tactical Combat

Status updated on **August 14, 2026**.

ARCCROSS has one production combat authority:
`CombatCore/Tactical/TacticalCombatScene.tscn`. `GameDirector` always hands it
an assembled `squad_7x5` encounter. `duel_12x1` and `skirmish_6x3` remain
loadable only for explicit Combat Lab and compatibility tests; they are not
player-selectable production modes.

## Encounter contract

- The production board is a seven-column, five-row orthogonal grid.
- An encounter contains one directly controlled player and up to five
  autonomous NPCs. The aware roster is assembled before entry, capped at six,
  and frozen for the encounter; late reinforcement is disabled.
- Relationships are pairwise authority. Faction and team labels do not invent
  hostility. NPC-versus-NPC conflict may continue after every player-hostile
  relationship ends.
- `LEAVE BATTLE` is neutral wording and becomes legal when no living actor is
  hostile to the player. It does not require all NPC conflicts to end.
- Same-sector hostile occupancy represents Engagement. Ordinary movement is
  orthogonal and cannot silently cross blocked or illegally occupied sectors.

## Turn and action contract

- Every turn grants one normal AP pool, capped at `12`. There is no reserved
  reaction AP, player reaction prompt, opportunity attack, or second defensive
  economy. The transaction layer may hold a pending action cost until commit;
  that is not a spendable reserve.
- The catalog owns action cost, context, legality metadata, targeting, effects,
  presentation, and AI metadata. Controllers and HUD code do not grow parallel
  action-ID policy tables.
- `strike` and `fire` are the canonical default weapon attacks. BLUNT/BLADE
  weapons derive `strike`; PISTOL/RIFLE/SHOTGUN weapons derive `fire`.
- `ItemData.specialized_action_ids` may add catalog-authored weapon attacks.
  The derived default is listed first, IDs are deterministic and unique, and
  an unknown specialized ID fails validation with the weapon and action named.
- Reload, cycle, and ready remain weapon-state actions. `cycle` clears a jam;
  there is no `clear_malfunction` alias and burst fire is not implemented.
- Retired production actions are `aimed_strike`, `aimed_fire`, `power_strike`,
  `stand`, `crouch`, `disengage`, `clear_malfunction`, `block`, `dodge`, and
  `opportunity_strike`.
- Shove, take cover, engage, escape, leave battle, incapacitate, execute,
  inventory, and communication actions remain catalog-owned where legal.

## Defense and displacement

Combat defense is composed only from persistent wounds, Stance, equipment,
geometry cover, weapon range, and observable conditions. There is no combat
posture, persistent facing, rear/flank modifier, attack arc, block, dodge, or
reaction window.

Cover belongs to the threatened edge of a sector. `take_cover` selects an
authored edge against a threat; resolution reads that geometry directly.
Presentation may orient sprites toward an action or target, but visual
direction is never saved as a combat rule.

If a shove moves an AI actor out of a hostile Engagement, the action outcome
queues exactly one AI-only replan after the shove presentation barrier drains.
It grants no action, spends no additional AP, changes no turn ownership, and
opens no player prompt.

## Resolution and persistence

- Forecast and resolution use the weapon-action family declared on the action
  definition, so future specialized attacks reuse generic melee or ranged
  resolution without hard-coded ID lists.
- Ballistic hits apply authored Flesh Damage to one Limb Region and do not
  automatically deal Stance Damage. Armor protection is filtered by damage
  type and covered body region.
- Wounds, blood, ammunition, item condition, inventory, and entity life state
  cross the combat boundary through neutral runtime records.
- `Incapacitate` removes a broken target from active occupancy while retaining a
  neutral handoff sector. `Strip` and `Execute` are allowed to resolve against
  that handoff projection; an executed actor moves into the sector body layer
  and its location persists through the combat result.
- Combat snapshots use a strict versioned schema. Historical snapshots carrying
  posture, facing, reserved AP, or another schema version are rejected with a
  clear error rather than partially hydrated.

## Presentation and audio

- The HUD projects snapshots and emits intent. Accepted actions retain a
  transaction/presentation barrier until the queued sequence completes.
- Cue-marker, body-animation, map-weapon-sheet, release-marker, and static-card
  pulse timing are independent. The active weapon card is static and only
  pulses briefly; it never plays a firearm source sheet.
- Ranged map presentation uses the authored firearm sheets. Melee map impacts
  animate the existing equipped-item sprite overlay.
- Every combat audio payload preserves encounter, action-event, action,
  attacker, victim, body-region, source-item, weapon, and result identity.
- Presentation impact audio is contact only. Creation of an actual `Wound` in
  `HumanoidBody` is the sole authority for `HumanInjured` and therefore the sole
  injury-vocal route.

## Verification contract

Headless/editor checks prove parsing, schema, deterministic rules, event
routing, projection, and layout math. Live Godot checks separately cover visual
composition, actual LMB/RMB propagation, pointer-relative menu placement,
source-sheet animation, and audible routing. A headless pass must never be
reported as physical-input or listening acceptance.
