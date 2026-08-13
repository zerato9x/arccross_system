extends RefCounted
class_name CombatActionQuoteService

const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")
const _CombatRulesState := preload("res://CombatCore/Tactical/CombatRulesState.gd")
const _ForecastService := preload("res://CombatCore/Tactical/CombatForecastService.gd")
const _CommunicationResolver := preload("res://SystemCore/CombatCommunicationResolver.gd")
const _CommunicationProfile := preload("res://SystemCore/CombatCommunicationProfile.gd")
const FACINGS := ["north", "east", "south", "west"]
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const MELEE_ACTIONS := ["strike", "power_strike", "aimed_strike", "shove", "opportunity_strike"]
const FACING_ACTIONS := ["strike", "power_strike", "aimed_strike", "shove", "opportunity_strike", "fire", "aimed_fire"]

## Pure quote authority for projected rules.  `rules_state` is a frozen
## CombatRulesState projection; this service never touches a live node, edits
## the request, consumes RNG, or reserves AP.


static func quote(request: CombatActionRequest, rules_state) -> CombatActionQuote:
	var result := CombatActionQuote.new()
	if request == null:
		return result.deny("missing_request", "No action request was supplied.")
	result.actor_id = request.actor_id
	result.action_id = request.action_id
	result.target_sector = request.target_sector
	result.shove_direction = request.shove_direction
	result.final_facing = request.final_facing
	if rules_state == null:
		return result.deny("missing_rules_state", "No projected combat rules were supplied.")
	var definition: CombatActionDefinition = rules_state.action_definitions.get(request.action_id) as CombatActionDefinition
	if definition == null:
		return result.deny("unknown_action", "Unknown action ID: %s" % request.action_id)
	result.presentation_profile_id = definition.presentation_profile.profile_id if definition.presentation_profile != null else "neutral"
	result.planning_uncertain = definition.planning_outcome == "uncertain"
	var actor: Dictionary = rules_state.actor(request.actor_id)
	if actor.is_empty():
		return result.deny("unknown_actor", "The acting entity is not present.")
	result.origin_sector = actor.get("sector", Vector2i(-1, -1))
	result.projected_origin = result.origin_sector
	if not rules_state.active_actor_id.is_empty() and rules_state.active_actor_id != request.actor_id:
		return result.deny("not_active_actor", "It is not this actor's turn.")
	if bool(actor.get("dead", false)) or bool(actor.get("comatose", false)):
		return result.deny("actor_incapacitated", "The actor cannot take actions.")
	var origin_index := int(actor.get("sector_index", -1))
	if origin_index < 0:
		return result.deny("actor_not_on_board", "The actor has no tactical sector.")
	if bool(actor.get("engaged", false)) and (request.action_id == "move" or not request.approach_path.is_empty()):
		return result.deny("engaged_movement_blocked", "Engaged actors must attack, Shove, or change the relationship before moving.")
	if not definition.required_postures.is_empty() and str(actor.get("posture", "standing")) not in definition.required_postures:
		return result.deny("posture_required", "This action is unavailable while %s." % str(actor.get("posture", "standing")))
	var requirement_denial := _validate_requirements(actor, definition)
	if not requirement_denial.is_empty():
		return result.deny(str(requirement_denial.get("code", "requirements_missing")), str(requirement_denial.get("message", "The action requirements are not met.")))

	var target: Dictionary = rules_state.actor(request.target_actor_id)
	if definition.target_mode == CombatActionDefinition.TARGET_ACTOR:
		if target.is_empty() or request.target_actor_id == request.actor_id:
			return result.deny("invalid_target_actor", "Select another actor.")
		result.target_sector = target.get("sector", Vector2i(-1, -1))
	if definition.target_mode == CombatActionDefinition.TARGET_SECTOR and rules_state.index_for(request.target_sector) < 0:
		return result.deny("invalid_target_sector", "Select a sector inside the arena.")

	var evaluation_origin := origin_index
	var requested_path: Array[Vector2i] = request.approach_path if not request.approach_path.is_empty() else request.path
	if definition.target_mode == CombatActionDefinition.TARGET_PATH or not requested_path.is_empty():
		var path_check := _validate_path(rules_state, actor, request, requested_path, target)
		if not bool(path_check.get("valid", false)):
			return result.deny(str(path_check.get("code", "path_blocked")), _path_message(str(path_check.get("code", "path_blocked"))))
		var indices: Array = path_check.get("path", [])
		for index in indices:
			result.path.append(rules_state.coordinate_for(int(index)))
		result.approach_path = result.path.duplicate()
		result.projected_origin = result.path.back()
		evaluation_origin = int(indices.back())
		if definition.target_mode == CombatActionDefinition.TARGET_PATH:
			result.target_sector = result.projected_origin
		result.movement_cost = _path_cost(rules_state, indices, actor)
		result.movement_ap_cost = result.movement_cost
		for index in indices.slice(1):
			result.movement_step_costs.append(_movement_step_cost(rules_state, int(index), actor))

	var target_index: int = rules_state.index_for(result.target_sector) if not target.is_empty() or definition.target_mode == CombatActionDefinition.TARGET_SECTOR else evaluation_origin
	if target_index < 0:
		target_index = evaluation_origin
	result.range_cells = _distance(rules_state, evaluation_origin, target_index)
	var allows_shared_sector_melee := request.action_id in MELEE_ACTIONS and result.range_cells == 0
	if definition.minimum_range_cells > 0 and result.range_cells < definition.minimum_range_cells and not allows_shared_sector_melee:
		return result.deny("target_too_close", "The target is inside the action's minimum range.")
	var maximum_range := _maximum_range(definition, request.action_id, actor)
	if request.action_id != "shove" and result.range_cells > maximum_range:
		if request.action_id in MELEE_ACTIONS and maximum_range <= 0:
			return result.deny("same_sector_melee_required", "Ordinary melee requires hostile co-occupancy; use an authored reach weapon for adjacency.")
		return result.deny("target_out_of_range", "The target is outside the action's range.")
	if request.action_id in MELEE_ACTIONS and not target.is_empty() and not _cardinal_reach(rules_state, actor, evaluation_origin, target_index):
		return result.deny("cardinal_reach_required", "Melee reach travels only along a clear cardinal line.")
	result.has_line_of_sight = _has_line_of_sight(rules_state, evaluation_origin, target_index)
	if definition.requires_line_of_sight and not result.has_line_of_sight:
		return result.deny("line_of_sight_blocked", "No clear line of sight reaches the target.")
	if request.action_id in ["fire", "aimed_fire"] and not result.has_line_of_sight:
		return result.deny("line_of_sight_blocked", "No clear line of sight reaches the target.")
	if request.action_id in ["aimed_strike", "aimed_fire"] and request.target_body_region < 0:
		return result.deny("body_region_required", "Select a body region on the target.")
	if request.action_id in ["move", "disengage", "engage"] and result.final_facing.is_empty() and rules_state.index_for(result.target_sector) >= 0:
		result.final_facing = _facing(rules_state, evaluation_origin, rules_state.index_for(result.target_sector))
	if request.action_id in FACING_ACTIONS and result.final_facing.is_empty() and not target.is_empty():
		result.final_facing = _facing_for_target(rules_state, actor, target, evaluation_origin, target_index)

	var relation := _RelationshipLedger.Relation.FRIENDLY
	if not target.is_empty():
		relation = rules_state.relation_between(request.actor_id, request.target_actor_id)
	if request.action_id in ["strike", "power_strike", "aimed_strike", "fire", "aimed_fire"] and not target.is_empty():
		if relation == _RelationshipLedger.Relation.FRIENDLY:
			return result.deny("friendly_fire_illegal", "Deliberate attacks against a friendly actor are not legal.")
		if relation == _RelationshipLedger.Relation.NEUTRAL:
			result.relation_consequence = {"requires_confirmation": true, "on_commit": "hostile", "target_id": request.target_actor_id}
			if not request.declared_neutral_attack_confirmation:
				return result.deny("neutral_attack_confirmation_required", "Confirm the attack to establish hostility with this neutral actor.")
	if not target.is_empty():
		result.cover_strength = _cover_strength(rules_state, target_index, evaluation_origin)
		if str(rules_state.occupancy_kind(target_index)) == "crowded" and request.action_id in ["strike", "power_strike", "fire", "aimed_fire"]:
			result.collateral_risk = float(rules_state.balance_facts.get("crowded_collateral_risk", 0.0))
	if target_index >= 0:
		result.set_meta("visibility_penalty", float(rules_state.sector(target_index).get("visibility_penalty", 0.0)))

	match request.action_id:
		"engage":
			if target.is_empty() or bool(target.get("dead", false)) or bool(target.get("comatose", false)):
				return result.deny("invalid_target_actor", "Engage requires an active target actor.")
			if relation == _RelationshipLedger.Relation.FRIENDLY:
				return result.deny("friendly_target_required", "Engage requires a hostile or neutral target.")
			if requested_path.is_empty():
				return result.deny("engage_path_required", "Engage requires a path into the target's sector.")
			if origin_index == int(target.get("sector_index", -1)):
				return result.deny("already_engaged", "The actors already share a sector.")
			if evaluation_origin != int(target.get("sector_index", -1)):
				return result.deny("engage_target_sector_required", "Engage must end in the target's sector.")
		"shove":
			if target.is_empty() or evaluation_origin != int(target.get("sector_index", -1)):
				return result.deny("co_occupancy_required", "Shove requires a hostile co-occupant.")
			if relation != _RelationshipLedger.Relation.HOSTILE:
				return result.deny("hostile_target_required", "Shove is only available against a hostile co-occupant.")
			if request.shove_direction.to_lower() not in FACINGS:
				return result.deny("cardinal_direction_required", "Choose north, east, south, or west for the shove.")
		"cycle":
			var cycle_weapon: Dictionary = actor.get("ranged_weapon", actor.get("weapon", {}))
			if cycle_weapon.is_empty():
				return result.deny("weapon_required", "No firearm is equipped.")
			if not bool(cycle_weapon.get("jammed", false)):
				return result.deny("cycle_not_needed", "Cycle is reserved for clearing a jammed weapon.")
		"clear_malfunction":
			return result.deny("retired_action", "Use Cycle to clear a jammed weapon.")
		"fire", "aimed_fire":
			var fire_weapon: Dictionary = actor.get("ranged_weapon", actor.get("weapon", {}))
			if fire_weapon.is_empty() or not bool(fire_weapon.get("ranged", false)):
				return result.deny("weapon_required", "No firearm is equipped.")
			if bool(fire_weapon.get("jammed", false)) or float(fire_weapon.get("condition", 0.0)) <= 0.0 or int(fire_weapon.get("current_magazine", 0)) <= 0:
				return result.deny("weapon_not_ready", "The ranged weapon is empty, damaged, jammed, or not ready.")
			if bool(fire_weapon.get("requires_ready_action", false)) and not bool(fire_weapon.get("is_readied", false)):
				return result.deny("weapon_not_ready", "The firearm has not been readied.")
			if result.range_cells == 0 and str(fire_weapon.get("engaged_fire_policy", "penalized")) == "prohibited":
				return result.deny("engaged_fire_prohibited", "This firearm cannot be fired while Engaged.")
		"reload":
			var reload_weapon: Dictionary = actor.get("ranged_weapon", actor.get("weapon", {}))
			if reload_weapon.is_empty():
				return result.deny("weapon_required", "No firearm is equipped.")
			if bool(reload_weapon.get("jammed", false)):
				return result.deny("weapon_not_ready", "Clear the malfunction before reloading.")
			if int(reload_weapon.get("current_magazine", 0)) >= int(reload_weapon.get("max_magazine", 0)):
				return result.deny("reload_not_needed", "The magazine is full.")
			if not bool(reload_weapon.get("reload_available", true)):
				return result.deny("ammunition_unavailable", "No compatible accessible ammunition is available.")
		"aimed_strike":
			if request.target_body_region < 0:
				return result.deny("body_region_required", "Select a body region on the target.")
		"communication", "offense", "defense", "support", "flee", "threaten", "ceasefire":
			if target.is_empty() or bool(target.get("dead", false)):
				return result.deny("communication_target_inactive", "That actor cannot receive a communication.")
			var friendly_intent := request.action_id in ["offense", "defense", "support", "flee"]
			if friendly_intent and relation != _RelationshipLedger.Relation.FRIENDLY:
				return result.deny("friendly_target_required", "That instruction is only available to an allied actor.")
			if not friendly_intent and relation == _RelationshipLedger.Relation.FRIENDLY:
				return result.deny("independent_target_required", "Threaten or ceasefire requires a neutral or hostile actor.")
			if rules_state.communication_points <= 0:
				return result.deny("communication_points_empty", "No Communication Points remain for communication.")
			var communication_profile := _communication_profile(rules_state.communication_facts)
			result.communication_acceptance_forecast = _CommunicationResolver.evaluate(
				request.action_id,
				actor.get("communication", actor.get("private", {})),
				target.get("communication", target.get("private", {})),
				relation,
				{"relative_force": 0.0},
				communication_profile
			)
			if request.action_id == "ceasefire":
				result.relation_consequence = {"on_accept": "friendly", "target_id": request.target_actor_id}

	result.action_ap_cost = _action_ap_cost(definition, actor, rules_state)
	result.ap_cost = result.movement_ap_cost + result.action_ap_cost
	if result.ap_cost > rules_state.current_ap_pool:
		return result.deny("insufficient_ap", "Needs %d AP; %d remains." % [result.ap_cost, rules_state.current_ap_pool])
	if request.action_id == "shove" and not target.is_empty():
		result.collision_preview = _preview_shove(rules_state, evaluation_origin, target_index, request.shove_direction)
		if str(result.collision_preview.get("type", "")) == "full":
			return result.deny("destination_full", "That shove destination already contains two actors.")
		if str(result.collision_preview.get("type", "")) == "clear":
			result.predicted_displacement.append({"actor_id": request.target_actor_id, "to": result.collision_preview.get("destination", Vector2i(-1, -1))})
		result.resulting_occupancy = str(result.collision_preview.get("type", ""))
		result.stance_forecast = {
			"target": float(rules_state.balance_facts.get("shove_stance_damage", 0.0)),
			"collision": float(rules_state.balance_facts.get("collision_stance_damage", 0.0)) if str(result.collision_preview.get("type", "")) == "actor_collision" else 0.0,
		}
	result.forecast = _ForecastService.build(request, definition, actor, target, rules_state, result)
	return result.allow()


