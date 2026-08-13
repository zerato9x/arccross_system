extends Resource
class_name CombatPresentationCue

## Marker IDs are the only timing vocabulary understood by the presentation
## player.  They describe a committed action's authored beat, never a rule
## outcome.  Keeping this as data lets a profile retime an action without
## teaching the renderer a new special case.
const MARKERS := [
	"focus_in",
	"anticipation",
	"release_contact",
	"travel",
	"impact",
	"reaction",
	"recovery",
	"focus_out",
]

@export var phase_id: String = "settle"
@export var marker_id: String = ""
@export var pacing_tier: String = "maintenance"
@export var action_id: String = ""
@export var actor_id: String = ""
@export var target_actor_id: String = ""
@export var target_body_region: int = -1
@export var start_time_seconds: float = 0.0
@export var start_sector: Vector2i = Vector2i(-1, -1)
@export var end_sector: Vector2i = Vector2i(-1, -1)
@export var facing: String = ""
@export var duration_seconds: float = 0.0
@export var animation_id: String = "neutral"
@export var actor_animation_id: String = ""
@export var target_animation_id: String = ""
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
@export var weapon_action_id: String = ""
@export var weapon_release_sequence_progress: float = -1.0
@export var sequence_progress_start: float = 0.0
@export var sequence_progress_end: float = 1.0
@export var authored_animation_duration_seconds: float = 0.0
@export var dialogue_event: String = ""
@export var dialogue_id: String = ""
@export var dialogue_priority: int = 0
@export var presentation_flags: Dictionary = {}

func is_marker(value: String) -> bool:
	return marker_id == value or phase_id == value

func is_release_marker() -> bool:
	return is_marker("release_contact") or phase_id == "contact"

func is_travel_marker() -> bool:
	return is_marker("travel") or phase_id == "transit"


func to_dict() -> Dictionary:
	return {
		"phase_id": phase_id,
		"marker_id": marker_id if not marker_id.is_empty() else phase_id,
		"pacing_tier": pacing_tier,
		"action_id": action_id,
		"actor_id": actor_id,
		"target_actor_id": target_actor_id,
		"target_body_region": target_body_region,
		"start_time_seconds": start_time_seconds,
		"start_sector": start_sector,
		"end_sector": end_sector,
		"facing": facing,
		"duration_seconds": duration_seconds,
		"animation_id": animation_id,
		"actor_animation_id": actor_animation_id,
		"target_animation_id": target_animation_id,
		"sfx_id": sfx_id,
		"vfx_id": vfx_id,
		"camera_cue_id": camera_cue_id,
		"path": path.duplicate(),
		"outcome_tag": outcome_tag,
		"lunge_pixels": lunge_pixels,
		"recoil_pixels": recoil_pixels,
		"hit_stop_seconds": hit_stop_seconds,
		"shake_amplitude": shake_amplitude,
		"shake_frequency": shake_frequency,
		"camera_impulse_pixels": camera_impulse_pixels,
		"impact_scale": impact_scale,
		"impact_rotation_degrees": impact_rotation_degrees,
		"moves_actor": moves_actor,
		"target_end_sector": target_end_sector,
		"weapon_class": weapon_class,
		"weapon_id": weapon_id,
		"weapon_action_id": weapon_action_id,
		"weapon_release_sequence_progress": weapon_release_sequence_progress,
		"sequence_progress_start": sequence_progress_start,
		"sequence_progress_end": sequence_progress_end,
		"authored_animation_duration_seconds": authored_animation_duration_seconds,
		"dialogue_event": dialogue_event,
		"dialogue_id": dialogue_id,
		"dialogue_priority": dialogue_priority,
		"presentation_flags": presentation_flags.duplicate(true),
	}
