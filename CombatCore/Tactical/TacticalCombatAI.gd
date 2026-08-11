extends Node
class_name TacticalCombatAI

const MAX_ACTIONS_PER_TURN := 6
const MAX_STALE_REEVALUATIONS := 3

const _NpcBehaviorState := preload("res://SystemCore/NpcBehaviorState.gd")
const _NpcBehaviorCatalog := preload("res://SystemCore/NpcBehaviorProfileCatalog.gd")
const _RulesState := preload("res://CombatCore/Tactical/CombatRulesState.gd")
const _PerceptionBuilder := preload("res://CombatCore/Tactical/CombatPerceptionBuilder.gd")
const _HardStateClassifier := preload("res://CombatCore/Tactical/CombatHardStateClassifier.gd")
const _MotiveEvaluator := preload("res://CombatCore/Tactical/CombatMotiveEvaluator.gd")
const _MotiveCandidate := preload("res://CombatCore/Tactical/CombatMotiveCandidate.gd")
const _ProblemClassifier := preload("res://CombatCore/Tactical/CombatTacticalProblemClassifier.gd")
const _Problem := preload("res://CombatCore/Tactical/CombatTacticalProblem.gd")
const _RequestProvider := preload("res://CombatCore/Tactical/CombatLegalRequestProvider.gd")
const _Planner := preload("res://CombatCore/Tactical/CombatBoundedPlanner.gd")
const _Plan := preload("res://CombatCore/Tactical/CombatPlanCandidate.gd")
const _UtilityEvaluator := preload("res://CombatCore/Tactical/CombatUtilityEvaluator.gd")
const _Intent := preload("res://CombatCore/Tactical/CombatIntent.gd")
const _DecisionTrace := preload("res://CombatCore/Tactical/CombatDecisionTrace.gd")

signal decision_trace_updated(actor_id: String, trace: Array)
signal intent_changed(actor_id: String, intent_view: Dictionary)

var actor: HumanoidCore
var controller: CombatActionController
var board: CombatBoard
var turn_manager: TacticalTurnManager
var behavior_state: Resource
var behavior_profile: Resource
var behavior_projection: Dictionary = {}

## These are the current publication records, not mutable target state.  A
## target exists only inside CombatIntent.current_request and its trace.
var current_intent
var current_request: CombatActionRequest
var snapshot_revision: int = -1
var decision_trace: Array[Dictionary] = []

var _running := false
var _intent_revision := 0
var _observation_memory: Dictionary = {}
var _last_evaluation: Dictionary = {}


func configure(
	ai_actor: HumanoidCore,
	action_controller: CombatActionController,
	tactical_board: CombatBoard,
	turns: TacticalTurnManager
) -> void:
	actor = ai_actor
	controller = action_controller
	board = tactical_board
	turn_manager = turns
	var behavior_payload: Dictionary = actor.get_meta("npc_behavior_state", {})
	behavior_state = _NpcBehaviorState.from_runtime(
		{_NpcBehaviorState.RUNTIME_KEY: behavior_payload},
		actor.definition.to_state() if actor.definition != null else {}
	)
	var behavior_catalog: Resource = _NpcBehaviorCatalog.load_default()
	behavior_profile = (
		behavior_catalog.profile_for_id(behavior_state.profile_id)
		if behavior_catalog != null
		else null
	)
	behavior_projection = (
		behavior_profile.combat_projection()
		if behavior_profile != null and behavior_profile.has_method("combat_projection")
		else {}
	)
	var memory: Dictionary = behavior_state.decision_memory if behavior_state != null else {}
	_intent_revision = maxi(_intent_revision, int(behavior_state.last_intent_revision if behavior_state != null else memory.get("last_intent_revision", 0)))
	if not turn_manager.turn_started.is_connected(_on_turn_started):
		turn_manager.turn_started.connect(_on_turn_started)
	if turn_manager.get_active_entity() == actor:
		call_deferred("_take_turn")


func _on_turn_started(active_actor: HumanoidCore) -> void:
	if active_actor != actor or _running:
		return
	call_deferred("_take_turn")


## Public evaluator seam used by lab tooling and deterministic smoke tests.
## It returns projections only; submitting an action remains the sole path that
## can cross into the live controller.
func evaluate_decision(trigger: String = "manual") -> Dictionary:
	if actor == null or controller == null or turn_manager == null:
		return {}
	var evaluation := _evaluate_once(trigger)
	_last_evaluation = evaluation
	return evaluation.duplicate(true)


