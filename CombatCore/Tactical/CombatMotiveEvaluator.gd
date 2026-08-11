extends RefCounted
class_name CombatMotiveEvaluator

const _Candidate := preload("res://CombatCore/Tactical/CombatMotiveCandidate.gd")
const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")

const MOTIVES := [
	"SURVIVE", "ESCAPE", "SUBMIT", "DEESCALATE", "PROTECT", "SUPPORT", "HOLD", "PRESSURE", "ATTACK", "PURSUE",
]
const DEFAULT_SWITCH_MARGIN := 0.15


static func evaluate(snapshot, hard_state, profile_data = {}, previous_motive: String = "", previous_subject_id: String = "") -> Array:
	var candidates: Array = []
	if snapshot == null:
		return candidates
	var self_id := str(snapshot.actor.get("actor_id", ""))
	var motive_weights: Dictionary = _dictionary_value(profile_data, "motive_weights", {})
	if motive_weights.is_empty():
		motive_weights = _dictionary_value(profile_data, "combat_weights", {})
	var instruction := "" if bool(snapshot.actor.get("mindless", false)) else str(snapshot.communication.get("accepted_order", "")).to_lower()
	for motive in MOTIVES:
		var subjects: Array = _subjects_for(snapshot, motive, self_id)
		for subject in subjects:
			var candidate = _Candidate.new()
			candidate.motive = motive
			candidate.subject_type = str(subject.get("type", "self"))
			candidate.subject_id = str(subject.get("id", self_id))
			candidate.base_weight = float(motive_weights.get(motive.to_lower(), motive_weights.get(motive, _default_weight(motive))))
			candidate.state_modifiers = _state_modifiers(motive, hard_state, snapshot)
			candidate.instruction_modifiers = _instruction_modifiers(motive, instruction)
			candidate.subject_modifiers = _subject_modifiers(snapshot, subject, motive)
			candidate.inertia_modifier = _inertia_modifier(candidate, previous_motive, previous_subject_id, profile_data)
			candidate.feasible = _is_feasible(snapshot, hard_state, candidate, subject)
			candidate.reason_tags.append_array(candidate.state_modifiers.keys())
			candidate.reason_tags.append_array(candidate.instruction_modifiers.keys())
			candidate.reason_tags.append_array(candidate.subject_modifiers.keys())
			if candidate.feasible:
				candidate.score = (
					candidate.base_weight
					+ _sum_values(candidate.state_modifiers)
					+ _sum_values(candidate.instruction_modifiers)
					+ _sum_values(candidate.subject_modifiers)
					+ candidate.inertia_modifier
				)
			candidates.append(candidate)
	_candidates_sort(candidates)
	return candidates


static func select(candidates: Array, profile_data = {}, current_motive: String = "", current_subject_id: String = ""):
	var feasible: Array = []
	for candidate in candidates:
		if candidate != null and candidate.feasible:
			feasible.append(candidate)
	if feasible.is_empty():
		return null
	_candidates_sort(feasible)
	var best = feasible[0]
	if not current_motive.is_empty():
		for candidate in feasible:
			if candidate.motive == current_motive and candidate.subject_id == current_subject_id:
				var margin: float = float(_dictionary_value(profile_data, "motive_switch_margin", DEFAULT_SWITCH_MARGIN))
				if best.score - candidate.score <= margin:
					return candidate
				break
	return best


static func _subjects_for(snapshot, motive: String, self_id: String) -> Array:
	var subjects: Array = []
	if motive in ["SURVIVE", "ESCAPE", "SUBMIT", "DEESCALATE", "HOLD"]:
		subjects.append({"type": "self", "id": self_id})
	for actor_id in snapshot.known_actors.keys():
		var observed = snapshot.known_actors[actor_id]
		if str(actor_id) == self_id:
			continue
		if str(observed.visible_condition) in ["dead", "incapacitated"]:
			continue
		var relation: int = int(observed.relation)
		var knowledge: String = str(observed.knowledge_state)
		if knowledge == "unknown":
			continue
		if motive in ["ATTACK", "PRESSURE", "PURSUE"] and relation == _RelationshipLedger.Relation.HOSTILE:
			subjects.append({"type": "actor", "id": str(actor_id), "relation": relation, "knowledge": knowledge})
		elif motive in ["PROTECT", "SUPPORT"] and relation == _RelationshipLedger.Relation.FRIENDLY:
			subjects.append({"type": "actor", "id": str(actor_id), "relation": relation, "knowledge": knowledge})
		elif motive in ["SUBMIT", "DEESCALATE"] and relation != _RelationshipLedger.Relation.FRIENDLY:
			subjects.append({"type": "actor", "id": str(actor_id), "relation": relation, "knowledge": knowledge})
	return subjects


