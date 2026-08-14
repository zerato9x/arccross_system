extends SceneTree

var _board: CombatBoard
var _turns: TacticalTurnManager
var _engine: CombatResolutionEngine
var _controller: CombatActionController
var _alpha: HumanoidCore
var _bravo: HumanoidCore
var _charlie: HumanoidCore
var _delta: HumanoidCore


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_board = CombatBoard.new()
	_turns = TacticalTurnManager.new()
	_engine = CombatResolutionEngine.new()
	_controller = CombatActionController.new()
	for node in [_board, _turns, _engine, _controller]:
		root.add_child(node)
	_alpha = _actor("alpha", GameEnums.Faction.ARCBORN_RESISTANCE)
	_bravo = _actor("bravo", GameEnums.Faction.CRAVEN_HIVE)
	_charlie = _actor("charlie", GameEnums.Faction.CRAVEN_HIVE)
	_delta = _actor("delta", GameEnums.Faction.CRAVEN_HIVE)
	await process_frame
	_board.configure_from_encounter(_encounter())
	_turns.initialize([_alpha, _bravo, _charlie, _delta], _alpha)
	_turns.combatants = [_alpha, _bravo, _charlie, _delta]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	_engine.board = _board
	_engine.turn_manager = _turns
	_controller.configure([_alpha, _bravo, _charlie, _delta], _board, _turns, _engine)

	if not await _engage_checks():
		return
	if not _occupancy_and_melee_checks():
		return
	if not _shove_checks():
		return
	if not _firearm_cycle_checks():
		return
	print("COMBAT_AI_PREREQUISITE_AUTHORITY_SMOKE: PASS")
	quit(0)


func _engage_checks() -> bool:
	_clear_board()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(3, 2), "enemy")
	var request := _request("engage")
	request.target_actor_id = "bravo"
	request.approach_path = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2)]
	var quote := _controller.quote(request)
	if not quote.legal:
		return _fail("Explicit Engage was not quoted as legal: %s" % quote.denial_code)
	var wounds_before := _bravo.body.get_total_wound_count()
	var outcome := await _controller.request_action(request)
	if not outcome.committed:
		return _fail("Explicit Engage did not commit.")
	if _board.position_of(_alpha) != _board.position_of(_bravo) or not _board.is_engaged(_board.position_of(_alpha)):
		return _fail("Explicit Engage did not create same-sector hostility.")
	if _bravo.body.get_total_wound_count() != wounds_before:
		return _fail("Engage performed a free attack instead of movement only.")
	return true


func _occupancy_and_melee_checks() -> bool:
	_clear_board()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(2, 2), "enemy")
	var move := _request("move")
	move.path = [Vector2i(1, 2), Vector2i(2, 2)]
	var blocked_move := _controller.quote(move)
	if blocked_move.legal or blocked_move.denial_code != "path_blocked":
		return _fail("Ordinary movement entered an occupied sector.")
	var strike := _request("strike")
	strike.target_actor_id = "bravo"
	var adjacent_strike := _controller.quote(strike)
	if adjacent_strike.legal or adjacent_strike.denial_code != "same_sector_melee_required":
		return _fail("Default adjacent melee was not rejected: %s" % adjacent_strike.denial_code)
	_clear_board()
	_deploy(_alpha, Vector2i(2, 2), "player")
	_deploy(_bravo, Vector2i(2, 2), "enemy", true)
	strike = _request("strike")
	strike.target_actor_id = "bravo"
	if not _controller.quote(strike).legal:
		return _fail("Same-sector hostile melee was rejected.")
	_clear_board()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(2, 2), "enemy")
	_equip_melee(_alpha, 2)
	strike = _request("strike")
	strike.target_actor_id = "bravo"
	if not _controller.quote(strike).legal:
		return _fail("Explicit reach weapon did not permit authored adjacent melee.")
	_clear_board()
	_deploy(_alpha, Vector2i(2, 2), "player")
	_deploy(_bravo, Vector2i(3, 2), "enemy", true)
	_deploy(_charlie, Vector2i(3, 2), "enemy", true)
	if _board.sectors[_index(Vector2i(3, 2))].occupants.size() != 2:
		return _fail("Forced displacement did not preserve two-actor capacity.")
	if _board.force_spawn_actor(_delta, _index(Vector2i(3, 2)), "enemy", true):
		return _fail("A third actor entered a full sector.")
	return true


