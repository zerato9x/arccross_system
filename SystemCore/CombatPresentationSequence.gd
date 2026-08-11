extends Resource
class_name CombatPresentationSequence

@export var action_id: String = ""
@export var cues: Array[CombatPresentationCue] = []
@export var timeline_id: String = ""
@export var total_duration_seconds: float = 0.0
@export var release_marker_seconds: float = -1.0
@export var impact_marker_seconds: float = -1.0


func to_dict() -> Dictionary:
	var result: Array[Dictionary] = []
	for cue in cues:
		if cue != null:
			result.append(cue.to_dict())
	return {
		"action_id": action_id,
		"timeline_id": timeline_id,
		"total_duration_seconds": total_duration(),
		"release_marker_seconds": release_marker_seconds,
		"impact_marker_seconds": impact_marker_seconds,
		"cues": result,
	}


func total_duration() -> float:
	var duration := 0.0
	for cue in cues:
		if cue != null:
			duration = maxf(duration, cue.start_time_seconds + maxf(0.0, cue.duration_seconds))
	total_duration_seconds = duration
	return duration
