extends Node
class_name CombatBoard

const _RelationshipLedger := preload("res://SystemCore/CombatRelationshipLedger.gd")
const _CombatActorState := preload("res://SystemCore/CombatActorState.gd")
const _CombatBalanceProfile := preload("res://SystemCore/CombatBalanceProfile.gd")
const _CombatBalanceProfileCatalog := preload("res://SystemCore/CombatBalanceProfileCatalog.gd")
const _CommunicationResolver := preload("res://SystemCore/CombatCommunicationResolver.gd")

signal board_changed
signal trap_triggered(actor: HumanoidCore, sector: TacticalSectorRuntime)
signal hazard_entered(actor: HumanoidCore, sector: TacticalSectorRuntime, hazard: Dictionary)
signal forced_exit(actor: HumanoidCore, edge: String)

const FACINGS := ["north", "east", "south", "west"]
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}
const ENTRY_ORDINARY := TacticalSectorRuntime.ENTRY_ORDINARY
const ENTRY_HOSTILE_ENGAGEMENT := TacticalSectorRuntime.ENTRY_HOSTILE_ENGAGEMENT
const ENTRY_FORCED_DISPLACEMENT := TacticalSectorRuntime.ENTRY_FORCED_DISPLACEMENT

var sectors: Array[TacticalSectorRuntime] = []
## Registry survives active-layer removal so terminal actors remain available to
## snapshots and runtime handoff while no longer consuming sector capacity.
var _known_actors: Array[HumanoidCore] = []
var arena_state: CombatArenaState
var _baseline_arena: CombatArenaState
var actor_facings: Dictionary = {}
var actor_cover_edges: Dictionary = {}
var actor_tactics: Dictionary = {}
var relationship_ledger: CombatRelationshipLedger = CombatRelationshipLedger.new()
var balance_profile: CombatBalanceProfile = CombatBalanceProfile.new()
var communication_profile: CombatCommunicationProfile
## Canonical encounter-long communication pool (CP).
var communication_points: int = 0
var communication_points_initial: int = 0
var communication_points_spent: int = 0
## Compatibility aliases for older action/controller code and fixtures.
var squad_points: int:
	get: return communication_points
	set(value): communication_points = clampi(value, 0, 12)
var squad_points_initial: int:
	get: return communication_points_initial
	set(value): communication_points_initial = clampi(value, 0, 12)
var squad_points_spent: int:
	get: return communication_points_spent
	set(value): communication_points_spent = maxi(0, value)
var trap_outcomes: Array[Dictionary] = []
var _generator := CombatArenaGenerator.new()


func _ready() -> void:
	_initialize_empty_arena()


func _initialize_empty_arena() -> void:
	arena_state = CombatArenaState.new()
	arena_state.configure_topology(CombatTopologyCatalog.load_profile(CombatTopologyCatalog.DEFAULT_ID))
	for index in range(arena_state.sector_count()):
		var record := TacticalSectorRecord.new()
		record.index = index
		record.coords = arena_state.coords_for(index)
		record.surface_id = "unresolved"
		record.surface_label = "UNRESOLVED"
		arena_state.sectors.append(record)
	_project_arena()


func configure_from_encounter(encounter: CombatEncounterRecord) -> void:
	clear_actors()
	trap_outcomes.clear()
	relationship_ledger = _RelationshipLedger.from_dict(encounter.relationship_state) if encounter != null else _RelationshipLedger.new()
	var balance_catalog := _CombatBalanceProfileCatalog.load_default()
	balance_profile = balance_catalog.profile_for_id(encounter.balance_profile_id) if balance_catalog != null else null
	if balance_profile == null:
		balance_profile = _CombatBalanceProfile.new()
	communication_profile = _CommunicationResolver.load_default_profile()
	communication_points = (
		encounter.resolved_communication_points()
		if encounter != null
		else 0
	)
	communication_points_initial = communication_points
	communication_points_spent = 0
	var baseline_encounter := CombatEncounterRecord.from_dict(encounter.to_dict())
	if baseline_encounter.center_hex != null:
		baseline_encounter.center_hex.combat_site_state.clear()
	_baseline_arena = _generator.generate(baseline_encounter)
	arena_state = _generator.generate(encounter)
	_project_arena()
	board_changed.emit()


