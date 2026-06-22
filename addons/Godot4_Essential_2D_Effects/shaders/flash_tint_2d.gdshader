shader_type canvas_item;

// Damage flash / pickup pulse / state highlight.
// Reliable one-pass tinting with optional automatic pulse.

uniform vec4 _FlashColor : source_color = vec4(1.0, 1.0, 1.0, 1.0); // Tint color and max influence
uniform float _FlashAmount : hint_range(0.0, 1.0, 0.01) = 0.0; // Manual blend amount
uniform bool _UseAdditive = false; // false = lerp tint, true = additive glow-like flash
uniform bool _AutoPulse = false; // Animate flash amount with sine wave
uniform float _PulseSpeed : hint_range(0.0, 20.0, 0.1) = 6.0; // Pulses/second-ish timing scalar
uniform float _PulseMin : hint_range(0.0, 1.0, 0.01) = 0.15; // Lower bound when auto pulse is enabled
uniform float _PulseMax : hint_range(0.0, 1.0, 0.01) = 1.0; // Upper bound when auto pulse is enabled

void fragment() {
	vec4 base_col = texture(TEXTURE, UV);

	float pulse = 1.0;
	if (_AutoPulse) {
		float wave = 0.5 + 0.5 * sin(TIME * _PulseSpeed);
		pulse = mix(_PulseMin, _PulseMax, wave);
	}

	float amount = clamp(_FlashAmount * pulse, 0.0, 1.0);
	float influence = amount * _FlashColor.a;

	vec3 out_rgb;
	if (_UseAdditive) {
		out_rgb = base_col.rgb + (_FlashColor.rgb * influence);
	} else {
		out_rgb = mix(base_col.rgb, _FlashColor.rgb, influence);
	}

	COLOR = vec4(out_rgb, base_col.a);
}
