extends RefCounted
class_name CombatRulesState

const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")

## Frozen, neutral input for quote and planning services.  It contains
## projections only; no service may reach back into a live gameplay node.

var revision: int = 0
var encounter_seed: String = ""
var round: int = 0
var current_ap_pool: int = 0
var active_actor_id: String = ""
var communication_points: int = 0
var action_definitions: Dictionary = {}
var actor_facts: Dictionary = {}
var sector_facts: Dictionary = {}
var ground_items: Dictionary = {}
var occupancy: Dictionary = {}
var relationships: Dictionary = {}
var balance_facts: Dictionary = {}
var communication_facts: Dictionary = {}
var coordinates_by_index: Dictionary = {}
var indices_by_coordinate: Dictionary = {}
var neighbors: Dictionary = {}
var frozen: bool = false


static func from_board(
	tactical_board: CombatBoard,
	turns: TacticalTurnManager = null,
	action_catalog: CombatActionCatalog = null,
	combatants: Array[HumanoidCore] = [],
	gameplay_revision: int = 0,
	ground_item_instances: Dictionary = {}
):
	var state = (load("res://CombatCore/Tactical/CombatRulesState.gd") as Script).new()
	state.revision = gameplay_revision
	if tactical_board == null or tactical_board.arena_state == null:
		return state.freeze()
	state.encounter_seed = str(tactical_board.arena_state.baseline_seed)
	state.communication_points = tactical_board.communication_points
	var balance := tactical_board.balance_profile
	if balance != null:
		state.balance_facts = {
			"ap_costs_by_category": balance.ap_costs_by_category.duplicate(true),
			"crowded_collateral_risk": balance.crowded_collateral_risk,
			"shove_stance_damage": balance.shove_stance_damage,
			"collision_stance_damage": balance.collision_stance_damage,
		}
	var communication := tactical_board.communication_profile
	if communication != null:
		state.communication_facts = {
			"intent_biases": communication.intent_biases.duplicate(true),
			"agenda_biases": communication.agenda_biases.duplicate(true),
			"morale_modifiers": communication.morale_modifiers.duplicate(true),
			"cohesion_modifiers": communication.cohesion_modifiers.duplicate(true),
			"biological_crisis_penalty": communication.biological_crisis_penalty,
			"acceptance_threshold": communication.acceptance_threshold,
		}
	if turns != null:
		state.current_ap_pool = turns.current_ap_pool
		state.round = turns.current_round
		var active := turns.get_active_entity()
		state.active_actor_id = _actor_id(active)
	if action_catalog != null:
		for definition in action_catalog.all():
			if definition != null:
				state.action_definitions[definition.action_id] = definition
	for instance_id in ground_item_instances.keys():
		var ground_item: Variant = ground_item_instances.get(instance_id)
		if ground_item is ItemData:
			state.ground_items[str(instance_id)] = _item_projection(ground_item, "ground")
		elif ground_item is Dictionary:
			state.ground_items[str(instance_id)] = ground_item.duplicate(true)

	var actors: Array[HumanoidCore] = []
	for candidate in combatants:
		if candidate != null and candidate not in actors:
			actors.append(candidate)
	for candidate in tactical_board.active_actors():
		if candidate != null and candidate not in actors:
			actors.append(candidate)
	for candidate in actors:
		var id := _actor_id(candidate)
		if id.is_empty():
			continue
		var index := tactical_board.position_of(candidate)
		var tactical_state := tactical_board.combat_state(candidate)
		var ranged_weapon := candidate.inventory.get_active_weapon(false) if candidate.inventory != null else null
		var melee_weapon := candidate.inventory.get_active_weapon(true) if candidate.inventory != null else null
		var weapon := ranged_weapon if ranged_weapon != null else melee_weapon
		var actor_conditions := tactical_board._tactics(candidate).duplicate(true)
		var armor_protection := _armor_projection(candidate)
		var private_projection := _private_actor_projection(candidate, tactical_board, weapon)
		var wounds: Array[Dictionary] = []
		if candidate.body != null:
			for region in candidate.body.wounds_by_limb.keys():
				for wound in candidate.body.wounds_by_limb[region]:
					if wound is Wound:
						wounds.append(wound.to_dict())
		private_projection["wounds"] = wounds
		state.actor_facts[id] = {
			"actor_id": id,
			"sector_index": index,
			"sector": tactical_board.arena_state.coords_for(index) if index >= 0 else Vector2i(-1, -1),
			"faction": int(candidate.definition.faction) if candidate.definition != null else -1,
			"combat_side": str(candidate.get_meta("combat_side", candidate.get_meta("combat_team_id", ""))),
			"team_id": str(candidate.get_meta("combat_team_id", candidate.get_meta("combat_side", ""))),
			"direct_player": bool(candidate.get_meta("direct_player", id == "player")),
			"kinetic_tier": int(candidate.kinetic_tier),
			"dead": candidate.is_dead,
			"comatose": candidate.is_comatose,
			"surrendered": bool(candidate.get_meta("combat_surrendered", false)),
			"broken": tactical_state.broken if tactical_state != null else false,
			"incapacitated": tactical_state.incapacitated if tactical_state != null else false,
			"engaged": tactical_board.is_engaged(index) if index >= 0 else false,
			"off_balance": bool(actor_conditions.get("off_balance", false)),
			"conditions": actor_conditions,
			"stance": tactical_state.stance if tactical_state != null else 0.0,
			"cover_edge": str(tactical_board.actor_cover_edges.get(id, "")),
			"public_intent": candidate.get_meta("combat_intent_view", {}).duplicate(true),
			"weapon": _weapon_projection(weapon),
			"ranged_weapon": _weapon_projection(ranged_weapon),
			"melee_weapon": _weapon_projection(melee_weapon),
			"right_arm_function": candidate.body.get_limb_function(GameEnums.LimbRegion.RIGHT_ARM) if candidate.body != null else 0.0,
			"left_arm_function": candidate.body.get_limb_function(GameEnums.LimbRegion.LEFT_ARM) if candidate.body != null else 0.0,
			"both_legs_disabled": candidate.body.are_both_legs_disabled() if candidate.body != null else true,
			"combat_accuracy_melee": candidate.get_combat_accuracy(false),
			"combat_accuracy_ranged": candidate.get_combat_accuracy(true),
			"armor_protection": armor_protection,
			"morale": candidate.current_morale,
			"agenda": str(candidate.definition.agenda) if candidate.definition != null else "",
			"survival_pressure": float(candidate.get_meta("survival_pressure", 0.0)),
			"max_stance": tactical_state.max_stance if tactical_state != null else 12.0,
			"communication": _communication_projection(candidate, tactical_board),
			"private": private_projection,
			"items": private_projection.get("items", []).duplicate(true),
			"wounds": wounds.duplicate(true),
		}

	for index in range(tactical_board.sectors.size()):
		var runtime := tactical_board.sectors[index]
		var coords := tactical_board.arena_state.coords_for(index)
		state.coordinates_by_index[index] = coords
		state.indices_by_coordinate[_coordinate_key(coords)] = index
		var occupant_ids: Array[String] = []
		for occupant in runtime.occupants:
			var occupant_id := _actor_id(occupant)
			if not occupant_id.is_empty():
				occupant_ids.append(occupant_id)
		state.occupancy[index] = occupant_ids
		state.sector_facts[index] = {
			"index": index,
			"coords": coords,
			"blocked": runtime.blocked,
			"opaque": runtime.opaque,
			"visibility_penalty": runtime.record.visibility_penalty,
			"movement_cost": runtime.movement_cost(2),
			"movement_modifier": runtime.movement_modifier,
			"cover_edges": runtime.cover_edges.duplicate(true),
			"escape_side": runtime.record.escape_side,
			"ground_item_instance_ids": runtime.record.ground_item_instance_ids.duplicate(),
			"hazard": runtime.hazard_state.duplicate(true),
			"trap": runtime.trap_state.duplicate(true),
			"object": runtime.record.object_state.duplicate(true),
		}
		state.neighbors[index] = []
	for index in state.coordinates_by_index.keys():
		var coords: Vector2i = state.coordinates_by_index[index]
		var adjacent: Array[int] = []
		for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor_index = state.indices_by_coordinate.get(_coordinate_key(coords + delta), -1)
			if int(neighbor_index) >= 0:
				adjacent.append(int(neighbor_index))
		state.neighbors[index] = adjacent

	if tactical_board.relationship_ledger != null:
		state.relationships = tactical_board.relationship_ledger.relation_by_pair.duplicate(true)
	state.frozen = true
	return state