func configure_communication_points(actors: Array[HumanoidCore], encounter: CombatEncounterRecord = null) -> int:
	if encounter != null and not encounter.resolved_communication_point_inputs().is_empty():
		communication_points = _CommunicationResolver.communication_points_for(
			encounter.resolved_communication_point_inputs(),
			communication_profile
		)
	elif encounter != null and encounter.resolved_communication_points() > 0:
		communication_points = encounter.resolved_communication_points()
	else:
		var player: HumanoidCore
		for candidate in actors:
			if candidate != null and str(candidate.get_meta("combat_team_id", candidate.get_meta("combat_side", ""))) == "player":
				player = candidate
				break
		var player_will := player.definition.will if player != null and player.definition != null else 0
		var morale := player.current_morale if player != null else 6.0
		var morale_band := "critical" if morale <= 3.0 else ("confident" if morale >= 9.0 else "normal")
		var cohesion_band := "normal"
		var crisis := 0
		if player != null and player.body != null:
			if player.body.blood_level <= 3.0 or player.body.consciousness <= 3.0:
				crisis += 1
			if player.body.thirst <= 1.0 or player.body.hunger <= 1.0 or player.body.fatigue >= 11.0:
				crisis += 1
		communication_points = _CommunicationResolver.communication_points_for({
			"player_will": player_will,
			"morale_band": morale_band,
			"cohesion_band": cohesion_band,
			"biological_crisis": crisis,
		}, communication_profile)
	communication_points_initial = communication_points
	communication_points_spent = 0
	return communication_points


func spend_communication_point() -> bool:
	if communication_points <= 0:
		return false
	communication_points -= 1
	communication_points_spent += 1
	board_changed.emit()
	return true


func communication_points_snapshot() -> Dictionary:
	return {
		"current": communication_points,
		"initial": communication_points_initial,
		"spent": communication_points_spent,
	}


## Compatibility aliases.  New code should use the CP names above.
func configure_squad_points(actors: Array[HumanoidCore], encounter: CombatEncounterRecord = null) -> int:
	return configure_communication_points(actors, encounter)


func spend_squad_point() -> bool:
	return spend_communication_point()


func squad_points_snapshot() -> Dictionary:
	return communication_points_snapshot()


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
		sector.clear_occupants()
	_known_actors.clear()
	actor_facings.clear()
	actor_cover_edges.clear()
	actor_tactics.clear()


func spawn_actor(actor: HumanoidCore, side: String, preferred_row: int = 2) -> int:
	var index := find_spawn_sector(side, preferred_row)
	if index < 0:
		return -1
	remove_actor(actor)
	if not sectors[index].add_occupant(actor):
		return -1
	if actor not in _known_actors:
		_known_actors.append(actor)
	_initialize_combat_state(actor)
	actor.set_meta("combat_side", side)
	actor_facings[_actor_id(actor)] = "east" if side == "player" else "west"
	actor_tactics[_actor_id(actor)] = _default_tactics()
	board_changed.emit()
	return index


func force_spawn_actor(actor: HumanoidCore, index: int, side: String = "", forced: bool = false) -> bool:
	if not _valid_index(index):
		return false
	remove_actor(actor)
	if not sectors[index].can_enter(actor, forced) or not sectors[index].add_occupant(actor, forced):
		return false
	if actor not in _known_actors:
		_known_actors.append(actor)
	_initialize_combat_state(actor)
	if not side.is_empty():
		actor.set_meta("combat_side", side)
	actor_facings[_actor_id(actor)] = "east" if str(actor.get_meta("combat_side", "player")) == "player" else "west"
	actor_tactics[_actor_id(actor)] = _default_tactics()
	board_changed.emit()
	return true


func remove_actor(actor: HumanoidCore) -> void:
	if actor == null:
		return
	for sector in sectors:
		sector.remove_occupant(actor)
		actor_facings.erase(_actor_id(actor))
		actor_cover_edges.erase(_actor_id(actor))
	actor_tactics.erase(_actor_id(actor))
	board_changed.emit()


