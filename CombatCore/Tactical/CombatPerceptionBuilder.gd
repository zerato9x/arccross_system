extends RefCounted
class_name CombatPerceptionBuilder

const _Snapshot := preload("res://CombatCore/Tactical/CombatPerceptionSnapshot.gd")
const _ObservedActor := preload("res://CombatCore/Tactical/CombatObservedActor.gd")
const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")

## Builds one actor's observation boundary from neutral rules facts.  No live
## gameplay object is retained by the returned snapshot.


static func build(
	rules_state,
	actor_id: String,
	observation_memory: Dictionary = {},
	previous_intent: Dictionary = {},
	reevaluation_trigger: String = "initial"
):
	var snapshot = _Snapshot.new()
	if rules_state == null:
		return snapshot
	snapshot.revision = rules_state.revision
	snapshot.encounter_seed = rules_state.encounter_seed
	snapshot.round = rules_state.round
	snapshot.reevaluation_trigger = reevaluation_trigger
	var self_facts: Dictionary = rules_state.actor(actor_id)
	snapshot.actor = self_facts.get("private", {}).duplicate(true)
	snapshot.actor["actor_id"] = actor_id
	snapshot.actor["sector"] = self_facts.get("sector", Vector2i(-1, -1))
	snapshot.actor["sector_index"] = int(self_facts.get("sector_index", -1))
	snapshot.actor["stance"] = float(self_facts.get("stance", 0.0))
	snapshot.actor["broken"] = bool(self_facts.get("broken", false))
	snapshot.actor["incapacitated"] = bool(self_facts.get("incapacitated", false))
	snapshot.actor["mindless"] = bool(self_facts.get("mindless", false))
	snapshot.hard_facts = _hard_facts(rules_state, actor_id, self_facts)
	snapshot.relationships = rules_state.relationships.duplicate(true)
	snapshot.previous_intent = previous_intent.duplicate(true)

	for candidate_id in rules_state.actor_facts.keys():
		var candidate: Dictionary = rules_state.actor(str(candidate_id))
		var observed = _ObservedActor.new()
		observed.actor_id = str(candidate_id)
		observed.relation = rules_state.relation_between(actor_id, observed.actor_id)
		if observed.actor_id == actor_id:
			observed.knowledge_state = "self"
			observed.sector = candidate.get("sector", Vector2i(-1, -1))
			observed.last_known_sector = observed.sector
			observed.visible_condition = _condition(candidate)
			observed.observable_weapon = candidate.get("weapon", {}).duplicate(true)
			observed.confidence = 1.0
			observed.observation_revision = rules_state.revision
		else:
			var visible := _visible_to_self(rules_state, actor_id, candidate)
			var memory: Dictionary = observation_memory.get(observed.actor_id, {})
			if visible:
				observed.knowledge_state = "visible"
				observed.sector = candidate.get("sector", Vector2i(-1, -1))
				observed.last_known_sector = observed.sector
				observed.visible_condition = _condition(candidate)
				var weapon: Dictionary = candidate.get("weapon", {})
				observed.public_intent = candidate.get("public_intent", {}).duplicate(true)
				observed.observable_weapon = {
					"category": "ranged" if bool(weapon.get("ranged", false)) else "melee",
					"ranged": bool(weapon.get("ranged", false)),
				}
				observed.observation_revision = rules_state.revision
				observed.confidence = 1.0
				observed.distance = _distance(rules_state, actor_id, observed.actor_id)
				observed.line_of_sight = true
				observed.cover = _cover_value(rules_state, candidate)
				observed.engagement = _engaged(rules_state, int(candidate.get("sector_index", -1)))
				observed.threat_estimate = _threat_estimate(rules_state, actor_id, candidate)
			else:
				observed.knowledge_state = "remembered" if not memory.is_empty() else "unknown"
				observed.last_known_sector = memory.get("sector", Vector2i(-1, -1))
				observed.sector = Vector2i(-1, -1)
				observed.visible_condition = str(memory.get("visible_condition", "unknown"))
				observed.observable_weapon = memory.get("observable_weapon", {}).duplicate(true)
				observed.observation_revision = int(memory.get("revision", -1))
				observed.confidence = clampf(float(memory.get("confidence", 0.0)), 0.0, 1.0)
		snapshot.known_actors[observed.actor_id] = observed

	var self_index := int(self_facts.get("sector_index", -1))
	for index in rules_state.sector_facts.keys():
		var sector: Dictionary = rules_state.sector(int(index))
		if int(index) == self_index or _sector_visible(rules_state, self_index, int(index)):
			snapshot.sectors[int(index)] = sector.duplicate(true)
			if sector.has("object"):
				snapshot.objects[int(index)] = sector.get("object", {}).duplicate(true)
			if sector.has("hazard"):
				snapshot.hazards[int(index)] = sector.get("hazard", {}).duplicate(true)

	var weapon_facts: Dictionary = self_facts.get("weapon", {})
	snapshot.capabilities = {
		"has_ranged_weapon": bool(weapon_facts.get("ranged", false)),
		"has_melee_weapon": not weapon_facts.is_empty() and not bool(weapon_facts.get("ranged", false)),
		"can_reload": bool(weapon_facts.get("ranged", false)) and int(weapon_facts.get("current_magazine", 0)) < int(weapon_facts.get("max_magazine", 0)),
		"can_cycle": bool(weapon_facts.get("jammed", false)),
		"can_engage": true,
		"action_ids": rules_state.action_definitions.keys().duplicate(),
	}
	snapshot.communication = {
		"points": rules_state.communication_points,
		"accepted_order": str(self_facts.get("private", {}).get("communication_order", "")),
	}
	snapshot.frozen = true
	return snapshot


