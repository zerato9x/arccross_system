extends RefCounted
class_name CombatUtilityEvaluator

## The planner compares exactly five authored signals. Detailed quote facts are
## folded into these signals here; they do not become a second hidden motive
## system.
const COMPONENTS := [
	"motive_progress",
	"survival_risk",
	"expected_effect",
	"ap_resource_cost",
	"collateral_relationship_safety",
]


static func evaluate_plan(plan, snapshot, motive_candidate, problem, profile_data = {}) -> Dictionary:
	var components: Dictionary = {}
	for component in COMPONENTS:
		components[component] = 0.0
	if plan == null:
		return _weighted_result(components, profile_data)
	var last_quote: CombatActionQuote = plan.quotes.back() if not plan.quotes.is_empty() else null
	var last_request: CombatActionRequest = plan.steps.back() if not plan.steps.is_empty() else null
	var actor_facts := _snapshot_actor(snapshot)
	var target: Variant = _target_observation(snapshot, last_request)
	var motive := _normalize_motive(str(_value(motive_candidate, "motive", "")))
	components["motive_progress"] = _motive_progress(motive, last_request, problem, target)
	components["survival_risk"] = _survival_safety(actor_facts, last_quote, snapshot)
	components["expected_effect"] = _expected_effect(last_quote, last_request, target)
	var remaining_ap := float(actor_facts.get("remaining_ap", actor_facts.get("max_ap", 12)))
	components["ap_resource_cost"] = clampf(1.0 - float(plan.projected_ap) / maxf(1.0, remaining_ap), -1.0, 1.0)
	components["collateral_relationship_safety"] = _relationship_safety(last_quote, last_request, target)
	return _weighted_result(_apply_utility_inputs(components, profile_data), profile_data)


static func score_components(components: Dictionary, profile_data = {}) -> float:
	return float(_weighted_result(components, profile_data).get("total", 0.0))


static func _weighted_result(components: Dictionary, profile_data) -> Dictionary:
	var weights := _weights(profile_data)
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
	var authored: Dictionary = {}
	if profile_data is Dictionary:
		authored = profile_data.get("utility_weights", {})
		if authored.is_empty():
			authored = profile_data.get("combat_score_weights", {})
	elif profile_data != null and profile_data.has_method("get"):
		var value = profile_data.get("utility_weights")
		if value is Dictionary:
			authored = value
	var result: Dictionary = {}
	for component in COMPONENTS:
		result[component] = float(authored.get(component, 1.0))
	# Compatibility aliases hydrate into the canonical five signals once.
	if authored.has("line_of_sight"):
		result["expected_effect"] = float(authored["line_of_sight"])
	if authored.has("collateral"):
		result["collateral_relationship_safety"] = float(authored["collateral"])
	return result


static func _snapshot_actor(snapshot) -> Dictionary:
	if snapshot is Dictionary:
		return snapshot.get("actor", {}).duplicate(true)
	return snapshot.actor if snapshot != null else {}


static func _target_observation(snapshot, request):
	if request == null or str(request.target_actor_id).is_empty() or snapshot == null:
		return null
	var known: Dictionary = snapshot.get("known_actors", {}) if snapshot is Dictionary else snapshot.known_actors
	return known.get(request.target_actor_id)


static func _motive_progress(motive: String, request, _problem, _target) -> float:
	if request == null:
		return -1.0
	if request.action_id == "end_turn":
		return 0.2 if motive == "HOLD" else 0.0
	var tags := _request_tags(request)
	match motive:
		"ATTACK": return 1.0 if "damage" in tags or "attack" in tags or "engagement" in tags else 0.2
		"EXIT": return 1.0 if "escape" in tags or "retreat" in tags or "break_engagement" in tags else 0.2
		"SURVIVE": return 1.0 if "survival" in tags or "retreat" in tags or "cover" in tags or "medical" in tags else 0.2
		"SUPPORT": return 1.0 if "support" in tags or "cover" in tags or "movement" in tags else 0.2
		"COMMUNICATE": return 1.0 if "communication" in tags else 0.0
		"HOLD": return 1.0 if "cover" in tags else 0.2
	return 0.0


