shader_type canvas_item;

// Hollow Pixel - Essential 2D Effects
// Outline shader for alpha sprites.
// Supports inside and outside outlines.

uniform vec4 _OutlineColor : source_color = vec4(0.05, 0.95, 1.0, 1.0);
uniform float _OutlineThicknessPx : hint_range(0.0, 8.0, 0.1) = 1.5;
uniform bool _DrawInside = false;
uniform bool _KeepOriginalAlpha = true;

void fragment() {
	vec4 base_col = texture(TEXTURE, UV);
	vec2 texel = TEXTURE_PIXEL_SIZE * _OutlineThicknessPx;

	// Neighbor alpha samples (4-way for predictable cost).
	float a_l = texture(TEXTURE, UV + vec2(-texel.x, 0.0)).a;
	float a_r = texture(TEXTURE, UV + vec2(texel.x, 0.0)).a;
	float a_u = texture(TEXTURE, UV + vec2(0.0, -texel.y)).a;
	float a_d = texture(TEXTURE, UV + vec2(0.0, texel.y)).a;

	float neighbor_alpha = max(max(a_l, a_r), max(a_u, a_d));

	float outline_mask = 0.0;
	if (_DrawInside) {
		// Inside outline appears where current pixel exists and any neighbor drops out.
		outline_mask = base_col.a * (1.0 - min(min(a_l, a_r), min(a_u, a_d)));
	} else {
		// Outside outline appears where current pixel is transparent but neighbors exist.
		outline_mask = (1.0 - base_col.a) * step(0.001, neighbor_alpha);
	}

	vec4 out_col = base_col;
	out_col.rgb = mix(out_col.rgb, _OutlineColor.rgb, outline_mask * _OutlineColor.a);

	if (_KeepOriginalAlpha) {
		out_col.a = max(base_col.a, outline_mask * _OutlineColor.a);
	} else {
		out_col.a = mix(base_col.a, _OutlineColor.a, outline_mask);
	}

	COLOR = out_col;
}
