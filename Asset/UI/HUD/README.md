# Arccross HUD Core Asset Pack

This folder contains the first authored HUD asset pass for exploration, combat,
medical monitor, menus, and settings surfaces.

The pack is intentionally small, flat, and replaceable. It is meant to unblock
real UI assembly before final art direction, not to become sacred techno-noise
with no owner.

Phase 2 combat HUD work shipped June 29, 2026. Ranged weapons use ItemCore
presentation sprites for static weapon cards and `GunAnimationCatalog` for
short-lived shoot, reload, empty, and cycle effects. This pack supplies frames,
bars, tabs, and generic command icons; weapon-specific art comes from ItemCore
and `Asset/Guns_Animation/`.

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

- Cyan/teal: world information, normal systems, health, interaction.
- Blue: travel, routes, navigation, and movement between world nodes.
- Green: discoveries, secured outcomes, recovery, and safe nodes.
- Amber: action points, warnings, reload/cycle, and caution.
- Crimson: blood, trauma, break, hostile events, and critical danger.
- Magenta: anomaly, infection, Red Mist, and impossible-state signals.
- Dim bone-white: disabled, fatigue, pass, metadata, and low-emphasis labels.

These roles are presentation contracts, not decoration. The World Signal Log
uses the same category names and colors that the node-map overhaul should use,
so route, discovery, danger, and anomaly information never changes meaning
between HUD surfaces.

## World Signal Log

`UI/HUD/Macro/MacroWorldStatusPanel.tscn` owns the bottom-right world feed.
It no longer uses the third-party pocket-clock frame, digit folders, or the
time-and-weather atlas. Time, phase, calendar, signal state, and categorized
log rows are native Control nodes styled through `HUDAssetLibrary`.

`icons/status/world_signal_128.png` is the original Arccross emblem generated
for this panel: a cyan hex compass/world node with restrained amber waypoints.
Keep it as the stable world/navigation mark; do not stretch it into panel
chrome or reuse it as a generic warning icon.

## Regeneration

Run the generator from the project root:

```powershell
& 'C:\Users\zerat\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' Tools\Build-HUDAssets.py
```

The preview sheet is `hud_asset_preview.png`.
