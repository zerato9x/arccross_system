extends SceneTree

var _board: CombatBoard
var _turns: TacticalTurnManager
var _engine: CombatResolutionEngine
var _controller: CombatActionController
var _player: HumanoidCore
var _target: HumanoidCore


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
	_player = _actor("player", GameEnums.Faction.ARCBORN_RESISTANCE)
	_target = _actor("target", GameEnums.Faction.SCAVENGER_CELL)
	await process_frame
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "terminal_handoff_smoke"
	encounter.center_hex = HexRecord.new()
	_board.configure_from_encounter(encounter)
	_deploy(_player, Vector2i(2, 2), "player")
	_deploy(_target, Vector2i(3, 2), "enemy")
	_board.set_relation(_player, _target, CombatRelationshipLedger.Relation.HOSTILE)
	_turns.initialize([_player, _target], _player, 101)
	_turns.combatants = [_player, _target]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	_engine.board = _board
	_engine.turn_manager = _turns
	_controller.configure([_player, _target], _board, _turns, _engine)
	var target_state := _board.combat_state(_target)
	target_state.stance = 0.0
	target_state.reconcile()
	_target.set_meta("combat_actor_state", target_state)
	var request := CombatActionRequest.new()
	request.actor_id = "player"
	request.action_id = "incapacitate"
	request.target_actor_id = "target"
	var quote := _controller.quote(request)
	if not quote.legal:
		return _fail("Broken target was not eligible for Incapacitate: %s" % quote.denial_code)
	var outcome := await _controller.request_action(request)
	if outcome == null or not outcome.committed:
		return _fail("Incapacitate did not commit.")
	if _board.position_of(_target) >= 0:
		return _fail("Incapacitated actor still occupies the active board layer.")
	if _turns.combatants.has(_target):
		return _fail("Incapacitated actor remained in initiative.")
	var handoff_sector := _board.sectors[_board.arena_state.index_for(Vector2i(3, 2))]
	if handoff_sector.record.incapacitated_entity_ids.is_empty():
		return _fail("Incapacitated handoff location was not preserved.")
	print("COMBAT_TERMINAL_HANDOFF_SMOKE: PASS")
	quit(0)


func _deploy(actor: HumanoidCore, coords: Vector2i, side: String) -> void:
	actor.set_meta("combat_side", side)
	actor.set_meta("combat_team_id", side)
	_board.force_spawn_actor(actor, _board.arena_state.index_for(coords), side, true)


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


func _fail(message: String) -> void:
	printerr("[FAIL] ", message)
	quit(1)