func mark_incapacitated(actor: HumanoidCore, reason: String = "combat_incapacitate") -> Dictionary:
	"""Move an actor from the active layer into the captive handoff layer.

	Incapacitation is deliberately not represented as a dead actor with zero AP:
	the board removes it from active occupancy/initiative while the sector record
	keeps its exact location for conversation and looting handoff.
	"""
	if actor == null:
		return {}
	var state := combat_state(actor)
	if state == null:
		return {}
	var index := position_of(actor)
	state.incapacitated = true
	state.surrendered = false
	state.broken = false
	state.activation_lost = false
	actor.is_comatose = true
	actor.current_max_ap = 0
	actor.set_meta("combat_actor_state", state)
	var receipt := {
		"actor_id": _actor_id(actor),
		"sector_index": index,
		"sector": arena_state.coords_for(index) if _valid_index(index) else Vector2i(-1, -1),
		"reason": reason,
	}
	if _valid_index(index):
		var ids := sectors[index].record.incapacitated_entity_ids
		if receipt.actor_id not in ids:
			ids.append(receipt.actor_id)
		sectors[index].record.body_entity_ids.erase(receipt.actor_id)
	remove_actor(actor)
	board_changed.emit()
	return receipt


func mark_surrendered(actor: HumanoidCore, reason: String = "surrender") -> Dictionary:
	"""Move a surrendered actor into the non-active surrender handoff layer."""
	if actor == null:
		return {}
	var state := combat_state(actor)
	if state == null:
		return {}
	var index := position_of(actor)
	state.surrendered = true
	state.incapacitated = false
	state.broken = false
	state.activation_lost = false
	actor.set_meta("combat_surrendered", true)
	actor.set_meta("combat_actor_state", state)
	var receipt := {
		"actor_id": _actor_id(actor),
		"sector_index": index,
		"sector": arena_state.coords_for(index) if _valid_index(index) else Vector2i(-1, -1),
		"reason": reason,
	}
	if _valid_index(index):
		var ids := sectors[index].record.surrendered_entity_ids
		if receipt.actor_id not in ids:
			ids.append(receipt.actor_id)
		sectors[index].record.incapacitated_entity_ids.erase(receipt.actor_id)
	remove_actor(actor)
	board_changed.emit()
	return receipt


func position_of(actor: HumanoidCore) -> int:
	for index in range(sectors.size()):
		if actor in sectors[index].occupants:
			return index
	return -1


func actor_at(index: int) -> HumanoidCore:
	return sectors[index].occupant if _valid_index(index) else null


func actors_at(index: int) -> Array[HumanoidCore]:
	if not _valid_index(index):
		return []
	return sectors[index].occupants.duplicate()


func active_actors() -> Array[HumanoidCore]:
	var result: Array[HumanoidCore] = []
	for sector in sectors:
		for actor in sector.occupants:
			if _is_active_combat_actor(actor):
				result.append(actor)
	return result


func has_active_player_hostile(player: HumanoidCore) -> bool:
	if player == null:
		return false
	for candidate in active_actors():
		if candidate != player and is_hostile(player, candidate):
			return true
	return false


func has_active_hostile_conflict(excluding: HumanoidCore = null) -> bool:
	var candidates := active_actors()
	for left_index in range(candidates.size()):
		for right_index in range(left_index + 1, candidates.size()):
			var left := candidates[left_index]
			var right := candidates[right_index]
			if excluding != null and (left == excluding or right == excluding):
				continue
			if is_hostile(left, right):
				return true
	return false


func can_enter(actor: HumanoidCore, index: int, forced: bool = false) -> bool:
	return can_enter_with_policy(
		actor,
		index,
		ENTRY_FORCED_DISPLACEMENT if forced else ENTRY_ORDINARY
	)


