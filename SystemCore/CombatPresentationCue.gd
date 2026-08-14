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
	"response",
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
@export var presentation_direction: String = ""
@export var duration_seconds: float = 0.0
@export var animation_id: String = "neutral"
@export var actor_animation_id: String = ""
@export var target_animation_id: String = ""
@export var sfx_id: String = ""
@export var vfx_id: String = ""
@export var camera_cue_id: String = ""
@export var path: Array[Vector2i] = []
@export var outcome_tag: String = "neutral"
@export var moves_actor: bool = false
@export var target_end_sector: Vector2i = Vector2i(-1, -1)
@export var weapon_class: int = 0
@export var weapon_id: String = ""
@export var weapon_action_id: String = ""
@export var encounter_id: String = ""
@export var action_event_id: String = ""
@export var source_item_instance_id: String = ""
@export var weapon_release_sequence_progress: float = -1.0
@export var sequence_progress_start: float = 0.0
@export var sequence_progress_end: float = 1.0
@export var authored_animation_duration_seconds: float = 0.0
@export var weapon_animation_duration_seconds: float = 0.0
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
		"presentation_direction": presentation_direction,
		"duration_seconds": duration_seconds,
		"animation_id": animation_id,
		"actor_animation_id": actor_animation_id,
		"target_animation_id": target_animation_id,
		"sfx_id": sfx_id,
		"vfx_id": vfx_id,
		"camera_cue_id": camera_cue_id,
		"path": path.duplicate(),
		"outcome_tag": outcome_tag,
		"moves_actor": moves_actor,
		"target_end_sector": target_end_sector,
		"weapon_class": weapon_class,
		"weapon_id": weapon_id,
		"weapon_action_id": weapon_action_id,
		"encounter_id": encounter_id,
		"action_event_id": action_event_id,
		"source_item_instance_id": source_item_instance_id,
		"weapon_release_sequence_progress": weapon_release_sequence_progress,
		"sequence_progress_start": sequence_progress_start,
		"sequence_progress_end": sequence_progress_end,
		"authored_animation_duration_seconds": authored_animation_duration_seconds,
		"weapon_animation_duration_seconds": weapon_animation_duration_seconds,
		"dialogue_event": dialogue_event,
		"dialogue_id": dialogue_id,
		"dialogue_priority": dialogue_priority,
		"presentation_flags": presentation_flags.duplicate(true),
	}
