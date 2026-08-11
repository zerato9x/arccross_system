extends Resource
class_name CombatPresentationProfile

## Authored presentation only. No resolver or state mutation is permitted here.

const WEAPON_PRESENTATION_CATALOG: CombatWeaponPresentationCatalog = preload(
	"res://CombatCore/Tactical/default_weapon_presentation_catalog.tres"
)

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
@export var movement_seconds_per_sector: float = 0.18
@export var effect_recipe: CombatEffectRecipe


func build_sequence(
	request: CombatActionRequest,
	quote: CombatActionQuote,
	outcome: CombatActionOutcome
) -> CombatPresentationSequence:
	var sequence := CombatPresentationSequence.new()
	sequence.action_id = request.action_id
	sequence.timeline_id = "%s_%s_%s" % [request.actor_id, request.action_id, str(Time.get_ticks_usec())]
	var presentation_target := quote.target_sector
	if presentation_target.x < 0 or presentation_target.y < 0:
		presentation_target = quote.origin_sector
	var path := quote.path.duplicate()
	if not path.is_empty() and path.front() != quote.origin_sector:
		path.push_front(quote.origin_sector)
	var has_composite_movement := (
		request.action_id not in ["move", "disengage"]
		and quote.approach_path.size() > 1
	)
	var action_origin := quote.projected_origin if has_composite_movement else quote.origin_sector
	var transit_duration := transit_seconds
	if request.action_id in ["move", "disengage"] and path.size() > 1:
		transit_duration = _movement_segment_seconds(quote, path.size() - 1) * float(path.size() - 1)
	elif projectile and quote.range_cells > 0 and effect_recipe != null:
		transit_duration = maxf(
			0.08,
			float(quote.range_cells) / maxf(1.0, effect_recipe.projectile_speed_cells_per_second)
		)
	var weapon_duration := WEAPON_PRESENTATION_CATALOG.duration_for(
		str(request.metadata.get("weapon_id", "")),
		request.action_id
	)
	if weapon_duration > 0.0 and request.action_id in ["reload", "cycle", "clear_malfunction"]:
		var non_transit_duration := wind_up_seconds + contact_seconds + reaction_seconds + impact_seconds + settle_seconds
		transit_duration = maxf(transit_duration, weapon_duration - non_transit_duration)
	var outcome_tag := _outcome_tag(outcome)
	var target_end_sector := _target_end_sector(outcome, presentation_target)
	var resolved_target_region := _resolved_target_body_region(request, outcome)
	var is_movement := request.action_id in ["move", "disengage"]
	var wind_animation := "neutral" if is_movement else actor_animation_id
	var transit_animation := actor_animation_id if is_movement else "neutral"
	var phases: Array = []
	if projectile:
		# Fire is deliberately ordered: raise, muzzle/audio release, projectile,
		# impact, then the target's reaction settles into the result.
		phases = [
			["wind_up", wind_up_seconds, wind_animation, "", ""],
			["contact", contact_seconds, "neutral", sfx_id, ""],
			["transit", transit_duration, transit_animation, "", vfx_id],
			["impact", impact_seconds, "neutral", "", vfx_id],
			["reaction", reaction_seconds, target_animation_id, "", ""],
			["settle", settle_seconds, "neutral", "", ""],
		]
	else:
		phases = [
			["wind_up", wind_up_seconds, wind_animation, "", ""],
			["transit", transit_duration, transit_animation, "", vfx_id],
			["contact", contact_seconds, "neutral", sfx_id, vfx_id],
			["impact", impact_seconds, "neutral", "", vfx_id],
			["reaction", reaction_seconds, "neutral", "", ""],
			["settle", settle_seconds, "neutral", "", ""],
		]
	var movement_duration := 0.0
	if has_composite_movement:
		movement_duration = _movement_segment_seconds(quote, quote.approach_path.size() - 1) * float(quote.approach_path.size() - 1)
	var total_duration := movement_duration
	for phase in phases:
		total_duration += maxf(0.0, float(phase[1]))
	var elapsed_duration := 0.0
	if has_composite_movement:
		var movement_cue := CombatPresentationCue.new()
		movement_cue.phase_id = "transit"
		movement_cue.action_id = request.action_id
		movement_cue.actor_id = request.actor_id
		movement_cue.start_sector = quote.origin_sector
		movement_cue.end_sector = quote.projected_origin
		movement_cue.duration_seconds = movement_duration
		movement_cue.animation_id = "Walk"
		movement_cue.actor_animation_id = "Walk"
		movement_cue.path = quote.approach_path.duplicate()
		movement_cue.moves_actor = true
		movement_cue.weapon_class = int(request.metadata.get("weapon_class", GameEnums.WeaponClass.NONE))
		movement_cue.weapon_id = str(request.metadata.get("weapon_id", ""))
		movement_cue.weapon_action_id = request.action_id
		movement_cue.start_time_seconds = elapsed_duration
		movement_cue.sequence_progress_start = 0.0
		movement_cue.sequence_progress_end = movement_duration / maxf(0.001, total_duration)
		sequence.cues.append(movement_cue)
		elapsed_duration += movement_duration
	for phase in phases:
		if float(phase[1]) <= 0.0:
			continue
		var cue := CombatPresentationCue.new()
		cue.phase_id = str(phase[0])
		cue.action_id = request.action_id
		cue.actor_id = request.actor_id
		cue.target_actor_id = request.target_actor_id
		cue.target_body_region = resolved_target_region
		cue.start_sector = action_origin
		cue.end_sector = presentation_target
		# Facing is no longer a gameplay input. The arena derives a visual vector
		# from movement when one exists and otherwise keeps the token's authored
		# facing row; it cannot alter hit resolution or projectile geometry.
		cue.facing = ""
		cue.duration_seconds = float(phase[1])
		cue.animation_id = str(phase[2])
		cue.actor_animation_id = wind_animation if cue.phase_id == "wind_up" else "neutral"
		# Impact starts the target one-shot once. Reaction is a readable hold and
		# must never restart the same animation on the following cue.
		cue.target_animation_id = target_animation_id if cue.phase_id == "impact" else "neutral"
		cue.sfx_id = str(phase[3])
		cue.vfx_id = str(phase[4])
		cue.camera_cue_id = camera_cue_id if cue.phase_id == "contact" else ""
		cue.path = path.duplicate()
		cue.outcome_tag = outcome_tag
		cue.moves_actor = is_movement
		cue.target_end_sector = target_end_sector
		cue.weapon_class = int(request.metadata.get("weapon_class", GameEnums.WeaponClass.NONE))
		cue.weapon_id = str(request.metadata.get("weapon_id", ""))
		cue.weapon_action_id = request.action_id
		cue.weapon_release_sequence_progress = (wind_up_seconds + contact_seconds) / maxf(0.001, total_duration) if projectile else -1.0
		cue.start_time_seconds = elapsed_duration
		if cue.phase_id == "contact" and sequence.release_marker_seconds < 0.0:
			sequence.release_marker_seconds = elapsed_duration + cue.duration_seconds
		if cue.phase_id == "impact" and sequence.impact_marker_seconds < 0.0:
			sequence.impact_marker_seconds = elapsed_duration
		cue.sequence_progress_start = elapsed_duration / maxf(0.001, total_duration)
		elapsed_duration += cue.duration_seconds
		cue.sequence_progress_end = elapsed_duration / maxf(0.001, total_duration)
		_apply_recipe(cue)
		sequence.cues.append(cue)
	sequence.total_duration_seconds = total_duration
	return sequence


