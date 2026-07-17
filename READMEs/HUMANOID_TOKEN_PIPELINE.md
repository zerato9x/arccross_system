# Humanoid Token Pipeline

This document owns the runtime asset contract for humanoid Entity Projections.
Macro-world tokens, combat-lane tokens, and the Innawoods Paper Doll derive
their appearance from authoritative equipped items instead of owning gameplay
state.

## Runtime Contract

Each layer is a transparent PNG sheet with:

- `1920x1024` dimensions.
- `15` animation columns.
- `8` direction rows.
- `128x128` cells.
- Identical body alignment and direction ordering across every layer.

The runtime animation contract is:

- `Idle`
- `Idle2`
- `Idle3`
- `Walk`
- `Run`
- `RunBackwards`
- `CrouchIdle`
- `CrouchRun`
- `Attack1`
- `Attack2`
- `Attack3`
- `Attack4`
- `StrafeLeft`
- `StrafeRight`
- `TakeDamage`
- `Taunt`
- `Die`

The moving-attack sheets `RunAttack`, `RunBackwardsAttack`,
`StrafeLeftAttack`, and `StrafeRightAttack` are source-only. Combat does not
permit simultaneous movement and attacks.

Animation semantics:

- Macro player: `Idle`; hostile NPC: `Idle2`; passive NPC: `Idle3`.
- Macro movement: `Walk`.
- Combat movement toward the opponent: `Run`; retreat: `RunBackwards`.
- Combat-ready idle: `Idle2`.
- Stance `0-6`, or two disabled legs: `CrouchIdle` and `CrouchRun`.
- Firearm movement recovery: `Run` or `RunBackwards`, then `Taunt`, then
  `Idle2`.
- `Attack1`: firearm shot.
- `Attack2`: Grapple, Break Stance, and other forceful special actions.
- `Attack3` and `Attack4`: alternating right and left melee swings.
- `StrafeLeft` and `StrafeRight`: Take Cover and Dodge presentation.
- `Taunt`: contextual interaction, firearm readying, reloading, cycling, and
  other miscellaneous actions.
- `Die` is terminal and freezes on its final frame.

`HumanoidVisualCatalog` maps item IDs to shared visual directories. Items that
use the same Innawoods equipped artwork must map to the same token directory.
Visual identity must not be inferred from unique item identity.

`HumanoidToken.tscn` owns twelve pooled `Sprite2D` layer nodes.
`HumanoidTokenView` activates only the nodes required by the current equipment,
loads only their active animation, and reuses the pool across equipment swaps.
`PaperDollModel.tscn` owns its static TextureRect layer stack for the
inventory portrait. `EntityProjectionAssets` caches token sheets, paper-doll
textures, and generated grip-mask textures so opening inventory or swapping
equipment does not recreate the same resources. The token renderer uses nearest
filtering and synchronizes one frame index across all active layers.

`Asset/Guns_Animation/` is not part of the humanoid token layer contract.
Combat HUD weapon feedback resolves those textures through
`CombatCore/DuelUI/GunAnimationCatalog.gd`, separate from token animation and
ItemCore inventory sprites.

## Current Coverage

The current pack supports:

- Base humanoid body.
- Inner and outer torso clothing.
- Four armor sets.
- Legwear, footwear, headwear, and backpacks.
- Generic shield presentation.
- Common pistols, revolver, rifles, shotgun, and selected melee weapons.

The current pack does not have dedicated token layers for:

- Vests and chest rigs.
- Eye, face, neck, or arm equipment.
- Greaves.
- Several improvised, polearm, unique, and special weapons.
- Every color variant represented by the Innawoods inventory artwork.

Unsupported items remain mechanically equipped but do not invent a misleading
visual substitute.

## Preparation For An Optimized Build

1. Move raw generator output outside `res://`, or place it under a source-only
   directory containing `.gdignore`.

   Godot imports every recognized asset under `res://` whether runtime code
   references it or not. The current source pack contains roughly 1,090 PNG
   sheets and occupies about 888 MB before imported cache expansion.

2. Produce a runtime export folder containing only the seventeen required
   animations for each supported layer.

   Keep the larger animation library as source material, not shipping content.

3. Normalize directory and file names before generating a manifest.

   Existing examples such as `servicerilfe`, `nake_64`, and
   `servicerifle(unused)` should not become permanent API names.

4. Supply a machine-readable visual manifest with these fields:

   - `visual_id`
   - `item_ids`
   - `layer_group`
   - `source_directory`
   - `supported_animations`
   - `color_or_variant`

5. Author missing layers in priority order:

   - Vests and chest rigs.
   - Face and eye equipment.
   - Arm and leg armor.
   - Unique player-facing weapons.
   - Remaining color variants.

6. Generate trimmed runtime atlases.

   The visible figure occupies only a fraction of each `128x128` cell. A build
   tool should calculate a common safe crop across the base, clothing, and
   longest weapon layers, then repack every animation with that shared crop.
   Do not crop layers independently or they will stop aligning.

7. Apply one import preset to generated runtime textures:

   - Nearest filtering.
   - No mipmaps for the current pixel-scale presentation.
   - Transparent alpha preserved.
   - Compression selected after checking pixel-edge quality in an exported
     build, not merely in the editor.

8. Benchmark representative scenes after generation:

   - Player plus the maximum proximity-loaded macro enemies.
   - Two fully equipped combatants in the lane.
   - Repeated equipment swaps.
   - Macro-to-combat and save/load transitions.

## Adding A Visual

1. Add the seventeen runtime sheets under one aligned layer directory.
2. Add or reuse its entry in
   `UI/Humanoid/HumanoidVisualCatalog.gd`.
3. Map every item sharing that Innawoods appearance to the same directory.
4. Run the headless editor import.
5. Run `PersistentPlayerSmoke.gd`, `MacroInteractionSmoke.gd`, and
   `RealtimeDuelSmoke.gd` and a live `RealtimeDuelHUD` projection probe.
