# Shader Doc — dissolve_burn_2d.gdshader

## Purpose
Animated dissolve transition with a glowing burn edge for death effects, teleports, spawn/despawn, and damage states.

## Setup
1. Apply shader to sprite material.
2. Assign a grayscale noise texture to `_NoiseTex` (seamless recommended).
3. Animate `_Dissolve` from `0.0` to `1.0` over time (AnimationPlayer or Tween).

## Parameters
- `_NoiseTex` (Texture2D): Dissolve pattern source.
- `_Dissolve` (0–1): Main dissolve threshold.
- `_EdgeWidth` (~0.01–0.15): Thickness of burn edge band.
- `_EdgeColor` (Color): Edge glow color.
- `_NoiseScale` (0.1–10): Pattern tiling scale.
- `_NoiseScroll` (Vector2): Time-based UV drift.
- `_EmissionStrength` (0–4): Brightness multiplier for edge.

## Recommended Defaults
- Natural burn: orange edge + `_EmissionStrength 1.2`
- Sci-fi vanish: cyan/magenta edge + `_NoiseScroll (0.1, 0.0)`

## Notes
- Best results with sprites that have clean alpha silhouettes.
- Keep `_EdgeWidth` moderate to avoid overpowering base art.
- Godot 4.6 compatibility: dissolve thresholding now includes derivative-based anti-aliasing (`fwidth`) and repeat+linear noise sampling to reduce striping/fizz artifacts.
