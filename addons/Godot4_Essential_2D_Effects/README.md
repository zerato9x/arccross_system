# Hollow Pixel — Godot 4 Essential 2D Effects

Drop-in **CanvasItem shaders** for high-demand 2D gameplay/UI effects in Godot 4.

## Compatibility
- Godot 4.2+
- Renderer: Forward+ / Mobile / GL Compatibility
- Target nodes: `Sprite2D`, `AnimatedSprite2D`, `TextureRect`, and other `CanvasItem`-derived nodes
- Godot 4.6 tested: Heat Distortion and Dissolve Burn include 4.6-safe sampling updates

## Included Shaders
1. `shaders/outline_2d.gdshader`
2. `shaders/dissolve_burn_2d.gdshader`
3. `shaders/heat_distortion_2d.gdshader`
4. `shaders/drop_shadow_2d.gdshader`
5. `shaders/flash_tint_2d.gdshader`
6. `shaders/radial_wipe_2d.gdshader`

## Quick Install
1. Copy this folder into your Godot project (e.g., `res://addons/hollow_pixel_effects/`).
2. Create a `ShaderMaterial` on a 2D node.
3. Load one shader from `shaders/`.
4. Tune uniforms using matching docs in `docs/`.

## Documentation
- `docs/outline_2d.md`
- `docs/dissolve_burn_2d.md`
- `docs/heat_distortion_2d.md`
- `docs/drop_shadow_2d.md`
- `docs/flash_tint_2d.md`
- `docs/radial_wipe_2d.md`

## Demo Project
A ready-to-run demo is included at `demos/minimal_godot_demo/`:
- Open the project in Godot 4.2+
- Press F5 to see all 6 shaders in action

## Known Limitations
- Outline and dissolve effects are alpha-dependent; tightly cropped opaque textures can reduce quality.
- Heat distortion relies on screen texture sampling; final look varies with render scale/post chain.
- Radial wipe assumes UV-friendly art layout; non-centered artwork may require `_Center` adjustment.
- Drop shadow may appear clipped if source art lacks transparent padding around silhouettes.

## License
Free for personal and commercial use. See `LICENSE` for details.
