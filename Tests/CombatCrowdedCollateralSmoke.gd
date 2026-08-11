extends SceneTree

## Crowded sectors are legal to attack, but the authored collateral rule must
## be visible in the quote and deterministic at commit.  The physical target
## remains the selected actor; any collateral hit is a second, explicitly
## tagged resolution event.

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := CombatBoard.new()
	var turns := TacticalTurnManager.new()
	var engine := CombatResolutionEngine.new()
	var controller := CombatActionController.new()
	root.add_child(board)
	root.add_child(turns)
	root.add_child(engine)
	root.add_child(controller)
	var shooter := _actor("shooter", GameEnums.Faction.ARCBORN_RESISTANCE, "player")
	var target := _actor("target", GameEnums.Faction.CRAVEN_HIVE, "enemy")
	var ally := _actor("ally", GameEnums.Faction.CRAVEN_HIVE, "enemy")
	await process_frame
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.world_seed = "CROWDED_COLLATERAL_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.relationship_state = {
		"schema_version": 1,
		"relation_by_pair": {
			"shooter|target": CombatRelationshipLedger.Relation.HOSTILE,
			"shooter|ally": CombatRelationshipLedger.Relation.HOSTILE,
			"target|ally": CombatRelationshipLedger.Relation.FRIENDLY,
		},
	}
	board.configure_from_encounter(encounter)
	var shooter_index := board.arena_state.index_for(Vector2i(0, 2))
	var shared_index := board.arena_state.index_for(Vector2i(4, 2))
	if not board.force_spawn_actor(shooter, shooter_index, "player"):
		_fail("Could not deploy shooter.")
	if not board.force_spawn_actor(target, shared_index, "enemy"):
		_fail("Could not deploy intended target.")
	if not board.force_spawn_actor(ally, shared_index, "enemy", true):
		_fail("Could not deploy the second occupant.")
	if board.occupancy_kind(shared_index) != "crowded":
		_fail("The friendly co-occupants were not classified as crowded.")
	_equip_pistol(shooter)
	board.balance_profile.crowded_collateral_risk = 1.0
	board.balance_profile.crowded_collateral_multiplier = 0.5
	turns.initialize([shooter, target, ally], shooter, 77)
	turns.combatants = [shooter, target, ally]
	turns.active_actor_index = 0
	turns.current_ap_pool = 12
	engine.board = board
	engine.turn_manager = turns
	controller.configure([shooter, target, ally], board, turns, engine)
	var request := CombatActionRequest.new()
	request.actor_id = "shooter"
	request.action_id = "fire"
	request.target_actor_id = "target"
	request.target_sector = Vector2i(4, 2)
	request.metadata["weapon_id"] = "crowded_pistol"
	var quote := controller.quote(request)
	if not quote.legal:
		_fail("A legal firearm attack into a crowded sector was denied: %s" % quote.denial_message)
	if not is_equal_approx(quote.collateral_risk, 1.0):
		_fail("Crowded quote did not expose the authored collateral risk.")
	var events: Array[Dictionary] = []
	var shots: Array[Dictionary] = []
	engine.damage_resolved.connect(func(event: Dictionary) -> void: events.append(event.duplicate(true)))
	engine.shot_resolved.connect(func(event: Dictionary) -> void: shots.append(event.duplicate(true)))
	engine.rng.seed = 1
	var resolved: bool = await engine.execute_ranged_strike(shooter, shared_index, null, null, target)
	if not resolved:
		_fail("Crowded firearm resolution was rejected at commit.")
	var collateral_seen := false
	for event in events:
		if bool(event.get("collateral", false)) and str(event.get("victim_id", "")) == "ally":
			collateral_seen = true
	if not collateral_seen:
		_fail("The deterministic crowded hit did not produce an explicitly tagged collateral event. occupancy=%s relation=%s events=%s shots=%s" % [board.occupancy_kind(shared_index), board.relation_between(target, ally), events, shots])
	if board.actors_at(shared_index).size() != 2:
		_fail("Collateral resolution changed sector occupancy.")
	if _failures.is_empty():
		print("COMBAT_CROWDED_COLLATERAL_SMOKE: PASS")
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
	pistol.id = "crowded_pistol"
	pistol.display_name = "Crowded Test Pistol"
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
