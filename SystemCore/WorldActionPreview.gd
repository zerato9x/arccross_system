extends RefCounted
class_name WorldActionPreview

## Read-only result shown before an action starts. Values are estimates when
## the actor lacks enough knowledge to know the exact target state.

var allowed: bool = false
var reason: String = ""
var elapsed_minutes: int = 0
var exertion: float = 0.0
var noise_intensity: float = 0.0
var light_intensity: float = 0.0
var tool_wear: float = 0.0
var risk: Dictionary = {}
var uncertainty: Dictionary = {}
var task_profile_id: String = ""
var reservation_key: String = ""

func to_dict() -> Dictionary:
	return {
		"allowed": allowed,
		"reason": reason,
		"elapsed_minutes": elapsed_minutes,
		"exertion": exertion,
		"noise_intensity": noise_intensity,
		"light_intensity": light_intensity,
		"tool_wear": tool_wear,
		"risk": risk.duplicate(true),
		"uncertainty": uncertainty.duplicate(true),
		"task_profile_id": task_profile_id,
		"reservation_key": reservation_key,
	}
