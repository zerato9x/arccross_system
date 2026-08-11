extends RefCounted
class_name CombatTacticalProblemClassifier

const _Problem := preload("res://CombatCore/Tactical/CombatTacticalProblem.gd")
const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")


static func classify(snapshot, hard_state, motive_candidate):
	var problem = _Problem.new()
	if motive_candidate != null:
		problem.motive = motive_candidate.motive
		problem.subject_type = motive_candidate.subject_type
		problem.subject_id = motive_candidate.subject_id
		problem.feasible = motive_candidate.feasible
	if snapshot == null or motive_candidate == null or not motive_candidate.feasible:
		problem.problem_id = _Problem.SUBJECT_INVALID
		problem.reason_tags.append("infeasible_subject")
		return problem
	var tags: Array = _hard_tags(hard_state)
	if "INACTIVE" in tags or ("BROKEN" in tags and motive_candidate.motive not in ["SURVIVE", "SUBMIT", "DEESCALATE"]):
		problem.problem_id = _Problem.NO_LEGAL_ACTION
		problem.terminal = true
		problem.reason_tags.append("terminal_state")
		return problem
	if motive_candidate.motive == "ESCAPE" and "ENGAGED" in tags:
		return _finish(problem, _Problem.NEED_BREAK_ENGAGEMENT, "engaged_escape")
	if motive_candidate.motive in ["SURVIVE", "ESCAPE"]:
		if "CRITICAL" in tags or "THREATENED" in tags:
			return _finish(problem, _Problem.NEED_RETREAT, "survival_pressure")
		return _finish(problem, _Problem.READY, "stable_survival")
	if motive_candidate.motive in ["HOLD"]:
		return _finish(problem, _Problem.NEED_COVER if "EXPOSED" in tags else _Problem.READY, "hold_position")
	if motive_candidate.motive in ["PROTECT", "SUPPORT"]:
		var support_target = snapshot.known_actors.get(motive_candidate.subject_id)
		if support_target == null or str(support_target.knowledge_state) == "unknown":
			return _finish(problem, _Problem.NEED_POSITION, "subject_not_observable")
		return _finish(problem, _Problem.READY, "support_subject_observable")
	if motive_candidate.motive in ["SUBMIT", "DEESCALATE"]:
		return _finish(problem, _Problem.READY, "communication_or_surrender")
	if motive_candidate.motive in ["ATTACK", "PRESSURE", "PURSUE"]:
		return _attack_problem(snapshot, problem)
	return _finish(problem, _Problem.NO_LEGAL_ACTION, "motive_without_problem_classifier")


static func _attack_problem(snapshot, problem):
	var target = snapshot.known_actors.get(problem.subject_id)
	if target == null or str(target.knowledge_state) == "unknown":
		return _finish(problem, _Problem.SUBJECT_INVALID, "target_not_observable")
	var weapon: Dictionary = snapshot.actor.get("weapon", {})
	var distance := int(target.distance)
	if distance < 0:
		return _finish(problem, _Problem.NEED_POSITION, "target_position_unknown")
	if bool(weapon.get("ranged", false)):
		if bool(weapon.get("jammed", false)):
			return _finish(problem, _Problem.NEED_UNJAM, "weapon_jammed")
		if bool(weapon.get("requires_ready_action", false)) and not bool(weapon.get("is_readied", false)):
			return _finish(problem, _Problem.NEED_READY, "weapon_not_readied")
		if int(weapon.get("current_magazine", 0)) <= 0:
			return _finish(problem, _Problem.NEED_RELOAD, "weapon_empty")
		if distance > int(weapon.get("maximum_range_cells", 0)):
			return _finish(problem, _Problem.NEED_RANGE, "target_outside_weapon_range")
		if not bool(target.line_of_sight):
			return _finish(problem, _Problem.NEED_LINE_OF_FIRE, "blocked_line_of_sight")
		return _finish(problem, _Problem.READY, "ranged_attack_ready")
	var reach := int(weapon.get("reach_cells", 0))
	if distance > reach:
		return _finish(problem, _Problem.NEED_ENGAGE, "ordinary_melee_requires_engagement")
	return _finish(problem, _Problem.READY, "melee_reach_ready")


static func _finish(problem, id: String, reason: String):
	problem.problem_id = id
	problem.reason_tags.append(reason)
	return problem


static func _hard_tags(hard_state) -> Array:
	if hard_state is Dictionary:
		return hard_state.get("tags", [])
	return hard_state.tags if hard_state != null else []
