extends Node
class_name CombatBoard

signal board_changed
signal trap_triggered(actor: HumanoidCore, sector: TacticalSectorRuntime)
signal hazard_entered(actor: HumanoidCore, sector: TacticalSectorRuntime, hazard: Dictionary)
signal forced_exit(actor: HumanoidCore, edge: String)

const FACINGS := ["north", "east", "south", "west"]
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}

var sectors: Array[TacticalSectorRuntime] = []
var arena_state: CombatArenaState
var _baseline_arena: CombatArenaState
var actor_facings: Dictionary = {}
var actor_cover_edges: Dictionary = {}
var actor_tactics: Dictionary = {}
var grapple_links: Dictionary = {}
var trap_outcomes: Array[Dictionary] = []
var _generator := CombatArenaGenerator.new()


func _ready() -> void:
	_initialize_empty_arena()


func _initialize_empty_arena() -> void:
	arena_state = CombatArenaState.new()
	for index in range(CombatArenaState.SECTOR_COUNT):
		var record := TacticalSectorRecord.new()
		record.index = index
		record.coords = CombatArenaState.coords_for_index(index)
		record.surface_id = "unresolved"
		record.surface_label = "UNRESOLVED"
		arena_state.sectors.append(record)
	_project_arena()


func configure_from_encounter(encounter: CombatEncounterRecord) -> void:
	clear_actors()
	trap_outcomes.clear()
	var baseline_encounter := CombatEncounterRecord.from_dict(encounter.to_dict())
	if baseline_encounter.center_hex != null:
		baseline_encounter.center_hex.combat_site_state.clear()
	_baseline_arena = _generator.generate(baseline_encounter)
	arena_state = _generator.generate(encounter)
	_project_arena()
	board_changed.emit()


func _project_arena() -> void:
	sectors.clear()
	if arena_state == null:
		return
	for record in arena_state.sectors:
		var runtime := TacticalSectorRuntime.new()
		runtime.configure(record)
		sectors.append(runtime)


func clear_actors() -> void:
	for sector in sectors:
		sector.occupant = null
	actor_facings.clear()
	actor_cover_edges.clear()
	actor_tactics.clear()
	grapple_links.clear()


func spawn_actor(actor: HumanoidCore, side: String, preferred_row: int = 2) -> int:
	var index := find_spawn_sector(side, preferred_row)
	if index < 0:
		return -1
	remove_actor(actor)
	sectors[index].occupant = actor
	actor.set_meta("combat_side", side)
	actor_facings[_actor_id(actor)] = "east" if side == "player" else "west"
	actor_tactics[_actor_id(actor)] = _default_tactics()
	board_changed.emit()
	return index


func force_spawn_actor(actor: HumanoidCore, index: int, side: String = "") -> bool:
	if not _valid_index(index) or not sectors[index].is_open_for():
		return false
	remove_actor(actor)
	sectors[index].occupant = actor
	if not side.is_empty():
		actor.set_meta("combat_side", side)
	actor_facings[_actor_id(actor)] = "east" if str(actor.get_meta("combat_side", "player")) == "player" else "west"
	actor_tactics[_actor_id(actor)] = _default_tactics()
	board_changed.emit()
	return true


func remove_actor(actor: HumanoidCore) -> void:
	if actor == null:
		return
	break_grapple(actor)
	for sector in sectors:
		if sector.occupant == actor:
			sector.occupant = null
	actor_facings.erase(_actor_id(actor))
	actor_cover_edges.erase(_actor_id(actor))
	actor_tactics.erase(_actor_id(actor))
	board_changed.emit()


func position_of(actor: HumanoidCore) -> int:
	for index in range(sectors.size()):
		if sectors[index].occupant == actor:
			return index
	return -1


func actor_at(index: int) -> HumanoidCore:
	return sectors[index].occupant if _valid_index(index) else null


func actor_by_id(actor_id: String) -> HumanoidCore:
	for sector in sectors:
		if sector.occupant != null and _actor_id(sector.occupant) == actor_id:
			return sector.occupant
	return null


func neighboring_indices(index: int) -> Array[int]:
	var result: Array[int] = []
	if not _valid_index(index):
		return result
	var coords := CombatArenaState.coords_for_index(index)
	for delta: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate := coords + delta
		if CombatArenaState.contains_coords(candidate):
			result.append(CombatArenaState.index_for_coords(candidate))
	return result


func grid_distance(left: int, right: int) -> int:
	if not _valid_index(left) or not _valid_index(right):
		return 999
	var a := CombatArenaState.coords_for_index(left)
	var b := CombatArenaState.coords_for_index(right)
	return absi(a.x - b.x) + absi(a.y - b.y)


