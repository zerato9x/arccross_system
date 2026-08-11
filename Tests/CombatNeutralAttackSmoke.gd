extends SceneTree

var _board: CombatBoard
var _turns: TacticalTurnManager
var _engine: CombatResolutionEngine
var _controller: CombatActionController
var _player: HumanoidCore
var _neutral: HumanoidCore


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
	_neutral = _actor("neutral", GameEnums.Faction.SCAVENGER_CELL)
	await process_frame
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "neutral_attack_smoke"
	encounter.center_hex = HexRecord.new()
	_board.configure_from_encounter(encounter)
	_deploy(_player, Vector2i(2, 2), "player")
	# Unarmed strikes require shared-sector melee. Keep this fixture focused on
	# neutral-target confirmation instead of failing earlier on reach legality.
	_deploy(_neutral, Vector2i(2, 2), "neutral")
	_board.set_relation(_player, _neutral, CombatRelationshipLedger.Relation.NEUTRAL)
	_turns.initialize([_player, _neutral], _player, 91)
	_turns.combatants = [_player, _neutral]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	_engine.board = _board
	_engine.turn_manager = _turns
	_controller.configure([_player, _neutral], _board, _turns, _engine)

	var request := CombatActionRequest.new()
	request.actor_id = "player"
	request.action_id = "strike"
	request.target_actor_id = "neutral"
	var quote := _controller.quote(request)
	if quote.legal or quote.denial_code != "neutral_attack_confirmation_required":
		return _fail("Neutral attack did not require explicit confirmation.")
	request.declared_neutral_attack_confirmation = true
	quote = _controller.quote(request)
	if not quote.legal:
		return _fail("Confirmed neutral attack remained illegal: %s" % quote.denial_code)
	var outcome := await _controller.request_action(request)
	if outcome == null or not outcome.committed:
		return _fail("Confirmed neutral attack did not commit.")
	if _board.relation_between(_player, _neutral) != CombatRelationshipLedger.Relation.HOSTILE:
		return _fail("Confirmed neutral attack did not establish hostility.")
	print("COMBAT_NEUTRAL_ATTACK_SMOKE: PASS")
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
