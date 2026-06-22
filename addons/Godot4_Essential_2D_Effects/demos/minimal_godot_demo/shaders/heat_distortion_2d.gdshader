shader_type canvas_item;

// Hollow Pixel - Essential 2D Effects
// Heat haze / shockwave-like distortion using screen texture sampling.
// Intended for additive VFX sprites or distortion masks.

uniform sampler2D _NoiseTex : source_color, repeat_enable, filter_linear;
uniform sampler2D _ScreenTex : hint_screen_texture, filter_linear;
uniform float _Strength : hint_range(0.0, 0.1, 0.001) = 0.02;
uniform float _NoiseScale : hint_range(0.1, 12.0, 0.1) = 4.0;
uniform float _ScrollSpeed : hint_range(0.0, 4.0, 0.01) = 0.6;
uniform float _DirectionAngleDeg : hint_range(0.0, 360.0, 1.0) = 35.0;
uniform float _Opacity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float _MaskSoftness : hint_range(0.0, 1.0, 0.01) = 0.15;
uniform float _VisibilityBoost : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float _ShimmerStrength : hint_range(0.0, 0.5, 0.01) = 0.08;

void fragment() {
	vec4 sprite = texture(TEXTURE, UV);

	// Direction-controlled distortion: user sets which way it stretches.
	float a = radians(_DirectionAngleDeg);
	vec2 dir = vec2(cos(a), sin(a));

	// Animated noise for scrolling visual variation.
	vec2 n_uv = UV * _NoiseScale + vec2(TIME * _ScrollSpeed, TIME * _ScrollSpeed * 0.73);
	float n = texture(_NoiseTex, n_uv).r;
	float offset = (n * 2.0 - 1.0) * _Strength;

	// Use sprite alpha as distortion mask (good for flames, smoke shapes, etc).
	float mask = smoothstep(_MaskSoftness, 1.0, sprite.a);
	vec2 screen_uv = SCREEN_UV + dir * offset * mask;
	screen_uv = clamp(screen_uv, vec2(0.001), vec2(0.999));

	vec3 warped = texture(_ScreenTex, screen_uv).rgb;

	// Pure screen warp can look invisible on flat backgrounds.
	// Blend a subtle emissive contribution from the source sprite for readability.
	float shimmer = (n * 0.5 + 0.5) * _ShimmerStrength * mask;
	vec3 boosted = warped + sprite.rgb * (_VisibilityBoost * mask + shimmer);

	float alpha = mask * _Opacity;
	COLOR = vec4(boosted, alpha);
}
