extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := CombatBoard.new()
	root.add_child(board)
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.world_seed = "MULTI_OCCUPANCY_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.relationship_state = {
		"schema_version": 1,
		"relation_by_pair": {"alpha|bravo": CombatRelationshipLedger.Relation.HOSTILE},
	}
	var alpha := _actor("alpha", GameEnums.Faction.ARCBORN_RESISTANCE, "team_a")
	var bravo := _actor("bravo", GameEnums.Faction.CRAVEN_HIVE, "team_b")
	var charlie := _actor("charlie", GameEnums.Faction.ARCBORN_RESISTANCE, "team_a")
	await process_frame
	board.configure_from_encounter(encounter)
	var index := board.arena_state.index_for(Vector2i(3, 2))
	if not board.force_spawn_actor(alpha, index, "player"):
		_fail("Could not place the first actor.")
	if not board.force_spawn_actor(bravo, index, "enemy", true):
		_fail("Forced co-occupancy did not admit the second actor.")
	if board.actors_at(index).size() != 2 or board.occupancy_kind(index) != "engaged":
		_fail("Hostile co-occupants were not represented as an engaged pair.")
	if board.can_enter(charlie, index) or board.can_enter(charlie, index, true):
		_fail("A full sector admitted a third actor.")
	var pair := board.actors_at(index)
	if pair[0] != alpha or pair[1] != bravo:
		_fail("Sector occupants lost stable insertion order.")
	board.set_relation(alpha, bravo, CombatRelationshipLedger.Relation.FRIENDLY)
	if board.occupancy_kind(index) != "crowded":
		_fail("A non-hostile co-occupant pair was not classified as crowded.")
	board.set_relation(alpha, bravo, CombatRelationshipLedger.Relation.HOSTILE)
	board.remove_actor(alpha)
	if board.actors_at(index).size() != 1 or board.actors_at(index)[0] != bravo:
		_fail("Removing one occupant removed or reordered the other occupant.")
	if board.occupancy_kind(index) != "single":
		_fail("A one-actor sector did not return the single occupancy state.")
	if failures.is_empty():
		print("COMBAT_MULTI_OCCUPANCY_SMOKE: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("[COMBAT_MULTI_OCCUPANCY] " + failure)
	quit(1)


func _actor(actor_id: String, faction: int, team_id: String) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	actor.set_meta("combat_team_id", team_id)
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.faction = faction as GameEnums.Faction
	definition.brawn = 6
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


func _fail(message: String) -> void:
	failures.append(message)
