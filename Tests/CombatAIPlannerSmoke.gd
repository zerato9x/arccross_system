extends SceneTree

const _RulesState := preload("res://CombatCore/Tactical/CombatRulesState.gd")
const _Builder := preload("res://CombatCore/Tactical/CombatPerceptionBuilder.gd")
const _Planner := preload("res://CombatCore/Tactical/CombatBoundedPlanner.gd")
const _Candidate := preload("res://CombatCore/Tactical/CombatMotiveCandidate.gd")
const _Problem := preload("res://CombatCore/Tactical/CombatTacticalProblem.gd")

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
	var rules_state = _RulesState.from_board(_board, _turns, _controller.catalog, [_alpha, _bravo], 12)
	var snapshot = _Builder.build(rules_state, "alpha")
	var motive = _Candidate.new()
	motive.motive = "ATTACK"
	motive.subject_type = "actor"
	motive.subject_id = "bravo"
	motive.feasible = true
	var problem = _Problem.new()
	problem.problem_id = _Problem.NEED_ENGAGE
	problem.feasible = true
	var first: Array = _Planner.plan(snapshot, motive, problem, rules_state)
	var second: Array = _Planner.plan(snapshot, motive, problem, rules_state)
	if first.is_empty() or _fingerprint(first) != _fingerprint(second):
		return _fail("Bounded planner was not deterministic.")
	var found_follow_up := false
	for plan in first:
		if plan.steps.size() >= 2 and plan.steps[0].action_id == "engage" and plan.steps[1].action_id in ["strike", "fire"]:
			found_follow_up = true
			if plan.projected_ap > 12:
				return _fail("Planner reserved more AP than the turn budget.")
			if plan.quotes[0].projected_origin == plan.quotes[1].projected_origin and plan.steps[1].action_id == "strike":
				found_follow_up = true
	if not found_follow_up:
		return _fail("Planner did not produce an Engage-to-attack follow-up plan.")
	print("COMBAT_AI_PLANNER_SMOKE: PASS")
	quit(0)


func _fingerprint(plans: Array) -> String:
	var result: Array[String] = []
	for plan in plans:
		var actions: Array[String] = []
		for request in plan.steps:
			actions.append(request.action_id + ":" + request.target_actor_id)
		result.append("%s|%s|%s" % ["->".join(actions), plan.projected_ap, plan.sort_key])
	return "\n".join(result)


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


func _encounter() -> CombatEncounterRecord:
	var encounter := CombatEncounterRecord.new()
	encounter.topology_id = "squad_7x5"
	encounter.encounter_id = "combat_ai_planner_smoke"
	encounter.world_seed = "COMBAT_AI_PLANNER_SMOKE"
	encounter.center_hex = HexRecord.new()
	encounter.center_hex.zone_id = "smoke"
	encounter.center_hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return encounter


func _index(coords: Vector2i) -> int:
	return _board.arena_state.index_for(coords)


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_PLANNER] " + message)
	quit(1)
	return false
