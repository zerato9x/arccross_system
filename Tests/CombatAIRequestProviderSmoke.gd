extends SceneTree

const _RulesState := preload("res://CombatCore/Tactical/CombatRulesState.gd")
const _Builder := preload("res://CombatCore/Tactical/CombatPerceptionBuilder.gd")
const _Provider := preload("res://CombatCore/Tactical/CombatLegalRequestProvider.gd")
const _Candidate := preload("res://CombatCore/Tactical/CombatMotiveCandidate.gd")
const _Problem := preload("res://CombatCore/Tactical/CombatTacticalProblem.gd")
const _Ledger := preload("res://SystemCore/CombatRelationshipLedger.gd")
const _Encounter := preload("res://SystemCore/CombatEncounterRecord.gd")
const _Hex := preload("res://SystemCore/HexRecord.gd")

var _board: CombatBoard
var _turns: TacticalTurnManager
var _controller: CombatActionController
var _alpha: HumanoidCore
var _bravo: HumanoidCore


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_board = CombatBoard.new()
	_turns = TacticalTurnManager.new()
	_controller = CombatActionController.new()
	root.add_child(_board)
	root.add_child(_turns)
	root.add_child(_controller)
	_alpha = _actor("alpha", GameEnums.Faction.ARCBORN_RESISTANCE)
	_bravo = _actor("bravo", GameEnums.Faction.CRAVEN_HIVE)
	await process_frame
	_board.configure_from_encounter(_encounter())
	_board.force_spawn_actor(_alpha, _index(Vector2i(1, 2)), "player")
	_board.force_spawn_actor(_bravo, _index(Vector2i(3, 2)), "enemy")
	_turns.initialize([_alpha, _bravo], _alpha)
	_turns.combatants = [_alpha, _bravo]
	_turns.active_actor_index = 0
	_turns.current_ap_pool = 12
	_controller.configure([_alpha, _bravo], _board, _turns, null)
	var rules_state = _RulesState.from_board(_board, _turns, _controller.catalog, [_alpha, _bravo], 4)
	var snapshot = _Builder.build(rules_state, "alpha")
	var motive = _Candidate.new()
	motive.motive = "ATTACK"
	motive.subject_type = "actor"
	motive.subject_id = "bravo"
	motive.feasible = true
	var problem = _Problem.new()
	problem.problem_id = _Problem.NEED_ENGAGE
	problem.feasible = true
	var generated: Dictionary = _Provider.generate(snapshot, motive, problem, rules_state)
	var found_engage := false
	for request in generated.requests:
		if request.action_id == "engage":
			found_engage = true
			if generated.quotes[generated.requests.find(request)].legal == false:
				return _fail("Provider returned an illegal Engage candidate.")
	if not found_engage:
		return _fail("Catalog-driven provider did not generate Engage for NEED_ENGAGE.")
	for request in generated.requests:
		if request.action_id == "clear_malfunction" or request.action_id == "disengage":
			return _fail("Provider enumerated a retired action.")
	print("COMBAT_AI_REQUEST_PROVIDER_SMOKE: PASS")
	quit(0)


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


func _encounter():
	var encounter = _Encounter.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "combat_ai_provider_smoke"
	encounter.world_seed = "COMBAT_AI_PROVIDER_SMOKE"
	encounter.center_hex = _Hex.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _index(coords: Vector2i) -> int:
	return _board.arena_state.index_for(coords)


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_PROVIDER] " + message)
	quit(1)
	return false
