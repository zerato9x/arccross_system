extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var duel := CombatTopologyCatalog.load_profile("duel_12x1")
	var skirmish := CombatTopologyCatalog.load_profile("skirmish_6x3")
	var squad := CombatTopologyCatalog.load_profile("squad_7x5")
	if duel.columns != 12 or duel.rows != 1 or duel.sector_count() != 12:
		return _fail("Legacy Lab duel profile is not 12 x 1.")
	if skirmish.columns != 6 or skirmish.rows != 3:
		return _fail("Legacy Lab skirmish profile lost its authored dimensions.")
	if squad.columns != 7 or squad.rows != 5 or squad.movement_policy != CombatTopologyProfile.MovementPolicy.ORTHOGONAL:
		return _fail("Production squad profile is not the canonical orthogonal 7 x 5 board.")

	var board := CombatBoard.new()
	var turns := TacticalTurnManager.new()
	var builder := TacticalEncounterBuilder.new()
	root.add_child(board)
	root.add_child(turns)
	root.add_child(builder)
	builder.board = board
	builder.turn_manager = turns
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.world_seed = "PRODUCTION_TOPOLOGY_SMOKE"
	encounter.initiator_id = "player"
	encounter.center_hex = HexRecord.new()
	if encounter.participant_cap != 6 or encounter.late_reinforcements_enabled:
		return _fail("Production encounter defaults do not freeze an aware six-actor roster.")
	var player := _actor("player", "player")
	var enemy_a := _actor("enemy_a", "enemy")
	var enemy_b := _actor("enemy_b", "enemy")
	await process_frame
	builder.build([player, enemy_a, enemy_b], encounter)
	if board.arena_state.width != 7 or board.arena_state.height != 5 or board.arena_state.topology_id != "squad_7x5":
		return _fail("Encounter builder did not configure the production squad topology.")
	for actor in [player, enemy_a, enemy_b]:
		if board.position_of(actor) < 0:
			return _fail("Production squad deployment omitted %s." % actor.name)

	# The old duel remains a deliberately isolated Lab/compatibility fixture.
	var lab_encounter := CombatEncounterRecord.new()
	lab_encounter.topology_id = "duel_12x1"
	lab_encounter.world_seed = "LEGACY_DUEL_LAB_SMOKE"
	lab_encounter.center_hex = HexRecord.new()
	board.configure_from_encounter(lab_encounter)
	board.clear_actors()
	board.force_spawn_actor(player, 0, "player")
	board.force_spawn_actor(enemy_a, 6, "enemy")
	board.force_spawn_actor(enemy_b, 10, "enemy")
	if not board.find_path(0, 7, player).is_empty():
		return _fail("Linear no-passing allowed a path through an occupied cell.")
	print("[COMBAT_TOPOLOGY_CONTRACT] PASS")
	quit(0)


func _actor(actor_id: String, side: String) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	actor.set_meta("combat_side", side)
	var body := HumanoidBody.new()
	body.name = "HumanoidBody"
	actor.add_child(body)
	var inventory := InventorySystem.new()
	inventory.name = "InventorySystem"
	actor.add_child(inventory)
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.brawn = 6
	definition.finesse = 6
	definition.fortitude = 6
	definition.will = 6
	actor.definition = definition
	root.add_child(actor)
	return actor


func _fail(message: String) -> void:
	push_error("[COMBAT_TOPOLOGY_CONTRACT] " + message)
	quit(1)
