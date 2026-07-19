extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(
		"res://CombatCore/TurnBased/TurnBasedDuelScene.tscn"
	) as PackedScene
	if scene == null:
		return _fail("Turn-based duel scene does not load.")
	var arena := scene.instantiate()
	root.add_child(arena)
	await process_frame

	var player_definition := load("res://BiologicalCore/player_def.tres") as EntityDefinition
	var enemy_definition := load("res://BiologicalCore/scavenger_def.tres") as EntityDefinition
	arena.setup_duel_from_records(
		{"entity_id": "turn_item_player", "definition": player_definition.to_state(), "runtime": {}},
		{"entity_id": "turn_item_enemy", "definition": enemy_definition.to_state(), "runtime": {}},
		{"initiator_id": "player"}
	)
	await process_frame
	arena.combat_briefing.visible = false
	arena.combat_briefing.combat_begin_requested.emit()
	await process_frame

	var player: HumanoidCore = arena.player_core
	var firearm := ItemData.new()
	firearm.id = "turn_jammed_firearm"
	firearm.display_name = "Turn Jammed Firearm"
	firearm.item_type = GameEnums.ItemType.WEAPON
	firearm.catalog_category = GameEnums.ItemCategory.FIREARM
	firearm.weapon_type = GameEnums.WeaponClass.PISTOL
	firearm.max_magazine = 6
	firearm.current_magazine = 6
	firearm.current_condition = 6.0
	firearm.is_jammed = true
	player.inventory.paper_doll[GameEnums.EquipmentSlot.HAND] = firearm
	player.inventory.paper_doll[GameEnums.EquipmentSlot.OFFHAND] = null
	arena.turn_manager.active_entity_index = 0
	arena.turn_manager.current_ap_pool = 12
	arena.turn_manager.is_halted = false

	var actions: Array = arena.command_adapter.get_snapshot().get("actions", [])
	var action_ids: Array = actions.map(func(entry: Dictionary): return int(entry.action))
	if not action_ids.has(GameEnums.ActionType.CLEAR_MALFUNCTION):
		return _fail("Jammed firearm did not expose CLEAR MALFUNCTION.")
	for hidden_action in [
		GameEnums.ActionType.SHOOT,
		GameEnums.ActionType.AIMED_SHOT,
		GameEnums.ActionType.RELOAD,
		GameEnums.ActionType.CYCLE,
	]:
		if action_ids.has(hidden_action):
			return _fail("Jammed firearm still exposed action %d." % hidden_action)

	if (
		CombatTurnManager.ACTION_CATEGORIES[GameEnums.ActionType.CLEAR_MALFUNCTION]
		!= CombatRules.ActionCategory.QUICK
	):
		return _fail("CLEAR MALFUNCTION is not registered as Quick.")
	var expected_costs := [1, 2, 3]
	for tier in GameEnums.KineticTier.values():
		player.kinetic_tier = tier
		if arena.turn_manager.get_action_cost(
			player, GameEnums.ActionType.CLEAR_MALFUNCTION
		) != expected_costs[tier]:
			return _fail("Quick AP cost mismatch for Kinetic tier %d." % tier)

	var ammo_before := firearm.current_magazine
	if not arena.resolution_engine.execute_clear_malfunction(player):
		return _fail("Turn resolver rejected deterministic malfunction clearing.")
	if firearm.is_jammed or firearm.current_magazine != ammo_before:
		return _fail("Turn malfunction clearing changed ammunition or retained the jam.")

	var shared_card: Node = arena.lane_hud.get_node_or_null(
		"WeaponCard/SharedItemCard"
	)
	if shared_card == null:
		return _fail("Turn HUD is not hosting the reusable combat item card.")

	arena.queue_free()
	await process_frame
	print("[TURN_ITEM_CONDITION] PASS // legality, Quick AP, deterministic clear, shared card")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TURN_ITEM_CONDITION] " + message)
	quit(1)