func freeze():
	frozen = true
	return self


func duplicate_state():
	var copy = (load("res://CombatCore/Tactical/CombatRulesState.gd") as Script).new()
	copy.revision = revision
	copy.encounter_seed = encounter_seed
	copy.round = round
	copy.current_ap_pool = current_ap_pool
	copy.active_actor_id = active_actor_id
	copy.communication_points = communication_points
	copy.action_definitions = action_definitions.duplicate(true)
	copy.actor_facts = actor_facts.duplicate(true)
	copy.sector_facts = sector_facts.duplicate(true)
	copy.ground_items = ground_items.duplicate(true)
	copy.occupancy = occupancy.duplicate(true)
	copy.relationships = relationships.duplicate(true)
	copy.balance_facts = balance_facts.duplicate(true)
	copy.communication_facts = communication_facts.duplicate(true)
	copy.coordinates_by_index = coordinates_by_index.duplicate(true)
	copy.indices_by_coordinate = indices_by_coordinate.duplicate(true)
	copy.neighbors = neighbors.duplicate(true)
	copy.frozen = true
	return copy


func actor(actor_id: String) -> Dictionary:
	return actor_facts.get(actor_id, {}).duplicate(true)


func sector(index: int) -> Dictionary:
	return sector_facts.get(index, {}).duplicate(true)


