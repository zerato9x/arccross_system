extends RefCounted
class_name CombatPlanningState

const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")

## Evaluation-local projected state.  It is deliberately separate from live
## CombatActorState and is never serialized as save data.

var actor_id: String = ""
var actor_sector: Vector2i = Vector2i(-1, -1)
var actor_index: int = -1
var remaining_ap: int = 0
var occupancy: Dictionary = {}
var engagement: Dictionary = {}
var cover: Dictionary = {}
var weapon_readiness: Dictionary = {}
var ammunition: Dictionary = {}
var jam: Dictionary = {}
var relations: Dictionary = {}
var indices_by_coordinate: Dictionary = {}
var active_subjects: Array[String] = []
var uncertain: bool = false
var signature: String = ""


static func from_rules_state(rules_state, for_actor_id: String):
	var result = (load("res://CombatCore/Tactical/CombatPlanningState.gd") as Script).new()
	if rules_state == null:
		return result
	result.actor_id = for_actor_id
	var actor: Dictionary = rules_state.actor(for_actor_id)
	result.actor_sector = actor.get("sector", Vector2i(-1, -1))
	result.actor_index = int(actor.get("sector_index", -1))
	result.remaining_ap = rules_state.current_ap_pool
	result.occupancy = rules_state.occupancy.duplicate(true)
	result.relations = rules_state.relationships.duplicate(true)
	result.indices_by_coordinate = rules_state.indices_by_coordinate.duplicate(true)
	result.weapon_readiness = actor.get("weapon", {}).duplicate(true)
	result.ammunition = {
		"current_magazine": int(result.weapon_readiness.get("current_magazine", 0)),
		"max_magazine": int(result.weapon_readiness.get("max_magazine", 0)),
	}
	result.jam = {"jammed": bool(result.weapon_readiness.get("jammed", false))}
	result.cover = {"edge": str(actor.get("cover_edge", ""))}
	result._rebuild_engagement(rules_state)
	result.signature = result.state_signature()
	return result


func duplicate_state():
	var result = (load("res://CombatCore/Tactical/CombatPlanningState.gd") as Script).new()
	result.actor_id = actor_id
	result.actor_sector = actor_sector
	result.actor_index = actor_index
	result.remaining_ap = remaining_ap
	result.occupancy = occupancy.duplicate(true)
	result.engagement = engagement.duplicate(true)
	result.cover = cover.duplicate(true)
	result.weapon_readiness = weapon_readiness.duplicate(true)
	result.ammunition = ammunition.duplicate(true)
	result.jam = jam.duplicate(true)
	result.relations = relations.duplicate(true)
	result.indices_by_coordinate = indices_by_coordinate.duplicate(true)
	result.active_subjects = active_subjects.duplicate()
	result.uncertain = uncertain
	result.signature = signature
	return result


func state_signature() -> String:
	return "%s|%d|%d|%s|%s|%s" % [
		actor_id,
		actor_index,
		remaining_ap,
		JSON.stringify(occupancy),
		JSON.stringify(ammunition),
		JSON.stringify(jam),
	]


func _rebuild_engagement(rules_state) -> void:
	engagement.clear()
	for index in occupancy.keys():
		var occupants: Array = occupancy[index]
		if occupants.size() < 2:
			continue
		for left_offset in range(occupants.size()):
			for right_offset in range(left_offset + 1, occupants.size()):
				var left_id := str(occupants[left_offset])
				var right_id := str(occupants[right_offset])
				if rules_state.relation_between(left_id, right_id) == _RelationshipLedger.Relation.HOSTILE:
					engagement[int(index)] = true
