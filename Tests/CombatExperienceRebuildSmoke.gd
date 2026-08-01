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
	if state.phase != CombatInteractionState.Phase.LOCAL_CONFIRMATION:
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
	elif not is_equal_approx(transit.duration_seconds, 0.54):
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
	elif impact.hit_stop_seconds < 0.05 or impact.shake_amplitude <= 0.0:
		failures.append("Collision recipe lacks readable hit-stop or shake.")

	var weapon_catalog: CombatWeaponPresentationCatalog = load(
		"res://CombatCore/Tactical/default_weapon_presentation_catalog.tres"
	)
	var revolver := weapon_catalog.definition_for("revolver")
	for weapon_id in ["service_pistol", "carbon_pistol", "revolver", "carbon_rifle", "ak47", "service_rifle", "shotgun"]:
		var weapon_definition := weapon_catalog.definition_for(weapon_id)
		if weapon_definition == null or weapon_definition.sheet_for_action("fire") == null or weapon_definition.sheet_for_action("reload") == null:
			failures.append("Missing recovered presentation sheets for %s." % weapon_id)
	if revolver == null or revolver.sheet_for_action("reload") == null:
		failures.append("Revolver presentation did not preserve the authored reload sheet.")
	elif revolver.duration_for_action("reload") < 2.0:
		failures.append("Revolver reload no longer honors its authored frame timing.")
	var reload_request := CombatActionRequest.new()
	reload_request.actor_id = "player"
	reload_request.action_id = "reload"
	reload_request.metadata = {"weapon_id": "revolver"}
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
	elif reload_sequence.cues.back().sequence_progress_end < 0.999:
		failures.append("Weapon sheet progress does not span the complete presentation.")

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
