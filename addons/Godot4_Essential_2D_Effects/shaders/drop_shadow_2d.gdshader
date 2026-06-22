shader_type canvas_item;

// Soft drop shadow for Sprite2D / UI textures.
// Designed as a fast readability aid for characters, pickups, and UI icons.

uniform vec4 _ShadowColor : source_color = vec4(0.0, 0.0, 0.0, 0.65); // Final tint + base alpha
uniform vec2 _ShadowOffsetPx = vec2(3.0, 3.0); // Shadow offset in texture pixels (+x right, +y down)
uniform float _ShadowSoftnessPx : hint_range(0.0, 4.0, 0.1) = 1.0; // Blur radius in texture pixels
uniform float _ShadowOpacity : hint_range(0.0, 1.0, 0.01) = 1.0; // Global shadow intensity multiplier
uniform bool _ShadowOnly = false; // Debug/use-case mode: render only shadow contribution

void fragment() {
	vec4 base_col = texture(TEXTURE, UV);
	vec2 texel = TEXTURE_PIXEL_SIZE;

	// Sample alpha from shifted source silhouette to place shadow behind the sprite.
	vec2 shifted_uv = UV - (_ShadowOffsetPx * texel);
	float s = max(_ShadowSoftnessPx, 0.0);
	vec2 blur = texel * s;

	// 5-tap soft blur (center + cross). Stable and mobile-friendly.
	float a_center = texture(TEXTURE, shifted_uv).a;
	float a_l = texture(TEXTURE, shifted_uv + vec2(-blur.x, 0.0)).a;
	float a_r = texture(TEXTURE, shifted_uv + vec2( blur.x, 0.0)).a;
	float a_u = texture(TEXTURE, shifted_uv + vec2(0.0, -blur.y)).a;
	float a_d = texture(TEXTURE, shifted_uv + vec2(0.0,  blur.y)).a;
	float shadow_mask = (a_center + a_l + a_r + a_u + a_d) * 0.2;

	float shadow_alpha = shadow_mask * _ShadowColor.a * _ShadowOpacity;
	vec3 shadow_rgb = _ShadowColor.rgb;

	if (_ShadowOnly) {
		COLOR = vec4(shadow_rgb, shadow_alpha);
	} else {
		// Composite shadow behind sprite.
		vec3 out_rgb = mix(shadow_rgb, base_col.rgb, base_col.a);
		float out_a = max(base_col.a, shadow_alpha);

		COLOR = vec4(out_rgb, out_a);
	}
}
