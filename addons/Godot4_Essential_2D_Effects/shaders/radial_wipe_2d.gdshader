shader_type canvas_item;

// Angular reveal/hide for UI cooldowns, radial transitions, and magic seals.
// Uses UV-space polar angle against progress threshold.

uniform float _Progress : hint_range(0.0, 1.0, 0.001) = 1.0; // 0=hidden, 1=fully revealed (unless inverted)
uniform vec2 _Center = vec2(0.5, 0.5); // Pivot in UV space
uniform float _StartAngleDeg : hint_range(-360.0, 360.0, 1.0) = -90.0; // 0 is +X axis
uniform bool _Clockwise = true; // Sweep direction
uniform bool _Invert = false; // Invert visible/invisible region
uniform float _EdgeFeather : hint_range(0.0, 0.2, 0.001) = 0.01; // Soft boundary in angular 0..1 units

void fragment() {
	vec4 base_col = texture(TEXTURE, UV);

	vec2 p = UV - _Center;
	float angle = atan(p.y, p.x); // -PI..PI
	float angle01 = fract((angle / TAU) + 1.0);
	float start01 = fract(_StartAngleDeg / 360.0);

	float delta = _Clockwise ? fract(start01 - angle01) : fract(angle01 - start01);
	float progress = clamp(_Progress, 0.0, 1.0);
	float feather = max(_EdgeFeather, 0.00001);

	// 1 inside revealed arc, 0 outside, with feathered edge.
	float mask = 1.0 - smoothstep(progress - feather, progress + feather, delta);
	if (_Invert) {
		mask = 1.0 - mask;
	}

	COLOR = vec4(base_col.rgb, base_col.a * mask);
}
