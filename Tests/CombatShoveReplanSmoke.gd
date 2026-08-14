extends SceneTree

var _board: CombatBoard
var _turns: TacticalTurnManager
var _engine: CombatResolutionEngine
var _controller: CombatActionController
var _player: HumanoidCore
var _npc: HumanoidCore


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
	_player = _actor("player", true, 100)
	_npc = _actor("npc", false, 0)
	await process_frame
	_board.configure_from_encounter(_encounter())
	_board.force_spawn_actor(_player, _board.arena_state.index_for(Vector2i(2, 2)), "player")
	_board.force_spawn_actor(_npc, _board.arena_state.index_for(Vector2i(2, 2)), "enemy", true)
	_turns.initialize([_player, _npc], _player, 13)
	_turns.combatants = [_player, _npc]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	_engine.board = _board
	_engine.turn_manager = _turns
	_engine.encounter_id = "shove_replan"
	_controller.configure([_player, _npc], _board, _turns, _engine)
	var ai := TacticalCombatAI.new()
	root.add_child(ai)
	ai.configure(_npc, _controller, _board, _turns)
	var order: Array[String] = []
	_controller.action_committed.connect(func(_outcome): order.append("committed"))
	_controller.ai_replan_requested.connect(func(_actor_id, _reason): order.append("replan"))
	var request := CombatActionRequest.new()
	request.actor_id = "player"
	request.action_id = "shove"
	request.target_actor_id = "npc"
	request.target_sector = Vector2i(2, 2)
	request.shove_direction = "east"
	var action_quote := _controller.quote(request)
	if not action_quote.legal:
		_fail("Shove setup was illegal: %s" % action_quote.denial_message)
		return
	var ap_before := _turns.current_ap_pool
	var outcome := await _controller.request_action(request)
	if outcome == null or not outcome.committed:
		_fail("Shove did not commit.")
		return
	if _board.position_of(_npc) != _board.arena_state.index_for(Vector2i(3, 2)):
		_fail("Shove did not move the AI actor out of same-sector Engagement.")
		return
	if ai.shove_replan_request_count() != 1 or not ai.has_queued_shove_replan():
		_fail("Shove did not queue exactly one AI replan.")
		return
	if order != ["committed", "replan"] or _controller.is_presentation_locked():
		_fail("AI replan was emitted before the action/presentation barrier completed.")
		return
	if _turns.get_active_entity() != _player or _turns.current_ap_pool != ap_before - action_quote.ap_cost:
		_fail("AI replan changed turn order or spent bonus AP.")
		return
	print("COMBAT_SHOVE_REPLAN_SMOKE: PASS")
	quit(0)


func _actor(actor_id: String, direct_player: bool, brawn: int) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	actor.set_meta("direct_player", direct_player)
	actor.set_meta("combat_side", "player" if direct_player else "enemy")
	actor.set_meta("combat_team_id", "player" if direct_player else "enemy")
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.brawn = brawn
	definition.faction = GameEnums.Faction.ARCBORN_RESISTANCE if direct_player else GameEnums.Faction.CRAVEN_HIVE
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
	encounter.encounter_id = "shove_replan"
	encounter.topology_id = "squad_7x5"
	encounter.world_seed = "SHOVE_REPLAN"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _fail(message: String) -> void:
	push_error("COMBAT_SHOVE_REPLAN_SMOKE: " + message)
	quit(1)