func validate_path(actor: HumanoidCore, requested: Array[Vector2i]) -> Dictionary:
	var origin := position_of(actor)
	if origin < 0:
		return {"valid": false, "code": "actor_not_on_board", "path": []}
	var normalized: Array[int] = [origin]
	var previous := origin
	for coords in requested:
		if not CombatArenaState.contains_coords(coords):
			return {"valid": false, "code": "path_out_of_bounds", "path": normalized}
		var index := CombatArenaState.index_for_coords(coords)
		if index == previous:
			continue
		if index not in neighboring_indices(previous):
			return {"valid": false, "code": "path_not_orthogonal", "path": normalized}
		if not sectors[index].is_open_for(actor):
			return {"valid": false, "code": "path_blocked", "path": normalized}
		normalized.append(index)
		previous = index
	return {"valid": normalized.size() > 1, "code": "" if normalized.size() > 1 else "empty_path", "path": normalized}


func path_cost(path: Array, base_step_cost: int) -> int:
	var total := 0
	for offset in range(1, path.size()):
		var index := int(path[offset])
		if _valid_index(index):
			total += sectors[index].movement_cost(base_step_cost)
	return total


func commit_path(actor: HumanoidCore, path: Array, suppress_reactions: bool = false) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if actor == null or path.size() < 2 or int(path[0]) != position_of(actor):
		return changes
	for offset in range(1, path.size()):
		var from_index := int(path[offset - 1])
		var to_index := int(path[offset])
		if not sectors[to_index].is_open_for(actor):
			return []
		sectors[from_index].occupant = null
		sectors[to_index].occupant = actor
		set_facing(actor, facing_toward(from_index, to_index))
		actor_cover_edges.erase(_actor_id(actor))
		changes.append({
			"actor_id": _actor_id(actor),
			"from": CombatArenaState.coords_for_index(from_index),
			"to": CombatArenaState.coords_for_index(to_index),
			"suppress_reactions": suppress_reactions,
		})
		_resolve_entry(actor, sectors[to_index])
	break_invalid_grapples()
	board_changed.emit()
	return changes


func find_path(from_index: int, to_index: int, actor: HumanoidCore = null) -> Array[int]:
	var empty: Array[int] = []
	if not _valid_index(from_index) or not _valid_index(to_index):
		return empty
	var frontier: Array[int] = [from_index]
	var came_from: Dictionary = {from_index: -1}
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		if current == to_index:
			break
		for neighbor in neighboring_indices(current):
			if came_from.has(neighbor) or not sectors[neighbor].is_open_for(actor):
				continue
			came_from[neighbor] = current
			frontier.append(neighbor)
	if not came_from.has(to_index):
		return empty
	var path: Array[int] = [to_index]
	var cursor := to_index
	while cursor != from_index:
		cursor = int(came_from[cursor])
		path.push_front(cursor)
	return path


func reachable_sectors(actor: HumanoidCore, base_step_cost: int, ap_budget: int) -> Dictionary:
	var origin := position_of(actor)
	var costs: Dictionary = {}
	if origin < 0:
		return costs
	costs[origin] = 0
	var frontier: Array[int] = [origin]
	while not frontier.is_empty():
		var current: int = frontier.pop_front()
		for neighbor in neighboring_indices(current):
			if not sectors[neighbor].is_open_for(actor):
				continue
			var next_cost := int(costs[current]) + sectors[neighbor].movement_cost(base_step_cost)
			if next_cost > ap_budget:
				continue
			if not costs.has(neighbor) or next_cost < int(costs[neighbor]):
				costs[neighbor] = next_cost
				frontier.append(neighbor)
	return costs


func reaction_threats(actor: HumanoidCore, path: Array) -> Array[String]:
	var ids: Array[String] = []
	if actor == null or path.size() < 2:
		return ids
	for offset in range(path.size() - 1):
		var from_index := int(path[offset])
		var to_index := int(path[offset + 1])
		for neighbor in neighboring_indices(from_index):
			var threat := sectors[neighbor].occupant
			if not _hostile(actor, threat):
				continue
			if grid_distance(to_index, position_of(threat)) <= weapon_reach(threat):
				continue
			var id := _actor_id(threat)
			if id not in ids:
				ids.append(id)
	return ids


func has_line_of_sight(from_index: int, to_index: int) -> bool:
	if not _valid_index(from_index) or not _valid_index(to_index):
		return false
	var start := Vector2(CombatArenaState.coords_for_index(from_index))
	var finish := Vector2(CombatArenaState.coords_for_index(to_index))
	var steps := maxi(absi(int(finish.x - start.x)), absi(int(finish.y - start.y)))
	for step in range(1, steps):
		var point := start.lerp(finish, float(step) / float(steps))
		var coords := Vector2i(roundi(point.x), roundi(point.y))
		if sectors[CombatArenaState.index_for_coords(coords)].opaque:
			return false
	return true


