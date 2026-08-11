extends SceneTree

var _board: CombatBoard
var _turns: TacticalTurnManager
var _engine: CombatResolutionEngine
var _controller: CombatActionController
var _player: HumanoidCore
var _alpha: HumanoidCore
var _bravo: HumanoidCore


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
	_alpha = _actor("alpha", GameEnums.Faction.SCAVENGER_CELL)
	_bravo = _actor("bravo", GameEnums.Faction.CRAVEN_HIVE)
	await process_frame
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "leave_battle_smoke"
	encounter.center_hex = HexRecord.new()
	_board.configure_from_encounter(encounter)
	_deploy(_player, Vector2i(1, 2), "player")
	_deploy(_alpha, Vector2i(4, 2), "enemy")
	_deploy(_bravo, Vector2i(5, 2), "enemy")
	_board.set_relation(_player, _alpha, CombatRelationshipLedger.Relation.FRIENDLY)
	_board.set_relation(_player, _bravo, CombatRelationshipLedger.Relation.FRIENDLY)
	_board.set_relation(_alpha, _bravo, CombatRelationshipLedger.Relation.HOSTILE)
	_turns.initialize([_player, _alpha, _bravo], _player, 77)
	_turns.combatants = [_player, _alpha, _bravo]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	_engine.board = _board
	_engine.turn_manager = _turns
	_controller.configure([_player, _alpha, _bravo], _board, _turns, _engine)
	if _board.has_active_player_hostile(_player):
		return _fail("Friendly player relations were treated as hostile.")
	if not _board.has_active_hostile_conflict(_player):
		return _fail("Hostile NPC conflict was not retained after the player became friendly to both actors.")
	var request := CombatActionRequest.new()
	request.actor_id = "player"
	request.action_id = "leave_battle"
	var quote := _controller.quote(request)
	if not quote.legal:
		return _fail("Leave Battle was not legal without a player-hostile actor: %s" % quote.denial_code)
	var outcome := await _controller.request_action(request)
	if outcome == null or not outcome.committed or outcome.result_events.is_empty():
		return _fail("Leave Battle did not commit a deterministic terminal receipt.")
	print("COMBAT_LEAVE_BATTLE_SMOKE: PASS")
	quit(0)


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


func _deploy(actor: HumanoidCore, coords: Vector2i, side: String) -> void:
	if not _board.force_spawn_actor(actor, _board.arena_state.index_for(coords), side):
		_fail("Could not deploy %s." % actor.name)


func _fail(message: String) -> void:
	push_error("[COMBAT_LEAVE_BATTLE_SMOKE] " + message)
	quit(1)
