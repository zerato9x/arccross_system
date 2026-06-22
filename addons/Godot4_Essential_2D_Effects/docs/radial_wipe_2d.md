# Shader Doc — radial_wipe_2d.gdshader

## Purpose
Angular mask-based reveal/hide for cooldown indicators, radial transitions, loading rings, and spell seals.

## Setup
1. Assign to a `ShaderMaterial` on UI/gameplay sprite nodes.
2. Animate `_Progress` from `0` to `1` (or inverse with `_Invert`).
3. Set `_Center` for non-centered pivots and `_StartAngleDeg` for orientation.

## Parameters
- `_Progress` (0–1): Visible arc amount.
- `_Center` (Vector2): UV pivot point for radial sweep.
- `_StartAngleDeg` (-360 to 360): Sweep start angle.
- `_Clockwise` (bool): Clockwise/counter-clockwise direction.
- `_Invert` (bool): Invert visible region.
- `_EdgeFeather` (0–0.2): Angular edge softness.

## Recommended Defaults
- Cooldown pie: `_StartAngleDeg -90`, `_Clockwise true`, `_EdgeFeather 0.005–0.015`
- Soft magical reveal: `_EdgeFeather 0.02–0.05`

## Performance Notes
- One texture read + angular math (atan/fract/smoothstep).
- Fine for UI and moderate gameplay counts.
- For very low-end mobile UI, use minimal overlap and avoid excessive full-screen layers.

## Notes
- Best results on textures designed for radial masking (icons/rings/discs).
- If your artwork appears offset, adjust `_Center` to match texture content pivot.
