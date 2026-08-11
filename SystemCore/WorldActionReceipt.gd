extends RefCounted
class_name WorldActionReceipt

## Authoritative result of a committed action or work attempt.

var action_id: String = ""
var actor_id: String = ""
var target_id: String = ""
var verb_id: String = ""
var method_id: String = ""
var committed: bool = false
var interrupted: bool = false
var elapsed_minutes: int = 0
var exertion: float = 0.0
var noise_intensity: float = 0.0
## Wear is semantic receipt data, not a presentation-side guess. The owning
## inventory/object system may apply the mutation immediately, while UI and
## AI logs can still explain why a tool changed condition.
var tool_wear: float = 0.0
var work_progress: float = 0.0
var work_completed: bool = false
var mutations: Array[Dictionary] = []
var signals: Array[Dictionary] = []
var events: Array[Dictionary] = []
var presentation: Dictionary = {}
var message: String = ""

func add_signal(signal_record: WorldSignalRecord) -> void:
	signals.append(signal_record.to_dict())

func to_dict() -> Dictionary:
	return {
		"action_id": action_id,
		"actor_id": actor_id,
		"target_id": target_id,
		"verb_id": verb_id,
		"method_id": method_id,
		"committed": committed,
		"interrupted": interrupted,
		"elapsed_minutes": elapsed_minutes,
		"exertion": exertion,
		"noise_intensity": noise_intensity,
		"tool_wear": tool_wear,
		"work_progress": work_progress,
		"work_completed": work_completed,
		"mutations": mutations.duplicate(true),
		"signals": signals.duplicate(true),
		"events": events.duplicate(true),
		"presentation": presentation.duplicate(true),
		"message": message,
	}
