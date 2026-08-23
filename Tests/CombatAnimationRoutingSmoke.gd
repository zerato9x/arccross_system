extends SceneTree

const ARENA_SCRIPT := preload("res://CombatCore/Tactical/TacticalArenaView.gd")
const TOKEN_SCENE := preload("res://UI/Humanoid/HumanoidToken.tscn")
const CATALOG := preload("res://CombatCore/Tactical/default_combat_action_catalog.tres")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_non_attack_actions_do_not_carry_weapon_tracks()
	_check_non_weapon_sequence_clears_stale_weapon_track()
	_check_miss_does_not_start_target_reaction()
	_check_hit_starts_target_reaction_once()
	_check_snapshot_reconcile_does_not_interrupt_one_shot()
	if _failures.is_empty():
		print("COMBAT_ANIMATION_ROUTING_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _check_non_attack_actions_do_not_carry_weapon_tracks() -> void:
	for action_id in ["move", "end_turn"]:
		var request := CombatActionRequest.new()
		request.actor_id = "player"
		request.action_id = action_id
		request.metadata = {
			"weapon_id": "revolver",
			"weapon_instance_id": "revolver_instance",
			"weapon_class": GameEnums.WeaponClass.PISTOL,
		}
		var quote := CombatActionQuote.new()
		quote.origin_sector = Vector2i(0, 0)
		quote.target_sector = Vector2i(1, 0)
		quote.path = [Vector2i(0, 0), Vector2i(1, 0)]
		var outcome := CombatActionOutcome.new()
		outcome.committed = true
		var definition := CATALOG.definition(action_id)
		var sequence := definition.presentation_profile.build_sequence(request, quote, outcome)
		if sequence.weapon_animation_duration_seconds > 0.0:
			_failures.append("%s retained an animated weapon duration." % action_id)
		for cue in sequence.cues:
			if cue.is_firearm_presentation() or cue.is_melee_presentation():
				_failures.append("%s emitted a weapon presentation cue at %s." % [action_id, cue.marker_id])
			if cue.weapon_class != GameEnums.WeaponClass.NONE or not cue.weapon_id.is_empty():
				_failures.append("%s copied equipped weapon identity into %s." % [action_id, cue.marker_id])


func _check_miss_does_not_start_target_reaction() -> void:
	var sequence := _build_fire_sequence("miss")
	for cue in sequence.cues:
		if cue.target_animation_id != "neutral":
			_failures.append("A miss started target animation at %s." % cue.marker_id)


func _check_non_weapon_sequence_clears_stale_weapon_track() -> void:
	var arena := ARENA_SCRIPT.new() as TacticalArenaView
	arena.size = Vector2(960.0, 540.0)
	root.add_child(arena)
	var player := TOKEN_SCENE.instantiate() as HumanoidTokenView
	arena.add_child(player)
	arena._actor_tokens = {"player": player}
	arena._ensure_token_overlays(player)
	var firearm_sequence := _build_fire_sequence("hit")
	arena.begin_sequence(firearm_sequence)
	var top_overlay := player.get_meta("combat_top_overlay", null) as CombatTokenOverlay
	if top_overlay == null or top_overlay.cue == null:
		_failures.append("Firearm sequence did not install its top overlay track.")
	var movement_request := CombatActionRequest.new()
	movement_request.actor_id = "player"
	movement_request.action_id = "move"
	var movement_quote := CombatActionQuote.new()
	movement_quote.origin_sector = Vector2i(0, 0)
	movement_quote.target_sector = Vector2i(1, 0)
	movement_quote.path = [Vector2i(0, 0), Vector2i(1, 0)]
	var movement_outcome := CombatActionOutcome.new()
	movement_outcome.committed = true
	var movement_sequence := CATALOG.definition("move").presentation_profile.build_sequence(
		movement_request,
		movement_quote,
		movement_outcome
	)
	arena.begin_sequence(movement_sequence)
	if top_overlay.cue != null:
		_failures.append("Non-weapon sequence inherited the prior firearm overlay track.")
	if bool(player.get("_suppress_equipment_layers")):
		_failures.append("Non-weapon sequence kept action equipment suppressed.")
	arena.queue_free()


func _check_hit_starts_target_reaction_once() -> void:
	var sequence := _build_fire_sequence("hit")
	var starts := 0
	for cue in sequence.cues:
		if cue.target_animation_id != "neutral":
			starts += 1
			if cue.marker_id != "impact" or cue.target_animation_id != "TakeDamage":
				_failures.append("Hit target reaction was scheduled on the wrong cue.")
	if starts != 1:
		_failures.append("Hit target reaction started %d times instead of once." % starts)


func _build_fire_sequence(result: String) -> CombatPresentationSequence:
	var request := CombatActionRequest.new()
	request.actor_id = "player"
	request.target_actor_id = "enemy"
	request.action_id = "fire"
	request.metadata = {
		"weapon_id": "revolver",
		"weapon_instance_id": "revolver_instance",
		"weapon_class": GameEnums.WeaponClass.PISTOL,
	}
	var quote := CombatActionQuote.new()
	quote.origin_sector = Vector2i(0, 0)
	quote.target_sector = Vector2i(4, 0)
	quote.range_cells = 4
	var outcome := CombatActionOutcome.new()
	outcome.committed = true
	outcome.presentation_events.append({
		"result": result,
		"victim_id": "enemy",
		"region": GameEnums.LimbRegion.UPPER_TORSO,
	})
	return CATALOG.definition("fire").presentation_profile.build_sequence(request, quote, outcome)


func _check_snapshot_reconcile_does_not_interrupt_one_shot() -> void:
	var arena := ARENA_SCRIPT.new() as TacticalArenaView
	arena.size = Vector2(960.0, 540.0)
	root.add_child(arena)
	var player := TOKEN_SCENE.instantiate() as HumanoidTokenView
	var enemy := TOKEN_SCENE.instantiate() as HumanoidTokenView
	arena.add_child(player)
	arena.add_child(enemy)
	arena._ensure_token_overlays(player)
	arena._ensure_token_overlays(enemy)
	arena._actor_tokens = {"player": player, "enemy": enemy}
	arena.snapshot = {
		"width": 2,
		"height": 1,
		"sectors": [
			{"coords": Vector2i(0, 0), "occupant_ids": ["player"]},
			{"coords": Vector2i(1, 0), "occupant_ids": ["enemy"]},
		],
	}
	arena.set_meta("actor_snapshot", [
		{"actor_id": "player", "team_id": "player", "items": []},
		{"actor_id": "enemy", "team_id": "enemy", "items": []},
	])
	enemy.play_one_shot("TakeDamage", "Idle")
	arena._sync_actor_tokens()
	if enemy.get_animation() != "TakeDamage":
		_failures.append("Snapshot reconciliation interrupted an active enemy reaction.")
	arena.queue_free()
