extends RefCounted
class_name CombatBoundedPlanner

const _Plan := preload("res://CombatCore/Tactical/CombatPlanCandidate.gd")
const _Provider := preload("res://CombatCore/Tactical/CombatLegalRequestProvider.gd")
const _Projection := preload("res://CombatCore/Tactical/CombatPlanningProjectionService.gd")
const _PerceptionBuilder := preload("res://CombatCore/Tactical/CombatPerceptionBuilder.gd")
const _Problem := preload("res://CombatCore/Tactical/CombatTacticalProblem.gd")
const _MotiveEvaluator := preload("res://CombatCore/Tactical/CombatMotiveEvaluator.gd")

const FIRST_EXPANSION_LIMIT := 12
const SECOND_EXPANSION_LIMIT := 6
const FINAL_PLAN_LIMIT := 3


static func plan(snapshot, motive_candidate, problem, rules_state, plan_metadata: Dictionary = {}) -> Array:
	var generated: Dictionary = _Provider.generate(snapshot, motive_candidate, problem, rules_state, plan_metadata)
	var first_requests: Array = generated.requests
	var first_quotes: Array = generated.quotes
	var plans: Array = []
	var first_count := mini(FIRST_EXPANSION_LIMIT, first_requests.size())
	for index in range(first_count):
		var request: CombatActionRequest = first_requests[index]
		var quote: CombatActionQuote = first_quotes[index]
		if quote == null or not quote.legal:
			continue
		if _reject_nonprogress(snapshot, motive_candidate, problem, request, quote, plan_metadata):
			continue
		var planning = _Projection.from_rules_state(rules_state, request.actor_id)
		var projected = _Projection.apply_quote(planning, request, quote, rules_state)
		var candidate_plan = _Plan.new()
		candidate_plan.steps.append(request)
		candidate_plan.quotes.append(quote)
		candidate_plan.projected_ap = quote.ap_cost
		candidate_plan.terminal_action = request.action_id
		candidate_plan.projected_state_signature = projected.signature
		candidate_plan.sort_key = "%03d|%s|%s" % [candidate_plan.projected_ap, request.action_id, request.target_actor_id]
		if _template_allowed([request], plan_metadata):
			plans.append(candidate_plan)
		if projected.uncertain or quote.planning_uncertain:
			continue
		var projected_rules = _Projection.to_rules_state(rules_state, projected)
		var projected_snapshot = _PerceptionBuilder.build(projected_rules, request.actor_id, {}, {}, "projected_plan")
		var follow_problem = _Problem.new()
		follow_problem.problem_id = _Problem.READY
		follow_problem.feasible = true
		follow_problem.motive = motive_candidate.motive
		follow_problem.subject_type = motive_candidate.subject_type
		follow_problem.subject_id = motive_candidate.subject_id
		var follow_generated: Dictionary = _Provider.generate(projected_snapshot, motive_candidate, follow_problem, projected_rules, plan_metadata)
		var second_count := mini(SECOND_EXPANSION_LIMIT, follow_generated.requests.size())
		for second_index in range(second_count):
			var follow_request: CombatActionRequest = follow_generated.requests[second_index]
			var follow_quote: CombatActionQuote = follow_generated.quotes[second_index]
			if follow_quote == null or not follow_quote.legal:
				continue
			if _reject_nonprogress(projected_snapshot, motive_candidate, follow_problem, follow_request, follow_quote, plan_metadata):
				continue
			var follow_planning = _Projection.apply_quote(projected, follow_request, follow_quote, projected_rules)
			if follow_planning.signature == projected.signature:
				continue
			var extended = _Plan.new()
			for prior_request in candidate_plan.steps:
				extended.steps.append(prior_request)
			for prior_quote in candidate_plan.quotes:
				extended.quotes.append(prior_quote)
			extended.steps.append(follow_request)
			extended.quotes.append(follow_quote)
			extended.projected_ap = candidate_plan.projected_ap + follow_quote.ap_cost
			extended.terminal_action = follow_request.action_id
			extended.projected_state_signature = follow_planning.signature
			extended.sort_key = "%03d|%s|%s|%s" % [extended.projected_ap, candidate_plan.steps[0].action_id, follow_request.action_id, follow_request.target_actor_id]
			if _template_allowed(extended.steps, plan_metadata):
				plans.append(extended)
	_dedupe_and_sort(plans)
	if plans.size() > FINAL_PLAN_LIMIT:
		plans.resize(FINAL_PLAN_LIMIT)
	if plans.is_empty():
		# The provider already guarantees a legal End Turn fallback. Reuse it so
		# the planner never invents AP or a special resolver.
		var fallback: Dictionary = _Provider.generate(snapshot, motive_candidate, _Problem.new(), rules_state)
		for fallback_index in range(fallback.requests.size()):
			if fallback.requests[fallback_index].action_id == "end_turn":
				var fallback_plan = _Plan.new()
				fallback_plan.steps.append(fallback.requests[fallback_index])
				fallback_plan.quotes.append(fallback.quotes[fallback_index])
				fallback_plan.terminal_action = "end_turn"
				fallback_plan.sort_key = "999|end_turn"
				plans.append(fallback_plan)
				break
	return plans


