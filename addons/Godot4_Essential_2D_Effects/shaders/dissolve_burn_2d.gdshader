shader_type canvas_item;

// Hollow Pixel - Essential 2D Effects
// Dissolve shader with emissive burn edge.

uniform sampler2D _NoiseTex : source_color, repeat_enable, filter_linear;
uniform float _Dissolve : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float _EdgeWidth : hint_range(0.001, 0.4, 0.001) = 0.08;
uniform vec4 _EdgeColor : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform float _NoiseScale : hint_range(0.1, 10.0, 0.1) = 2.0;
uniform vec2 _NoiseScroll = vec2(0.0, 0.0);
uniform float _EmissionStrength : hint_range(0.0, 4.0, 0.05) = 1.2;

void fragment() {
	vec4 base_col = texture(TEXTURE, UV);

	// Scrollable, tiling noise read for dissolve pattern.
	vec2 n_uv = UV * _NoiseScale + _NoiseScroll * TIME;
	vec3 n_col = texture(_NoiseTex, n_uv).rgb;
	float n = dot(n_col, vec3(0.33333334));

	// Small analytic AA around threshold reduces striping/fizz on modern renderers.
	float aa = max(fwidth(n), 0.0015);

	// Alive pixels survive where noise is above dissolve threshold.
	float survive = smoothstep(_Dissolve - aa, _Dissolve + aa, n);

	// Burn band appears around threshold crossing.
	float edge_lo = smoothstep(_Dissolve - _EdgeWidth - aa, _Dissolve - _EdgeWidth + aa, n);
	float edge_hi = 1.0 - smoothstep(_Dissolve - aa, _Dissolve + aa, n);
	float edge_band = edge_lo * edge_hi;

	// Keep burn band constrained to sprite alpha.
	edge_band *= base_col.a;

	vec3 rgb = base_col.rgb * survive;
	rgb += _EdgeColor.rgb * edge_band * _EdgeColor.a * _EmissionStrength;

	float out_alpha = base_col.a * survive;
	out_alpha = max(out_alpha, edge_band * _EdgeColor.a);

	COLOR = vec4(rgb, out_alpha);
}
