extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var duel := CombatTopologyProfile.load_profile("duel_12x1")
	var skirmish := CombatTopologyProfile.load_profile("skirmish_6x3")
	var squad := CombatTopologyProfile.load_profile("squad_7x5")
	if duel.columns != 12 or duel.rows != 1 or duel.sector_count() != 12:
		return _fail("Production duel profile is not 12 x 1.")
	if skirmish.columns != 6 or skirmish.rows != 3 or squad.columns != 7 or squad.rows != 5:
		return _fail("Laboratory topology profiles lost their authored dimensions.")

	var board := CombatBoard.new()
	var turns := TacticalTurnManager.new()
	var builder := TacticalEncounterBuilder.new()
	root.add_child(board)
	root.add_child(turns)
	root.add_child(builder)
	builder.board = board
	builder.turn_manager = turns
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "duel_12x1"
	encounter.world_seed = "DUEL_TOPOLOGY_SMOKE"
	encounter.initiator_id = "player"
	encounter.center_hex = HexRecord.new()
	var player := _actor("player", "player")
	var enemy_a := _actor("enemy_a", "enemy")
	var enemy_b := _actor("enemy_b", "enemy")
	await process_frame
	builder.build([player, enemy_a, enemy_b], encounter)
	if board.arena_state.width != 12 or board.arena_state.height != 1:
		return _fail("Encounter builder did not configure the production topology.")
	if board.position_of(player) != 0 or board.position_of(enemy_a) != 11 or board.position_of(enemy_b) != 10:
		return _fail("The 1v2 duel deployment is not player 0 versus enemies 11 and 10.")
	for sector in board.arena_state.sectors:
		if sector.blocked or not sector.cover_edges.is_empty() or not sector.object_state.is_empty():
			return _fail("The concise duel lane inherited grid terrain clutter.")

	board.clear_actors()
	board.force_spawn_actor(player, 0, "player")
	board.force_spawn_actor(enemy_a, 6, "enemy")
	board.force_spawn_actor(enemy_b, 10, "enemy")
	if not board.find_path(0, 7, player).is_empty():
		return _fail("Linear no-passing allowed a path through an occupied cell.")
	print("[COMBAT_DUEL_TOPOLOGY] PASS")
	quit(0)


func _actor(actor_id: String, side: String) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	actor.set_meta("combat_side", side)
	root.add_child(actor)
	return actor


func _fail(message: String) -> void:
	push_error("[COMBAT_DUEL_TOPOLOGY] " + message)
	quit(1)
