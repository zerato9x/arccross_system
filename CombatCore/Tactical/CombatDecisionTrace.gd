extends RefCounted
class_name CombatDecisionTrace

## Lab/replay evidence for one immutable evaluation and its one submitted
## request.  This is intentionally richer than CombatIntentView.

var actor_id: String = ""
var snapshot_revision: int = -1
var reevaluation_trigger: String = ""
var hard_state_tags: Array[String] = []
var dominant_hard_state: String = ""
var motive_candidates: Array[Dictionary] = []
var chosen_motive: String = ""
var chosen_subject_type: String = ""
var chosen_subject_id: String = ""
var tactical_problem: Dictionary = {}
var plan_candidates: Array[Dictionary] = []
var quote_evidence: Array[Dictionary] = []
var utility_components: Array[Dictionary] = []
var selected_plan: Dictionary = {}
var intent: Dictionary = {}
var first_request: Dictionary = {}
var outcome: Dictionary = {}
var deterministic_seed: String = ""
var tie_break_key: String = ""
var ending_reason: String = ""
var reevaluation_reason: String = ""


func to_dict() -> Dictionary:
	return {
		"actor_id": actor_id,
		"snapshot_revision": snapshot_revision,
		"reevaluation_trigger": reevaluation_trigger,
		"hard_state_tags": hard_state_tags.duplicate(),
		"dominant_hard_state": dominant_hard_state,
		"motive_candidates": motive_candidates.duplicate(true),
		"chosen_motive": chosen_motive,
		"chosen_subject_type": chosen_subject_type,
		"chosen_subject_id": chosen_subject_id,
		"tactical_problem": tactical_problem.duplicate(true),
		"plan_candidates": plan_candidates.duplicate(true),
		"quote_evidence": quote_evidence.duplicate(true),
		"utility_components": utility_components.duplicate(true),
		"selected_plan": selected_plan.duplicate(true),
		"intent": intent.duplicate(true),
		"first_request": first_request.duplicate(true),
		"outcome": outcome.duplicate(true),
		"deterministic_seed": deterministic_seed,
		"tie_break_key": tie_break_key,
		"ending_reason": ending_reason,
		"reevaluation_reason": reevaluation_reason,
	}


func compact_summary() -> Dictionary:
	return {
		"actor_id": actor_id,
		"snapshot_revision": snapshot_revision,
		"motive": chosen_motive,
		"subject_id": chosen_subject_id,
		"problem": str(tactical_problem.get("problem_id", "")),
		"request": str(first_request.get("action_id", "end_turn")),
		"outcome": str(outcome.get("action_id", "")),
		"ending_reason": ending_reason,
	}