func can_enter_with_policy(
	actor: HumanoidCore,
	index: int,
	entry_policy: String = ENTRY_ORDINARY,
	engagement_target: HumanoidCore = null
) -> bool:
	if not _valid_index(index):
		return false
	var sector := sectors[index]
	if not sector.can_enter_with_policy(actor, entry_policy, engagement_target):
		return false
	if entry_policy == ENTRY_HOSTILE_ENGAGEMENT:
		return (
			engagement_target != null
			and sector.occupants.size() == 1
			and sector.occupants[0] == engagement_target
			and is_hostile(actor, engagement_target)
		)
	return true


func occupancy_kind(index: int) -> String:
	if not _valid_index(index):
		return "invalid"
	var occupants := sectors[index].occupants
	if occupants.is_empty():
		return "empty"
	if occupants.size() == 1:
		return "single"
	for left_index in range(occupants.size()):
		for right_index in range(left_index + 1, occupants.size()):
			if is_hostile(occupants[left_index], occupants[right_index]):
				return "engaged"
	return "crowded"


func is_engaged(index: int) -> bool:
	return occupancy_kind(index) == "engaged"


func is_crowded(index: int) -> bool:
	return occupancy_kind(index) == "crowded"


func combat_state(actor: HumanoidCore) -> CombatActorState:
	if actor == null:
		return null
	var existing: Variant = actor.get_meta("combat_actor_state") if actor.has_meta("combat_actor_state") else null
	if existing is CombatActorState:
		(existing as CombatActorState).reconcile()
		return existing as CombatActorState
	var state := _CombatActorState.from_runtime(existing if existing is Dictionary else {})
	actor.set_meta("combat_actor_state", state)
	return state


func stance(actor: HumanoidCore) -> float:
	var state := combat_state(actor)
	return state.stance if state != null else 0.0


func max_stance(actor: HumanoidCore) -> float:
	var state := combat_state(actor)
	return state.max_stance if state != null else 0.0


func apply_stance_damage(actor: HumanoidCore, amount: float, critical: bool = false, source: String = "") -> Dictionary:
	var state := combat_state(actor)
	if state == null or amount <= 0.0 or actor.is_dead or state.incapacitated:
		return {"actor_id": _actor_id(actor), "amount": 0.0, "broken": state != null and state.broken}
	var applied := balance_profile.critical_stance_damage(amount) if critical else amount
	var before := state.stance
	state.stance = maxf(0.0, state.stance - applied)
	state.reconcile()
	set_condition(actor, "broken", state.broken)
	return {
		"actor_id": _actor_id(actor),
		"before": before,
		"after": state.stance,
		"amount": applied,
		"critical": critical,
		"broken": state.broken,
		"source": source,
	}


func _initialize_combat_state(actor: HumanoidCore) -> void:
	if actor == null or actor.definition == null:
		return
	var state := combat_state(actor)
	if state.max_stance <= 0.0 or state.max_stance == 12.0:
		var equipment_modifier := 0.0
		if actor.inventory != null:
			for equipped in actor.inventory.paper_doll.values():
				if equipped is ItemData:
					equipment_modifier += float(equipped.stance_modifier)
		state.max_stance = balance_profile.stance_for(
			actor.definition.brawn,
			actor.definition.fortitude,
			actor.definition.will,
			equipment_modifier
		)
	if state.stance <= 0.0 or state.stance > state.max_stance:
		state.stance = state.max_stance
	state.reconcile()


func actor_by_id(actor_id: String) -> HumanoidCore:
	for actor in _known_actors:
		if _actor_id(actor) == actor_id:
			return actor
	for sector in sectors:
		for occupant in sector.occupants:
			if _actor_id(occupant) == actor_id:
				return occupant
	return null


func neighboring_indices(index: int) -> Array[int]:
	var result: Array[int] = []
	if not _valid_index(index):
		return result
	var coords := arena_state.coords_for(index)
	for delta: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var candidate := coords + delta
		if arena_state.contains(candidate):
			result.append(arena_state.index_for(candidate))
	return result


func grid_distance(left: int, right: int) -> int:
	if not _valid_index(left) or not _valid_index(right):
		return 999
	var a := arena_state.coords_for(left)
	var b := arena_state.coords_for(right)
	return absi(a.x - b.x) + absi(a.y - b.y)


