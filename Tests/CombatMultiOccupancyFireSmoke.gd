extends SceneTree

## The request path must carry an actor identity all the way into resolution.
## A sector can contain two hostile targets; selecting the first occupant as a
## fallback would make the wrong body take the hit (and made the old combat
## look immortal when the visible target was not the resolved target).

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := CombatBoard.new()
	var turns := TacticalTurnManager.new()
	var engine := CombatResolutionEngine.new()
	root.add_child(board)
	root.add_child(turns)
	root.add_child(engine)
	var shooter := _actor("shooter", GameEnums.Faction.ARCBORN_RESISTANCE, "player")
	var first_target := _actor("first_target", GameEnums.Faction.CRAVEN_HIVE, "enemy")
	var selected_target := _actor("selected_target", GameEnums.Faction.CRAVEN_HIVE, "enemy")
	await process_frame
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.world_seed = "MULTI_OCCUPANCY_FIRE_SMOKE"
	encounter.center_hex = HexRecord.new()
	board.configure_from_encounter(encounter)
	if not board.force_spawn_actor(shooter, board.arena_state.index_for(Vector2i(0, 2)), "player"):
		_fail("Could not deploy shooter.")
	var shared_index := board.arena_state.index_for(Vector2i(4, 2))
	if not board.force_spawn_actor(first_target, shared_index, "enemy"):
		_fail("Could not deploy first target.")
	if not board.force_spawn_actor(selected_target, shared_index, "enemy", true):
		_fail("Could not force the second hostile target into the sector.")
	_equip_pistol(shooter)
	turns.initialize([shooter, first_target, selected_target], shooter, 991)
	turns.combatants = [shooter, first_target, selected_target]
	turns.active_actor_index = 0
	turns.current_ap_pool = 12
	engine.board = board
	engine.turn_manager = turns
	var resolved_events: Array[Dictionary] = []
	engine.shot_resolved.connect(func(event: Dictionary) -> void: resolved_events.append(event.duplicate(true)))
	var resolved: bool = await engine.execute_ranged_strike(
		shooter,
		shared_index,
		null,
		null,
		selected_target
	)
	if not resolved:
		_fail("Explicit-target firearm resolution was rejected.")
	if resolved_events.is_empty() or str(resolved_events.back().get("victim_id", "")) != "selected_target":
		_fail("Firearm resolution fell back to the first occupant instead of the selected actor.")
	if board.actors_at(shared_index).size() != 2:
		_fail("Fire resolution changed shared-sector occupancy.")
	if _failures.is_empty():
		print("COMBAT_MULTI_OCCUPANCY_FIRE_SMOKE: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _actor(actor_id: String, faction: int, side: String) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	actor.set_meta("combat_side", side)
	actor.set_meta("combat_team_id", side)
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.faction = faction as GameEnums.Faction
	definition.brawn = 6
	definition.finesse = 8
	definition.fortitude = 6
	definition.will = 6
	actor.definition = definition
	var body := HumanoidBody.new()
	body.name = "HumanoidBody"
	actor.add_child(body)
	var inventory := InventorySystem.new()
	inventory.name = "InventorySystem"
	actor.add_child(inventory)
	root.add_child(actor)
	return actor


func _equip_pistol(actor: HumanoidCore) -> void:
	var pistol := ItemData.new()
	pistol.id = "multi_target_pistol"
	pistol.display_name = "Multi Target Pistol"
	pistol.item_type = GameEnums.ItemType.WEAPON
	pistol.weapon_type = GameEnums.WeaponClass.PISTOL
	pistol.damage_type = GameEnums.DamageType.BALLISTIC
	pistol.flesh_damage = 1.0
	pistol.maximum_range_cells = 8
	pistol.optimal_range_cells = Vector2i(1, 5)
	pistol.max_magazine = 6
	var runtime := pistol.create_runtime_instance()
	runtime.current_magazine = 6
	actor.inventory.equip_item(runtime, GameEnums.EquipmentSlot.HAND)


func _fail(message: String) -> void:
	_failures.append(message)