func _take_turn() -> void:
	if _running or actor == null or controller == null or turn_manager == null:
		return
	_running = true
	decision_trace.clear()
	var actions_taken := 0
	var stale_evaluations := 0
	var last_progress_signature := ""
	while (
		actions_taken < MAX_ACTIONS_PER_TURN
		and turn_manager.get_active_entity() == actor
		and turn_manager.current_ap_pool > 0
		and not actor.is_dead
		and not actor.is_comatose
	):
		while controller.is_presentation_locked() and turn_manager.get_active_entity() == actor:
			await get_tree().process_frame
		if turn_manager.get_active_entity() != actor:
			break

		var evaluation := _evaluate_once("turn")
		_last_evaluation = evaluation
		var intent = evaluation.get("intent")
		var trace = evaluation.get("trace")
		if intent == null or trace == null:
			await _submit_end_turn("no_intent")
			break
		_publish_intent(intent)
		if not controller.is_revision_current(int(intent.snapshot_revision)):
			stale_evaluations += 1
			trace.reevaluation_reason = "stale_revision_before_request"
			trace.ending_reason = "reevaluate"
			decision_trace.append(trace.to_dict())
			if stale_evaluations >= MAX_STALE_REEVALUATIONS:
				await _submit_end_turn("repeated_stale_revision")
				break
			continue
		stale_evaluations = 0

		var request: CombatActionRequest = intent.current_request
		if request == null:
			trace.ending_reason = "missing_request"
			decision_trace.append(trace.to_dict())
			await _submit_end_turn("missing_request")
			break

		var before := _progress_signature()
		var outcome: CombatActionOutcome = await controller.request_action(request)
		actions_taken += 1
		trace.outcome = outcome.to_dict() if outcome != null else {}
		var after := _progress_signature()
		if outcome != null:
			# The controller owns the authoritative outcome; the trace is attached
			# as replay/debug evidence only.
			outcome.decision_trace = decision_trace.duplicate(true)

		if outcome == null or not outcome.committed:
			trace.ending_reason = "resolution_failed"
			decision_trace.append(trace.to_dict())
			await _submit_end_turn("resolution_failed")
			break
		_persist_decision_memory(intent, outcome, trace)
		if request.action_id == "end_turn":
			trace.ending_reason = "explicit_end_turn"
			decision_trace.append(trace.to_dict())
			break
		if after == before or after == last_progress_signature:
			trace.ending_reason = "no_progress"
			decision_trace.append(trace.to_dict())
			await _submit_end_turn("no_progress")
			break
		trace.ending_reason = "request_committed"
		decision_trace.append(trace.to_dict())
		last_progress_signature = after

	if turn_manager.get_active_entity() == actor and turn_manager.current_ap_pool > 0:
		await _submit_end_turn("action_limit")
	decision_trace_updated.emit(_actor_id(actor), decision_trace.duplicate(true))
	_running = false


## Compatibility surface for older callers.  Requests are now generated by
## the catalog-backed provider for the current selected motive/problem rather
## than by an AI-owned action array.
func enumerate_requests() -> Array[CombatActionRequest]:
	var result: Array[CombatActionRequest] = []
	if actor == null or controller == null or turn_manager == null:
		return result
	var evaluation := _evaluate_once("request_enumeration")
	_last_evaluation = evaluation
	for request in evaluation.get("legal_requests", []):
		if request is CombatActionRequest:
			result.append(request)
	if not result.any(func(candidate: CombatActionRequest) -> bool: return candidate.action_id == "end_turn"):
		var end_turn := _end_turn_request()
		if controller.projected_quote(end_turn).legal:
			result.append(end_turn)
	return result


