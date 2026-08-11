extends SceneTree

const _Snapshot := preload("res://CombatCore/Tactical/CombatPerceptionSnapshot.gd")
const _Observed := preload("res://CombatCore/Tactical/CombatObservedActor.gd")
const _Candidate := preload("res://CombatCore/Tactical/CombatMotiveCandidate.gd")
const _Classifier := preload("res://CombatCore/Tactical/CombatTacticalProblemClassifier.gd")
const _Problem := preload("res://CombatCore/Tactical/CombatTacticalProblem.gd")
const _Ledger := preload("res://SystemCore/CombatRelationshipLedger.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot = _Snapshot.new()
	snapshot.actor = {"actor_id": "alpha", "weapon": {"ranged": false, "reach_cells": 0}}
	var target = _Observed.new()
	target.actor_id = "bravo"
	target.knowledge_state = "visible"
	target.relation = _Ledger.Relation.HOSTILE
	target.distance = 1
	target.line_of_sight = true
	snapshot.known_actors = {"bravo": target}
	var attack = _Candidate.new()
	attack.motive = "ATTACK"
	attack.subject_type = "actor"
	attack.subject_id = "bravo"
	attack.feasible = true
	var problem = _Classifier.classify(snapshot, {"tags": ["STABLE"]}, attack)
	if problem.problem_id != _Problem.NEED_ENGAGE:
		return _fail("Default melee attack did not classify as NEED_ENGAGE.")
	snapshot.actor.weapon = {"ranged": true, "current_magazine": 0, "max_magazine": 6, "maximum_range_cells": 8, "jammed": false}
	problem = _Classifier.classify(snapshot, {"tags": ["OUT_OF_AMMO"]}, attack)
	if problem.problem_id != _Problem.NEED_RELOAD:
		return _fail("Empty firearm did not classify as NEED_RELOAD.")
	snapshot.actor.weapon["current_magazine"] = 3
	snapshot.actor.weapon["jammed"] = true
	problem = _Classifier.classify(snapshot, {"tags": ["WEAPON_DISABLED"]}, attack)
	if problem.problem_id != _Problem.NEED_UNJAM:
		return _fail("Jammed firearm did not classify as NEED_UNJAM.")
	snapshot.actor.weapon["jammed"] = false
	target.line_of_sight = false
	problem = _Classifier.classify(snapshot, {"tags": ["THREATENED"]}, attack)
	if problem.problem_id != _Problem.NEED_LINE_OF_FIRE:
		return _fail("Blocked firearm LOS did not classify as NEED_LINE_OF_FIRE.")
	var escape = _Candidate.new()
	escape.motive = "ESCAPE"
	escape.subject_type = "self"
	escape.subject_id = "alpha"
	escape.feasible = true
	problem = _Classifier.classify(snapshot, {"tags": ["ENGAGED"]}, escape)
	if problem.problem_id != _Problem.NEED_BREAK_ENGAGEMENT:
		return _fail("Engaged Escape did not classify as NEED_BREAK_ENGAGEMENT.")
	print("COMBAT_AI_PROBLEM_SMOKE: PASS")
	quit(0)


func _fail(message: String) -> bool:
	push_error("[COMBAT_AI_PROBLEM] " + message)
	quit(1)
	return false
