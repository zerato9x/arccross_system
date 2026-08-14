extends SceneTree


func _init() -> void:
	var failures: Array[String] = []
	var catalog: CombatActionCatalog = load("res://CombatCore/Tactical/default_combat_action_catalog.tres")
	if catalog.definition("brace") != null:
		failures.append("Brace remains in the player action catalog.")
	for definition in catalog.all():
		if not definition.presentation_ready():
			failures.append("Visible action %s lacks description, selection context, or presentation." % definition.action_id)

	var state := CombatInteractionState.new()
	state.select("sector", {"sector": Vector2i(4, 0)})
	state.open_actions()
	state.stage("move", true)
	if state.phase != CombatInteractionState.Phase.CONFIRMATION:
		failures.append("Legal staged action did not enter local confirmation.")
	state.cancel_one_step()
	if state.phase != CombatInteractionState.Phase.ACTION_MENU:
		failures.append("Cancel did not return one interaction state.")

	var move_request := CombatActionRequest.new()
	move_request.actor_id = "player"
	move_request.action_id = "move"
	var move_quote := CombatActionQuote.new()
	move_quote.origin_sector = Vector2i(0, 0)
	move_quote.target_sector = Vector2i(3, 0)
	move_quote.path = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var move_outcome := CombatActionOutcome.new()
	move_outcome.committed = true
	var move_sequence := catalog.definition("move").presentation_profile.build_sequence(move_request, move_quote, move_outcome)
	var transit := _cue(move_sequence, "transit")
	if transit == null or transit.path.size() != 4:
		failures.append("Movement presentation did not preserve every traversed sector.")
	elif not is_equal_approx(transit.duration_seconds, 0.84):
		failures.append("Movement duration is not per-sector: %.3f." % transit.duration_seconds)
	if transit != null and not transit.moves_actor:
		failures.append("Movement transit was not marked as actor movement.")

	var shove_request := CombatActionRequest.new()
	shove_request.actor_id = "player"
	shove_request.target_actor_id = "enemy"
	shove_request.action_id = "shove"
	var shove_quote := CombatActionQuote.new()
	shove_quote.origin_sector = Vector2i(2, 0)
	shove_quote.target_sector = Vector2i(3, 0)
	var shove_outcome := CombatActionOutcome.new()
	shove_outcome.committed = true
	shove_outcome.actor_changes.append({"actor_id": "enemy", "shove": {"type": "object_collision", "destination": Vector2i(4, 0)}})
	var shove_sequence := catalog.definition("shove").presentation_profile.build_sequence(shove_request, shove_quote, shove_outcome)
	var impact := _cue(shove_sequence, "impact")
	if impact == null or impact.outcome_tag != "object_collision":
		failures.append("Shove presentation ignored its committed collision result.")

	var weapon_catalog: CombatWeaponPresentationCatalog = load(
		"res://CombatCore/Tactical/default_weapon_presentation_catalog.tres"
	)
	var revolver := weapon_catalog.definition_for("revolver")
	var authored_pivots: Array[Vector2] = []
	for weapon_id in ["service_pistol", "carbon_pistol", "revolver", "carbon_rifle", "ak47", "service_rifle", "shotgun"]:
		var weapon_definition := weapon_catalog.definition_for(weapon_id)
		if weapon_definition == null or weapon_definition.sheet_for_action("fire") == null or weapon_definition.sheet_for_action("reload") == null:
			failures.append("Missing recovered presentation sheets for %s." % weapon_id)
		elif weapon_definition.hand_anchor_for_action("reload") == Vector2.ZERO or weapon_definition.hand_anchor_for_action("cycle") == Vector2.ZERO:
			failures.append("Weapon %s still uses a zero reload/cycle hand pivot." % weapon_id)
		else:
			authored_pivots.append(weapon_definition.hand_anchor_for_action("fire"))
	if authored_pivots.size() > 1:
		var all_pivots_match := true
		for pivot in authored_pivots.slice(1):
			if pivot != authored_pivots[0]:
				all_pivots_match = false
				break
		if all_pivots_match:
			failures.append("Every firearm still shares one default hand pivot.")
	if revolver == null or revolver.sheet_for_action("reload") == null:
		failures.append("Revolver presentation did not preserve the authored reload sheet.")
	elif revolver.duration_for_action("reload") < 2.0:
		failures.append("Revolver reload no longer honors its authored frame timing.")
	var reload_request := CombatActionRequest.new()
	reload_request.actor_id = "player"
	reload_request.action_id = "reload"
	reload_request.metadata = {"weapon_id": "revolver", "weapon_class": GameEnums.WeaponClass.PISTOL}
	var reload_quote := CombatActionQuote.new()
	reload_quote.origin_sector = Vector2i(2, 0)
	reload_quote.target_sector = Vector2i(2, 0)
	var reload_outcome := CombatActionOutcome.new()
	reload_outcome.committed = true
	var reload_sequence := catalog.definition("reload").presentation_profile.build_sequence(
		reload_request,
		reload_quote,
		reload_outcome
	)
	if reload_sequence.total_duration() < 2.0:
		failures.append("Committed revolver reload is shorter than its authored animation.")
	elif not is_equal_approx(reload_sequence.weapon_animation_duration_seconds, revolver.duration_for_action("reload")):
		failures.append("Weapon source-sheet clock was conflated with marker time.")
	elif reload_sequence.cues.back().sequence_progress_end < 0.999:
		failures.append("Weapon sheet progress does not span the complete presentation.")

	var ranged_definition := catalog.definition("fire")
	if ranged_definition == null or ranged_definition.presentation_profile == null:
		failures.append("Ranged action lost its authored presentation profile.")
	else:
		var ranged_profile := ranged_definition.presentation_profile
		var ranged_request := CombatActionRequest.new()
		ranged_request.actor_id = "player"
		ranged_request.target_actor_id = "enemy"
		ranged_request.action_id = "fire"
		ranged_request.metadata = {
			"weapon_id": "service_pistol",
			"weapon_instance_id": "service_pistol_instance",
			"weapon_class": GameEnums.WeaponClass.PISTOL,
			"encounter_id": "clock_test",
			"action_event_id": "clock_test:1:fire",
		}
		var ranged_quote := CombatActionQuote.new()
		ranged_quote.origin_sector = Vector2i(0, 0)
		ranged_quote.target_sector = Vector2i(5, 0)
		ranged_quote.range_cells = 5
		var ranged_outcome := CombatActionOutcome.new()
		ranged_outcome.committed = true
		ranged_outcome.presentation_events.append({"result": "hit"})
		var ranged_sequence := ranged_profile.build_sequence(
			ranged_request,
			ranged_quote,
			ranged_outcome
		)
		var ranged_transit := _cue(ranged_sequence, "transit")
		var ranged_response := _cue(ranged_sequence, "response")
		var ranged_impact := _cue(ranged_sequence, "impact")
		if ranged_transit == null or ranged_transit.vfx_id != "projectile":
			failures.append("Ranged transit lost the projectile VFX cue.")
		if ranged_profile.effect_recipe == null or ranged_profile.effect_recipe.projectile_speed_cells_per_second > 10.0:
			failures.append("Ranged projectile speed is still tuned for a blink-and-miss-it hit.")
		if ranged_profile.wind_up_seconds < 0.28 or ranged_profile.response_seconds < 0.35:
			failures.append("Ranged actor/target animation windows are still too compressed.")
		if ranged_sequence.total_duration() < 1.20:
			failures.append("Ranged presentation remains too short for readable wind-up, flight, and impact.")
		if ranged_impact == null or ranged_impact.target_animation_id != "TakeDamage":
			failures.append("Ranged impact does not own the target damage one-shot.")
		if ranged_response == null or ranged_response.target_animation_id != "neutral":
			failures.append("Ranged response restarts the target damage one-shot instead of holding it.")
		if ranged_impact == null or ranged_impact.vfx_id != "projectile" or ranged_impact.outcome_tag != "hit":
			failures.append("Ranged impact cue does not carry the blood-capable hit result.")
		if ranged_definition.presentation_profile.actor_animation_id != "Attack1":
			failures.append("Fire does not use the firearm body animation.")
		if ranged_sequence.timeline_id.is_empty() or ranged_sequence.release_marker_seconds < 0.0 or ranged_sequence.impact_marker_seconds < 0.0:
			failures.append("Ranged presentation is missing its timeline identity or release/impact markers.")
		if ranged_sequence.release_marker_seconds >= ranged_sequence.impact_marker_seconds:
			failures.append("Fire release occurs after impact in the authored timeline.")
		if ranged_response == null or ranged_response.start_time_seconds <= ranged_impact.start_time_seconds:
			failures.append("Fire target response is not scheduled after impact.")
		var service_pistol_release_progress := weapon_catalog.definition_for("service_pistol").release_progress_for_action("fire")
		for cue in ranged_sequence.cues:
			if not is_equal_approx(cue.weapon_release_progress, service_pistol_release_progress):
				failures.append("Weapon release progress was serialized in the action-sequence clock instead of the weapon clock.")
				break
			if cue.presentation_direction != "east":
				failures.append("Ranged presentation did not derive a stable visual direction: %s." % cue.presentation_direction)
				break
			if cue.encounter_id != "clock_test" or cue.action_event_id != "clock_test:1:fire":
				failures.append("Presentation cue dropped encounter/action correlation identity.")
				break
		var actor_animation_starts := 0
		var target_animation_starts := 0
		for cue in ranged_sequence.cues:
			if cue.actor_animation_id != "neutral":
				actor_animation_starts += 1
			if cue.target_animation_id != "neutral":
				target_animation_starts += 1
		if actor_animation_starts != 1 or target_animation_starts != 1:
			failures.append("Ranged timeline does not start actor and target one-shots exactly once.")
		if _cue(ranged_sequence, "contact") == null or _cue(ranged_sequence, "contact").sfx_id != "weapon_fire":
			failures.append("Firearm release cue lost its weapon sound marker.")
		if ranged_sequence.total_duration_seconds < 1.20:
			failures.append("Sequence did not retain its typed total duration.")
		var marker_ids: Array[String] = []
		for cue in ranged_sequence.cues:
			marker_ids.append(cue.marker_id)
		if marker_ids != ["focus_in", "anticipation", "release_contact", "travel", "impact", "response", "recovery", "focus_out"]:
			failures.append("Ranged timeline did not emit the canonical synchronized marker channel.")

	for semantic_pair in [
		["strike", "Attack2"],
		["shove", "Attack3"],
	]:
		var semantic_definition := catalog.definition(str(semantic_pair[0]))
		if semantic_definition == null or semantic_definition.presentation_profile.actor_animation_id != str(semantic_pair[1]):
			failures.append("%s is mapped to the wrong semantic animation." % str(semantic_pair[0]))
	if HumanoidVisualCatalog.animation_frames("Attack1") != HumanoidVisualCatalog.FRAME_COLUMNS:
		failures.append("Attack1 body animation still uses the firearm sheet frame override.")
	if HumanoidVisualCatalog.animation_frames_for_layer("Attack1", "res://Asset/humanoid_spritesheets/weapons/guns/pistol") != 5:
		failures.append("Firearm equipment layer does not use its authored five-frame track.")

	if not ResourceLoader.exists("res://Asset/Guns_Animation/Bullet.png"):
		failures.append("Compact projectile sprite asset is missing.")
	if not ResourceLoader.exists("res://Asset/VFX/BLOOD VFX/1/1_000.png"):
		failures.append("Blood impact animation asset is missing.")
	if TacticalArenaView.PROJECTILE_TRAIL_LENGTH > 32.0:
		failures.append("Projectile trail regressed to an oversized legacy streak.")

	var visual_profile = load("res://CombatCore/Tactical/readable_moody_visual_profile.tres")
	if visual_profile == null:
		failures.append("Readable moody combat visual profile is missing.")
	else:
		if visual_profile.backdrop_modulate.get_luminance() < 0.70 or visual_profile.duel_surface_alpha < 0.30:
			failures.append("Combat visual profile regressed to an unreadably dark battlefield.")
		if visual_profile.grid_alpha < 0.30 or visual_profile.panel_opacity > 0.92:
			failures.append("Combat visual profile lost grid separation or battlefield context through opaque panels.")
	var arena_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/TacticalArenaView.gd")
	if arena_source.find("token.z_index = 10") < 0 or arena_source.find("top.z_index = 40") < 0:
		failures.append("Weapon overlay is no longer explicitly layered above the humanoid token.")
	if arena_source.find("_world_layer") < 0 or arena_source.find("draw_set_transform") < 0 or arena_source.find("_screen_to_world") < 0:
		failures.append("Arena camera does not expose one shared world transform with inverse input mapping.")
	if arena_source.find("scaled_size := base.size * _view_zoom") >= 0:
		failures.append("Arena grid geometry still bakes camera zoom into the logical world rect.")

	var same_sector_melee_request := CombatActionRequest.new()
	same_sector_melee_request.actor_id = "player"
	same_sector_melee_request.target_actor_id = "enemy"
	same_sector_melee_request.action_id = "strike"
	var same_sector_melee_quote := CombatActionQuote.new()
	same_sector_melee_quote.origin_sector = Vector2i(2, 0)
	same_sector_melee_quote.target_sector = Vector2i(2, 0)
	var same_sector_melee_outcome := CombatActionOutcome.new()
	same_sector_melee_outcome.committed = true
	var same_sector_melee_sequence := catalog.definition("strike").presentation_profile.build_sequence(
		same_sector_melee_request,
		same_sector_melee_quote,
		same_sector_melee_outcome
	)
	for cue in same_sector_melee_sequence.cues:
		if cue.presentation_direction != "east":
			failures.append("Same-sector melee did not use the stable presentation-only default direction.")
			break

	var presentation_player := TacticalPresentationPlayer.new()
	root.add_child(presentation_player)
	var completed_timelines: Array[String] = []
	presentation_player.timeline_finished.connect(func(timeline_id: String) -> void: completed_timelines.append(timeline_id))
	await presentation_player.play(move_sequence)
	await presentation_player.play(shove_sequence)
	if completed_timelines != [move_sequence.timeline_id, shove_sequence.timeline_id]:
		failures.append("Presentation acknowledgements did not preserve timeline identity and order.")

	if failures.is_empty():
		print("COMBAT_EXPERIENCE_REBUILD_SMOKE: PASS")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _cue(sequence: CombatPresentationSequence, phase_id: String) -> CombatPresentationCue:
	for cue in sequence.cues:
		if cue.phase_id == phase_id:
			return cue
	return null
