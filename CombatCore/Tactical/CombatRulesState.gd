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
var occupancy: Dictionary = {}
var relationships: Dictionary = {}
var coordinates_by_index: Dictionary = {}
var indices_by_coordinate: Dictionary = {}
var neighbors: Dictionary = {}
var frozen: bool = false


static func from_board(
	tactical_board: CombatBoard,
	turns: TacticalTurnManager = null,
	action_catalog: CombatActionCatalog = null,
	combatants: Array[HumanoidCore] = [],
	gameplay_revision: int = 0
):
	var state = (load("res://CombatCore/Tactical/CombatRulesState.gd") as Script).new()
	state.revision = gameplay_revision
	if tactical_board == null or tactical_board.arena_state == null:
		return state.freeze()
	state.encounter_seed = str(tactical_board.arena_state.baseline_seed)
	state.communication_points = tactical_board.communication_points
	if turns != null:
		state.current_ap_pool = turns.current_ap_pool
		state.round = turns.current_round
		var active := turns.get_active_entity()
		state.active_actor_id = _actor_id(active)
	if action_catalog != null:
		for definition in action_catalog.all():
			if definition != null:
				state.action_definitions[definition.action_id] = definition

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
		var weapon := candidate.inventory.get_active_weapon(false) if candidate.inventory != null else null
		state.actor_facts[id] = {
			"actor_id": id,
			"sector_index": index,
			"sector": tactical_board.arena_state.coords_for(index) if index >= 0 else Vector2i(-1, -1),
			"faction": int(candidate.definition.faction) if candidate.definition != null else -1,
			"kinetic_tier": int(candidate.kinetic_tier),
			"dead": candidate.is_dead,
			"comatose": candidate.is_comatose,
			"surrendered": bool(candidate.get_meta("combat_surrendered", false)),
			"broken": tactical_state.broken if tactical_state != null else false,
			"incapacitated": tactical_state.incapacitated if tactical_state != null else false,
			"stance": tactical_state.stance if tactical_state != null else 0.0,
			"posture": tactical_board.posture(candidate),
			"facing": tactical_board.get_facing(candidate),
			"cover_edge": str(tactical_board.actor_cover_edges.get(id, "")),
			"public_intent": candidate.get_meta("combat_intent_view", {}).duplicate(true),
			"weapon": _weapon_projection(weapon),
			"morale": candidate.current_morale,
			"private": _private_actor_projection(candidate, tactical_board, weapon),
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
			"movement_cost": runtime.movement_cost(2),
			"cover_edges": runtime.cover_edges.duplicate(true),
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
	copy.occupancy = occupancy.duplicate(true)
	copy.relationships = relationships.duplicate(true)
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
		"reload_available": true,
	}


static func _private_actor_projection(actor: HumanoidCore, tactical_board: CombatBoard, weapon: ItemData) -> Dictionary:
	var items: Array[Dictionary] = []
	if actor.inventory != null:
		for item in actor.inventory.get_all_items():
			if item == null:
				continue
			items.append({
				"instance_id": item.instance_id,
				"definition_id": item.id,
				"access": actor.inventory.get_access_tier(item),
				"quantity": item.stack_count,
				"equipped_slot": item.equipped_slot,
			})
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


static func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))


static func _coordinate_key(coords: Vector2i) -> String:
	return "%d,%d" % [coords.x, coords.y]