func cover_against(defender_index: int, attacker_index: int) -> float:
	if not _valid_index(defender_index) or not _valid_index(attacker_index):
		return 0.0
	var edge := facing_toward(defender_index, attacker_index)
	var strength := float(sectors[defender_index].cover_edges.get(edge, 0.0))
	var defender := sectors[defender_index].occupant
	if defender != null and str(actor_cover_edges.get(_actor_id(defender), "")) == edge:
		return strength
	return strength * 0.35


func take_cover(actor: HumanoidCore, threat_index: int) -> bool:
	var index := position_of(actor)
	if index < 0:
		return false
	var edge := facing_toward(index, threat_index)
	if float(sectors[index].cover_edges.get(edge, 0.0)) <= 0.0:
		return false
	actor_cover_edges[_actor_id(actor)] = edge
	set_facing(actor, edge)
	board_changed.emit()
	return true


func set_facing(actor: HumanoidCore, facing: String) -> bool:
	if actor == null or facing not in FACINGS:
		return false
	actor_facings[_actor_id(actor)] = facing
	board_changed.emit()
	return true


func get_facing(actor: HumanoidCore) -> String:
	return str(actor_facings.get(_actor_id(actor), "east"))


func facing_toward(from_index: int, to_index: int) -> String:
	if not _valid_index(from_index) or not _valid_index(to_index):
		return "east"
	var delta := CombatArenaState.coords_for_index(to_index) - CombatArenaState.coords_for_index(from_index)
	if absi(delta.x) >= absi(delta.y):
		return "east" if delta.x >= 0 else "west"
	return "south" if delta.y >= 0 else "north"


func attack_arc(attacker: HumanoidCore, defender: HumanoidCore) -> Dictionary:
	var incoming := facing_toward(position_of(defender), position_of(attacker))
	var facing := get_facing(defender)
	if incoming == facing:
		return {"arc": "front", "accuracy": 0.0, "reaction_penalty": 0}
	if incoming == str(OPPOSITE.get(facing, "")):
		return {"arc": "rear", "accuracy": 0.16, "reaction_penalty": 3}
	return {"arc": "side", "accuracy": 0.08, "reaction_penalty": 1}


func posture(actor: HumanoidCore) -> String:
	return str(_tactics(actor).get("posture", "standing"))


func set_posture(actor: HumanoidCore, value: String) -> bool:
	if value not in ["standing", "crouched", "prone"]:
		return false
	_tactics(actor)["posture"] = value
	board_changed.emit()
	return true


func has_condition(actor: HumanoidCore, condition_id: String) -> bool:
	return bool(_tactics(actor).get(condition_id, false))


func set_condition(actor: HumanoidCore, condition_id: String, enabled: bool) -> void:
	_tactics(actor)[condition_id] = enabled
	board_changed.emit()


func control_role(actor: HumanoidCore) -> String:
	var id := _actor_id(actor)
	if grapple_links.has(id):
		return "controller"
	if id in grapple_links.values():
		return "controlled"
	return ""


func grapple_target(controller: HumanoidCore) -> HumanoidCore:
	return actor_by_id(str(grapple_links.get(_actor_id(controller), "")))


func grapple_controller(controlled: HumanoidCore) -> HumanoidCore:
	var target_id := _actor_id(controlled)
	for controller_id in grapple_links:
		if str(grapple_links[controller_id]) == target_id:
			return actor_by_id(str(controller_id))
	return null


func establish_grapple(controller: HumanoidCore, controlled: HumanoidCore) -> bool:
	if controller == null or controlled == null or grid_distance(position_of(controller), position_of(controlled)) != 1:
		return false
	break_grapple(controller)
	break_grapple(controlled)
	grapple_links[_actor_id(controller)] = _actor_id(controlled)
	set_condition(controlled, "restrained", false)
	board_changed.emit()
	return true


func break_grapple(actor: HumanoidCore) -> void:
	if actor == null:
		return
	var id := _actor_id(actor)
	var counterpart: HumanoidCore
	if grapple_links.has(id):
		counterpart = actor_by_id(str(grapple_links[id]))
		grapple_links.erase(id)
	else:
		for controller_id in grapple_links.keys():
			if str(grapple_links[controller_id]) == id:
				counterpart = actor_by_id(str(controller_id))
				grapple_links.erase(controller_id)
				break
	set_condition(actor, "restrained", false)
	if counterpart != null:
		set_condition(counterpart, "restrained", false)
	board_changed.emit()