func validate_path(
	actor: HumanoidCore,
	requested: Array[Vector2i],
	entry_policy: String = ENTRY_ORDINARY,
	engagement_target: HumanoidCore = null
) -> Dictionary:
	var origin := position_of(actor)
	if origin < 0:
		return {"valid": false, "code": "actor_not_on_board", "path": []}
	var normalized: Array[int] = [origin]
	var previous := origin
	for coords in requested:
		if not arena_state.contains(coords):
			return {"valid": false, "code": "path_out_of_bounds", "path": normalized}
		var index := arena_state.index_for(coords)
		if index == previous:
			continue
		if index not in neighboring_indices(previous):
			return {"valid": false, "code": "path_not_orthogonal", "path": normalized}
		var step_policy := entry_policy if coords == requested.back() else ENTRY_ORDINARY
		if not can_enter_with_policy(actor, index, step_policy, engagement_target):
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


func commit_path(
	actor: HumanoidCore,
	path: Array,
	suppress_reactions: bool = false,
	entry_policy: String = ENTRY_ORDINARY,
	engagement_target: HumanoidCore = null
) -> Array[Dictionary]:
	var changes: Array[Dictionary] = []
	if actor == null or path.size() < 2 or int(path[0]) != position_of(actor):
		return changes
	for offset in range(1, path.size()):
		var preflight_policy := entry_policy if offset == path.size() - 1 else ENTRY_ORDINARY
		if not can_enter_with_policy(actor, int(path[offset]), preflight_policy, engagement_target):
			return []
	for offset in range(1, path.size()):
		var from_index := int(path[offset - 1])
		var to_index := int(path[offset])
		var step_policy := entry_policy if offset == path.size() - 1 else ENTRY_ORDINARY
		if not can_enter_with_policy(actor, to_index, step_policy, engagement_target):
			return []
		sectors[from_index].remove_occupant(actor)
		if not sectors[to_index].add_occupant_with_policy(actor, step_policy, engagement_target):
			return []
		set_facing(actor, facing_toward(from_index, to_index))
		actor_cover_edges.erase(_actor_id(actor))
		changes.append({
			"actor_id": _actor_id(actor),
			"from": arena_state.coords_for(from_index),
			"to": arena_state.coords_for(to_index),
			"suppress_reactions": suppress_reactions,
		})
		_resolve_entry(actor, sectors[to_index])
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
			if came_from.has(neighbor) or not sectors[neighbor].can_enter(actor):
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
			if not sectors[neighbor].can_enter(actor):
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
			for threat in sectors[neighbor].occupants:
				if not _hostile(actor, threat):
					continue
				if can_melee_reach(threat, to_index):
					continue
				var id := _actor_id(threat)
				if id not in ids:
					ids.append(id)
	return ids


func has_line_of_sight(from_index: int, to_index: int) -> bool:
	if not _valid_index(from_index) or not _valid_index(to_index):
		return false
	var start := Vector2(arena_state.coords_for(from_index))
	var finish := Vector2(arena_state.coords_for(to_index))
	var steps := maxi(absi(int(finish.x - start.x)), absi(int(finish.y - start.y)))
	for step in range(1, steps):
		var point := start.lerp(finish, float(step) / float(steps))
		var coords := Vector2i(roundi(point.x), roundi(point.y))
		if sectors[arena_state.index_for(coords)].opaque:
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
	var delta := arena_state.coords_for(to_index) - arena_state.coords_for(from_index)
	if absi(delta.x) >= absi(delta.y):
		return "east" if delta.x >= 0 else "west"
	return "south" if delta.y >= 0 else "north"


func attack_arc(attacker: HumanoidCore, defender: HumanoidCore) -> Dictionary:
	return attack_arc_from(position_of(attacker), position_of(defender), defender)


func attack_arc_from(attacker_index: int, defender_index: int, defender: HumanoidCore = null) -> Dictionary:
	var incoming := facing_toward(defender_index, attacker_index)
	var facing := get_facing(defender)
	if incoming == facing:
		return {"arc": "front", "accuracy": 0.0, "reaction_penalty": 0}
	if incoming == str(OPPOSITE.get(facing, "")):
		return {"arc": "rear", "accuracy": 0.16, "reaction_penalty": 3}
	return {"arc": "side", "accuracy": 0.08, "reaction_penalty": 1}


