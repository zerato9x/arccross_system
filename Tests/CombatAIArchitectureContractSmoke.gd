extends SceneTree

## Phase 1 contract test for the deterministic combat-AI refactor.
##
## This intentionally inspects source contracts instead of instantiating the
## future evaluator. A failure here must identify a missing architecture seam,
## not collapse into a parser error caused by production code that does not
## exist yet.

const CONTRACTS := {
	"CombatPerceptionSnapshot": {
		"path": "res://CombatCore/Tactical/CombatPerceptionSnapshot.gd",
		"required": ["class_name CombatPerceptionSnapshot", "hard_facts", "known_actors", "reevaluation_trigger"],
	},
	"CombatObservedActor": {
		"path": "res://CombatCore/Tactical/CombatObservedActor.gd",
		"required": ["class_name CombatObservedActor", "knowledge_state", "confidence", "observable_weapon"],
	},
	"CombatHardStateResult": {
		"path": "res://CombatCore/Tactical/CombatHardStateResult.gd",
		"required": ["class_name CombatHardStateResult", "tags", "dominant_tag"],
	},
	"CombatMotiveCandidate": {
		"path": "res://CombatCore/Tactical/CombatMotiveCandidate.gd",
		"required": ["class_name CombatMotiveCandidate", "subject_id", "feasible", "inertia_modifier"],
	},
	"CombatTacticalProblem": {
		"path": "res://CombatCore/Tactical/CombatTacticalProblem.gd",
		"required": ["class_name CombatTacticalProblem", "problem_id", "reason_tags"],
	},
	"CombatPlanningState": {
		"path": "res://CombatCore/Tactical/CombatPlanningState.gd",
		"required": ["class_name CombatPlanningState", "remaining_ap", "occupancy", "weapon_readiness"],
	},
	"CombatPlanCandidate": {
		"path": "res://CombatCore/Tactical/CombatPlanCandidate.gd",
		"required": ["class_name CombatPlanCandidate", "quotes", "projected_ap", "sort_key"],
	},
	"CombatIntent": {
		"path": "res://CombatCore/Tactical/CombatIntent.gd",
		"required": ["class_name CombatIntent", "current_request", "snapshot_revision", "intent_revision"],
	},
	"CombatIntentView": {
		"path": "res://CombatCore/Tactical/CombatIntentView.gd",
		"required": ["class_name CombatIntentView", "readable_label", "intent_revision"],
	},
	"CombatDecisionTrace": {
		"path": "res://CombatCore/Tactical/CombatDecisionTrace.gd",
		"required": ["class_name CombatDecisionTrace", "selected_plan", "deterministic_seed"],
	},
	"CombatActionQuoteService": {
		"path": "res://CombatCore/Tactical/CombatActionQuoteService.gd",
		"required": ["class_name CombatActionQuoteService", "static func quote", "CombatRulesState"],
	},
	"CombatRevisionAuthority": {
		"path": "res://CombatCore/Tactical/CombatRevisionAuthority.gd",
		"required": ["class_name CombatRevisionAuthority", "revision", "bump"],
	},
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	for contract_name in CONTRACTS.keys():
		var contract: Dictionary = CONTRACTS[contract_name]
		var path: String = contract["path"]
		if not FileAccess.file_exists(path):
			failures.append("%s is missing: %s" % [contract_name, path])
			continue
		var source := FileAccess.get_file_as_string(path)
		for required_token in contract["required"]:
			if source.find(str(required_token)) == -1:
				failures.append("%s is missing contract token: %s" % [path, required_token])

	var ai_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/TacticalCombatAI.gd")
	for required_token in [
		"CombatPerceptionSnapshot",
		"CombatIntent",
		"decision_trace",
		"snapshot_revision",
		"current_request",
	]:
		if ai_source.find(required_token) == -1:
			failures.append("TacticalCombatAI.gd is missing evaluator contract token: %s" % required_token)
	if ai_source.find("var target:") != -1 or ai_source.find("var target =") != -1:
		failures.append("TacticalCombatAI.gd still exposes a mutable global target field.")
	var provider_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatLegalRequestProvider.gd")
	var planner_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatBoundedPlanner.gd")
	var projection_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatPlanningProjectionService.gd")
	if provider_source.find("ai_tags") == -1 or planner_source.find("_request_ai_tags") == -1:
		failures.append("AI request generation is not catalog/tag driven.")
	for source_entry in [provider_source, planner_source, projection_source]:
		if source_entry.find("action_id in [") != -1:
			failures.append("AI planning still owns a hard-coded action array.")
	for retired_token in ["aimed_strike", "aimed_fire", "disengage", "clear_malfunction"]:
		if provider_source.find(retired_token) != -1 or planner_source.find(retired_token) != -1 or projection_source.find(retired_token) != -1:
			failures.append("AI planning still depends on retired action: %s" % retired_token)
	var definition_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatActionDefinition.gd")
	if definition_source.find("planning_outcome") == -1:
		failures.append("CombatActionDefinition.gd is missing authored planning outcome metadata.")

	if failures.is_empty():
		print("COMBAT_AI_ARCHITECTURE_CONTRACT_SMOKE: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("[COMBAT_AI_CONTRACT] " + failure)
	push_error("COMBAT_AI_ARCHITECTURE_CONTRACT_SMOKE: FAIL")
	quit(1)