func break_invalid_grapples() -> void:
	for controller_id in grapple_links.keys():
		var controller := actor_by_id(str(controller_id))
		var controlled := actor_by_id(str(grapple_links[controller_id]))
		if (
			controller == null
			or controlled == null
			or controller.is_dead
			or controlled.is_dead
			or grid_distance(position_of(controller), position_of(controlled)) != 1
			or not controller.body.has_functional_arms()
		):
			grapple_links.erase(controller_id)
			if controlled != null:
				set_condition(controlled, "restrained", false)


func preview_shove(initiator: HumanoidCore, target: HumanoidCore) -> Dictionary:
	var source_index := position_of(initiator)
	var target_index := position_of(target)
	if grid_distance(source_index, target_index) != 1:
		return {"type": "invalid", "reason": "not_adjacent"}
	var delta := CombatArenaState.coords_for_index(target_index) - CombatArenaState.coords_for_index(source_index)
	var destination_coords := CombatArenaState.coords_for_index(target_index) + delta
	var direction := facing_toward(source_index, target_index)
	if not CombatArenaState.contains_coords(destination_coords):
		var forced_edges: Array = sectors[target_index].record.object_state.get("forced_exit_edges", [])
		return {
			"type": "forced_exit" if direction in forced_edges else "boundary",
			"from": CombatArenaState.coords_for_index(target_index),
			"direction": direction,
		}
	var destination := CombatArenaState.index_for_coords(destination_coords)
	var destination_sector := sectors[destination]
	if destination_sector.occupant != null:
		return {
			"type": "actor_collision",
			"from": CombatArenaState.coords_for_index(target_index),
			"destination": destination_coords,
			"other_actor_id": _actor_id(destination_sector.occupant),
		}
	if destination_sector.blocked:
		return {
			"type": "object_collision",
			"from": CombatArenaState.coords_for_index(target_index),
			"destination": destination_coords,
			"object_id": str(destination_sector.record.object_state.get("id", "")),
			"destructible": destination_sector.object_durability > 0.0,
		}
	return {
		"type": "clear",
		"from": CombatArenaState.coords_for_index(target_index),
		"destination": destination_coords,
		"hazard": destination_sector.hazard_state.duplicate(true),
		"trap": destination_sector.trap_state.duplicate(true),
	}


func commit_shove(
	initiator: HumanoidCore,
	target: HumanoidCore,
	margin: float,
	collision_damage: float
) -> Dictionary:
	var preview := preview_shove(initiator, target)
	var result := preview.duplicate(true)
	result["moved"] = false
	match str(preview.get("type", "invalid")):
		"clear":
			var from_index := position_of(target)
			var destination := CombatArenaState.index_for_coords(preview.destination)
			sectors[from_index].occupant = null
			sectors[destination].occupant = target
			set_facing(target, facing_toward(from_index, destination))
			_resolve_entry(target, sectors[destination])
			result["moved"] = true
		"object_collision":
			var destination := CombatArenaState.index_for_coords(preview.destination)
			result["terrain_mutation"] = sectors[destination].damage_object(collision_damage)
			set_condition(target, "off_balance", true)
		"actor_collision":
			var other := actor_by_id(str(preview.other_actor_id))
			set_condition(target, "off_balance", true)
			set_condition(other, "off_balance", true)
		"forced_exit":
			remove_actor(target)
			forced_exit.emit(target, str(preview.direction))
			result["moved"] = true
		"boundary":
			set_condition(target, "off_balance", true)
	if margin >= 4.0 and str(preview.get("type", "")) == "clear":
		set_posture(target, "prone")
	break_invalid_grapples()
	board_changed.emit()
	return result


func commit_drag(controller: HumanoidCore, destination: int) -> Array[Dictionary]:
	var controlled := grapple_target(controller)
	if controlled == null:
		return []
	var controller_origin := position_of(controller)
	var controlled_origin := position_of(controlled)
	if destination != controlled_origin or destination not in neighboring_indices(controller_origin):
		return []
	sectors[controller_origin].occupant = null
	sectors[controlled_origin].occupant = null
	sectors[destination].occupant = controller
	sectors[controller_origin].occupant = controlled
	set_facing(controller, facing_toward(controller_origin, destination))
	set_facing(controlled, facing_toward(controlled_origin, controller_origin))
	_resolve_entry(controller, sectors[destination])
	_resolve_entry(controlled, sectors[controller_origin])
	board_changed.emit()
	return [
		{"actor_id": _actor_id(controller), "from": CombatArenaState.coords_for_index(controller_origin), "to": CombatArenaState.coords_for_index(destination)},
		{"actor_id": _actor_id(controlled), "from": CombatArenaState.coords_for_index(controlled_origin), "to": CombatArenaState.coords_for_index(controller_origin)},
	]