func posture(actor: HumanoidCore) -> String:
	return str(_tactics(actor).get("posture", "standing"))


func set_posture(actor: HumanoidCore, value: String) -> bool:
	if value not in ["standing", "crouched"]:
		return false
	_tactics(actor)["posture"] = value
	board_changed.emit()
	return true


func has_condition(actor: HumanoidCore, condition_id: String) -> bool:
	return bool(_tactics(actor).get(condition_id, false))


func set_condition(actor: HumanoidCore, condition_id: String, enabled: bool) -> void:
	_tactics(actor)[condition_id] = enabled
	board_changed.emit()


func preview_shove(initiator: HumanoidCore, target: HumanoidCore, shove_direction: String = "") -> Dictionary:
	var source_index := position_of(initiator)
	var target_index := position_of(target)
	return preview_shove_from(source_index, target_index, shove_direction)


func preview_shove_from(source_index: int, target_index: int, shove_direction: String = "") -> Dictionary:
	var separation := grid_distance(source_index, target_index)
	if separation != 0:
		return {"type": "invalid", "reason": "co_occupancy_required"}
	var direction := shove_direction.to_lower()
	if direction.is_empty() and separation == 1:
		direction = facing_toward(source_index, target_index)
	if direction not in FACINGS:
		return {"type": "invalid", "reason": "cardinal_direction_required"}
	var destination_coords := arena_state.coords_for(target_index) + _direction_vector(direction)
	if not arena_state.contains(destination_coords):
		var forced_edges: Array = sectors[target_index].record.object_state.get("forced_exit_edges", [])
		return {
			"type": "forced_exit" if direction in forced_edges else "boundary",
			"from": arena_state.coords_for(target_index),
			"direction": direction,
		}
	var destination := arena_state.index_for(destination_coords)
	var destination_sector := sectors[destination]
	if destination_sector.occupants.size() >= 2:
		return {
			"type": "full",
			"from": arena_state.coords_for(target_index),
			"destination": destination_coords,
			"direction": direction,
		}
	if not destination_sector.occupants.is_empty():
		return {
			"type": "actor_collision",
			"from": arena_state.coords_for(target_index),
			"destination": destination_coords,
			"other_actor_id": _actor_id(destination_sector.occupant),
			"direction": direction,
		}
	if destination_sector.blocked:
		return {
			"type": "object_collision",
			"from": arena_state.coords_for(target_index),
			"destination": destination_coords,
			"object_id": str(destination_sector.record.object_state.get("id", "")),
			"destructible": destination_sector.object_durability > 0.0,
			"direction": direction,
		}
	return {
		"type": "clear",
		"from": arena_state.coords_for(target_index),
		"destination": destination_coords,
		"direction": direction,
		"hazard": destination_sector.hazard_state.duplicate(true),
		"trap": destination_sector.trap_state.duplicate(true),
	}


func commit_shove(
	initiator: HumanoidCore,
	target: HumanoidCore,
	margin: float,
	collision_damage: float,
	shove_direction: String = ""
) -> Dictionary:
	var preview := preview_shove(initiator, target, shove_direction)
	var result := preview.duplicate(true)
	result["moved"] = false
	match str(preview.get("type", "invalid")):
		"clear":
			var from_index := position_of(target)
			var destination := arena_state.index_for(preview.destination)
			sectors[from_index].remove_occupant(target)
			sectors[destination].add_occupant(target, true)
			set_facing(target, facing_toward(from_index, destination))
			_resolve_entry(target, sectors[destination])
			result["moved"] = true
		"object_collision":
			var destination := arena_state.index_for(preview.destination)
			result["terrain_mutation"] = sectors[destination].damage_object(collision_damage)
			set_condition(target, "off_balance", true)
		"actor_collision":
			var other := actor_by_id(str(preview.other_actor_id))
			var from_index := position_of(target)
			var destination := arena_state.index_for(preview.destination)
			if other == null or from_index < 0 or not sectors[destination].add_occupant_with_policy(target, ENTRY_FORCED_DISPLACEMENT):
				result["moved"] = false
			else:
				sectors[from_index].remove_occupant(target)
				set_facing(target, facing_toward(from_index, destination))
				_resolve_entry(target, sectors[destination])
				result["moved"] = true
				apply_stance_damage(target, balance_profile.collision_stance_damage, false, "shove_collision")
				apply_stance_damage(other, balance_profile.collision_stance_damage, false, "shove_collision")
				set_condition(target, "off_balance", true)
				set_condition(other, "off_balance", true)
		"forced_exit":
			remove_actor(target)
			forced_exit.emit(target, str(preview.direction))
			result["moved"] = true
		"boundary":
			set_condition(target, "off_balance", true)
		"full":
			result["moved"] = false
	if margin >= balance_profile.off_balance_margin:
		set_condition(target, "off_balance", true)
	board_changed.emit()
	return result


