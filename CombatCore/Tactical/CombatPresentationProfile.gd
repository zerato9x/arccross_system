extends Resource
class_name CombatPresentationProfile

## Authored presentation only. No resolver or state mutation is permitted here.
## The profile owns the clock; the player only executes this data.

const WEAPON_PRESENTATION_CATALOG: CombatWeaponPresentationCatalog = preload(
	"res://CombatCore/Tactical/default_weapon_presentation_catalog.tres"
)

@export var profile_id: String = "neutral"
## Legacy fields remain serialized so existing authored profiles hydrate without
## migration noise. New profiles may use the explicit marker fields below.
@export var wind_up_seconds: float = 0.08
@export var transit_seconds: float = 0.12
@export var contact_seconds: float = 0.08
@export var response_seconds: float = 0.10
@export var impact_seconds: float = 0.10
@export var settle_seconds: float = 0.12
@export var focus_in_seconds: float = -1.0
@export var anticipation_seconds: float = -1.0
@export var release_contact_seconds: float = -1.0
@export var travel_marker_seconds: float = -1.0
@export var recovery_seconds: float = -1.0
@export var focus_out_seconds: float = -1.0
@export_enum("maintenance", "attack", "critical") var default_pacing_tier: String = "attack"
@export var maintenance_pacing_scale: float = 0.82
@export var attack_pacing_scale: float = 1.0
@export var critical_pacing_scale: float = 1.12
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
	sequence.pacing_tier = _resolve_pacing_tier(request, outcome)
	var pacing_scale := _pacing_scale(sequence.pacing_tier)
	var presentation_target := quote.target_sector
	if presentation_target.x < 0 or presentation_target.y < 0:
		presentation_target = quote.origin_sector
	var path := quote.path.duplicate()
	if not path.is_empty() and path.front() != quote.origin_sector:
		path.push_front(quote.origin_sector)
	var has_composite_movement := (
		request.action_id != "move"
		and quote.approach_path.size() > 1
	)
	var action_origin := quote.projected_origin if has_composite_movement else quote.origin_sector
	var travel_duration := _travel_duration(request, quote, pacing_scale)
	var weapon_duration := WEAPON_PRESENTATION_CATALOG.duration_for(
		str(request.metadata.get("weapon_id", "")),
		request.action_id
	)
	var weapon_definition := WEAPON_PRESENTATION_CATALOG.definition_for(str(request.metadata.get("weapon_id", "")))
	var weapon_release_progress := (
		weapon_definition.release_progress_for_action(request.action_id)
		if weapon_definition != null
		else -1.0
	)
	sequence.weapon_animation_duration_seconds = weapon_duration
	var outcome_tag := _outcome_tag(outcome)
	var target_end_sector := _target_end_sector(outcome, presentation_target)
	var resolved_target_region := _resolved_target_body_region(request, outcome)
	var presentation_direction := _direction_between(action_origin, presentation_target)
	var is_movement := request.action_id == "move"
	var actor_animation := "neutral" if is_movement else actor_animation_id
	var authored_animation_duration := _authored_animation_duration(actor_animation)
	sequence.authored_animation_duration_seconds = authored_animation_duration
	var durations := _marker_durations(travel_duration, pacing_scale, is_movement)
	var total_duration := _sum_durations(durations)
	if has_composite_movement:
		# The approach is a committed movement segment before the action beats.
		# It is still a normal travel marker, so the camera and transform code do
		# not need a second movement protocol.
		durations["travel"] = _movement_segment_seconds(quote, quote.approach_path.size() - 1) * float(quote.approach_path.size() - 1) * pacing_scale
		total_duration = _sum_durations(durations)
	if authored_animation_duration > 0.0 and not is_movement:
		# Preserve the authored body track as the minimum span for the actor's
		# anticipation/release/recovery beats. Projectile flight and response may
		# extend beyond it, but never compress it into a clipped one-shot.
		var actor_span: float = float(durations["focus_in"]) + float(durations["anticipation"]) + float(durations["release_contact"]) + float(durations["recovery"])
		if actor_span < authored_animation_duration * pacing_scale:
			durations["recovery"] += authored_animation_duration * pacing_scale - actor_span
			total_duration = _sum_durations(durations)
	if weapon_duration > total_duration:
		# The weapon sheet advances on its authored FPS clock. Recovery may hold
		# the action frame open long enough to see it finish, but marker timing is
		# never derived from frame count.
		durations["recovery"] += weapon_duration - total_duration
		total_duration = _sum_durations(durations)

	var elapsed := 0.0
	var previous_marker := ""
	for marker in CombatPresentationCue.MARKERS:
		var duration := maxf(0.0, float(durations.get(marker, 0.0)))
		if duration <= 0.0:
			continue
		var cue := CombatPresentationCue.new()
		cue.phase_id = _legacy_phase_for_marker(marker)
		cue.marker_id = marker
		cue.pacing_tier = sequence.pacing_tier
		cue.action_id = request.action_id
		cue.actor_id = request.actor_id
		cue.target_actor_id = request.target_actor_id
		cue.target_body_region = resolved_target_region
		cue.start_sector = action_origin
		cue.end_sector = presentation_target
		cue.presentation_direction = presentation_direction
		cue.duration_seconds = duration
		cue.authored_animation_duration_seconds = authored_animation_duration
		cue.weapon_animation_duration_seconds = weapon_duration
		cue.animation_id = actor_animation if marker == "focus_in" else _animation_for_marker(marker, actor_animation, is_movement)
		cue.actor_animation_id = actor_animation if marker == "focus_in" else "neutral"
		cue.target_animation_id = target_animation_id if marker == "impact" else "neutral"
		cue.sfx_id = sfx_id if marker == "release_contact" else ""
		cue.vfx_id = _vfx_for_marker(marker)
		cue.camera_cue_id = camera_cue_id if marker in ["focus_in", "release_contact", "impact", "focus_out"] else ""
		cue.path = path.duplicate()
		cue.outcome_tag = outcome_tag
		cue.moves_actor = is_movement and marker == "travel"
		cue.target_end_sector = target_end_sector
		cue.weapon_class = int(request.metadata.get("weapon_class", GameEnums.WeaponClass.NONE))
		cue.weapon_id = str(request.metadata.get("weapon_id", ""))
		cue.weapon_action_id = request.action_id
		cue.encounter_id = str(request.metadata.get("encounter_id", ""))
		cue.action_event_id = str(request.metadata.get("action_event_id", ""))
		cue.source_item_instance_id = str(request.metadata.get("weapon_instance_id", ""))
		cue.weapon_release_progress = weapon_release_progress
		cue.weapon_release_sequence_progress = _release_progress(durations, total_duration)
		cue.start_time_seconds = elapsed
		cue.sequence_progress_start = elapsed / maxf(0.001, total_duration)
		elapsed += duration
		cue.sequence_progress_end = elapsed / maxf(0.001, total_duration)
		cue.presentation_flags = {
			"previous_marker": previous_marker,
			"keep_camera_framing": marker in ["focus_in", "anticipation", "release_contact", "impact", "response"],
			"dialogue_allowed": marker in ["focus_in", "anticipation", "recovery"],
		}
		if marker == "focus_in":
			cue.presentation_flags["actor_animation_duration_seconds"] = authored_animation_duration
		if marker == "impact":
			cue.presentation_flags["target_animation_duration_seconds"] = _authored_animation_duration(target_animation_id)
		previous_marker = marker
		if marker == "release_contact":
			sequence.release_marker_seconds = cue.start_time_seconds + cue.duration_seconds
		if marker == "impact":
			sequence.impact_marker_seconds = cue.start_time_seconds
		if marker in ["focus_in", "recovery"] and not str(request.metadata.get("dialogue_event", "")).is_empty():
			cue.dialogue_event = str(request.metadata.get("dialogue_event", ""))
			cue.dialogue_id = str(request.metadata.get("dialogue_id", ""))
			cue.dialogue_priority = int(request.metadata.get("dialogue_priority", 0))
			sequence.dialogue_events.append({
				"marker": marker,
				"event": cue.dialogue_event,
				"dialogue_id": cue.dialogue_id,
				"priority": cue.dialogue_priority,
			})
		sequence.cues.append(cue)
	sequence.total_duration_seconds = total_duration
	return sequence


