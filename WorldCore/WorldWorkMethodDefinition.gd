@tool
extends Resource
class_name WorldWorkMethodDefinition

## Data-only modifier for a work method.  The resolver owns the algorithm;
## designers own the measurable trade-offs here.

@export var method_id: String = ""
@export var success_window_bonus: float = 0.0
@export var work_units_delta: int = 0
@export var noise_delta: float = 0.0
@export var tool_wear_delta: float = 0.0


func apply_to(profile: WorldWorkTaskProfile) -> void:
	if profile == null:
		return
	profile.base_success_window = clampf(
		profile.base_success_window + success_window_bonus,
		0.08,
		0.82
	)
	profile.work_units = maxi(1, profile.work_units + work_units_delta)
	profile.base_noise = maxf(0.0, profile.base_noise + noise_delta)
	profile.base_tool_wear = maxf(0.0, profile.base_tool_wear + tool_wear_delta)
