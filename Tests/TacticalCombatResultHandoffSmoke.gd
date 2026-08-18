extends SceneTree

const SCENE := preload("res://CombatCore/Tactical/TacticalCombatScene.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := SCENE.instantiate() as TacticalCombatScene
	root.add_child(scene)
	await process_frame

	var encounter := CombatEncounterRecord.new()
	encounter.encounter_id = "result_handoff_smoke"
	encounter.topology_id = "squad_7x5"
	encounter.initiator_id = "player"
	encounter.center_hex = HexRecord.new()
	encounter.world_seed = "RESULT_HANDOFF_SMOKE"
	var player_definition := preload("res://BiologicalCore/player_def.tres")
	var enemy_definition := preload("res://BiologicalCore/scavenger_def.tres")
	encounter.actors = [
		{
			"actor_id": "player",
			"team_id": "player",
			"runtime_record": {"entity_id": "player", "definition": player_definition.to_state(), "runtime": {}},
		},
		{
			"actor_id": "enemy",
			"team_id": "enemy",
			"runtime_record": {"entity_id": "enemy", "definition": enemy_definition.to_state(), "runtime": {}},
		},
	]
	scene.setup_encounter(encounter)
	if scene.player_core == null or scene.enemy_core == null:
		_failures.append("Full-scene result smoke did not deploy both actors.")
		return _finish()

	var results: Array[CombatResultRecord] = []
	scene.combat_finished.connect(func(result: CombatResultRecord) -> void: results.append(result))
	var player_sector_index := scene.board.position_of(scene.player_core)
	var neighboring_indices := scene.board.neighboring_indices(player_sector_index)
	if neighboring_indices.is_empty():
		_failures.append("Full-scene result smoke could not find an adjacent tactical sector.")
		return _finish()
	scene.board.force_spawn_actor(scene.enemy_core, neighboring_indices[0], "enemy", true)
	var expected_sector_index := scene.board.position_of(scene.enemy_core)
	scene.board.set_relation(scene.player_core, scene.enemy_core, CombatRelationshipLedger.Relation.HOSTILE)
	var state := scene.board.combat_state(scene.enemy_core)
	state.broken = true
	state.incapacitated = false
	scene.enemy_core.set_meta("combat_actor_state", state)
	var incapacitated := scene.board.mark_incapacitated(scene.enemy_core, "result_handoff_smoke")
	if int(incapacitated.get("sector_index", -1)) != expected_sector_index:
		_failures.append("Full-scene result smoke changed the handoff sector during incapacitation.")
	scene.turn_manager.remove_combatant(scene.enemy_core)
	scene.turn_manager.active_actor_index = 0
	scene.turn_manager.current_ap_pool = 12

	var request := CombatActionRequest.new()
	request.actor_id = "player"
	request.action_id = "execute"
	request.target_actor_id = "enemy"
	var quote := scene.action_controller.quote(request)
	if not quote.legal:
		_failures.append("Full-scene execution was not quoted as legal: %s" % quote.denial_code)
		return _finish()
	var outcome := await scene.action_controller.request_action(request)
	if outcome == null or not outcome.committed:
		_failures.append("Full-scene execution did not commit.")
		return _finish()

	for _frame in range(6):
		await process_frame
	if results.is_empty():
		_failures.append("Full-scene execution did not emit a CombatResultRecord.")
	else:
		var found_location := false
		for location in results[0].body_locations:
			if str(location.get("actor_id", "")) == "enemy" and int(location.get("sector_index", -1)) == expected_sector_index:
				found_location = true
				break
		if not found_location:
			_failures.append("CombatResultRecord.body_locations lost the executed handoff sector.")
		if scene.board.handoff_layer_of_id("enemy") != "body":
			_failures.append("Full-scene execution did not leave the enemy in the body layer.")
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("TACTICAL_COMBAT_RESULT_HANDOFF_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)
