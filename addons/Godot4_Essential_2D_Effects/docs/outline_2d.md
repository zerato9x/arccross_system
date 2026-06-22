# Shader Doc — outline_2d.gdshader

## Purpose
Adds a configurable outline to alpha sprites. Can render outside the sprite silhouette or as an inner edge.

## Setup
1. Assign to a `ShaderMaterial` on Sprite2D (or equivalent CanvasItem node).
2. For outside outlines, ensure source texture has transparent padding around the sprite.

## Parameters
- `_OutlineColor` (Color): Outline tint and intensity.
- `_OutlineThicknessPx` (0–8): Thickness in texture-pixel units.
- `_DrawInside` (bool): `false` = outside outline, `true` = inside contour line.
- `_KeepOriginalAlpha` (bool): Preserve source alpha while adding outline alpha.

## Recommended Defaults
- Pixel art: `_OutlineThicknessPx = 1.0`
- HD sprites: `_OutlineThicknessPx = 1.5 to 2.5`
- UI highlight: cyan/white outline with alpha 0.8–1.0

## Notes
- Uses 4-direction neighbor sampling (fast and stable).
- If the texture is tightly cropped, outside outlines may clip at sprite bounds.
