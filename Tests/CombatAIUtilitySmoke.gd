extends SceneTree

const _Plan := preload("res://CombatCore/Tactical/CombatPlanCandidate.gd")
const _Utility := preload("res://CombatCore/Tactical/CombatUtilityEvaluator.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var plan = _Plan.new()
	var request := CombatActionRequest.new()
	request.actor_id = "alpha"
	request.action_id = "fire"
	request.target_actor_id = "bravo"
	plan.steps.append(request)
	var quote := CombatActionQuote.new()
	quote.legal = true
	quote.ap_cost = 4
	quote.range_cells = 2
	quote.has_line_of_sight = true
	quote.collateral_risk = 0.1
	quote.cover_strength = 0.25
	plan.quotes.append(quote)
	plan.projected_ap = 4
	plan.terminal_action = "fire"
	var snapshot = {"actor": {"remaining_ap": 12}}
	var motive = {"motive": "ATTACK"}
	var problem = {"problem_id": "READY"}
	var result: Dictionary = _Utility.evaluate_plan(plan, snapshot, motive, problem, {"utility_weights": {"line_of_sight": 2.0, "collateral": 3.0}})
	var sum := 0.0
	for value in result.weighted_components.values():
		sum += float(value)
	if not is_equal_approx(sum, float(result.total)):
		return _fail("Utility component contributions did not reproduce total score.")
	var altered: Dictionary = _Utility.evaluate_plan(plan, snapshot, motive, problem, {"utility_weights": {"line_of_sight": 8.0, "collateral": 0.0}})
	if is_equal_approx(float(result.total), float(altered.total)):
		return _fail("Profile utility weight changes did not alter plan score.")
	print("COMBAT_AI_UTILITY_SMOKE: PASS")
	quit(0)


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_UTILITY] " + message)
	quit(1)
	return false
