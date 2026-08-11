extends RefCounted
class_name CombatPlanningProjectionService

const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")
const _PlanningState := preload("res://CombatCore/Tactical/CombatPlanningState.gd")

## Applies only deterministic preparation effects to a copied planning state.
## Attacks, Shove resolution, and communication acceptance are uncertain and
## terminate a plan instead of being guessed through.


static func from_rules_state(rules_state, actor_id: String):
	return _PlanningState.from_rules_state(rules_state, actor_id)


static func to_rules_state(base_rules_state, planning_state):
	var projected = base_rules_state.duplicate_state()
	projected.current_ap_pool = planning_state.remaining_ap
	var actor: Dictionary = projected.actor_facts.get(planning_state.actor_id, {})
	if not actor.is_empty():
		actor["sector_index"] = planning_state.actor_index
		actor["sector"] = planning_state.actor_sector
		actor["weapon"] = planning_state.weapon_readiness.duplicate(true)
		projected.actor_facts[planning_state.actor_id] = actor
	projected.occupancy = planning_state.occupancy.duplicate(true)
	return projected.freeze()


static func apply_quote(
	planning_state,
	request: CombatActionRequest,
	quote: CombatActionQuote,
	rules_state
):
	var projected = planning_state.duplicate_state()
	if quote == null or not quote.legal:
		projected.uncertain = true
		projected.signature = projected.state_signature()
		return projected
	projected.remaining_ap = maxi(0, projected.remaining_ap - quote.ap_cost)
	projected.actor_sector = quote.projected_origin
	projected.actor_index = rules_state.index_for(quote.projected_origin)
	if not quote.path.is_empty():
		_move_actor(
			projected,
			quote.path[0],
			quote.path.back(),
			"engagement" in _request_ai_tags(request),
			request.target_actor_id
		)
	var action_tags := _request_ai_tags(request)
	if "reload" in action_tags:
		projected.ammunition["current_magazine"] = projected.ammunition.get("max_magazine", 0)
		projected.weapon_readiness["current_magazine"] = projected.ammunition["current_magazine"]
		projected.weapon_readiness["jammed"] = false
		projected.jam["jammed"] = false
	elif "unjam" in action_tags:
		projected.weapon_readiness["jammed"] = false
		projected.jam["jammed"] = false
	elif "ready" in action_tags:
		projected.weapon_readiness["is_readied"] = true
	if quote.planning_uncertain:
		projected.uncertain = true
		projected.signature = projected.state_signature()
		return projected
	projected.signature = projected.state_signature()
	return projected


static func _move_actor(
	planning_state,
	from_coords: Vector2i,
	to_coords: Vector2i,
	engage: bool,
	target_actor_id: String
) -> void:
	var from_index: int = _index_from_occupancy_coords(planning_state, from_coords)
	var to_index: int = _index_from_occupancy_coords(planning_state, to_coords)
	# PlanningState deliberately stores the already-quoted destination. When a
	# caller cannot map coordinates back to indices, leave occupancy untouched;
	# AP/range projection remains valid and no false occupancy is invented.
	if from_index < 0 or to_index < 0:
		return
	var occupants: Array = planning_state.occupancy.get(from_index, []).duplicate()
	occupants.erase(planning_state.actor_id)
	planning_state.occupancy[from_index] = occupants
	var destination: Array = planning_state.occupancy.get(to_index, []).duplicate()
	if not engage:
		destination.erase(planning_state.actor_id)
	if planning_state.actor_id not in destination:
		destination.append(planning_state.actor_id)
	planning_state.occupancy[to_index] = destination
	if engage and target_actor_id not in destination:
		# A valid Engage quote always has the target as the sole destination
		# occupant; this guard keeps malformed external projections conservative.
		planning_state.uncertain = true


static func _index_from_occupancy_coords(planning_state, coords: Vector2i) -> int:
	return int(planning_state.indices_by_coordinate.get("%d,%d" % [coords.x, coords.y], -1))


static func _request_ai_tags(request: CombatActionRequest) -> Array:
	if request == null:
		return []
	var tags: Variant = request.metadata.get("ai_tags", [])
	return tags.duplicate() if tags is Array else []