static func _survival_safety(actor_facts: Dictionary, quote, snapshot) -> float:
	var blood := float(actor_facts.get("blood", 12.0))
	var pain := float(actor_facts.get("pain", 0.0))
	var shock := float(actor_facts.get("shock", 0.0))
	var consciousness := float(actor_facts.get("consciousness", 12.0))
	var danger := clampf((12.0 - blood) / 12.0 * 0.4 + pain / 12.0 * 0.2 + shock / 12.0 * 0.2 + (12.0 - consciousness) / 12.0 * 0.2, 0.0, 1.0)
	var cover := float(quote.cover_strength) if quote != null else 0.0
	return clampf(1.0 - danger + cover * 0.4 - _hazard(snapshot, quote), -1.0, 1.0)


static func _expected_effect(quote, request, _target) -> float:
	if quote == null:
		return 0.0
	var value := 0.0
	if quote.forecast != null:
		value = maxf(float(quote.forecast.expected_post_armor_trauma), float(quote.forecast.hit_probability))
	if "communication" in _request_tags(request):
		value = maxf(value, _communication_value(quote))
	if value <= 0.0 and request != null and ("attack" in _request_tags(request) or "damage" in _request_tags(request)):
		value = 0.5 if quote.has_line_of_sight else 0.0
	return clampf(value, -1.0, 1.0)


static func _relationship_safety(quote, request, target) -> float:
	if quote == null:
		return 0.0
	var value := 1.0 - clampf(float(quote.collateral_risk), 0.0, 1.0)
	if "communication" in _request_tags(request):
		value = maxf(value, _communication_value(quote))
	if target != null and int(_value(target, "relation", 0)) < 0 and request != null and "communication" not in _request_tags(request):
		value -= 0.1
	return clampf(value, -1.0, 1.0)


static func _communication_value(quote) -> float:
	if quote == null or quote.communication_acceptance_forecast.is_empty():
		return 0.0
	return clampf(float(quote.communication_acceptance_forecast.get("acceptance_probability", quote.communication_acceptance_forecast.get("probability", 0.0))), 0.0, 1.0)


static func _hazard(snapshot, quote) -> float:
	if snapshot == null or quote == null:
		return 0.0
	var sectors: Dictionary = snapshot.get("sectors", {}) if snapshot is Dictionary else snapshot.sectors
	for sector in sectors.values():
		if sector.get("coords", Vector2i(-1, -1)) != quote.projected_origin:
			continue
		var hazard: Dictionary = sector.get("hazard", {})
		return clampf(float(hazard.get("severity", hazard.get("damage", 0.0))), 0.0, 1.0)
	return 0.0


static func _request_tags(request) -> Array:
	if request == null:
		return []
	var tags: Variant = request.metadata.get("ai_tags", [])
	return tags.duplicate() if tags is Array else []


static func _apply_utility_inputs(components: Dictionary, profile_data) -> Dictionary:
	var result := components.duplicate(true)
	var inputs: Dictionary = {}
	if profile_data is Dictionary:
		inputs = profile_data.get("utility_inputs", {})
	elif profile_data != null and profile_data.has_method("get"):
		var authored = profile_data.get("utility_inputs")
		if authored is Dictionary:
			inputs = authored
	for component in COMPONENTS:
		result[component] = float(result.get(component, 0.0)) * float(inputs.get("%s_scale" % component, 1.0)) + float(inputs.get("%s_bias" % component, 0.0))
	return result


static func _normalize_motive(value: String) -> String:
	var aliases := {"ESCAPE": "EXIT", "SUBMIT": "COMMUNICATE", "DEESCALATE": "COMMUNICATE", "PROTECT": "SUPPORT", "PRESSURE": "ATTACK", "PURSUE": "ATTACK"}
	return str(aliases.get(value.to_upper(), value.to_upper()))


static func _value(source, key: String, fallback):
	if source is Dictionary:
		return source.get(key, fallback)
	if source == null:
		return fallback
	var value = source.get(key)
	return fallback if value == null else value
