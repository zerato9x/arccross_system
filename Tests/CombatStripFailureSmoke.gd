extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _run_case("equipped_item")
	await _run_case("equipped_backpack")
	if _failures.is_empty():
		print("COMBAT_STRIP_FAILURE_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _run_case(case_id: String) -> void:
	var board := CombatBoard.new()
	var turns := TacticalTurnManager.new()
	var engine := CombatResolutionEngine.new()
	var controller := CombatActionController.new()
	root.add_child(board)
	root.add_child(turns)
	root.add_child(engine)
	root.add_child(controller)
	var player := _actor("player_%s" % case_id, GameEnums.Faction.ARCBORN_RESISTANCE)
	var target := _actor("target_%s" % case_id, GameEnums.Faction.SCAVENGER_CELL)
	await process_frame

	var encounter := CombatEncounterRecord.new()
	encounter.encounter_id = "strip_failure_%s" % case_id
	encounter.topology_id = "squad_7x5"
	encounter.initiator_id = player.get_meta("actor_id")
	encounter.center_hex = HexRecord.new()
	board.configure_from_encounter(encounter)
	_deploy(board, player, Vector2i(2, 2), "player")
	_deploy(board, target, Vector2i(3, 2), "enemy")
	board.set_relation(player, target, CombatRelationshipLedger.Relation.HOSTILE)
	turns.initialize([player, target], player, 211)
	turns.combatants = [player, target]
	turns.active_actor_index = 0
	turns.current_ap_pool = 12
	engine.board = board
	engine.turn_manager = turns
	controller.configure([player, target], board, turns, engine)

	var target_item_id := "rollback_%s" % case_id
	if case_id == "equipped_item":
		var item_definition := ItemData.new()
		item_definition.id = target_item_id
		item_definition.display_name = "Rollback Test Weapon"
		item_definition.item_type = GameEnums.ItemType.WEAPON
		item_definition.weapon_type = GameEnums.WeaponClass.BLUNT
		item_definition.flesh_damage = 1.0
		var item := item_definition.create_runtime_instance()
		item.instance_id = target_item_id
		if not target.inventory.equip_item(item, GameEnums.EquipmentSlot.HAND):
			_failures.append("%s: could not equip the ordinary source item." % case_id)
			return
	else:
		var backpack_definition := load("res://ItemCore/Items/backpack_service_big.tres") as ItemData
		var backpack := backpack_definition.create_runtime_instance()
		if not target.inventory.equip_item(backpack, GameEnums.EquipmentSlot.BACKPACK):
			_failures.append("%s: could not equip the source backpack." % case_id)
			return
		var contents_definition := load("res://ItemCore/Items/water_bottle.tres") as ItemData
		var contents := contents_definition.create_runtime_instance()
		contents.instance_id = "contents_%s" % case_id
		if not target.inventory.add_to_backpack(contents, GameEnums.EquipmentSlot.BACKPACK):
			_failures.append("%s: could not place contents in the source backpack." % case_id)
			return
		target_item_id = backpack.instance_id

	var handoff := board.mark_incapacitated(target, "strip_failure_smoke")
	turns.remove_combatant(target)
	if handoff.is_empty():
		_failures.append("%s: source target did not enter the handoff layer." % case_id)
		return

	var target_before := target.inventory.capture_runtime_state().to_dict()
	var player_ap_before := turns.current_ap_pool
	var request := CombatActionRequest.new()
	request.actor_id = player.get_meta("actor_id")
	request.action_id = "strip"
	request.target_actor_id = target.get_meta("actor_id")
	request.target_item_instance_id = target_item_id
	var quote := controller.quote(request)
	if not quote.legal:
		_failures.append("%s: failed Strip was not quoted as legal: %s" % [case_id, quote.denial_code])
		return
	var outcome := await controller.request_action(request)
	if outcome == null or outcome.committed:
		_failures.append("%s: failed Strip unexpectedly committed." % case_id)
		return
	if turns.current_ap_pool != player_ap_before:
		_failures.append("%s: failed Strip changed AP." % case_id)
	if target.inventory.capture_runtime_state().to_dict() != target_before:
		_failures.append("%s: failed Strip changed the source inventory." % case_id)
	if target.inventory.find_item_by_instance_id(target_item_id) == null:
		_failures.append("%s: failed Strip lost the source item." % case_id)
	if player.inventory.find_item_by_instance_id(target_item_id) != null:
		_failures.append("%s: failed Strip transferred an item into the rejecting destination." % case_id)


func _deploy(board: CombatBoard, actor: HumanoidCore, coords: Vector2i, side: String) -> void:
	actor.set_meta("combat_side", side)
	actor.set_meta("combat_team_id", side)
	board.force_spawn_actor(actor, board.arena_state.index_for(coords), side, true)


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
