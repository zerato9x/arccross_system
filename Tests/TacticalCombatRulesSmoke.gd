extends SceneTree

var _board: CombatBoard
var _turns: TacticalTurnManager
var _controller: CombatActionController
var _engine: CombatResolutionEngine
var _alpha: HumanoidCore
var _bravo: HumanoidCore
var _charlie: HumanoidCore


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_board = CombatBoard.new()
	_turns = TacticalTurnManager.new()
	_engine = CombatResolutionEngine.new()
	_controller = CombatActionController.new()
	root.add_child(_board)
	root.add_child(_turns)
	root.add_child(_engine)
	root.add_child(_controller)
	_alpha = _actor("alpha", GameEnums.Faction.ARCBORN_RESISTANCE)
	_bravo = _actor("bravo", GameEnums.Faction.CRAVEN_HIVE)
	_charlie = _actor("charlie", GameEnums.Faction.CRAVEN_HIVE)
	await process_frame
	_board.configure_from_encounter(_encounter())
	_clear_board()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(4, 2), "enemy")
	_turns.initialize([_alpha, _bravo], _alpha)
	# Make turn ownership deterministic without changing production initiative rules.
	_turns.combatants = [_alpha, _bravo]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	_engine.board = _board
	_engine.turn_manager = _turns
	_controller.configure([_alpha, _bravo, _charlie], _board, _turns, _engine)

	if not await _transaction_and_movement_checks():
		return
	if not await _posture_checks():
		return
	if not _shove_checks():
		return
	if not _grapple_checks():
		return
	print("[TACTICAL_COMBAT_RULES] PASS")
	quit(0)


func _transaction_and_movement_checks() -> bool:
	var invalid := _request("turn")
	invalid.final_facing = _board.get_facing(_alpha)
	var before_ap := _turns.current_ap_pool
	var before_state := _board.snapshot()
	var before_rng := _controller._rng.state
	var denied := await _controller.request_action(invalid)
	if denied.committed:
		return _fail("An invalid turn committed.")
	if _turns.current_ap_pool != before_ap or _board.snapshot() != before_state:
		return _fail("An invalid action mutated AP or board state.")
	if _controller._rng.state != before_rng:
		return _fail("An invalid action advanced tactical RNG.")

	var path: Array[Vector2i] = []
	for x in range(0, 7):
		path.append(Vector2i(x, 0))
	if _board.path_cost(_indices(path), 2) != 12:
		return _fail("Six clear fluid steps do not cost exactly 12 AP.")

	var move := _request("move")
	move.path = [Vector2i(1, 2), Vector2i(2, 2)]
	move.final_facing = "south"
	var action_quote := _controller.preview(move)
	if not action_quote.legal or action_quote.ap_cost != 2:
		return _fail("A one-sector clear move was not quoted at 2 AP.")
	var outcome := await _controller.request_action(move)
	if not outcome.committed or _board.position_of(_alpha) != _index(Vector2i(2, 2)):
		return _fail("The committed path did not match its preview.")
	if _turns.current_ap_pool != before_ap - action_quote.ap_cost:
		return _fail("Committed AP did not match the quote.")
	return true


func _posture_checks() -> bool:
	_turns.current_ap_pool = 12
	var prone := _request("go_prone")
	var quote := _controller.quote(prone)
	if not quote.legal:
		return _fail("Go Prone was not exposed as a legal authored action.")
	var outcome := await _controller.request_action(prone)
	if not outcome.committed or _board.posture(_alpha) != "prone":
		return _fail("Go Prone did not commit discrete posture state.")
	_turns.current_ap_pool = 12
	var stand := _request("stand")
	var stand_outcome := await _controller.request_action(stand)
	if not stand_outcome.committed or _board.posture(_alpha) != "standing":
		return _fail("Stand did not recover from prone posture.")
	return true