func occupants_at(index: int) -> Array:
	return occupancy.get(index, []).duplicate()


func occupancy_kind(index: int) -> String:
	var occupants := occupants_at(index)
	if occupants.is_empty():
		return "empty"
	if occupants.size() == 1:
		return "single"
	for left_index in range(occupants.size()):
		for right_index in range(left_index + 1, occupants.size()):
			if relation_between(str(occupants[left_index]), str(occupants[right_index])) == _RelationshipLedger.Relation.HOSTILE:
				return "engaged"
	return "crowded"


func relation_between(left_id: String, right_id: String) -> int:
	if left_id.is_empty() or right_id.is_empty() or left_id == right_id:
		return _RelationshipLedger.Relation.FRIENDLY
	return int(relationships.get(_RelationshipLedger.pair_key(left_id, right_id), _RelationshipLedger.Relation.HOSTILE))


func coordinate_for(index: int) -> Vector2i:
	return coordinates_by_index.get(index, Vector2i(-1, -1))


func index_for(coords: Vector2i) -> int:
	return int(indices_by_coordinate.get(_coordinate_key(coords), -1))


func neighboring_indices(index: int) -> Array:
	return neighbors.get(index, []).duplicate()


func progress_fingerprint() -> String:
	return JSON.stringify(_canonicalize({
		"revision": revision,
		"encounter_seed": encounter_seed,
		"round": round,
		"current_ap_pool": current_ap_pool,
		"communication_points": communication_points,
		"active_actor_id": active_actor_id,
		"actors": actor_facts,
		"sectors": sector_facts,
		"ground_items": ground_items,
		"occupancy": occupancy,
		"relationships": relationships,
	}))


func canonical_progress_fingerprint() -> String:
	return progress_fingerprint()


static func _weapon_projection(weapon: ItemData) -> Dictionary:
	if weapon == null:
		return {}
	return {
		"id": weapon.id,
		"instance_id": weapon.instance_id,
		"ranged": weapon.is_ranged(),
		"reach_cells": maxi(0, weapon.weapon_reach_cells - 1),
		"maximum_range_cells": weapon.maximum_range_cells,
		"current_magazine": weapon.current_magazine,
		"max_magazine": weapon.max_magazine,
		"condition": weapon.current_condition,
		"jammed": weapon.is_jammed,
		"needs_cycling": weapon.needs_cycling,
		"requires_ready_action": weapon.requires_ready_action,
		"is_readied": weapon.is_readied,
		"engaged_fire_policy": weapon.engaged_fire_policy,
		"engaged_fire_accuracy_penalty": weapon.engaged_fire_accuracy_penalty,
		"flesh_damage": weapon.flesh_damage,
		"damage_type": int(weapon.damage_type),
		"armor_penetration": weapon.armor_penetration,
		"accuracy_rating": weapon.accuracy_rating,
		"optimal_range_cells": weapon.optimal_range_cells,
		"range_falloff": weapon.range_falloff,
		"weapon_type": int(weapon.weapon_type),
		"combat_action_ids": Array(weapon.combat_action_ids()),
		"reload_available": true,
	}


