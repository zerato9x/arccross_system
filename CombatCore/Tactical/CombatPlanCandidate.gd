extends RefCounted
class_name CombatPlanCandidate

var steps: Array[CombatActionRequest] = []
var quotes: Array[CombatActionQuote] = []
var projected_ap: int = 0
var terminal_action: String = ""
var component_scores: Dictionary = {}
var rejection_reason: String = ""
var sort_key: String = ""
var projected_state_signature: String = ""


func to_dict() -> Dictionary:
	var request_data: Array[Dictionary] = []
	for request in steps:
		request_data.append(request.to_dict())
	var quote_data: Array[Dictionary] = []
	for quote in quotes:
		quote_data.append(quote.to_dict())
	return {
		"steps": request_data,
		"quotes": quote_data,
		"projected_ap": projected_ap,
		"terminal_action": terminal_action,
		"component_scores": component_scores.duplicate(true),
		"rejection_reason": rejection_reason,
		"sort_key": sort_key,
		"projected_state_signature": projected_state_signature,
	}
