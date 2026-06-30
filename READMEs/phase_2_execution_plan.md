# ARCCROSS Phase 2 Execution Plan

Phase 2 begins after the verified Phase 1 vertical slice. Phase 2 expands
presentation, combat readability, authored content, and player-facing systems
without weakening the existing ownership rule: presentation emits intent, while
domain cores validate and mutate authoritative state.

## Current Phase 2 Focus

Status updated on **June 30, 2026**:

- Phase 1 remains closed and verified in
  [phase_1_execution_plan.md](phase_1_execution_plan.md).
- Combat HUD workstreams **P2-01 through P2-04 are complete**. See
  [June 29 changelog](CHANGELOG.md#june-29-2026).
- Remaining Phase 2 goals:
  - Expand humanoid token visual coverage per
    [HUMANOID_TOKEN_PIPELINE.md](HUMANOID_TOKEN_PIPELINE.md).
  - Replace generic BLOCK with shield-specific coverage and mitigation.
  - Polish macro and combat presentation using the HUD asset packs.
  - Expand authored content, loadouts, and loot profiles without breaking the
    owner-validated rule boundaries.

## Completed Workstreams

### P2-01: Combat HUD Command Deck — Verified June 29, 2026

- Bottom-screen command deck replaces the old narrow floating action list.
- Legal actions remain owner-produced descriptors from `CombatCommandAdapter`
  with `group` metadata.
- Groups: firearm, movement, melee, field, items, and reaction.
- Group selection supports pointer input and keyboard shortcuts.
- Verified by `CombatLaneHUDSmoke.gd`.

### P2-02: Weapon-First Ranged HUD — Verified June 29, 2026

- Active weapon card shows loaded/unloaded sprite from ItemCore presentation
  paths.
- Card shows name, rounds, capacity, optimal/effective range, and READY, EMPTY,
  RELOAD, or CYCLE state.
- Firearm actions appear in the firearm group when legal.
- AIMED SHOT exposes visible Limb Region choices in the command deck.
- Verified by `CombatLaneHUDSmoke.gd`.

### P2-03: Gun Animation Feedback — Verified June 29, 2026

- `CombatCore/DuelUI/GunAnimationCatalog.gd` maps weapon IDs to shoot, reload,
  empty, cycle, casing, shell, and muzzle-flash textures under
  `Asset/Guns_Animation/`.
- `CombatLaneHUD` consumes resolved presentation descriptors.
- SHOOT, RELOAD, and CYCLE show short-lived weapon effects without changing
  CombatCore rules.
- Missing animation assets degrade to the static weapon card.
- Verified by `CombatLaneHUDSmoke.gd`.

### P2-04: Combat HUD Regression Coverage — Verified June 29, 2026

- `CombatLaneHUDSmoke.gd` covers bottom deck layout, grouped actions, weapon
  card sprites, ammo/range/state text, and aimed-shot target choices.
- `CombatInterfaceSmoke.gd` still covers command execution, reactions, outcomes,
  loot spill, defeat, and escape paths.
- `WeaponDataSmoke.gd` remains the firearm rules source of truth.

## Remaining Phase 2 Workstreams

### P2-05: Token Visual Coverage

Goal: close the largest gaps in humanoid Entity Projection artwork.

Acceptance criteria:

- Add priority layers listed in
  [HUMANOID_TOKEN_PIPELINE.md](HUMANOID_TOKEN_PIPELINE.md): vests/chest rigs,
  face/eye equipment, arm/leg armor, and remaining player-facing weapons.
- Every new visual maps through `HumanoidVisualCatalog` and passes
  `PersistentPlayerSmoke.gd` and `CombatLaneHUDSmoke.gd`.

### P2-06: Shield-Specific BLOCK Rules

Goal: make ballistic shields mechanically distinct from generic BLOCK.

Acceptance criteria:

- Shield items such as `shield_ballistic` and `makeshift_shield` apply authored
  coverage and mitigation during BLOCK reactions.
- Rules remain in CombatCore; presentation only reflects owner-produced outcomes.
- Regression coverage extends `CombatInterfaceSmoke.gd` or a focused shield smoke.

### P2-07: Presentation Polish

Goal: align macro and combat HUDs with the authored asset packs.

Acceptance criteria:

- Wire remaining regions from `Asset/UI/HUD/` and
  `design/COMBAT_HUD_ASSET_MAP.md` where they improve readability.
- Preserve presentation boundaries: no gameplay legality in UI scripts.

## Implementation Record: Combat HUD (Completed)

The following plan shipped on **June 29, 2026**:

1. Moved action layout ownership inside `CombatLaneHUD.gd` with a bottom
   `_action_rect` command deck.
2. Enriched action descriptors in `CombatCommandAdapter.gd` with `group`
   metadata.
3. Replaced flat action rendering with group tabs and active-group buttons.
4. Made AIMED SHOT limb selection visible in the command deck.
5. Added weapon card presentation for sprite, ammo, range, and readiness.
6. Resolved static weapon sprites from ItemCore paths first.
7. Added `GunAnimationCatalog` for short-lived ranged weapon effects.
8. Validated with `CombatLaneHUDSmoke.gd`, `CombatInterfaceSmoke.gd`, and
   `WeaponDataSmoke.gd`.

## Current Non-Goals

- Rewriting combat legality.
- Reintroducing `CombatPanel`.
- Implementing macro SNIPE.
- Making every `Asset/Guns_Animation/` filename a permanent API.
- Replacing humanoid token animation with HUD gun effects.
- Squad combat beyond the current 1v1 slice.
