shader_type canvas_item;

// Soft panel rim darkening for HUD chrome. Multiply over StyleBox panels.
uniform float edge_softness : hint_range(0.05, 0.6) = 0.28;
uniform float edge_strength : hint_range(0.0, 0.8) = 0.22;
uniform vec4 edge_color : source_color = vec4(0.02, 0.03, 0.02, 1.0);

void fragment() {
	vec2 centered = abs(UV - vec2(0.5)) * 2.0;
	float edge = max(centered.x, centered.y);
	float mask = smoothstep(1.0 - edge_softness, 1.0, edge);
	COLOR = vec4(edge_color.rgb, mask * edge_strength * edge_color.a);
}