static func generate(snapshot, motive_candidate, problem, rules_state, plan_metadata: Dictionary = {}) -> Array:
	return plan(snapshot, motive_candidate, problem, rules_state, plan_metadata)


static func _dedupe_and_sort(plans: Array) -> void:
	var unique: Dictionary = {}
	for candidate_plan in plans:
		var signature: String = candidate_plan.sort_key + "|" + candidate_plan.projected_state_signature
		if not unique.has(signature):
			unique[signature] = candidate_plan
	plans.clear()
	for candidate_plan in unique.values():
		plans.append(candidate_plan)
	plans.sort_custom(func(left, right): return left.sort_key < right.sort_key)


static func _template_allowed(steps: Array, plan_metadata: Dictionary) -> bool:
	var allowed: Array = plan_metadata.get("allowed_plan_templates", [])
	if allowed.is_empty():
		return true
	var template_id := "single_action"
	if steps.size() >= 2:
		var first_tags := _request_ai_tags(steps[0])
		var second_tags := _request_ai_tags(steps[1])
		if "engagement" in first_tags and "damage" in second_tags:
			template_id = "engage_then_attack"
		elif "reload" in first_tags and "damage" in second_tags:
			template_id = "reload_then_attack"
		elif "unjam" in first_tags and "damage" in second_tags:
			template_id = "cycle_then_attack"
		elif "ready" in first_tags and "damage" in second_tags:
			template_id = "ready_then_attack"
		else:
			template_id = "preparation_then_action"
	return template_id in allowed


static func _request_ai_tags(request: CombatActionRequest) -> Array:
	if request == null:
		return []
	var tags: Variant = request.metadata.get("ai_tags", [])
	return tags.duplicate() if tags is Array else []


static func _reject_nonprogress(snapshot, motive_candidate, problem, request: CombatActionRequest, quote: CombatActionQuote, plan_metadata: Dictionary) -> bool:
	if request == null or quote == null or snapshot == null:
		return false
	if request.action_id != "move":
		return false
	var current: Vector2i = snapshot.actor.get("sector", Vector2i(-1, -1))
	var destination: Vector2i = quote.projected_origin
	if current == destination:
		return true
	var recent: Array = plan_metadata.get("recent_sectors", [])
	if recent.size() >= 2:
		var last_sector: Vector2i = recent[recent.size() - 1]
		var prior_sector: Vector2i = recent[recent.size() - 2]
		if current == last_sector and destination == prior_sector:
			return true
	var motive := _MotiveEvaluator.normalize_motive(str(motive_candidate.motive))
	if motive == "EXIT" or motive == "SURVIVE":
		var current_exit := _nearest_exit_distance(snapshot.exits, current)
		var destination_exit := _nearest_exit_distance(snapshot.exits, destination)
		if current_exit < 999 and destination_exit >= current_exit:
			return true
	var subject_id := str(motive_candidate.subject_id)
	var observed = snapshot.known_actors.get(subject_id)
	if observed != null and observed.sector != Vector2i(-1, -1) and str(problem.problem_id) in [_Problem.NEED_ENGAGE, _Problem.NEED_RANGE, _Problem.NEED_LINE_OF_FIRE, _Problem.NEED_POSITION]:
		var current_distance := _grid_distance(current, observed.sector)
		var destination_distance := _grid_distance(destination, observed.sector)
		if destination_distance >= current_distance:
			return true
	return false


static func _nearest_exit_distance(exits: Dictionary, coords: Vector2i) -> int:
	if exits.is_empty() or coords == Vector2i(-1, -1):
		return 999
	var best := 999
	for exit_data in exits.values():
		best = mini(best, _grid_distance(coords, exit_data.get("coords", Vector2i(-1, -1))))
	return best


static func _grid_distance(left: Vector2i, right: Vector2i) -> int:
	return absi(left.x - right.x) + absi(left.y - right.y)
