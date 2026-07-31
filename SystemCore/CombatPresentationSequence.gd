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
