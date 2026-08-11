@tool
extends Resource
class_name WorldWorkTaskProfile

## Data-driven manual work profile shared by player timing input and AI
## statistical resolution. One profile can serve locks, repairs, salvage, and
## medical work without inventing a new resolver for every prop.

@export var profile_id: String = ""
@export var work_units: int = 1
@export var cycle_seconds: float = 2.4
@export var cursor_speed: float = 1.0
@export_range(0.05, 0.95) var base_success_window: float = 0.28
@export var miss_resets_stage: bool = false
@export var severe_miss_threshold: int = 2
@export var base_noise: float = 1.0
@export var base_tool_wear: float = 0.02
@export var failure_payload: Dictionary = {}
@export var method_modifiers: Dictionary = {}

func normalized_units() -> int:
	return clampi(work_units, 1, 4)

func success_window(modifiers: Dictionary = {}) -> float:
	return clampf(
		base_success_window + float(modifiers.get("success_window_bonus", 0.0)),
		0.08,
		0.82
	)

func cycle_duration(modifiers: Dictionary = {}) -> float:
	return maxf(
		0.8,
		cycle_seconds * maxf(0.35, float(modifiers.get("cycle_scale", 1.0)))
	)

func to_dict() -> Dictionary:
	return {
		"profile_id": profile_id,
		"work_units": normalized_units(),
		"cycle_seconds": cycle_seconds,
		"cursor_speed": cursor_speed,
		"base_success_window": base_success_window,
		"miss_resets_stage": miss_resets_stage,
		"severe_miss_threshold": severe_miss_threshold,
		"base_noise": base_noise,
		"base_tool_wear": base_tool_wear,
		"failure_payload": failure_payload.duplicate(true),
		"method_modifiers": method_modifiers.duplicate(true),
	}
