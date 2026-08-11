extends RefCounted
class_name CombatUtilityEvaluator

const COMPONENTS := [
	"motive_satisfaction",
	"expected_wounds",
	"stance_impact",
	"target_priority",
	"threat_reduction",
	"survival",
	"range_quality",
	"line_of_sight",
	"cover",
	"exposure",
	"engagement",
	"hazard",
	"collateral",
	"relation",
	"communication",
	"ap_efficiency",
	"useful_ap_remaining",
	"plan_complexity",
]


static func evaluate_plan(plan, snapshot, motive_candidate, problem, profile_data = {}) -> Dictionary:
	var components: Dictionary = {}
	for component in COMPONENTS:
		components[component] = 0.0
	if plan == null:
		components["plan_complexity"] = -1.0
		return _weighted_result(components, profile_data)
	var first_quote: CombatActionQuote = plan.quotes[0] if not plan.quotes.is_empty() else null
	var last_quote: CombatActionQuote = plan.quotes.back() if not plan.quotes.is_empty() else null
	components["motive_satisfaction"] = 1.0 if motive_candidate != null and plan.terminal_action != "end_turn" else 0.0
	if last_quote != null:
		if last_quote.forecast != null:
			components["expected_wounds"] = float(last_quote.forecast.hit_probability)
		components["line_of_sight"] = 1.0 if last_quote.has_line_of_sight else 0.0
		components["engagement"] = 1.0 if last_quote.range_cells == 0 else 0.0
		components["collateral"] = -float(last_quote.collateral_risk)
		components["cover"] = float(last_quote.cover_strength)
		components["range_quality"] = 1.0 / maxf(1.0, float(last_quote.range_cells))
	if motive_candidate != null and motive_candidate.motive in ["SURVIVE", "ESCAPE"]:
		components["survival"] = 1.0
	if problem != null and problem.problem_id in ["NEED_RELOAD", "NEED_UNJAM", "NEED_READY"]:
		components["threat_reduction"] = 0.5
	components["ap_efficiency"] = 1.0 / maxf(1.0, float(plan.projected_ap))
	var remaining_ap := float(snapshot.actor.get("remaining_ap", 0.0)) if snapshot != null else 0.0
	components["useful_ap_remaining"] = maxf(0.0, remaining_ap - float(plan.projected_ap)) / 12.0
	components["plan_complexity"] = -float(maxi(0, plan.steps.size() - 1)) * 0.1
	return _weighted_result(components, profile_data)


static func score_components(components: Dictionary, profile_data = {}) -> float:
	return float(_weighted_result(components, profile_data).get("total", 0.0))


static func _weighted_result(components: Dictionary, profile_data) -> Dictionary:
	var weights: Dictionary = _weights(profile_data)
	var weighted: Dictionary = {}
	var total := 0.0
	for component in COMPONENTS:
		var value := float(components.get(component, 0.0))
		var weight := float(weights.get(component, 1.0))
		var contribution := value * weight
		weighted[component] = contribution
		total += contribution
	return {
		"components": components.duplicate(true),
		"weights": weights.duplicate(true),
		"weighted_components": weighted,
		"total": total,
	}


static func _weights(profile_data) -> Dictionary:
	if profile_data is Dictionary:
		var explicit: Dictionary = profile_data.get("utility_weights", {})
		return explicit if not explicit.is_empty() else profile_data.get("combat_score_weights", {})
	if profile_data != null and profile_data.has_method("get"):
		var authored = profile_data.get("utility_weights")
		if authored is Dictionary:
			return authored
	return {}
