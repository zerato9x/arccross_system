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
	for retired_token in ["stand", "crouch", "aimed_strike", "aimed_fire", "power_strike", "disengage", "clear_malfunction", "block", "dodge", "opportunity_strike"]:
		var action_literal := '"%s"' % retired_token
		if provider_source.find(action_literal) != -1 or planner_source.find(action_literal) != -1 or projection_source.find(action_literal) != -1:
			failures.append("AI planning still depends on retired action: %s" % retired_token)
	var definition_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatActionDefinition.gd")
	if definition_source.find("planning_outcome") == -1:
		failures.append("CombatActionDefinition.gd is missing authored planning outcome metadata.")
	failures.append_array(_interaction_authority_contract_violations())

	if failures.is_empty():
		print("COMBAT_AI_ARCHITECTURE_CONTRACT_SMOKE: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("[COMBAT_AI_CONTRACT] " + failure)
	push_error("COMBAT_AI_ARCHITECTURE_CONTRACT_SMOKE: FAIL")
	quit(1)


func _interaction_authority_contract_violations() -> Array[String]:
	var violations: Array[String] = []
	var hud_path := "res://CombatCore/Tactical/TacticalCombatHUD.gd"
	var scene_path := "res://CombatCore/Tactical/TacticalCombatScene.gd"
	for path in [hud_path, scene_path]:
		var source := FileAccess.get_file_as_string(path)
		for line in source.split("\n"):
			var trimmed := str(line).strip_edges()
			if (trimmed.begins_with("interaction.") or trimmed.begins_with("_interaction_coordinator.state.")) and trimmed.find("=") != -1 and trimmed.find("==") == -1:
				violations.append("%s writes coordinator-owned interaction state directly: %s" % [path, trimmed])
	var arena_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/TacticalArenaView.gd")
	if arena_source.find("sector_selected") != -1:
		violations.append("TacticalArenaView.gd still exposes the retired sector_selected compatibility signal.")
	var state_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatInteractionState.gd")
	for retired_alias in [
		"NAVIGATION = INSPECTING",
		"BUMP_MENU = ACTION_MENU",
		"MOVE_PREVIEW = ROUTE_PREVIEW",
		"TARGET_MENU = ACTION_MENU",
		"AIMING = ACTION_PREVIEW",
		"WEAPON_MENU = ACTION_MENU",
		"SELF_MENU = ACTION_MENU",
		"OBJECT_MENU = ACTION_MENU",
		"SELECTED = INSPECTING",
		"TARGETING = ACTION_PREVIEW",
		"STAGED_PREVIEW = ACTION_PREVIEW",
		"LOCAL_CONFIRMATION = CONFIRMATION",
		"CONTEXT_MENU = ROOT_MENU",
		"COMMUNICATION = COMMUNICATION_MENU",
		"INVENTORY = ACTION_MENU",
		"REACTION = PRESENTING",
	]:
		if state_source.find(retired_alias) != -1:
			violations.append("CombatInteractionState.gd still exposes retired phase alias: %s" % retired_alias)
	var coordinator_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/TacticalCombatInteractionCoordinator.gd")
	for required_method in [
		"state_snapshot",
		"set_route_path",
		"stage_request",
		"take_request",
		"cancel_one_step",
	]:
		if coordinator_source.find("func %s" % required_method) == -1:
			violations.append("Interaction coordinator is missing ownership method: %s" % required_method)
	var controller_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatActionController.gd")
	var quote_source := FileAccess.get_file_as_string("res://CombatCore/Tactical/CombatActionQuoteService.gd")
	if controller_source.find("func _normalized_request") == -1:
		violations.append("CombatActionController has no copied request normalization seam.")
	if controller_source.find("build_forecast") != -1:
		violations.append("CombatActionController still owns a separate forecast implementation.")
	if quote_source.find("CombatForecastService") == -1:
		violations.append("CombatActionQuoteService does not delegate forecast authority to CombatForecastService.")
	return violations