static func _validate_path(
	rules_state,
	actor: Dictionary,
	request: CombatActionRequest,
	requested_path: Array[Vector2i],
	target: Dictionary
) -> Dictionary:
	var origin := int(actor.get("sector_index", -1))
	var normalized: Array[int] = [origin]
	var previous := origin
	for coords in requested_path:
		var index: int = rules_state.index_for(coords)
		if index < 0:
			return {"valid": false, "code": "path_out_of_bounds", "path": normalized}
		if index == previous:
			continue
		if index not in rules_state.neighboring_indices(previous):
			return {"valid": false, "code": "path_not_orthogonal", "path": normalized}
		var final_step: bool = coords == requested_path.back()
		var policy := "hostile_engagement" if request.action_id == "engage" and final_step else "ordinary"
		if str(request.metadata.get("entry_policy", "")) == "forced_displacement" and final_step:
			policy = "forced_displacement"
		if not _can_enter(rules_state, request.actor_id, index, policy, target):
			return {"valid": false, "code": "path_blocked", "path": normalized}
		normalized.append(index)
		previous = index
	return {"valid": normalized.size() > 1, "code": "" if normalized.size() > 1 else "empty_path", "path": normalized}


static func _can_enter(state, actor_id: String, index: int, policy: String, target: Dictionary) -> bool:
	var sector: Dictionary = state.sector(index)
	if sector.is_empty() or bool(sector.get("blocked", false)):
		return false
	var occupants: Array = state.occupants_at(index)
	if actor_id in occupants:
		return true
	if occupants.size() >= 2:
		return false
	if policy == "ordinary":
		return occupants.is_empty()
	if policy == "hostile_engagement":
		return occupants.size() == 1 and not target.is_empty() and str(occupants[0]) == str(target.get("actor_id", "")) and state.relation_between(actor_id, str(target.get("actor_id", ""))) == _RelationshipLedger.Relation.HOSTILE
	if policy == "forced_displacement":
		return true
	return false


