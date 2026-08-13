extends RefCounted
class_name CombatMotiveEvaluator

const _Candidate := preload("res://CombatCore/Tactical/CombatMotiveCandidate.gd")
const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")

## Canonical motive vocabulary. Legacy profile/save names are hydrated into
## these six values and are never published as a new intent.
const MOTIVES := ["SURVIVE", "EXIT", "SUPPORT", "ATTACK", "HOLD", "COMMUNICATE"]
const DEFAULT_SWITCH_MARGIN := 0.15

const LEGACY_MOTIVE_ALIASES := {
	"ESCAPE": "EXIT",
	"SUBMIT": "COMMUNICATE",
	"DEESCALATE": "COMMUNICATE",
	"PROTECT": "SUPPORT",
	"PRESSURE": "ATTACK",
	"PURSUE": "ATTACK",
}


static func normalize_motive(value: String) -> String:
	var upper := value.to_upper()
	return str(LEGACY_MOTIVE_ALIASES.get(upper, upper)) if upper not in MOTIVES else upper


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
			candidate.base_weight = _weight_for(motive_weights, motive)
			candidate.state_modifiers = _state_modifiers(motive, hard_state, snapshot)
			candidate.instruction_modifiers = _instruction_modifiers(motive, instruction, snapshot)
			candidate.subject_modifiers = _subject_modifiers(snapshot, subject, motive)
			candidate.inertia_modifier = _inertia_modifier(candidate, previous_motive, previous_subject_id, profile_data)
			candidate.feasible = _is_feasible(snapshot, hard_state, candidate, subject)
			candidate.reason_tags.append_array(candidate.state_modifiers.keys())
			candidate.reason_tags.append_array(candidate.instruction_modifiers.keys())
			candidate.reason_tags.append_array(candidate.subject_modifiers.keys())
			if candidate.feasible:
				candidate.score = candidate.base_weight + _sum_values(candidate.state_modifiers) + _sum_values(candidate.instruction_modifiers) + _sum_values(candidate.subject_modifiers) + candidate.inertia_modifier
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
	# Priority is explicit, not an accidental consequence of numeric weights:
	# hard state first, then an authored communication commitment, then motive
	# subject hysteresis and the remaining deterministic score/tie-break order.
	var critical_candidates: Array = []
	for candidate in feasible:
		if candidate.state_modifiers.has("hard_critical_pressure"):
			critical_candidates.append(candidate)
	if not critical_candidates.is_empty():
		feasible = critical_candidates
	var neutral_exit_candidates: Array = []
	for candidate in feasible:
		if candidate.state_modifiers.has("uncommitted_neutral_exit"):
			neutral_exit_candidates.append(candidate)
	if not neutral_exit_candidates.is_empty():
		# A neutral, uncommitted participant has no authored basis for joining
		# the fight.  Keep this as a precedence rule rather than a profile bias,
		# so an extreme HOLD/ATTACK weight cannot turn neutrality into hostility.
		feasible = neutral_exit_candidates
	var committed_candidates: Array = []
	for candidate in feasible:
		if candidate.instruction_modifiers.has("accepted_commitment"):
			committed_candidates.append(candidate)
	if not committed_candidates.is_empty():
		feasible = committed_candidates
	_candidates_sort(feasible)
	var best = feasible[0]
	var normalized_current := normalize_motive(current_motive)
	if not normalized_current.is_empty():
		for candidate in feasible:
			if candidate.motive == normalized_current and candidate.subject_id == current_subject_id:
				var margin := float(_dictionary_value(profile_data, "motive_switch_margin", DEFAULT_SWITCH_MARGIN))
				if best.score - candidate.score <= margin:
					return candidate
				break
	return best


static func _subjects_for(snapshot, motive: String, self_id: String) -> Array:
	var subjects: Array = []
	if motive in ["SURVIVE", "EXIT", "HOLD"]:
		subjects.append({"type": "self", "id": self_id})
	var actor_ids: Array[String] = []
	for actor_id in snapshot.known_actors.keys():
		actor_ids.append(str(actor_id))
	actor_ids.sort()
	for actor_id in actor_ids:
		if actor_id == self_id:
			continue
		var observed = snapshot.known_actors[actor_id]
		if observed == null or str(observed.visible_condition) in ["dead", "incapacitated"] or str(observed.knowledge_state) == "unknown":
			continue
		var relation := int(observed.relation)
		if motive == "ATTACK" and relation == _RelationshipLedger.Relation.HOSTILE:
			subjects.append({"type": "actor", "id": actor_id, "relation": relation})
		elif motive == "SUPPORT" and relation == _RelationshipLedger.Relation.FRIENDLY:
			subjects.append({"type": "actor", "id": actor_id, "relation": relation})
		elif motive == "COMMUNICATE" and relation != _RelationshipLedger.Relation.FRIENDLY:
			subjects.append({"type": "actor", "id": actor_id, "relation": relation})
	return subjects


