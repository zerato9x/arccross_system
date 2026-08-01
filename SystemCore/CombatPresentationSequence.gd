extends Resource
class_name CombatPresentationSequence

@export var action_id: String = ""
@export var cues: Array[CombatPresentationCue] = []


func to_dict() -> Dictionary:
	var result: Array[Dictionary] = []
	for cue in cues:
		if cue != null:
			result.append(cue.to_dict())
	return {"action_id": action_id, "cues": result}


func total_duration() -> float:
	var duration := 0.0
	for cue in cues:
		if cue != null:
			duration += maxf(0.0, cue.duration_seconds)
	return duration
