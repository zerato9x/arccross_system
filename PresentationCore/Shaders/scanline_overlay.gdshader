shader_type canvas_item;

// Subtle CRT scanline overlay for macro HUD. Keep strength low.
uniform float strength : hint_range(0.0, 0.5) = 0.12;
uniform float line_density : hint_range(40.0, 400.0) = 180.0;
uniform float scroll_speed : hint_range(0.0, 2.0) = 0.15;
uniform vec4 tint : source_color = vec4(0.05, 0.08, 0.06, 1.0);

void fragment() {
	float lines = sin((UV.y + TIME * scroll_speed) * line_density) * 0.5 + 0.5;
	float band = smoothstep(0.35, 0.85, lines);
	COLOR = vec4(tint.rgb, band * strength * tint.a);
}
