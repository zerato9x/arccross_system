# Shader Doc — flash_tint_2d.gdshader

## Purpose
Reliable color flash/tint for hit feedback, invulnerability blinking, pickup highlight pulses, and status emphasis.

## Setup
1. Apply to any CanvasItem texture node (`Sprite2D`, `TextureRect`, etc.).
2. Drive `_FlashAmount` directly from gameplay events, or enable `_AutoPulse`.
3. Use `_UseAdditive` for glow-like effects, regular mode for cleaner UI/gameplay readability.

## Parameters
- `_FlashColor` (Color): Tint color and max influence via alpha channel.
- `_FlashAmount` (0–1): Manual intensity control.
- `_UseAdditive` (bool): Additive blend-style output for glow flashes.
- `_AutoPulse` (bool): Enables time-based pulse.
- `_PulseSpeed` (0–20): Pulse animation speed.
- `_PulseMin` (0–1): Lower pulse bound.
- `_PulseMax` (0–1): Upper pulse bound.

## Recommended Defaults
- Damage flash: white/red, `_FlashAmount 0.7–1.0`, `_UseAdditive false`
- Power-up pulse: cyan/yellow, `_AutoPulse true`, `_PulseSpeed 4–8`
- UI attention ping: `_FlashAmount 0.25–0.45`, `_UseAdditive false`

## Performance Notes
- Very lightweight: one texture sample and basic ALU.
- Safe for broad UI usage and high object counts.

## Notes
- Keeps original alpha unchanged for predictable stacking.
- In additive mode, clamp/grade colors in art pipeline if overbright output is undesirable.
