extends SceneTree

const _Snapshot := preload("res://CombatCore/Tactical/CombatPerceptionSnapshot.gd")
const _Observed := preload("res://CombatCore/Tactical/CombatObservedActor.gd")
const _Evaluator := preload("res://CombatCore/Tactical/CombatMotiveEvaluator.gd")
const _Ledger := preload("res://SystemCore/CombatRelationshipLedger.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot = _Snapshot.new()
	snapshot.actor = {"actor_id": "alpha", "mindless": false, "survival_pressure": 0.0}
	snapshot.communication = {"accepted_order": "offense"}
	snapshot.hard_facts = {"tags": ["THREATENED"], "dominant_tag": "THREATENED"}
	var bravo = _Observed.new()
	bravo.actor_id = "bravo"
	bravo.knowledge_state = "visible"
	bravo.relation = _Ledger.Relation.HOSTILE
	bravo.threat_estimate = 0.8
	var charlie = _Observed.new()
	charlie.actor_id = "charlie"
	charlie.knowledge_state = "visible"
	charlie.relation = _Ledger.Relation.HOSTILE
	charlie.threat_estimate = 0.8
	snapshot.known_actors = {"alpha": _self_observed(), "bravo": bravo, "charlie": charlie}
	var profile := {"motive_weights": {"attack": 10.0, "survive": 0.0}, "motive_switch_margin": 0.15}
	var candidates: Array = _Evaluator.evaluate(snapshot, _hard_state(), profile)
	var selected = _Evaluator.select(candidates, profile)
	if selected == null or selected.motive != "ATTACK" or selected.subject_id != "bravo":
		return _fail("Motive evaluator did not select the stable first hostile subject.")
	var repeated: Array = _Evaluator.evaluate(snapshot, _hard_state(), profile)
	if _candidate_fingerprint(candidates) != _candidate_fingerprint(repeated):
		return _fail("Motive-subject ordering was not deterministic.")
	var neutral_snapshot = _Snapshot.new()
	neutral_snapshot.actor = {"actor_id": "neutral", "mindless": false, "survival_pressure": 0.0}
	neutral_snapshot.communication = {"accepted_order": ""}
	neutral_snapshot.hard_facts = {"tags": ["STABLE"], "dominant_tag": "STABLE"}
	neutral_snapshot.known_actors = {"neutral": _self_observed()}
	var neutral_candidates: Array = _Evaluator.evaluate(
		neutral_snapshot,
		{"tags": ["STABLE"], "dominant_tag": "STABLE"},
		{"motive_weights": {"hold": 100.0, "attack": 100.0}}
	)
	var neutral_selected = _Evaluator.select(neutral_candidates, {"motive_weights": {"hold": 100.0, "attack": 100.0}})
	if neutral_selected == null or neutral_selected.motive != "EXIT":
		return _fail("Uncommitted neutral actor did not select EXIT as a precedence rule.")
	var mindless_snapshot = _Snapshot.new()
	var mindless_actor: Dictionary = snapshot.actor
	mindless_actor["mindless"] = true
	mindless_snapshot.actor = mindless_actor
	mindless_snapshot.communication = {"accepted_order": "flee"}
	mindless_snapshot.hard_facts = snapshot.hard_facts
	mindless_snapshot.known_actors = snapshot.known_actors
	var mindless: Array = _Evaluator.evaluate(mindless_snapshot, _hard_state(), profile)
	for candidate in mindless:
		if not candidate.instruction_modifiers.is_empty():
			return _fail("Mindless actor accepted a communication instruction bias.")
	print("COMBAT_AI_MOTIVE_SMOKE: PASS")
	quit(0)


func _self_observed():
	var observed = _Observed.new()
	observed.actor_id = "alpha"
	observed.knowledge_state = "self"
	observed.relation = _Ledger.Relation.FRIENDLY
	return observed


func _hard_state():
	return {"tags": ["THREATENED"], "dominant_tag": "THREATENED"}


func _candidate_fingerprint(candidates: Array) -> String:
	var result: Array[String] = []
	for candidate in candidates:
		if candidate.feasible:
			result.append("%s|%s|%.3f" % [candidate.motive, candidate.subject_id, candidate.score])
	return "\n".join(result)


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_MOTIVE] " + message)
	quit(1)
	return false