func _apply_recipe(cue: CombatPresentationCue) -> void:
	if effect_recipe == null:
		return
	# Combat motion stays grounded even when older effect resources contain the
	# exaggerated prototype values.
	cue.lunge_pixels = minf(8.0, effect_recipe.lunge_pixels)
	cue.recoil_pixels = minf(8.0, effect_recipe.recoil_pixels)
	cue.shake_amplitude = minf(1.5, effect_recipe.shake_amplitude)
	cue.shake_frequency = effect_recipe.shake_frequency
	cue.hit_stop_seconds = effect_recipe.hit_stop_seconds if cue.phase_id == "impact" else 0.0
	cue.camera_impulse_pixels = minf(1.0, effect_recipe.camera_impulse_pixels)
	cue.impact_scale = 0.0
	cue.impact_rotation_degrees = 0.0


func _outcome_tag(outcome: CombatActionOutcome) -> String:
	if outcome == null:
		return "neutral"
	for change in outcome.actor_changes:
		var shove: Dictionary = change.get("shove", {})
		if not shove.is_empty():
			return str(shove.get("type", "shove"))
	for event in outcome.presentation_events:
		var result := str(event.get("result", event.get("type", "")))
		if result == "damage":
			return "hit"
		if result in [
			"hit", "collateral_hit", "miss", "block", "shield_block", "dodge",
			"cover", "cover_impact", "malfunction", "damage", "object_collision",
			"actor_collision", "boundary"
		]:
			return result
	if not outcome.wound_events.is_empty():
		return "wound"
	if outcome.message.to_lower().contains("failed"):
		return "miss"
	return "neutral"


func _target_end_sector(outcome: CombatActionOutcome, fallback: Vector2i) -> Vector2i:
	if outcome == null:
		return fallback
	for change in outcome.actor_changes:
		var shove: Dictionary = change.get("shove", {})
		if shove.has("destination"):
			return shove.destination
	return fallback


func _resolved_target_body_region(request: CombatActionRequest, outcome: CombatActionOutcome) -> int:
	if request != null and request.target_body_region >= 0:
		return request.target_body_region
	if outcome != null:
		for event in outcome.presentation_events:
			if str(event.get("victim_id", "")) == str(request.target_actor_id) and event.has("region"):
				return int(event.get("region", -1))
		for event in outcome.wound_events:
			if str(event.get("actor_id", "")) == str(request.target_actor_id) and event.has("region"):
				return int(event.get("region", -1))
	return -1


func _movement_segment_seconds(quote: CombatActionQuote, steps: int) -> float:
	if steps <= 0 or quote.movement_cost <= 0:
		return movement_seconds_per_sector
	var average_cost := float(quote.movement_cost) / float(steps)
	if average_cost <= 2.0:
		return 0.28
	if average_cost <= 3.0:
		return 0.36
	return 0.46 + maxf(0.0, average_cost - 4.0) * 0.05
