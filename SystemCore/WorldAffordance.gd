extends RefCounted
class_name WorldAffordance

## A capability exposed by a target in the current actor/context state.

var verb_id: String = ""
var label: String = ""
var target_id: String = ""
var method_ids: Array[String] = []
var allowed: bool = true
var denial_reason: String = ""
var requirements: Dictionary = {}
var preview: Dictionary = {}
var task_profile_id: String = ""

func to_dict() -> Dictionary:
	return {
		"verb_id": verb_id,
		"label": label,
		"target_id": target_id,
		"method_ids": method_ids.duplicate(),
		"allowed": allowed,
		"denial_reason": denial_reason,
		"requirements": requirements.duplicate(true),
		"preview": preview.duplicate(true),
		"task_profile_id": task_profile_id,
	}