func _shove_checks() -> bool:
	_clear_board()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(2, 2), "enemy")
	var shove := _request("shove")
	shove.target_actor_id = "bravo"
	if _controller.quote(shove).denial_code != "co_occupancy_required":
		return _fail("Shove remained legal against an adjacent actor.")
	_clear_board()
	_deploy(_alpha, Vector2i(2, 2), "player")
	_deploy(_bravo, Vector2i(2, 2), "enemy", true)
	_deploy(_charlie, Vector2i(3, 2), "enemy", true)
	var result := _board.commit_shove(_alpha, _bravo, 4.0, 2.0, "east")
	if not result.get("moved", false) or _board.position_of(_bravo) != _index(Vector2i(3, 2)):
		return _fail("Actor-collision Shove did not relocate the target.")
	if _board.sectors[_index(Vector2i(3, 2))].occupants.size() != 2:
		return _fail("Actor-collision Shove violated capacity.")
	return true


func _firearm_cycle_checks() -> bool:
	_clear_board()
	_deploy(_alpha, Vector2i(1, 2), "player")
	_deploy(_bravo, Vector2i(3, 2), "enemy")
	_equip_firearm(_alpha)
	var weapon := _alpha.inventory.get_active_weapon(false)
	weapon.is_jammed = true
	var cycle := _request("cycle")
	if not _controller.quote(cycle).legal:
		return _fail("Jam-only Cycle was not legal.")
	if _controller.catalog.definition("clear_malfunction") != null:
		return _fail("Retired clear_malfunction remained defined.")
	weapon.is_jammed = false
	weapon.needs_cycling = true
	var fire := _request("fire")
	fire.target_actor_id = "bravo"
	if not _controller.quote(fire).legal:
		return _fail("Ordinary cycling was not folded into Fire legality.")
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


func _equip_firearm(actor: HumanoidCore) -> void:
	var definition := ItemData.new()
	definition.id = "prerequisite_pistol"
	definition.item_type = GameEnums.ItemType.WEAPON
	definition.weapon_type = GameEnums.WeaponClass.PISTOL
	definition.max_magazine = 6
	definition.maximum_range_cells = 8
	var weapon := definition.create_runtime_instance()
	actor.inventory.equip_item(weapon, GameEnums.EquipmentSlot.HAND)


func _equip_melee(actor: HumanoidCore, reach: int) -> void:
	var definition := ItemData.new()
	definition.id = "prerequisite_reach_weapon"
	definition.item_type = GameEnums.ItemType.WEAPON
	definition.weapon_type = GameEnums.WeaponClass.BLADE
	definition.flesh_damage = 1.0
	definition.weapon_reach_cells = reach
	var weapon := definition.create_runtime_instance()
	actor.inventory.equip_item(weapon, GameEnums.EquipmentSlot.HAND)


func _encounter() -> CombatEncounterRecord:
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "combat_ai_prerequisite_smoke"
	encounter.world_seed = "COMBAT_AI_PREREQUISITE_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _clear_board() -> void:
	_board.clear_actors()
	for sector in _board.sectors:
		sector.record.blocked = false
		sector.record.object_state.clear()
		sector.record.hazard_state.clear()
		sector.configure(sector.record)
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12


func _deploy(actor: HumanoidCore, coords: Vector2i, side: String, forced: bool = false) -> void:
	if not _board.force_spawn_actor(actor, _index(coords), side, forced):
		_fail("Could not deploy %s at %s." % [actor.name, coords])


func _request(action_id: String) -> CombatActionRequest:
	var request := CombatActionRequest.new()
	request.actor_id = "alpha"
	request.action_id = action_id
	return request


func _index(coords: Vector2i) -> int:
	return _board.arena_state.index_for(coords)


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_PREREQUISITE] " + message)
	quit(1)
	return false