func _direction_vector(direction: String) -> Vector2i:
	match direction:
		"north":
			return Vector2i.UP
		"south":
			return Vector2i.DOWN
		"west":
			return Vector2i.LEFT
		"east":
			return Vector2i.RIGHT
	return Vector2i.ZERO


func weapon_reach(actor: HumanoidCore) -> int:
	if actor == null:
		return 0
	var weapon := actor.inventory.get_active_weapon(true)
	return maxi(0, (weapon.weapon_reach_cells - 1) if weapon != null else 0)


func can_melee_reach(actor: HumanoidCore, target_index: int) -> bool:
	return can_melee_reach_from(position_of(actor), target_index, actor)


func can_melee_reach_from(origin: int, target_index: int, actor: HumanoidCore = null) -> bool:
	if not _valid_index(origin) or not _valid_index(target_index):
		return false
	var from := arena_state.coords_for(origin)
	var target := arena_state.coords_for(target_index)
	var delta := target - from
	var distance := absi(delta.x) + absi(delta.y)
	# Two hostile actors may share a sector. They are already engaged, so a
	# melee attack is legal at distance zero; ordinary movement still remains
	# blocked by the engagement rule in the action quote.
	if distance == 0:
		return actor != null
	if actor != null and distance > weapon_reach(actor):
		return false
	if actor == null and distance > 1:
		return false
	if delta.x != 0 and delta.y != 0:
		return false
	if distance > 1:
		var step := Vector2i(signi(delta.x), signi(delta.y))
		for offset in range(1, distance):
			var intervening := sectors[arena_state.index_for(from + step * offset)]
			if intervening.opaque or not intervening.occupants.is_empty():
				return false
	return true


func find_spawn_sector(side: String, preferred_row: int = 2) -> int:
	var profile := CombatTopologyCatalog.load_profile(arena_state.topology_id)
	var deployment := profile.player_deployment if side == "player" else profile.enemy_deployment
	for coords in deployment:
		if not arena_state.contains(coords):
			continue
		var index := arena_state.index_for(coords)
		if sectors[index].spawnable and sectors[index].is_open_for():
			return index
	var fallback_x := 0 if side == "player" else arena_state.width - 1
	var fallback := Vector2i(fallback_x, clampi(preferred_row, 0, arena_state.height - 1))
	if arena_state.contains(fallback):
		var fallback_index := arena_state.index_for(fallback)
		if sectors[fallback_index].spawnable and sectors[fallback_index].is_open_for():
			return fallback_index
	return -1


func find_nearest_open_sector(
	preferred_index: int,
	actor: HumanoidCore = null,
	forced: bool = false
) -> int:
	if _valid_index(preferred_index) and sectors[preferred_index].spawnable and _sector_open_for(sectors[preferred_index], actor, forced):
		return preferred_index
	for radius in range(1, arena_state.width + arena_state.height):
		for index in range(sectors.size()):
			if grid_distance(preferred_index, index) == radius and sectors[index].spawnable and _sector_open_for(sectors[index], actor, forced):
				return index
	return -1