static func _path_cost(state, indices: Array, actor: Dictionary) -> int:
	var total := 0
	for offset in range(1, indices.size()):
		total += _movement_step_cost(state, int(indices[offset]), actor)
	return total


static func _movement_step_cost(state, index: int, actor: Dictionary) -> int:
	var base := 2
	match int(actor.get("kinetic_tier", 0)):
		1: base = 3
		2: base = 4
	if str(actor.get("posture", "standing")) == "crouched":
		base += 1
	return maxi(1, base + int(state.sector(index).get("movement_modifier", 0)))


static func _maximum_range(definition: CombatActionDefinition, action_id: String, actor: Dictionary) -> int:
	if action_id in MELEE_ACTIONS:
		var melee_weapon: Dictionary = actor.get("melee_weapon", actor.get("weapon", {}))
		return int(melee_weapon.get("reach_cells", definition.reach_cells))
	var ranged_weapon: Dictionary = actor.get("ranged_weapon", actor.get("weapon", {}))
	var authored := int(definition.maximum_range_cells)
	var weapon_range := int(ranged_weapon.get("maximum_range_cells", 0))
	if weapon_range > 0:
		return mini(authored, weapon_range) if authored > 0 else weapon_range
	return authored


static func _cardinal_reach(state, actor: Dictionary, origin: int, target: int) -> bool:
	var from: Vector2i = state.coordinate_for(origin)
	var to: Vector2i = state.coordinate_for(target)
	var delta: Vector2i = to - from
	var distance := absi(delta.x) + absi(delta.y)
	if distance == 0:
		return true
	var weapon: Dictionary = actor.get("melee_weapon", actor.get("weapon", {}))
	if distance > int(weapon.get("reach_cells", 0)):
		return false
	if delta.x != 0 and delta.y != 0:
		return false
	if distance <= 1:
		return true
	var step := Vector2i(signi(delta.x), signi(delta.y))
	for offset in range(1, distance):
		var index: int = state.index_for(from + step * offset)
		if index < 0 or not state.occupants_at(index).is_empty() or bool(state.sector(index).get("opaque", false)):
			return false
	return true


