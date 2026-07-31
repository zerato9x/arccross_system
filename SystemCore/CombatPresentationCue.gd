extends Resource
class_name CombatPresentationCue

@export var phase_id: String = "settle"
@export var actor_id: String = ""
@export var target_actor_id: String = ""
@export var start_sector: Vector2i = Vector2i(-1, -1)
@export var end_sector: Vector2i = Vector2i(-1, -1)
@export var facing: String = ""
@export var duration_seconds: float = 0.0
@export var animation_id: String = "neutral"
@export var sfx_id: String = ""
@export var vfx_id: String = ""
@export var camera_cue_id: String = ""
@export var path: Array[Vector2i] = []


func to_dict() -> Dictionary:
	return {
		"phase_id": phase_id,
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"start_sector": start_sector,
		"end_sector": end_sector,
		"facing": facing,
		"duration_seconds": duration_seconds,
		"animation_id": animation_id,
		"sfx_id": sfx_id,
		"vfx_id": vfx_id,
		"camera_cue_id": camera_cue_id,
		"path": path.duplicate(),
	}
