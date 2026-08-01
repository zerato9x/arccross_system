extends Resource
class_name CombatPresentationCue

@export var phase_id: String = "settle"
@export var action_id: String = ""
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
@export var outcome_tag: String = "neutral"
@export var lunge_pixels: float = 0.0
@export var recoil_pixels: float = 0.0
@export var shake_amplitude: float = 0.0
@export var shake_frequency: float = 24.0
@export var hit_stop_seconds: float = 0.0
@export var camera_impulse_pixels: float = 0.0
@export var impact_scale: float = 0.0
@export var impact_rotation_degrees: float = 0.0
@export var moves_actor: bool = false
@export var target_end_sector: Vector2i = Vector2i(-1, -1)
@export var weapon_class: int = 0
@export var weapon_id: String = ""
@export var sequence_progress_start: float = 0.0
@export var sequence_progress_end: float = 1.0


func to_dict() -> Dictionary:
	return {
		"phase_id": phase_id,
		"action_id": action_id,
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
		"outcome_tag": outcome_tag,
		"hit_stop_seconds": hit_stop_seconds,
		"shake_amplitude": shake_amplitude,
		"moves_actor": moves_actor,
		"target_end_sector": target_end_sector,
		"weapon_class": weapon_class,
		"weapon_id": weapon_id,
		"sequence_progress_start": sequence_progress_start,
		"sequence_progress_end": sequence_progress_end,
	}