static func _has_line_of_sight(state, from_index: int, to_index: int) -> bool:
	if from_index < 0 or to_index < 0:
		return false
	var start: Vector2i = state.coordinate_for(from_index)
	var finish: Vector2i = state.coordinate_for(to_index)
	var steps := maxi(absi(finish.x - start.x), absi(finish.y - start.y))
	if steps <= 1:
		return true
	for step in range(1, steps):
		var point := Vector2(start).lerp(Vector2(finish), float(step) / float(steps))
		var coords := Vector2i(roundi(point.x), roundi(point.y))
		var index: int = state.index_for(coords)
		if index >= 0 and bool(state.sector(index).get("opaque", false)):
			return false
	return true


static func _distance(state, left: int, right: int) -> int:
	var a: Vector2i = state.coordinate_for(left)
	var b: Vector2i = state.coordinate_for(right)
	return absi(a.x - b.x) + absi(a.y - b.y)


static func _path_message(code: String) -> String:
	match code:
		"path_out_of_bounds":
			return "The selected path leaves the arena."
		"path_not_orthogonal":
			return "The selected path is not a legal cardinal route."
		"empty_path":
			return "A movement path is required."
	return "The selected path is blocked by the projected occupancy or terrain."


static func _validate_requirements(actor: Dictionary, definition: CombatActionDefinition) -> Dictionary:
	var left_arm := float(actor.get("left_arm_function", GameEnums.SCALE_MAX))
	var right_arm := float(actor.get("right_arm_function", GameEnums.SCALE_MAX))
	for tag in definition.required_limb_tags:
		if tag == "one_arm" and maxf(left_arm, right_arm) <= 0.0:
			return {"code": "functional_arm_required", "message": "A functional arm is required."}
		if tag == "two_arms" and (left_arm <= 0.0 or right_arm <= 0.0):
			return {"code": "two_arms_required", "message": "Two functional arms are required."}
		if tag == "legs" and bool(actor.get("both_legs_disabled", false)):
			return {"code": "functional_leg_required", "message": "A functional leg is required."}
	for tag in definition.required_equipment_tags:
		if tag == "ranged_weapon" and actor.get("ranged_weapon", actor.get("weapon", {})).is_empty():
			return {"code": "ranged_weapon_required", "message": "Ready a functional ranged weapon."}
	return {}


