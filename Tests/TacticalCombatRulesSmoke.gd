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
	if not _melee_geometry_checks():
		return
	if not _forecast_and_catalog_checks():
		return
	print("[TACTICAL_COMBAT_RULES] PASS")
	quit(0)


func _transaction_and_movement_checks() -> bool:
	var invalid := _request("move")
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
	var crouch := _request("crouch")
	var quote := _controller.quote(crouch)
	if not quote.legal:
		return _fail("Crouch was not exposed as a legal authored action.")
	var outcome := await _controller.request_action(crouch)
	if not outcome.committed or _board.posture(_alpha) != "crouched":
		return _fail("Crouch did not commit discrete posture state.")
	if _controller.movement_step_base(_alpha) != 3:
		return _fail("Crouch did not add one AP to fluid movement steps.")
	_turns.current_ap_pool = 12
	var stand := _request("stand")
	var stand_outcome := await _controller.request_action(stand)
	if not stand_outcome.committed or _board.posture(_alpha) != "standing":
		return _fail("Stand did not recover from crouched posture.")
	return true


func _shove_checks() -> bool:
	_clear_occupants()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(2, 2), "enemy")
	if _board.preview_shove(_alpha, _bravo).get("type") != "clear":
		return _fail("Clear shove displacement was not predicted.")
	var clear_result := _board.commit_shove(_alpha, _bravo, 4.0, 2.0)
	if not clear_result.get("moved", false) or not _board.has_condition(_bravo, "off_balance"):
		return _fail("Strong clear shove did not move and apply off-balance.")

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


func _melee_geometry_checks() -> bool:
	_clear_occupants()
	_deploy(_alpha, Vector2i(2, 2), "player")
	_deploy(_bravo, Vector2i(3, 3), "enemy")
	if _board.grid_distance(_board.position_of(_alpha), _board.position_of(_bravo)) != 2:
		return _fail("Diagonal adjacency was not measured as distance two.")
	if _board.can_melee_reach(_alpha, _board.position_of(_bravo)):
		return _fail("Reach-one melee illegally attacked a diagonal sector.")
	_clear_occupants()
	_deploy(_alpha, Vector2i(2, 2), "player")
	_deploy(_bravo, Vector2i(3, 2), "enemy")
	if not _board.can_melee_reach(_alpha, _board.position_of(_bravo)):
		return _fail("Cardinal adjacency did not enable reach-one melee.")
	return true


func _forecast_and_catalog_checks() -> bool:
	for removed_id in ["go_prone", "rush", "reserve", "grapple", "drag", "takedown", "throw", "restrain", "release", "break_free", "heavy_strike"]:
		if _controller.catalog.definition(removed_id) != null:
			return _fail("Removed action remained in the production catalog: %s" % removed_id)
	for required_id in ["move", "strike", "power_strike", "aimed_strike", "shove", "fire", "aimed_fire", "end_turn"]:
		if _controller.catalog.definition(required_id) == null:
			return _fail("Required contextual action is missing: %s" % required_id)
	_turns.current_ap_pool = 12
	var aimed := _request("aimed_strike")
	aimed.target_actor_id = "bravo"
	aimed.target_body_region = GameEnums.LimbRegion.HEAD
	var before_rng := _controller._rng.state
	var action_quote := _controller.preview(aimed)
	if not action_quote.legal or action_quote.forecast == null:
		return _fail("Aimed strike did not produce a legal typed forecast.")
	if action_quote.forecast.target_body_region != GameEnums.LimbRegion.HEAD:
		return _fail("Aimed strike forecast lost the selected body region.")
	if action_quote.forecast.hit_probability <= 0.0 or action_quote.forecast.hit_probability > 1.0:
		return _fail("Forecast hit probability escaped its valid range.")
	if _controller._rng.state != before_rng:
		return _fail("Read-only forecasting advanced tactical RNG.")
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
	encounter.topology_id = "squad_7x5"
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
	return _board.arena_state.index_for(coords)


func _fail(message: String) -> bool:
	push_error("[TACTICAL_COMBAT_RULES] " + message)
	quit(1)
	return false