func weapon_reach(actor: HumanoidCore) -> int:
	if actor == null:
		return 0
	var weapon := actor.inventory.get_active_weapon(true)
	return maxi(1, weapon.weapon_reach_cells if weapon != null else 1)


func find_spawn_sector(side: String, preferred_row: int = 2) -> int:
	var x := 0 if side == "player" else CombatArenaState.WIDTH - 1
	for y in [preferred_row, 1, 3, 0, 4]:
		var index := CombatArenaState.index_for_coords(Vector2i(x, y))
		if sectors[index].spawnable and sectors[index].is_open_for():
			return index
	return -1


func find_nearest_open_sector(preferred_index: int) -> int:
	if _valid_index(preferred_index) and sectors[preferred_index].spawnable and sectors[preferred_index].is_open_for():
		return preferred_index
	for radius in range(1, CombatArenaState.WIDTH + CombatArenaState.HEIGHT):
		for index in range(sectors.size()):
			if grid_distance(preferred_index, index) == radius and sectors[index].spawnable and sectors[index].is_open_for():
				return index
	return -1


func capture_environment_patch() -> Dictionary:
	var patches: Dictionary = {}
	for sector in sectors:
		var current := sector.capture_mutation_patch()
		var baseline := _record_patch(_baseline_arena.sector_at(sector.coords)) if _baseline_arena != null else {}
		if current != baseline:
			patches[str(sector.index)] = current
	return {
		"schema_version": CombatArenaState.SCHEMA_VERSION,
		"baseline_seed": arena_state.baseline_seed if arena_state != null else 0,
		"sector_patches": patches,
	}


func snapshot() -> Dictionary:
	var sector_data: Array[Dictionary] = []
	for sector in sectors:
		sector_data.append(sector.presentation_descriptor())
	return {
		"width": CombatArenaState.WIDTH,
		"height": CombatArenaState.HEIGHT,
		"sectors": sector_data,
		"facings": actor_facings.duplicate(true),
		"cover_edges": actor_cover_edges.duplicate(true),
		"tactics": actor_tactics.duplicate(true),
		"grapples": grapple_links.duplicate(true),
		"backdrop_asset_path": arena_state.backdrop_asset_path if arena_state != null else "",
	}


func _resolve_entry(actor: HumanoidCore, sector: TacticalSectorRuntime) -> void:
	if bool(sector.trap_state.get("armed", false)):
		var owner_side := str(sector.trap_state.get("owner_side", ""))
		if owner_side.is_empty() or owner_side != str(actor.get_meta("combat_side", "")):
			sector.trap_state["armed"] = false
			sector.record.trap_state["armed"] = false
			var damage := float(sector.trap_state.get("damage", 2.5))
			actor.body.apply_targeted_hit(GameEnums.LimbRegion.LEFT_LEG, damage, 0.0)
			trap_outcomes.append({"trap_instance_id": str(sector.trap_state.get("id", "")), "sector": sector.coords, "actor_id": _actor_id(actor), "outcome": "sprung", "damage": damage})
			trap_triggered.emit(actor, sector)
	if not sector.hazard_state.is_empty():
		actor.body.apply_environment_exposure(sector.hazard_state)
		hazard_entered.emit(actor, sector, sector.hazard_state.duplicate(true))


func _default_tactics() -> Dictionary:
	return {
		"posture": "standing",
		"off_balance": false,
		"braced": false,
		"restrained": false,
		"momentum": 0,
	}


func _tactics(actor: HumanoidCore) -> Dictionary:
	var id := _actor_id(actor)
	if not actor_tactics.has(id):
		actor_tactics[id] = _default_tactics()
	return actor_tactics[id]


func _record_patch(record: TacticalSectorRecord) -> Dictionary:
	if record == null:
		return {}
	return {
		"object_state": record.object_state.duplicate(true),
		"hazard_state": record.hazard_state.duplicate(true),
		"trap_state": record.trap_state.duplicate(true),
		"surface_id": record.surface_id,
		"blocked": record.blocked,
		"cover_edges": record.cover_edges.duplicate(true),
	}


func _valid_index(index: int) -> bool:
	return index >= 0 and index < sectors.size()


func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))


func _hostile(left: HumanoidCore, right: HumanoidCore) -> bool:
	return left != null and right != null and left != right and left.definition != null and right.definition != null and left.definition.faction != right.definition.faction