static func _is_feasible(snapshot, hard_state, candidate, subject: Dictionary) -> bool:
	if hard_state != null and _hard_tags(hard_state).has("INACTIVE"):
		return false
	if hard_state != null and _hard_tags(hard_state).has("BROKEN") and candidate.motive not in ["SUBMIT", "DEESCALATE", "SURVIVE"]:
		return false
	if candidate.motive in ["ATTACK", "PRESSURE", "PURSUE", "PROTECT", "SUPPORT", "SUBMIT", "DEESCALATE"]:
		return not str(subject.get("id", "")).is_empty() and subject.get("type", "") == "actor"
	return true


static func _state_modifiers(motive: String, hard_state, snapshot) -> Dictionary:
	var result: Dictionary = {}
	if hard_state == null:
		return result
	var tags := _hard_tags(hard_state)
	if "CRITICAL" in tags and motive in ["SURVIVE", "ESCAPE", "SUBMIT"]:
		result["critical_pressure"] = 3.0
	if "THREATENED" in tags and motive in ["SURVIVE", "ESCAPE", "ATTACK", "PURSUE"]:
		result["immediate_threat"] = 1.5
	if "ENGAGED" in tags and motive in ["ATTACK", "PRESSURE", "HOLD"]:
		result["engagement_ready"] = 1.0
	var pressure := float(snapshot.actor.get("survival_pressure", 0.0))
	if motive in ["SURVIVE", "ESCAPE"]:
		result["survival_pressure"] = pressure * 0.25
	return result


static func _instruction_modifiers(motive: String, instruction: String) -> Dictionary:
	var result: Dictionary = {}
	if instruction.is_empty():
		return result
	var mapping := {
		"offense": ["ATTACK", "PRESSURE"],
		"defense": ["HOLD", "SURVIVE", "PROTECT"],
		"support": ["SUPPORT", "PROTECT"],
		"flee": ["ESCAPE", "SURVIVE"],
	}
	if instruction in mapping and motive in mapping[instruction]:
		result["accepted_instruction"] = 2.0
	return result


static func _subject_modifiers(snapshot, subject: Dictionary, motive: String) -> Dictionary:
	var result: Dictionary = {}
	if subject.get("type", "") != "actor":
		return result
	var observed = snapshot.known_actors.get(str(subject.get("id", "")))
	if observed == null:
		return result
	if observed.engagement and motive in ["ATTACK", "PRESSURE"]:
		result["engaged_subject"] = 1.0
	if observed.threat_estimate > 0.0 and motive in ["SURVIVE", "ESCAPE", "ATTACK"]:
		result["threat_estimate"] = observed.threat_estimate
	if observed.distance >= 0 and motive in ["ATTACK", "PRESSURE", "PURSUE", "PROTECT", "SUPPORT"]:
		# Deterministic subject priority comes from the observation, never from a
		# mutable global target.  Nearer known subjects are easier to validate and
		# less likely to invalidate a bounded plan before submission.
		result["proximity"] = 1.0 / maxf(1.0, float(observed.distance))
	return result


static func _inertia_modifier(candidate, previous_motive: String, previous_subject_id: String, profile_data) -> float:
	if candidate.motive == previous_motive and candidate.subject_id == previous_subject_id:
		return float(_dictionary_value(profile_data, "motive_inertia", DEFAULT_SWITCH_MARGIN))
	return 0.0


static func _default_weight(motive: String) -> float:
	return 1.0 if motive in ["SURVIVE", "HOLD", "ATTACK"] else 0.0


static func _dictionary_value(source, key: String, fallback):
	if source is Dictionary:
		return source.get(key, fallback)
	if source != null and source.has_method("get"):
		return source.get(key) if source.get(key) != null else fallback
	return fallback


static func _sum_values(values: Dictionary) -> float:
	var total := 0.0
	for value in values.values():
		total += float(value)
	return total


static func _hard_tags(hard_state) -> Array:
	if hard_state is Dictionary:
		return hard_state.get("tags", [])
	return hard_state.tags if hard_state != null else []


static func _candidates_sort(candidates: Array) -> void:
	candidates.sort_custom(func(left, right):
		if not is_equal_approx(left.score, right.score):
			return left.score > right.score
		if left.motive != right.motive:
			return MOTIVES.find(left.motive) < MOTIVES.find(right.motive)
		return left.subject_id < right.subject_id
	)
