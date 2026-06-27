# Arccross HUD Core Asset Pack

This folder contains the first authored HUD asset pass for exploration, combat,
medical monitor, menus, and settings surfaces.

The pack is intentionally small, flat, and replaceable. It is meant to unblock
real UI assembly before final art direction, not to become sacred techno-noise
with no owner.

Phase 2 combat HUD work should use this pack for frames, bars, tabs, and
generic command icons. Ranged weapon cards should use ItemCore weapon sprites,
while short shoot, reload, empty, cycle, casing, shell, and muzzle-flash effects
should be resolved from `Asset/Guns_Animation/` through a catalog.

## Folders

- `frames/` - 9-slice panel and button state sprites.
- `bars/` - bar frames and fill strips for health, blood, AP, stance, warning,
  critical, and anomaly values.
- `icons/status/` - vitals and systemic condition icons.
- `icons/actions/` - exploration, inventory, menu, save/load, and interaction
  icons.
- `icons/combat/` - combat command and reaction icons.
- `medical/` - limb readout plates plus trauma/state badges.
- `menus/` - toggles, checkboxes, slider pieces, tabs, and dropdown arrow.
- `overlays/` - scanline tile and warning/critical/anomaly vignette overlays.

## Godot Usage

- Import these as 2D pixel UI textures with nearest filtering.
- Use `frames/panel_*_64.png` as `StyleBoxTexture` or `NinePatchRect` assets
  with 8 px patch margins.
- Use `frames/button_*_64x24.png` with 6 px left/right and 4 px top/bottom
  patch margins.
- Use `bars/bar_frame_*` behind a clipped `bar_fill_*` texture or a
  `TextureProgressBar`.
- Keep 32 px icons at integer scale factors.
- Layer `medical/state_*` and `medical/trauma_*` over `medical/limb_*` plates.

## Palette Roles

- Teal: normal systems, location, health, interaction.
- Amber: action points, warnings, reload/cycle, caution.
- Crimson: blood, trauma, break, critical danger.
- Magenta: anomaly, infection, Red Mist style exceptional states.
- Dim white: disabled, fatigue, pass, low-emphasis labels.

## Regeneration

Run the generator from the project root:

```powershell
& 'C:\Users\zerat\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' Tools\Build-HUDAssets.py
```

The preview sheet is `hud_asset_preview.png`.