static func _action_ap_cost(definition: CombatActionDefinition, actor: Dictionary, rules_state) -> int:
	var costs: Dictionary = rules_state.balance_facts.get("ap_costs_by_category", {})
	if costs.is_empty():
		return definition.base_ap_cost(int(actor.get("kinetic_tier", 0)), rules_state.current_ap_pool)
	if definition.ap_category == CombatActionDefinition.AP_FREE:
		return 0
	if definition.ap_category == CombatActionDefinition.AP_COMMITTED:
		return maxi(0, rules_state.current_ap_pool)
	var values: Array = costs.get(definition.ap_category, [])
	if values.is_empty():
		return 0
	return int(values[clampi(int(actor.get("kinetic_tier", 0)), 0, values.size() - 1)])


static func _cover_strength(state, defender_index: int, attacker_index: int) -> float:
	if defender_index < 0 or attacker_index < 0:
		return 0.0
	var defender_sector: Dictionary = state.sector(defender_index)
	var edge := _facing(state, defender_index, attacker_index)
	var strength := float(defender_sector.get("cover_edges", {}).get(edge, 0.0))
	var occupant_ids: Array = state.occupants_at(defender_index)
	if not occupant_ids.is_empty():
		var defender: Dictionary = state.actor(str(occupant_ids[0]))
		if str(defender.get("cover_edge", "")) == edge:
			return strength
	return strength * 0.35