func _evaluate_once(trigger: String) -> Dictionary:
	var rules_state = controller.rules_state_snapshot()
	# CombatPerceptionSnapshot is the immutable observation boundary for every
	# downstream evaluator in this method.
	var perception_snapshot = _PerceptionBuilder.build(
		rules_state,
		_actor_id(actor),
		_observation_memory,
		current_intent.to_dict() if current_intent != null else {},
		trigger
	)
	var hard_state = _HardStateClassifier.classify(perception_snapshot)
	var previous_motive := str(
		behavior_state.current_motive
		if behavior_state != null
		else ""
	)
	var previous_subject_id := str(
		behavior_state.current_subject_id
		if behavior_state != null
		else ""
	)
	var motives: Array = _MotiveEvaluator.evaluate(
		perception_snapshot,
		hard_state,
		behavior_projection,
		previous_motive,
		previous_subject_id
	)
	var selected_motive = _MotiveEvaluator.select(
		motives,
		behavior_projection,
		previous_motive,
		previous_subject_id
	)
	var problem = _ProblemClassifier.classify(perception_snapshot, hard_state, selected_motive)
	var generated: Dictionary = {"requests": [], "quotes": [], "denials": []}
	if selected_motive != null and not problem.terminal:
		generated = _RequestProvider.generate(
			perception_snapshot,
			selected_motive,
			problem,
			rules_state,
			behavior_projection
		)
	var plans: Array = []
	if selected_motive != null and not problem.terminal:
		plans = _Planner.plan(
			perception_snapshot,
			selected_motive,
			problem,
			rules_state,
			behavior_projection
		)
	if plans.is_empty():
		plans.append(_fallback_plan(rules_state))
	var utility_evaluations: Array[Dictionary] = []
	for plan in plans:
		var utility: Dictionary = _UtilityEvaluator.evaluate_plan(
			plan,
			perception_snapshot,
			selected_motive,
			problem,
			behavior_projection
		)
		plan.component_scores = utility
		utility_evaluations.append({
			"terminal_action": plan.terminal_action,
			"sort_key": plan.sort_key,
			"total": float(utility.get("total", 0.0)),
			"components": utility.get("components", {}),
			"weighted_components": utility.get("weighted_components", {}),
		})
	plans.sort_custom(func(left, right):
		var left_score := float(left.component_scores.get("total", 0.0))
		var right_score := float(right.component_scores.get("total", 0.0))
		if not is_equal_approx(left_score, right_score):
			return left_score > right_score
		return left.sort_key < right.sort_key
	)
	var selected_plan = plans[0] if not plans.is_empty() else null
	var intent = _build_intent(
		perception_snapshot,
		selected_motive,
		problem,
		selected_plan,
		rules_state
	)
	var trace = _build_trace(
		perception_snapshot,
		hard_state,
		motives,
		selected_motive,
		problem,
		plans,
		utility_evaluations,
		generated,
		intent,
		rules_state,
		trigger
	)
	return {
		"rules_state": rules_state,
		"snapshot": perception_snapshot,
		"hard_state": hard_state,
		"motive_candidates": motives,
		"selected_motive": selected_motive,
		"problem": problem,
		"plans": plans,
		"intent": intent,
		"trace": trace,
		"legal_requests": generated.get("requests", []),
	}


func _build_intent(perception_snapshot, selected_motive, problem, selected_plan, rules_state):
	var intent = _Intent.new()
	intent.actor_id = _actor_id(actor)
	intent.snapshot_revision = int(perception_snapshot.revision)
	_intent_revision += 1
	intent.intent_revision = _intent_revision
	intent.decision_seed = "%s|%s|%d|%d" % [
		str(rules_state.encounter_seed),
		intent.actor_id,
		int(rules_state.round),
		intent.snapshot_revision,
	]
	if selected_motive != null:
		intent.motive = selected_motive.motive
		intent.subject_type = selected_motive.subject_type
		intent.subject_id = selected_motive.subject_id
		intent.score = selected_motive.score
	if problem != null:
		intent.tactical_problem = problem.problem_id
		intent.reason_tags.append_array(problem.reason_tags)
	if selected_plan != null:
		intent.plan = selected_plan
		var utility_total := float(selected_plan.component_scores.get("total", 0.0))
		intent.score = utility_total
		if not selected_plan.steps.is_empty():
			intent.current_request = selected_plan.steps[0]
	if intent.current_request == null:
		intent.current_request = _end_turn_request()
	if intent.current_request != null:
		intent.target_actor_id = intent.current_request.target_actor_id
		intent.target_sector = intent.current_request.target_sector
	if intent.target_actor_id.is_empty() and intent.subject_type == "actor":
		intent.target_actor_id = intent.subject_id
	var hard_facts: Dictionary = perception_snapshot.hard_facts
	for raw_tag in hard_facts.get("tags", []):
		if str(raw_tag) not in intent.reason_tags:
			intent.reason_tags.append(str(raw_tag))
	return intent


