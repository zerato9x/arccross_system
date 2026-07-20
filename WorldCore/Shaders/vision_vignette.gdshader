shader_type canvas_item;

// Soft screen-edge vignette + player-centered vision disk.
// Disk darkens smoothly outside vision radius — no world-space square slabs.
uniform float strength : hint_range(0.0, 1.0) = 0.42;
uniform float softness : hint_range(0.05, 1.0) = 0.52;
uniform float inner : hint_range(0.0, 1.0) = 0.18;
uniform float aspect_bias : hint_range(0.8, 1.6) = 1.18;
uniform float breathe : hint_range(0.0, 0.15) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.02, 0.025, 0.02, 1.0);

uniform vec2 viewport_size = vec2(1920.0, 1080.0);
uniform vec2 focus_px = vec2(960.0, 540.0);
uniform float vision_inner_px = 420.0;
uniform float vision_soft_px = 220.0;
uniform float vision_strength : hint_range(0.0, 1.0) = 0.58;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	centered.x *= aspect_bias;
	float edge_dist = length(centered) * 1.41421356;
	float corner = smoothstep(inner, inner + softness + breathe, edge_dist);

	vec2 px = UV * viewport_size;
	float focus_dist = distance(px, focus_px);
	float soft = max(vision_soft_px + breathe * 80.0, 1.0);
	float vision = smoothstep(vision_inner_px, vision_inner_px + soft, focus_dist);

	float a = max(corner * strength, vision * vision_strength);
	COLOR = vec4(vignette_color.rgb, clamp(a, 0.0, 1.0) * vignette_color.a);
}
