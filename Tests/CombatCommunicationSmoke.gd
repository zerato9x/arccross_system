extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var board := CombatBoard.new()
	var turns := TacticalTurnManager.new()
	var engine := CombatResolutionEngine.new()
	var controller := CombatActionController.new()
	for node in [board, turns, engine, controller]:
		root.add_child(node)
	var player := _actor("player", GameEnums.Faction.ARCBORN_RESISTANCE, "player")
	var ally := _actor("ally", GameEnums.Faction.ARCBORN_RESISTANCE, "allies")
	var hostile := _actor("hostile", GameEnums.Faction.SCAVENGER_CELL, "hostiles")
	await process_frame
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "communication_smoke"
	encounter.world_seed = "COMMUNICATION_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.communication_points = 4
	encounter.relationship_state = {
		"schema_version": 1,
		"relation_by_pair": {
			"ally|player": CombatRelationshipLedger.Relation.FRIENDLY,
			"hostile|player": CombatRelationshipLedger.Relation.HOSTILE,
			"ally|hostile": CombatRelationshipLedger.Relation.HOSTILE,
		},
	}
	await process_frame
	board.configure_from_encounter(encounter)
	board.configure_communication_points([player, ally, hostile], encounter)
	_deploy(board, player, Vector2i(1, 2), "player")
	_deploy(board, ally, Vector2i(2, 2), "allies")
	_deploy(board, hostile, Vector2i(5, 2), "hostiles")
	turns.initialize([player, ally, hostile], player, 17)
	turns.combatants = [player, ally, hostile]
	turns.active_actor_index = 0
	turns.current_ap_pool = 12
	engine.board = board
	engine.turn_manager = turns
	controller.configure([player, ally, hostile], board, turns, engine)

	var offense := _request("player", "offense", "ally")
	var offense_quote := controller.quote(offense)
	if not offense_quote.legal or not bool(offense_quote.communication_acceptance_forecast.get("accepted", false)):
		_fail("Friendly communication did not produce an accepted authoritative forecast.")
	var points_before := board.communication_points
	var offense_outcome := await controller.request_action(offense)
	if offense_outcome == null or not offense_outcome.committed:
		_fail("Accepted friendly communication did not commit.")
	if board.squad_points != points_before - 1:
		_fail("Accepted communication did not spend exactly one Communication Point.")
	if board.combat_state(ally).communication_order != "offense":
		_fail("Accepted instruction was not persisted on the target combat state.")

	ally.is_mindless_hive_thrall = true
	ally.definition.agenda = GameEnums.Agenda.MINDLESS
	var refusal := _request("player", "defense", "ally")
	var refusal_quote := controller.quote(refusal)
	if not refusal_quote.legal or bool(refusal_quote.communication_acceptance_forecast.get("accepted", true)):
		_fail("Mindless refusal was not quoted deterministically.")
	points_before = board.communication_points
	var refusal_outcome := await controller.request_action(refusal)
	if refusal_outcome == null or not refusal_outcome.committed:
		_fail("A refused communication should still commit its attempt and end cleanly.")
	if board.squad_points != points_before - 1:
		_fail("Refused communication did not spend exactly one Communication Point.")
	if board.combat_state(ally).communication_order != "offense":
		_fail("A refusal replaced the previous accepted instruction.")

	var ceasefire := _request("player", "ceasefire", "hostile")
	var ceasefire_quote := controller.quote(ceasefire)
	if not ceasefire_quote.legal:
		_fail("Ceasefire was rejected before its authoritative relation check: %s" % ceasefire_quote.denial_code)
	var ceasefire_outcome := await controller.request_action(ceasefire)
	if ceasefire_outcome == null or not ceasefire_outcome.committed:
		_fail("Ceasefire did not commit.")
	if board.relation_between(player, hostile) != CombatRelationshipLedger.Relation.FRIENDLY:
		_fail("Accepted ceasefire did not change the pairwise relation ledger.")
	if board.is_hostile(player, hostile):
		_fail("Ceasefire left a stale hostile projection in the board.")

	if failures.is_empty():
		print("COMBAT_COMMUNICATION_SMOKE: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("[COMBAT_COMMUNICATION] " + failure)
	quit(1)


func _request(actor_id: String, action_id: String, target_id: String) -> CombatActionRequest:
	var request := CombatActionRequest.new()
	request.actor_id = actor_id
	request.action_id = action_id
	request.target_actor_id = target_id
	request.communication_intent = action_id
	return request


func _deploy(board: CombatBoard, actor: HumanoidCore, coords: Vector2i, side: String) -> void:
	if not board.force_spawn_actor(actor, board.arena_state.index_for(coords), side):
		_fail("Could not deploy %s." % actor.name)


func _actor(actor_id: String, faction: int, team_id: String) -> HumanoidCore:
	var actor := HumanoidCore.new()
	actor.name = actor_id
	actor.set_meta("actor_id", actor_id)
	actor.set_meta("combat_team_id", team_id)
	var definition := EntityDefinition.new()
	definition.archetype_name = actor_id
	definition.faction = faction as GameEnums.Faction
	definition.agenda = GameEnums.Agenda.SURVIVALIST
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