func _build_trace(
	perception_snapshot,
	hard_state,
	motives: Array,
	selected_motive,
	problem,
	plans: Array,
	utility_evaluations: Array[Dictionary],
	generated: Dictionary,
	intent,
	rules_state,
	trigger: String
):
	var trace = _DecisionTrace.new()
	trace.actor_id = _actor_id(actor)
	trace.snapshot_revision = int(perception_snapshot.revision)
	trace.reevaluation_trigger = trigger
	trace.hard_state_tags = hard_state.tags.duplicate() if hard_state != null else []
	trace.dominant_hard_state = hard_state.dominant_tag if hard_state != null else ""
	for candidate in motives:
		trace.motive_candidates.append(candidate.to_dict())
	if selected_motive != null:
		trace.chosen_motive = selected_motive.motive
		trace.chosen_subject_type = selected_motive.subject_type
		trace.chosen_subject_id = selected_motive.subject_id
	trace.tactical_problem = problem.to_dict() if problem != null else {}
	for plan in plans:
		trace.plan_candidates.append(plan.to_dict())
	trace.utility_components = utility_evaluations.duplicate(true)
	if not plans.is_empty():
		trace.selected_plan = plans[0].to_dict()
	for quote in generated.get("quotes", []):
		trace.quote_evidence.append({
			"action_id": quote.action_id,
			"legal": quote.legal,
			"ap_cost": quote.ap_cost,
			"denial_code": quote.denial_code,
		})
	for denial in generated.get("denials", []):
		trace.quote_evidence.append(denial.duplicate(true))
	trace.intent = intent.to_dict() if intent != null else {}
	trace.first_request = intent.current_request.to_dict() if intent != null and intent.current_request != null else {}
	trace.deterministic_seed = intent.decision_seed if intent != null else str(rules_state.encounter_seed)
	trace.tie_break_key = str(plans[0].sort_key) if not plans.is_empty() else "999|end_turn"
	return trace


func _fallback_plan(rules_state):
	var plan = _Plan.new()
	var request := _end_turn_request()
	var quote: CombatActionQuote = controller.projected_quote(request, rules_state)
	plan.steps.append(request)
	plan.quotes.append(quote)
	plan.terminal_action = request.action_id
	plan.sort_key = "999|end_turn"
	return plan


func _end_turn_request() -> CombatActionRequest:
	var request := CombatActionRequest.new()
	request.actor_id = _actor_id(actor)
	request.action_id = "end_turn"
	return request


func _submit_end_turn(_reason: String) -> void:
	if turn_manager == null or turn_manager.get_active_entity() != actor:
		return
	var request := _end_turn_request()
	var quote := controller.projected_quote(request)
	if quote.legal:
		await controller.request_action(request)
	else:
		turn_manager.pass_turn(actor)


func _publish_intent(intent) -> void:
	current_intent = intent
	current_request = intent.current_request
	snapshot_revision = int(intent.snapshot_revision)
	var view = intent.to_view(
		str(behavior_profile.profile_id)
		if behavior_profile != null
		else ""
	)
	if controller != null and controller.has_method("publish_intent_view"):
		controller.publish_intent_view(_actor_id(actor), view.to_dict())
	else:
		actor.set_meta("combat_intent_view", view.to_dict())
	intent_changed.emit(_actor_id(actor), view.to_dict())


func _persist_decision_memory(intent, outcome: CombatActionOutcome, trace) -> void:
	if behavior_state == null or actor == null:
		return
	var memory: Dictionary = behavior_state.decision_memory if behavior_state.decision_memory is Dictionary else {}
	memory["current_motive"] = intent.motive
	memory["current_subject_id"] = intent.subject_id
	memory["last_intent_revision"] = intent.intent_revision
	behavior_state.current_motive = intent.motive
	behavior_state.current_subject_id = intent.subject_id
	behavior_state.last_intent_revision = intent.intent_revision
	memory["last_action_id"] = outcome.action_id if outcome != null else "end_turn"
	memory["last_target_id"] = intent.target_actor_id
	memory["last_committed"] = outcome != null and outcome.committed
	memory["last_round"] = turn_manager.current_round
	behavior_state.decision_memory = memory
	behavior_state.last_decision_trace = trace.compact_summary()
	actor.set_meta("npc_behavior_state", behavior_state.to_dict())


func _progress_signature() -> String:
	var tactical_state := board.combat_state(actor) if board != null else null
	return "%d|%d|%.3f|%s|%d" % [
		turn_manager.current_ap_pool,
		board.position_of(actor) if board != null else -1,
		tactical_state.stance if tactical_state != null else 0.0,
		str(actor.get_meta("combat_surrendered", false)),
		controller.combat_revision if controller != null else -1,
	]


func _actor_id(value: HumanoidCore) -> String:
	return "" if value == null else str(value.get_meta("actor_id", value.name))