static func _hard_facts(rules_state, actor_id: String, actor: Dictionary) -> Dictionary:
	var tags: Array[String] = []
	var index := int(actor.get("sector_index", -1))
	var occupants: Array = rules_state.occupants_at(index)
	var engaged := false
	for other_id in occupants:
		if str(other_id) != actor_id and rules_state.relation_between(actor_id, str(other_id)) == _RelationshipLedger.Relation.HOSTILE:
			engaged = true
	if engaged:
		tags.append("ENGAGED")
	if bool(actor.get("dead", false)) or bool(actor.get("comatose", false)) or bool(actor.get("surrendered", false)):
		tags.append("INACTIVE")
	if bool(actor.get("broken", false)):
		tags.append("BROKEN")
	var private: Dictionary = actor.get("private", {})
	if float(private.get("blood", 12.0)) <= 3.0 or float(private.get("consciousness", 12.0)) <= 3.0:
		tags.append("CRITICAL")
	var weapon: Dictionary = actor.get("weapon", {})
	if not weapon.is_empty() and (bool(weapon.get("jammed", false)) or float(weapon.get("condition", 1.0)) <= 0.0):
		tags.append("WEAPON_DISABLED")
	if not weapon.is_empty() and bool(weapon.get("ranged", false)) and int(weapon.get("current_magazine", 0)) <= 0:
		tags.append("OUT_OF_AMMO")
	var threatened := false
	var outnumbered := false
	for candidate_id in rules_state.actor_facts.keys():
		var candidate: Dictionary = rules_state.actor(str(candidate_id))
		if str(candidate_id) == actor_id or bool(candidate.get("dead", false)):
			continue
		if rules_state.relation_between(actor_id, str(candidate_id)) != _RelationshipLedger.Relation.HOSTILE:
			continue
		var candidate_index := int(candidate.get("sector_index", -1))
		if _distance_indices(rules_state, index, candidate_index) <= 3:
			threatened = true
		if candidate_index == index:
			outnumbered = outnumbered or occupants.size() > 2
	if threatened:
		tags.append("THREATENED")
	if outnumbered:
		tags.append("OUTNUMBERED")
	var cover_edge := str(actor.get("cover_edge", ""))
	if cover_edge.is_empty():
		tags.append("EXPOSED")
	if tags.is_empty():
		tags.append("STABLE")
	var dominant := "STABLE"
	for priority in ["INACTIVE", "BROKEN", "ENGAGED", "CRITICAL", "WEAPON_DISABLED", "OUT_OF_AMMO", "THREATENED", "OUTNUMBERED", "EXPOSED", "STABLE"]:
		if priority in tags:
			dominant = priority
			break
	return {"tags": tags, "dominant_tag": dominant, "engaged": engaged}


static func _visible_to_self(rules_state, actor_id: String, candidate: Dictionary) -> bool:
	var self_facts: Dictionary = rules_state.actor(actor_id)
	var self_index := int(self_facts.get("sector_index", -1))
	var candidate_index := int(candidate.get("sector_index", -1))
	return candidate_index >= 0 and _distance_indices(rules_state, self_index, candidate_index) <= 8 and _has_line_of_sight(rules_state, self_index, candidate_index)


static func _sector_visible(rules_state, self_index: int, candidate_index: int) -> bool:
	return candidate_index == self_index or _distance_indices(rules_state, self_index, candidate_index) <= 3


static func _has_line_of_sight(rules_state, from_index: int, to_index: int) -> bool:
	var start: Vector2i = rules_state.coordinate_for(from_index)
	var finish: Vector2i = rules_state.coordinate_for(to_index)
	var steps := maxi(absi(finish.x - start.x), absi(finish.y - start.y))
	for step in range(1, steps):
		var point := Vector2(start).lerp(Vector2(finish), float(step) / float(steps))
		var index: int = rules_state.index_for(Vector2i(roundi(point.x), roundi(point.y)))
		if index >= 0 and bool(rules_state.sector(index).get("opaque", false)):
			return false
	return true


static func _distance(rules_state, actor_id: String, other_id: String) -> int:
	var left: Dictionary = rules_state.actor(actor_id)
	var right: Dictionary = rules_state.actor(other_id)
	return _distance_indices(rules_state, int(left.get("sector_index", -1)), int(right.get("sector_index", -1)))


static func _distance_indices(rules_state, left: int, right: int) -> int:
	if left < 0 or right < 0:
		return 999
	var a: Vector2i = rules_state.coordinate_for(left)
	var b: Vector2i = rules_state.coordinate_for(right)
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _cover_value(rules_state, actor: Dictionary) -> float:
	var index := int(actor.get("sector_index", -1))
	var sector: Dictionary = rules_state.sector(index)
	var edges: Dictionary = sector.get("cover_edges", {})
	var strongest := 0.0
	for value in edges.values():
		strongest = maxf(strongest, float(value))
	return strongest


static func _engaged(rules_state, index: int) -> bool:
	var occupants: Array = rules_state.occupants_at(index)
	for left in range(occupants.size()):
		for right in range(left + 1, occupants.size()):
			if rules_state.relation_between(str(occupants[left]), str(occupants[right])) == _RelationshipLedger.Relation.HOSTILE:
				return true
	return false


static func _threat_estimate(rules_state, actor_id: String, candidate: Dictionary) -> float:
	var candidate_id := str(candidate.get("actor_id", ""))
	var relation: int = rules_state.relation_between(actor_id, candidate_id)
	return 1.0 if relation == _RelationshipLedger.Relation.HOSTILE else 0.0


static func _condition(actor: Dictionary) -> String:
	if bool(actor.get("dead", false)):
		return "dead"
	if bool(actor.get("incapacitated", false)):
		return "incapacitated"
	if bool(actor.get("broken", false)):
		return "broken"
	return "active"