static func _facing(state, from_index: int, to_index: int) -> String:
	var delta: Vector2i = state.coordinate_for(to_index) - state.coordinate_for(from_index)
	if absi(delta.x) >= absi(delta.y):
		return "east" if delta.x >= 0 else "west"
	return "south" if delta.y >= 0 else "north"


static func _facing_for_target(state, actor: Dictionary, target: Dictionary, from_index: int, to_index: int) -> String:
	if from_index != to_index and from_index >= 0 and to_index >= 0:
		return _facing(state, from_index, to_index)
	if str(target.get("facing", "")) in FACINGS:
		return str(OPPOSITE.get(str(target.get("facing", "")), "east"))
	if str(actor.get("facing", "")) in FACINGS:
		return str(actor.get("facing", "east"))
	return "east"


static func _preview_shove(state, source_index: int, target_index: int, direction: String) -> Dictionary:
	if source_index != target_index or direction.to_lower() not in FACINGS:
		return {"type": "invalid", "reason": "co_occupancy_required"}
	var destination: Vector2i = state.coordinate_for(target_index) + _direction_vector(direction.to_lower())
	var destination_index: int = state.index_for(destination)
	if destination_index < 0:
		var forced_edges: Array = state.sector(target_index).get("object", {}).get("forced_exit_edges", [])
		return {"type": "forced_exit" if direction.to_lower() in forced_edges else "boundary", "from": state.coordinate_for(target_index), "direction": direction.to_lower()}
	var destination_sector: Dictionary = state.sector(destination_index)
	var occupants: Array = state.occupants_at(destination_index)
	if occupants.size() >= 2:
		return {"type": "full", "from": state.coordinate_for(target_index), "destination": destination, "direction": direction.to_lower()}
	if not occupants.is_empty():
		return {"type": "actor_collision", "from": state.coordinate_for(target_index), "destination": destination, "other_actor_id": str(occupants[0]), "direction": direction.to_lower()}
	if bool(destination_sector.get("blocked", false)):
		return {"type": "object_collision", "from": state.coordinate_for(target_index), "destination": destination, "object_id": str(destination_sector.get("object", {}).get("id", "")), "direction": direction.to_lower()}
	return {"type": "clear", "from": state.coordinate_for(target_index), "destination": destination, "direction": direction.to_lower(), "hazard": destination_sector.get("hazard", {}).duplicate(true), "trap": destination_sector.get("trap", {}).duplicate(true)}


static func _direction_vector(direction: String) -> Vector2i:
	match direction:
		"north": return Vector2i.UP
		"south": return Vector2i.DOWN
		"west": return Vector2i.LEFT
		_: return Vector2i.RIGHT


static func _communication_profile(facts: Dictionary) -> CombatCommunicationProfile:
	var profile := CombatCommunicationProfile.new()
	profile.intent_biases = facts.get("intent_biases", profile.intent_biases).duplicate(true)
	profile.agenda_biases = facts.get("agenda_biases", profile.agenda_biases).duplicate(true)
	profile.morale_modifiers = facts.get("morale_modifiers", profile.morale_modifiers).duplicate(true)
	profile.cohesion_modifiers = facts.get("cohesion_modifiers", profile.cohesion_modifiers).duplicate(true)
	profile.biological_crisis_penalty = int(facts.get("biological_crisis_penalty", profile.biological_crisis_penalty))
	profile.acceptance_threshold = float(facts.get("acceptance_threshold", profile.acceptance_threshold))
	return profile