func _marker_durations(travel_duration: float, pacing_scale: float, is_movement: bool) -> Dictionary:
	var focus_in := focus_in_seconds if focus_in_seconds >= 0.0 else 0.06
	var anticipation := anticipation_seconds if anticipation_seconds >= 0.0 else wind_up_seconds
	var release := release_contact_seconds if release_contact_seconds >= 0.0 else contact_seconds
	var impact := impact_seconds
	var response := response_seconds
	var recovery := recovery_seconds if recovery_seconds >= 0.0 else settle_seconds * 0.65
	var focus_out := focus_out_seconds if focus_out_seconds >= 0.0 else settle_seconds * 0.35
	if is_movement:
		focus_in = minf(focus_in, 0.04)
		anticipation = 0.0
		release = minf(release, 0.04)
		impact = minf(impact, 0.04)
		response = minf(response, 0.04)
	return {
		"focus_in": focus_in * pacing_scale,
		"anticipation": anticipation * pacing_scale,
		"release_contact": release * pacing_scale,
		"travel": travel_duration,
		"impact": impact * pacing_scale,
		"response": response * pacing_scale,
		"recovery": recovery * pacing_scale,
		"focus_out": focus_out * pacing_scale,
	}


func _sum_durations(durations: Dictionary) -> float:
	var total := 0.0
	for value in durations.values():
		total += maxf(0.0, float(value))
	return total


