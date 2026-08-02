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
	var presentation_target := quote.target_sector
	if presentation_target.x < 0 or presentation_target.y < 0:
		presentation_target = quote.origin_sector
	var path := quote.path.duplicate()
	if not path.is_empty() and path.front() != quote.origin_sector:
		path.push_front(quote.origin_sector)
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
	var is_movement := request.action_id in ["move", "disengage"]
	var wind_animation := "neutral" if is_movement else actor_animation_id
	var transit_animation := actor_animation_id if is_movement else "neutral"
	var phases := [
		["wind_up", wind_up_seconds, wind_animation, "", ""],
		["transit", transit_duration, transit_animation, "", vfx_id],
		["contact", contact_seconds, "neutral", sfx_id, vfx_id],
		["reaction", reaction_seconds, target_animation_id, "", ""],
		["impact", impact_seconds, "neutral", "", vfx_id],
		["settle", settle_seconds, "neutral", "", ""],
	]
	var total_duration := 0.0
	for phase in phases:
		total_duration += maxf(0.0, float(phase[1]))
	var elapsed_duration := 0.0
	for phase in phases:
		if float(phase[1]) <= 0.0:
			continue
		var cue := CombatPresentationCue.new()
		cue.phase_id = str(phase[0])
		cue.action_id = request.action_id
		cue.actor_id = request.actor_id
		cue.target_actor_id = request.target_actor_id
		cue.start_sector = quote.origin_sector
		cue.end_sector = presentation_target
		cue.facing = quote.final_facing
		cue.duration_seconds = float(phase[1])
		cue.animation_id = str(phase[2])
		cue.sfx_id = str(phase[3])
		cue.vfx_id = str(phase[4])
		cue.camera_cue_id = camera_cue_id if cue.phase_id == "contact" else ""
		cue.path = path.duplicate()
		cue.outcome_tag = outcome_tag
		cue.moves_actor = is_movement
		cue.target_end_sector = target_end_sector
		cue.weapon_class = int(request.metadata.get("weapon_class", GameEnums.WeaponClass.NONE))
		cue.weapon_id = str(request.metadata.get("weapon_id", ""))
		cue.sequence_progress_start = elapsed_duration / maxf(0.001, total_duration)
		elapsed_duration += cue.duration_seconds
		cue.sequence_progress_end = elapsed_duration / maxf(0.001, total_duration)
		_apply_recipe(cue)
		sequence.cues.append(cue)
	return sequence


func _apply_recipe(cue: CombatPresentationCue) -> void:
	if effect_recipe == null:
		return
	cue.lunge_pixels = effect_recipe.lunge_pixels
	cue.recoil_pixels = effect_recipe.recoil_pixels
	cue.shake_amplitude = effect_recipe.shake_amplitude
	cue.shake_frequency = effect_recipe.shake_frequency
	cue.hit_stop_seconds = effect_recipe.hit_stop_seconds if cue.phase_id == "impact" else 0.0
	cue.camera_impulse_pixels = effect_recipe.camera_impulse_pixels
	cue.impact_scale = effect_recipe.impact_scale
	cue.impact_rotation_degrees = effect_recipe.impact_rotation_degrees


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


func _movement_segment_seconds(quote: CombatActionQuote, steps: int) -> float:
	if steps <= 0 or quote.movement_cost <= 0:
		return movement_seconds_per_sector
	var average_cost := float(quote.movement_cost) / float(steps)
	if average_cost <= 2.0:
		return 0.18
	if average_cost <= 3.0:
		return 0.245
	return 0.33 + maxf(0.0, average_cost - 4.0) * 0.05
