# Shader Doc — drop_shadow_2d.gdshader

## Purpose
Adds a soft, controllable drop shadow behind alpha sprites/UI textures to improve readability and depth.

## Setup
1. Assign to a `ShaderMaterial` on `Sprite2D`, `AnimatedSprite2D`, or `TextureRect`.
2. Ensure texture has enough transparent padding if using larger offsets/softness.
3. Tune `_ShadowOffsetPx` and `_ShadowSoftnessPx` for your art scale.

## Parameters
- `_ShadowColor` (Color): Shadow tint and base alpha.
- `_ShadowOffsetPx` (Vector2): Pixel offset direction and distance.
- `_ShadowSoftnessPx` (0–4): Soft blur radius (5-tap cross blur).
- `_ShadowOpacity` (0–1): Global shadow intensity multiplier.
- `_ShadowOnly` (bool): Renders only the shadow contribution.

## Recommended Defaults
- Pixel art readability: offset `(1, 1)`, softness `0.0–0.5`, opacity `0.5–0.7`
- HD UI icon: offset `(3, 3)`, softness `1.0–2.0`, opacity `0.45–0.65`

## Performance Notes
- Uses 5 texture reads per pixel (base + 5 alpha taps for shadow mask).
- Suitable for common gameplay/UI counts on desktop and mobile.
- Prefer moderate softness values for low-end mobile.

## Notes
- Large offsets can clip visually if source texture is tightly cropped.
- For only-silhouette shadows on dedicated layers, enable `_ShadowOnly`.
