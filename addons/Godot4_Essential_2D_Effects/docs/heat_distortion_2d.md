# Shader Doc — heat_distortion_2d.gdshader

## Purpose
Screen-space distortion for heat haze, energy fields, exhaust, shockwaves, and magical refraction effects.

## Setup
1. Apply shader to a sprite or VFX mask texture.
2. Assign a noise texture to `_NoiseTex`.
3. Use additive-style VFX art with soft alpha for smooth distortion falloff.

## Parameters
- `_NoiseTex` (Texture2D): Distortion normal-like source (RG channels used).
- `_ScreenTex` (screen texture): Auto-bound screen source in Godot.
- `_Strength` (0–0.1): Distortion magnitude in screen UV space.
- `_NoiseScale` (0.1–12): Detail scale of distortion pattern.
- `_ScrollSpeed` (0–4): Animation speed.
- `_Opacity` (0–1): Output alpha for compositing intensity.
- `_MaskSoftness` (0–1): Alpha threshold shaping for mask edge softness.

## Recommended Defaults
- Subtle heat shimmer: `_Strength 0.01 to 0.02`
- Strong blastwave: `_Strength 0.03 to 0.05` with brief lifetime

## Notes
- Distortion quality depends on final render scale.
- Avoid stacking many full-screen distortion sprites on low-end mobile hardware.
- Godot 4.6 compatibility: shader now uses explicit UV clamp for screen sampling and non-mipmapped screen texture filtering (`filter_linear`) to avoid black output regressions seen on some mobile/Vulkan paths.
- `_NoiseTex` is sampled with repeat + linear filtering so high `_NoiseScale` remains stable.