func _shove_checks() -> bool:
	_clear_occupants()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(2, 2), "enemy")
	if _board.preview_shove(_alpha, _bravo).get("type") != "clear":
		return _fail("Clear shove displacement was not predicted.")
	var clear_result := _board.commit_shove(_alpha, _bravo, 4.0, 2.0)
	if not clear_result.get("moved", false) or _board.posture(_bravo) != "prone":
		return _fail("Strong clear shove did not move and knock prone.")

	_clear_occupants()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(2, 2), "enemy")
	var obstacle := _board.sectors[_index(Vector2i(3, 2))]
	obstacle.record.blocked = true
	obstacle.record.object_state = {"id": "crate", "durability": 4.0}
	obstacle.configure(obstacle.record)
	if _board.commit_shove(_alpha, _bravo, 2.0, 2.0).get("type") != "object_collision":
		return _fail("Stable obstacle collision was not resolved without displacement.")

	obstacle.record.blocked = false
	obstacle.record.object_state.clear()
	obstacle.configure(obstacle.record)
	_deploy(_charlie, Vector2i(3, 2), "enemy")
	var actor_collision := _board.commit_shove(_alpha, _bravo, 2.0, 2.0)
	if actor_collision.get("type") != "actor_collision" or not _board.has_condition(_charlie, "off_balance"):
		return _fail("Actor collision recursively displaced or missed balance effects.")

	_clear_occupants()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(0, 2), "enemy")
	if _board.preview_shove(_alpha, _bravo).get("type") != "boundary":
		return _fail("Ordinary arena edge did not behave as a boundary.")
	_board.sectors[_index(Vector2i(0, 2))].record.object_state["forced_exit_edges"] = ["west"]
	if _board.preview_shove(_alpha, _bravo).get("type") != "forced_exit":
		return _fail("Authored forced-exit edge was ignored.")
	return true


func _grapple_checks() -> bool:
	_clear_occupants()
	_deploy(_alpha, Vector2i(2, 2), "player")
	_deploy(_bravo, Vector2i(3, 2), "enemy")
	if not _board.establish_grapple(_alpha, _bravo):
		return _fail("Adjacent grapple control could not be established.")
	_board.set_condition(_bravo, "restrained", true)
	if _board.control_role(_alpha) != "controller" or _board.control_role(_bravo) != "controlled":
		return _fail("Grapple roles were not persistent and directional.")
	var dragged := _board.commit_drag(_alpha, _index(Vector2i(3, 2)))
	if dragged.size() != 2 or _board.grid_distance(_board.position_of(_alpha), _board.position_of(_bravo)) != 1:
		return _fail("Drag did not preserve adjacent grapple control.")
	_board.break_grapple(_alpha)
	if not _board.control_role(_alpha).is_empty() or _board.has_condition(_bravo, "restrained"):
		return _fail("Release did not clear control transients.")
	return true


func _actor(actor_id: String, faction: int) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.faction = faction as GameEnums.Faction
	actor.definition = definition
	var body := HumanoidBody.new()
	body.name = "HumanoidBody"
	actor.add_child(body)
	var inventory := InventorySystem.new()
	inventory.name = "InventorySystem"
	actor.add_child(inventory)
	root.add_child(actor)
	return actor


func _encounter() -> CombatEncounterRecord:
	var encounter := CombatEncounterRecord.new()
	encounter.encounter_id = "tactical_rules_smoke"
	encounter.world_seed = "TACTICAL_RULES_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _clear_board() -> void:
	for sector in _board.sectors:
		sector.record.blocked = false
		sector.record.object_state.clear()
		sector.record.hazard_state.clear()
		sector.record.trap_state.clear()
		sector.record.movement_modifier = 0
		sector.configure(sector.record)


func _clear_occupants() -> void:
	_board.clear_actors()
	for sector in _board.sectors:
		sector.occupant = null
		sector.record.blocked = false
		sector.record.object_state.clear()
		sector.configure(sector.record)


func _deploy(actor: HumanoidCore, coords: Vector2i, side: String) -> void:
	if not _board.force_spawn_actor(actor, _index(coords), side):
		_fail("Could not deploy %s at %s." % [actor.name, coords])


func _request(action_id: String) -> CombatActionRequest:
	var request := CombatActionRequest.new()
	request.actor_id = "alpha"
	request.action_id = action_id
	return request


func _indices(path: Array[Vector2i]) -> Array[int]:
	var result: Array[int] = []
	for coords in path:
		result.append(_index(coords))
	return result


func _index(coords: Vector2i) -> int:
	return CombatArenaState.index_for_coords(coords)


func _fail(message: String) -> bool:
	push_error("[TACTICAL_COMBAT_RULES] " + message)
	quit(1)
	return false
