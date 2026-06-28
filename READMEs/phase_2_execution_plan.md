# ARCCROSS Phase 2 Execution Plan

Phase 2 begins after the verified Phase 1 vertical slice. Phase 2 expands
presentation, combat readability, authored content, and player-facing systems
without weakening the existing ownership rule: presentation emits intent, while
domain cores validate and mutate authoritative state.

## Current Phase 2 Focus

Status recorded on **June 28, 2026**:

- Phase 1 remains closed and verified in
  [phase_1_execution_plan.md](phase_1_execution_plan.md).
- The active Phase 2 planning target is the new combat HUD.
- The combat HUD should move the action interface to the bottom of the screen,
  group legal actions by type, and make active weapon sprites and firearm state
  central to ranged play.
- The implementation should preserve the current `CombatLaneHUD` /
  `CombatLaneView` / `CombatCommandAdapter` boundary instead of resurrecting
  the old monolithic `CombatPanel` path.

## Phase 2 Workstreams

### P2-01: Combat HUD Command Deck

Goal: replace the narrow flat action list with a bottom-screen command deck.

Acceptance criteria:

- The action HUD is anchored at the bottom of the combat screen and no longer
  floats above the tactical lane.
- Legal actions remain owner-produced descriptors from `CombatCommandAdapter`.
- The HUD groups actions into firearm, movement, melee, field, item, and
  reaction command types.
- The selected group can be changed by pointer input and visible keyboard
  shortcuts.
- The lane remains readable while the command deck is open.
- `CombatLaneHUDSmoke.gd` verifies the bottom placement, grouped action data,
  and active firearm group.

### P2-02: Weapon-First Ranged HUD

Goal: make ranged weapon state the main decision surface during combat.

Acceptance criteria:

- The active weapon card shows a loaded or unloaded weapon sprite from
  ItemCore presentation paths.
- The weapon card shows weapon name, current rounds, capacity, optimal range,
  effective range, and READY, EMPTY, RELOAD, or CYCLE state.
- Firearm actions such as SHOOT, AIMED SHOT, RELOAD, and CYCLE appear in the
  firearm group when legal.
- AIMED SHOT exposes visible Limb Region choices instead of relying on hidden
  right-click cycling.
- The HUD does not infer legality from sprite state; CombatCore remains the
  authority.

### P2-03: Gun Animation Feedback

Goal: use `Asset/Guns_Animation/` for readable ranged weapon feedback after the
static weapon card works.

Acceptance criteria:

- A small catalog maps weapon IDs such as `service_pistol`, `carbon_pistol`,
  `revolver`, `ak47`, `carbon_rifle`, `service_rifle`, and `shotgun` to
  available shoot, reload, empty, cycle, casing, shell, and muzzle-flash
  textures.
- `CombatLaneHUD` receives resolved presentation descriptors instead of
  parsing raw filenames.
- SHOOT, RELOAD, and CYCLE can show short-lived weapon effects without changing
  CombatCore rules.
- Missing animation assets degrade to the static weapon card.

### P2-04: Combat HUD Regression Coverage

Goal: keep the UI redesign from breaking the working combat loop.

Acceptance criteria:

- `CombatLaneHUDSmoke.gd` covers bottom command deck layout, grouped actions,
  weapon card sprite loading, ammo/range/state text, and aimed-shot target
  choices.
- `CombatInterfaceSmoke.gd` still covers command execution, reactions, outcome
  resolution, loot spill, defeat, and escape paths.
- `WeaponDataSmoke.gd` remains the firearm rules source of truth.
- `git diff --check` is clean.

## Implementation Plan: New Combat HUD

1. Move action layout ownership inside `CombatLaneHUD.gd`.

   Rework `_calculate_duel_layout()` so `_action_rect` belongs to the bottom
   screen region. Replace the old narrow `ACTION_PANEL_SIZE` with a wide command
   deck sized from the viewport. Keep the tactical lane and Melee Lock visuals
   clear.

2. Enrich action descriptors in `CombatCommandAdapter.gd`.

   Add an action `group` field when actions are appended. Suggested group values
   are `firearm`, `movement`, `melee`, `field`, `items`, and `reaction`.
   Continue to build legal actions from current combat state only; the group is
   presentation metadata, not a rules shortcut.

3. Replace flat action rendering.

   Update `_render_actions()` so it builds group tabs or group slots first, then
   renders only the active group's buttons. Default to `firearm` when the player
     has legal ranged actions, `melee` while Melee Locked, and `movement`
     otherwise. Preserve `0` for GUARD or reaction decline.

4. Make target selection visible.

   Keep the existing target-limb payload route, but present AIMED SHOT Limb
   Region choices in the command deck. Right-click cycling may remain as a
   fallback. It should not be the only way to choose a limb, because secret UI
   controls are just bugs wearing sunglasses.

5. Add a weapon card component.

   Create a small `CombatWeaponPanel` component or an equivalent authored
   subtree under `CombatLaneHUD.tscn`. It should consume the player combatant
   snapshot and show active weapon sprite, name, rounds, capacity, optimal
   range, effective range, and readiness state.

6. Resolve weapon sprites from item data first.

   Use `inventory_sprite_path` and `unloaded_sprite_path` already stored on
   `ItemData`. Extend the combatant snapshot only if the HUD cannot reliably
   derive those paths from the existing equipment descriptors.

7. Add a gun animation catalog second.

   Create a presentation-only catalog for `Asset/Guns_Animation/` after the
   static weapon card is working. Map weapon IDs to named effects instead of
   string-searching filenames inside the HUD.

8. Validate with focused smokes.

   Update `CombatLaneHUDSmoke.gd` for layout and presentation contracts, keep
   `CombatInterfaceSmoke.gd` for command behavior, and run `git diff --check`.
   If standalone Godot smoke hits the known headless crash path, use the editor
   import/load check and live evaluation fallback.

## Current Non-Goals

- Rewriting combat legality.
- Reintroducing `CombatPanel`.
- Implementing macro SNIPE.
- Solving shield-specific BLOCK rules.
- Making every `Asset/Guns_Animation/` filename a permanent API.
- Replacing humanoid token animation with HUD gun effects.
