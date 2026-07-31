extends Resource
class_name CombatPresentationProfile

## Authored presentation only. No resolver or state mutation is permitted here.

@export var profile_id: String = "neutral"
@export var wind_up_seconds: float = 0.08
@export var transit_seconds: float = 0.12
@export var contact_seconds: float = 0.08
@export var reaction_seconds: float = 0.10
@export var impact_seconds: float = 0.10
@export var settle_seconds: float = 0.12
@export var actor_animation_id: String = "neutral"
@export var target_animation_id: String = "neutral"
@export var sfx_id: String = ""
@export var vfx_id: String = ""
@export var camera_cue_id: String = "frame_action"
@export var projectile: bool = false


func build_sequence(
	action_id: String,
	actor_id: String,
	target_actor_id: String,
	origin: Vector2i,
	target: Vector2i,
	facing: String,
	path: Array[Vector2i] = []
) -> CombatPresentationSequence:
	var sequence := CombatPresentationSequence.new()
	sequence.action_id = action_id
	var phases := [
		["wind_up", wind_up_seconds, actor_animation_id, sfx_id, ""],
		["transit", transit_seconds, actor_animation_id, "", vfx_id],
		["contact", contact_seconds, actor_animation_id, "", vfx_id],
		["reaction", reaction_seconds, target_animation_id, "", ""],
		["impact", impact_seconds, target_animation_id, "", vfx_id],
		["settle", settle_seconds, "neutral", "", ""],
	]
	for phase in phases:
		if float(phase[1]) <= 0.0:
			continue
		var cue := CombatPresentationCue.new()
		cue.phase_id = str(phase[0])
		cue.actor_id = actor_id
		cue.target_actor_id = target_actor_id
		cue.start_sector = origin
		cue.end_sector = target
		cue.facing = facing
		cue.duration_seconds = float(phase[1])
		cue.animation_id = str(phase[2])
		cue.sfx_id = str(phase[3])
		cue.vfx_id = str(phase[4])
		cue.camera_cue_id = camera_cue_id if cue.phase_id == "contact" else ""
		cue.path = path.duplicate()
		sequence.cues.append(cue)
	return sequence