static func _is_feasible(snapshot, hard_state, candidate, subject: Dictionary) -> bool:
	if hard_state != null and _hard_tags(hard_state).has("INACTIVE"):
		return false
	if hard_state != null and _hard_tags(hard_state).has("BROKEN") and candidate.motive not in ["SURVIVE", "EXIT", "COMMUNICATE"]:
		return false
	if candidate.motive in ["ATTACK", "SUPPORT", "COMMUNICATE"]:
		return subject.get("type", "") == "actor" and not str(subject.get("id", "")).is_empty()
	return true


static func _state_modifiers(motive: String, hard_state, snapshot) -> Dictionary:
	var result: Dictionary = {}
	var tags := _hard_tags(hard_state)
	if "CRITICAL" in tags and motive in ["SURVIVE", "EXIT", "COMMUNICATE"]:
		result["hard_critical_pressure"] = 3.0
	if "THREATENED" in tags and motive in ["SURVIVE", "EXIT", "ATTACK"]:
		result["hard_immediate_threat"] = 1.5
	if "ENGAGED" in tags and motive in ["ATTACK", "HOLD", "EXIT"]:
		result["hard_engagement"] = 1.0
	var pressure := float(snapshot.actor.get("survival_pressure", 0.0))
	if motive in ["SURVIVE", "EXIT"]:
		result["survival_pressure"] = pressure * 0.25
	if motive == "EXIT" and _is_uncommitted_neutral(snapshot):
		result["uncommitted_neutral_exit"] = 4.0
	return result


static func _instruction_modifiers(motive: String, instruction: String, snapshot) -> Dictionary:
	var result: Dictionary = {}
	if instruction.is_empty() or bool(snapshot.actor.get("mindless", false)):
		return result
	var mapping := {
		"offense": ["ATTACK"],
		"defense": ["HOLD", "SURVIVE"],
		"support": ["SUPPORT"],
		"flee": ["EXIT", "SURVIVE"],
		"communicate": ["COMMUNICATE"],
	}
	if instruction in mapping and motive in mapping[instruction]:
		result["accepted_commitment"] = 2.0
	return result


static func _subject_modifiers(snapshot, subject: Dictionary, motive: String) -> Dictionary:
	var result: Dictionary = {}
	if subject.get("type", "") != "actor":
		return result
	var observed = snapshot.known_actors.get(str(subject.get("id", "")))
	if observed == null:
		return result
	if observed.engagement and motive == "ATTACK":
		result["committed_engagement"] = 1.0
	if observed.threat_estimate > 0.0 and motive in ["SURVIVE", "EXIT", "ATTACK"]:
		result["threat_estimate"] = observed.threat_estimate
	if observed.distance >= 0 and motive in ["ATTACK", "SUPPORT", "COMMUNICATE"]:
		result["observable_proximity"] = 1.0 / maxf(1.0, float(observed.distance))
	return result


static func _inertia_modifier(candidate, previous_motive: String, previous_subject_id: String, profile_data) -> float:
	if candidate.motive == normalize_motive(previous_motive) and candidate.subject_id == previous_subject_id:
		return float(_dictionary_value(profile_data, "motive_inertia", DEFAULT_SWITCH_MARGIN))
	return 0.0


static func _weight_for(weights: Dictionary, motive: String) -> float:
	if weights.has(motive):
		return float(weights[motive])
	if weights.has(motive.to_lower()):
		return float(weights[motive.to_lower()])
	for alias in LEGACY_MOTIVE_ALIASES:
		if LEGACY_MOTIVE_ALIASES[alias] == motive:
			if weights.has(alias) or weights.has(alias.to_lower()):
				return float(weights.get(alias, weights.get(alias.to_lower(), 0.0)))
	return 1.0 if motive in ["SURVIVE", "EXIT", "HOLD", "ATTACK"] else 0.0


static func _is_uncommitted_neutral(snapshot) -> bool:
	if not str(snapshot.communication.get("accepted_order", "")).is_empty():
		return false
	if not str(snapshot.actor.get("commitment_subject_id", "")).is_empty():
		return false
	for observed in snapshot.known_actors.values():
		if observed != null and int(observed.relation) == _RelationshipLedger.Relation.HOSTILE and str(observed.knowledge_state) != "unknown":
			return false
	return true


static func _dictionary_value(source, key: String, fallback):
	if source is Dictionary:
		return source.get(key, fallback)
	if source != null and source.has_method("get"):
		var value = source.get(key)
		return value if value != null else fallback
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
		var left_index := MOTIVES.find(left.motive)
		var right_index := MOTIVES.find(right.motive)
		if left_index != right_index:
			return left_index < right_index
		return left.subject_id < right.subject_id
	)