func _animation_for_marker(marker: String, actor_animation: String, is_movement: bool) -> String:
	if marker == "travel" and is_movement:
		return "Walk"
	return "neutral"


func _direction_between(from_sector: Vector2i, to_sector: Vector2i) -> String:
	var delta := to_sector - from_sector
	if absi(delta.x) >= absi(delta.y):
		return "east" if delta.x >= 0 else "west"
	return "south" if delta.y >= 0 else "north"


func _legacy_phase_for_marker(marker: String) -> String:
	# Existing replay/debug consumers use the old phase vocabulary. Keep it as a
	# serialized alias while marker_id remains the canonical presentation API.
	return {
		"focus_in": "focus_in",
		"anticipation": "wind_up",
		"release_contact": "contact",
		"travel": "transit",
		"impact": "impact",
		"response": "response",
		"recovery": "settle",
		"focus_out": "focus_out",
	}.get(marker, marker)


func _vfx_for_marker(marker: String) -> String:
	if marker == "travel" and projectile:
		return "projectile"
	if marker in ["release_contact", "impact"]:
		return vfx_id
	return ""


func _release_progress(durations: Dictionary, total_duration: float) -> float:
	var release_end := float(durations.get("focus_in", 0.0)) + float(durations.get("anticipation", 0.0)) + float(durations.get("release_contact", 0.0))
	return release_end / maxf(0.001, total_duration) if projectile else -1.0


func _authored_animation_duration(animation_id: String) -> float:
	if animation_id.is_empty() or animation_id == "neutral" or not HumanoidVisualCatalog.supports_animation(animation_id):
		return 0.0
	return float(HumanoidVisualCatalog.animation_frames(animation_id)) / maxf(0.01, float(HumanoidVisualCatalog.animation_fps(animation_id)))


func _resolve_pacing_tier(request: CombatActionRequest, outcome: CombatActionOutcome) -> String:
	var authored := str(request.metadata.get("pacing_tier", ""))
	if authored in ["maintenance", "attack", "critical"]:
		return authored
	if request.action_id in ["move", "reload", "cycle", "end_turn"]:
		return "maintenance"
	if request.action_id in ["execute", "incapacitate"]:
		return "critical"
	if _outcome_tag(outcome) in ["critical", "wound", "collateral_hit"]:
		return "critical"
	return default_pacing_tier


func _pacing_scale(tier: String) -> float:
	match tier:
		"maintenance": return maxf(0.1, maintenance_pacing_scale)
		"critical": return maxf(0.1, critical_pacing_scale)
		_: return maxf(0.1, attack_pacing_scale)


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
		if result in ["hit", "collateral_hit", "miss", "cover", "cover_impact", "malfunction", "damage", "object_collision", "actor_collision", "boundary"]:
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


func _travel_duration(request: CombatActionRequest, quote: CombatActionQuote, pacing_scale: float) -> float:
	var duration := transit_seconds * pacing_scale
	if request.action_id == "move" and quote.path.size() > 1:
		var path_steps := quote.path.size() - 1
		if quote.path.front() != quote.origin_sector:
			path_steps += 1
		return movement_seconds_per_sector * float(path_steps)
	if projectile and quote.range_cells > 0 and effect_recipe != null:
		return maxf(0.08, float(quote.range_cells) / maxf(1.0, effect_recipe.projectile_speed_cells_per_second)) * pacing_scale
	return duration


func _movement_segment_seconds(quote: CombatActionQuote, steps: int) -> float:
	if steps <= 0 or quote.movement_cost <= 0:
		return movement_seconds_per_sector
	var average_cost := float(quote.movement_cost) / float(steps)
	if average_cost <= 2.0:
		return 0.28
	if average_cost <= 3.0:
		return 0.36
	return 0.46 + maxf(0.0, average_cost - 4.0) * 0.05