func _sector_open_for(sector: TacticalSectorRuntime, actor: HumanoidCore, forced: bool) -> bool:
	if sector == null:
		return false
	if actor == null:
		return sector.is_open_for()
	return sector.can_enter(actor, forced)


func capture_environment_patch() -> Dictionary:
	var patches: Dictionary = {}
	for sector in sectors:
		var current := sector.capture_mutation_patch()
		var baseline := _record_patch(_baseline_arena.sector_at(sector.coords)) if _baseline_arena != null else {}
		if current != baseline:
			patches[str(sector.index)] = current
	return {
		"schema_version": CombatArenaState.SCHEMA_VERSION,
		"topology_id": arena_state.topology_id if arena_state != null else CombatTopologyCatalog.DEFAULT_ID,
		"baseline_seed": arena_state.baseline_seed if arena_state != null else 0,
		"sector_patches": patches,
	}


func snapshot() -> Dictionary:
	var sector_data: Array[Dictionary] = []
	for sector in sectors:
		sector_data.append(sector.presentation_descriptor())
	var direct_player := actor_by_id("player")
	if direct_player == null:
		for candidate in active_actors():
			if bool(candidate.get_meta("direct_player", false)):
				direct_player = candidate
				break
	return {
		"topology_id": arena_state.topology_id,
		"width": arena_state.width,
		"height": arena_state.height,
		"movement_policy": arena_state.movement_policy,
		"presentation_style": CombatTopologyCatalog.load_profile(arena_state.topology_id).presentation_style,
		"sectors": sector_data,
		"facings": actor_facings.duplicate(true),
		"cover_edges": actor_cover_edges.duplicate(true),
		"tactics": actor_tactics.duplicate(true),
		"relationships": relationship_ledger.to_dict() if relationship_ledger != null else {},
		"communication_points": communication_points_snapshot(),
		# Compatibility snapshot key for older HUD/test readers.
		"squad_points": communication_points_snapshot(),
		"combat_states": _combat_states_snapshot(),
		"player_hostile_active": has_active_player_hostile(direct_player),
		"hostile_conflict_active": has_active_hostile_conflict(direct_player),
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
	}


func _combat_states_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for actor in _known_actors:
		var known_state := combat_state(actor)
		if known_state != null:
			result[_actor_id(actor)] = known_state.to_dict()
	for sector in sectors:
		for actor in sector.occupants:
			var state := combat_state(actor)
			if state != null:
				result[_actor_id(actor)] = state.to_dict()
	return result


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


func _is_active_combat_actor(actor: HumanoidCore) -> bool:
	if actor == null or actor.is_dead or actor.is_comatose:
		return false
	var state := combat_state(actor)
	return state == null or (not state.incapacitated and not state.surrendered)


func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))


func _hostile(left: HumanoidCore, right: HumanoidCore) -> bool:
	if left == null or right == null or left == right:
		return false
	var left_id := _actor_id(left)
	var right_id := _actor_id(right)
	if relationship_ledger != null and relationship_ledger.relation_by_pair.has(_RelationshipLedger.pair_key(left_id, right_id)):
		return relationship_ledger.relation(left_id, right_id) == _RelationshipLedger.Relation.HOSTILE
	return left.definition != null and right.definition != null and left.definition.faction != right.definition.faction


func relation_between(left: HumanoidCore, right: HumanoidCore) -> int:
	if left == null or right == null:
		return _RelationshipLedger.Relation.NEUTRAL
	var fallback := _RelationshipLedger.Relation.NEUTRAL
	if left.definition != null and right.definition != null and left.definition.faction != right.definition.faction:
		fallback = _RelationshipLedger.Relation.HOSTILE
	return relationship_ledger.relation(_actor_id(left), _actor_id(right), fallback)


func is_hostile(left: HumanoidCore, right: HumanoidCore) -> bool:
	return _hostile(left, right)


func set_relation(left: HumanoidCore, right: HumanoidCore, value: int) -> void:
	if relationship_ledger == null:
		relationship_ledger = _RelationshipLedger.new()
	if left != null and right != null:
		relationship_ledger.set_relation(_actor_id(left), _actor_id(right), value)
	board_changed.emit()