static func _item_projection(item: ItemData, access: String) -> Dictionary:
	if item == null:
		return {}
	return {
		"instance_id": item.instance_id,
		"definition_id": item.id,
		"id": item.id,
		"item_type": int(item.item_type),
		"weapon_type": int(item.weapon_type),
		"ranged": item.is_ranged(),
		"melee": item.is_melee(),
		"access": access,
		"access_tier": access,
		"physical_location": item.physical_location,
		"equipped_slot": item.equipped_slot,
		"quantity": item.stack_count,
		"stack_count": item.stack_count,
		"condition": item.current_condition,
		"requires_ready_action": item.requires_ready_action,
		"is_readied": item.is_readied,
		"consumable_effect": int(item.consumable_effect),
		"consumable_potency": item.consumable_potency,
		"combat_action_ids": Array(item.combat_action_ids()),
	}


static func _armor_projection(actor: HumanoidCore) -> Dictionary:
	var result: Dictionary = {}
	if actor == null or actor.inventory == null:
		return result
	for damage_type in [GameEnums.DamageType.BLUNT, GameEnums.DamageType.SHARP, GameEnums.DamageType.BALLISTIC]:
		for region in range(GameEnums.LimbRegion.keys().size()):
			result["%d|%d" % [int(damage_type), region]] = actor.inventory.preview_protection(damage_type, region)
		result[str(int(damage_type))] = actor.inventory.preview_protection(damage_type, GameEnums.LimbRegion.UPPER_TORSO)
	return result


static func _canonicalize(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array[String] = []
		for key in value.keys():
			keys.append(str(key))
		keys.sort()
		var result: Dictionary = {}
		for key in keys:
			result[key] = _canonicalize(value.get(key))
		return result
	if value is Array:
		var result_array: Array = []
		for entry in value:
			result_array.append(_canonicalize(entry))
		return result_array
	if value is Vector2i:
		return {"x": value.x, "y": value.y}
	return value


static func _private_actor_projection(actor: HumanoidCore, tactical_board: CombatBoard, weapon: ItemData) -> Dictionary:
	var items: Array[Dictionary] = []
	if actor.inventory != null:
		for item in actor.inventory.get_all_items():
			if item == null:
				continue
			items.append(_item_projection(item, actor.inventory.get_access_tier(item)))
	var behavior_payload: Dictionary = actor.get_meta("npc_behavior_state", {})
	var survival_pressure := float(actor.get_meta("survival_pressure", behavior_payload.get("survival_pressure", 0.0)))
	return {
		"blood": actor.body.blood_level if actor.body != null else 0.0,
		"pain": actor.body.get_total_pain() if actor.body != null else 0.0,
		"shock": actor.body.shock if actor.body != null else 0.0,
		"consciousness": actor.body.consciousness if actor.body != null else 0.0,
		"morale": actor.current_morale,
		"items": items,
		"weapon": _weapon_projection(weapon),
		"survival_pressure": survival_pressure,
		"communication_order": str(tactical_board.combat_state(actor).communication_order) if tactical_board.combat_state(actor) != null else "",
	}


static func _communication_projection(actor: HumanoidCore, tactical_board: CombatBoard) -> Dictionary:
	var state := tactical_board.combat_state(actor)
	return {
		"actor_id": _actor_id(actor),
		"morale": actor.current_morale,
		"pain": actor.body.get_total_pain() if actor.body != null else 0.0,
		"shock": actor.body.shock if actor.body != null else 0.0,
		"stance": state.stance if state != null else 0.0,
		"max_stance": state.max_stance if state != null else 12.0,
		"survival_pressure": float(actor.get_meta("survival_pressure", 0.0)),
		"agenda": str(actor.definition.agenda) if actor.definition != null else "",
		"mindless": actor.is_mindless_hive_thrall,
	}


static func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))


static func _coordinate_key(coords: Vector2i) -> String:
	return "%d,%d" % [coords.x, coords.y]
