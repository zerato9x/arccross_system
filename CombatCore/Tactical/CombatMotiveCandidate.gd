extends RefCounted
class_name CombatMotiveCandidate

var motive: String = ""
var subject_type: String = "self"
var subject_id: String = ""
var feasible: bool = false
var base_weight: float = 0.0
var state_modifiers: Dictionary = {}
var instruction_modifiers: Dictionary = {}
var subject_modifiers: Dictionary = {}
var inertia_modifier: float = 0.0
var score: float = -INF
var reason_tags: Array[String] = []


func to_dict() -> Dictionary:
	return {
		"motive": motive,
		"subject_type": subject_type,
		"subject_id": subject_id,
		"feasible": feasible,
		"base_weight": base_weight,
		"state_modifiers": state_modifiers.duplicate(true),
		"instruction_modifiers": instruction_modifiers.duplicate(true),
		"subject_modifiers": subject_modifiers.duplicate(true),
		"inertia_modifier": inertia_modifier,
		"score": score,
		"reason_tags": reason_tags.duplicate(),
	}
