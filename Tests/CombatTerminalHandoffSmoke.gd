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
	_equip_player_storage()
	_equip_target_item()
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
	var strip_request := CombatActionRequest.new()
	strip_request.actor_id = "player"
	strip_request.action_id = "strip"
	strip_request.target_actor_id = "target"
	strip_request.target_item_instance_id = "terminal_target_item"
	var strip_quote := _controller.quote(strip_request)
	if not strip_quote.legal:
		return _fail("Strip could not target the off-board incapacitated body: %s" % strip_quote.denial_code)
	var strip_outcome := await _controller.request_action(strip_request)
	if strip_outcome == null or not strip_outcome.committed:
		return _fail("Strip did not resolve against the handoff body.")
	if _target.inventory.find_item_by_instance_id("terminal_target_item") != null:
		return _fail("Strip left the selected item on the incapacitated body.")
	if _player.inventory.find_item_by_instance_id("terminal_target_item") == null:
		return _fail("Strip did not transfer the selected item to the acting actor.")

	var execute_request := CombatActionRequest.new()
	execute_request.actor_id = "player"
	execute_request.action_id = "execute"
	execute_request.target_actor_id = "target"
	var execute_quote := _controller.quote(execute_request)
	if not execute_quote.legal:
		return _fail("Execute could not target the off-board incapacitated body: %s" % execute_quote.denial_code)
	var execute_outcome := await _controller.request_action(execute_request)
	if execute_outcome == null or not execute_outcome.committed or not _target.is_dead:
		return _fail("Execute did not resolve lethally against the handoff body.")
	if _board.handoff_layer_of_id("target") != "body":
		return _fail("Execute did not transition the handoff actor into the body layer.")
	if "target" in handoff_sector.record.incapacitated_entity_ids or "target" not in handoff_sector.record.body_entity_ids:
		return _fail("Execute left the target in the incapacitated layer instead of the body layer.")
	print("COMBAT_TERMINAL_HANDOFF_SMOKE: PASS")
	quit(0)


func _deploy(actor: HumanoidCore, coords: Vector2i, side: String) -> void:
	actor.set_meta("combat_side", side)
	actor.set_meta("combat_team_id", side)
	_board.force_spawn_actor(actor, _board.arena_state.index_for(coords), side, true)


func _equip_player_storage() -> void:
	var backpack_definition := load("res://ItemCore/Items/backpack_service_big.tres") as ItemData
	if backpack_definition == null or not _player.inventory.equip_item(backpack_definition.create_runtime_instance(), GameEnums.EquipmentSlot.BACKPACK):
		_fail("The player could not receive storage for the strip transfer.")


func _equip_target_item() -> void:
	var item_definition := ItemData.new()
	item_definition.id = "terminal_target_item"
	item_definition.display_name = "Terminal Test Item"
	item_definition.item_type = GameEnums.ItemType.WEAPON
	item_definition.weapon_type = GameEnums.WeaponClass.BLUNT
	item_definition.flesh_damage = 1.0
	var item := item_definition.create_runtime_instance()
	item.instance_id = "terminal_target_item"
	if not _target.inventory.equip_item(item, GameEnums.EquipmentSlot.HAND):
		_fail("The incapacitated target could not receive the strip test item.")


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
