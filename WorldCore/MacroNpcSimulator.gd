extends RefCounted

const _Perception := preload("res://WorldCore/WorldPerceptionQuery.gd")
const _NpcBehaviorState := preload("res://SystemCore/NpcBehaviorState.gd")
const _NpcBehaviorCatalog := preload("res://SystemCore/NpcBehaviorProfileCatalog.gd")

## Neutral NPC macro AI, projection scoring, and encounter roll planning.
## MacroGameManager applies moves, spawns tokens, and handles collisions.

const HEX_NEIGHBORS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const AI_SCHEMA_VERSION := 1
const ROLE_CATALOG_PATH := "res://WorldCore/npc_roles.tres"
const BEHAVIOR_PROFILE_PATH := "res://WorldCore/npc_behavior_profiles.tres"


static func role_descriptor(record: EntityRecord) -> Dictionary:
	var role_id := str(record.runtime.get("npc_role_id", ""))
	if role_id.is_empty():
		role_id = str(record.definition.get("npc_role_id", ""))
	if role_id.is_empty():
		role_id = _fallback_role_id(record)
	record.runtime["npc_role_id"] = role_id
	var catalog := load(ROLE_CATALOG_PATH) as NpcRoleCatalog
	var descriptor := catalog.descriptor(role_id) if catalog != null else {}
	var behavior_catalog := load(BEHAVIOR_PROFILE_PATH) as NpcBehaviorProfileCatalog
	var behavior := (
		behavior_catalog.profile_for_role(role_id)
		if behavior_catalog != null
		else null
	)
	if behavior != null:
		descriptor["behavior_profile_id"] = behavior.profile_id
		descriptor["hunger_threshold"] = behavior.hunger_threshold
		descriptor["thirst_threshold"] = behavior.thirst_threshold
		if behavior.pursuit_radius > 0:
			descriptor["pursuit_radius"] = behavior.pursuit_radius
		descriptor["work_weights"] = behavior.work_weights.duplicate(true)
		descriptor["combat_weights"] = behavior.combat_weights.duplicate(true)
	var shared_catalog: Resource = _NpcBehaviorCatalog.load_default()
	var shared_state: Resource = _NpcBehaviorState.from_runtime(record.runtime, record.definition)
	record.runtime[_NpcBehaviorState.RUNTIME_KEY] = shared_state.to_dict()
	var shared_profile: Resource = (
		shared_catalog.profile_for_id(shared_state.profile_id)
		if shared_catalog != null
		else null
	)
	if shared_profile != null:
		var exploration: Dictionary = shared_profile.exploration_projection()
		descriptor["behavior_profile_id"] = shared_profile.profile_id
		descriptor["goal_weights"] = exploration.get("goal_weights", {}).duplicate(true)
		descriptor["survival_pressure"] = shared_state.survival_pressure
		descriptor["retreat_pressure"] = shared_profile.retreat_pressure
	return descriptor


static func _fallback_role_id(record: EntityRecord) -> String:
	if _is_stationary_guard(record):
		return "sentry"
	var faction: GameEnums.Faction = record.definition.get(
		"faction", GameEnums.Faction.UNALIGNED
	)
	match faction:
		GameEnums.Faction.CRAVEN_HIVE:
			return "stalker"
		GameEnums.Faction.ARCBORN_RESISTANCE:
			return "patrol"
		GameEnums.Faction.SCAVENGER_CELL:
			return "raider"
		_:
			return "salvager"


static func ensure_npc_memory(record: EntityRecord) -> Dictionary:
	var ai: Dictionary = record.runtime.get("macro_ai", {})
	ai["schema_version"] = AI_SCHEMA_VERSION
	ai["role_id"] = str(record.runtime.get("npc_role_id", _fallback_role_id(record)))
	if not ai.has("memory"):
		ai["memory"] = {
			"player_trust": 0.0,
			"player_threat": 0.0,
			"last_player_coords": null,
			"last_player_turn": -1,
			"events": [],
		}
	record.runtime["macro_ai"] = ai
	return ai


static func remember_player_event(
	record: EntityRecord,
	event_id: String,
	turn_index: int,
	player_coords: Vector2i,
	trust_delta: float = 0.0,
	threat_delta: float = 0.0
) -> void:
	var ai := ensure_npc_memory(record)
	var memory: Dictionary = ai.get("memory", {})
	memory["player_trust"] = clampf(float(memory.get("player_trust", 0.0)) + trust_delta, -12.0, 12.0)
	memory["player_threat"] = clampf(float(memory.get("player_threat", 0.0)) + threat_delta, 0.0, 12.0)
	memory["last_player_coords"] = player_coords
	memory["last_player_turn"] = turn_index
	var events: Array = memory.get("events", [])
	events.append({"id": event_id, "turn": turn_index, "coords": player_coords})
	while events.size() > 8:
		events.pop_front()
	memory["events"] = events
	ai["memory"] = memory
	record.runtime["macro_ai"] = ai


static func select_goal(
	record: EntityRecord,
	player_coords: Vector2i,
	world_seed: String,
	macro_turn_index: int
) -> String:
	var role := role_descriptor(record)
	var ai := ensure_npc_memory(record)
	var memory: Dictionary = ai.get("memory", {})
	var weights: Dictionary = role.get("goal_weights", {}).duplicate(true)
	if weights.is_empty():
		weights[str(role.get("default_goal_id", "roam"))] = 1.0
	var distance := hex_distance(record.coords, player_coords)
	var detection_radius := int(role.get("detection_radius", 5))
	if record.world_status == GameEnums.EntityWorldStatus.HOSTILE and distance <= detection_radius:
		weights["hunt"] = float(weights.get("hunt", 0.0)) + 12.0
		memory["last_player_coords"] = player_coords
		memory["last_player_turn"] = macro_turn_index
	if float(memory.get("player_threat", 0.0)) >= 6.0 and record.world_status != GameEnums.EntityWorldStatus.HOSTILE:
		weights["evade"] = float(weights.get("evade", 0.0)) + 8.0
	var pressure := float(role.get("survival_pressure", 0.0))
	var retreat_pressure := float(role.get("retreat_pressure", GameEnums.SCALE_MAX))
	if pressure >= retreat_pressure:
		weights["scavenge"] = float(weights.get("scavenge", 0.0)) + pressure
		weights["evade"] = float(weights.get("evade", 0.0)) + pressure * 0.75
	var best_goal := str(role.get("default_goal_id", "roam"))
	var best_score := -INF
	for goal_key in weights.keys():
		var jitter_seed := (
			world_seed + ":npc_goal:" + record.entity_id + ":"
			+ str(macro_turn_index / 4) + ":" + str(goal_key)
		).hash()
		var score := float(weights[goal_key]) + float(posmod(jitter_seed, 1000)) / 10000.0
		if score > best_score:
			best_score = score
			best_goal = str(goal_key)
	ai["goal_id"] = best_goal
	ai["goal_label"] = best_goal.capitalize()
	ai["goal_selected_turn"] = macro_turn_index
	ai["memory"] = memory
	record.runtime["macro_ai"] = ai
	record.runtime["macro_purpose"] = _goal_to_purpose(best_goal)
	record.runtime["macro_purpose_label"] = best_goal.capitalize()
	return best_goal


static func _goal_to_purpose(goal_id: String) -> String:
	match goal_id:
		"hunt", "ambush":
			return GameEnums.NPC_PURPOSE_HUNT
		"scavenge":
			return GameEnums.NPC_PURPOSE_SCAVENGE
		"patrol", "investigate":
			return GameEnums.NPC_PURPOSE_PATROL
		"hold", "trade":
			return GameEnums.NPC_PURPOSE_HOLD
		_:
			return GameEnums.NPC_PURPOSE_ROAM


static func hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))


static func coords_in_radius(
	center_coords: Vector2i,
	radius: int
) -> Array[Vector2i]:
	var coords_list: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		for r in range(
			max(-radius, -q - radius),
			min(radius, -q + radius) + 1
		):
			coords_list.append(center_coords + Vector2i(q, r))
	return coords_list


static func encounter_key(world_seed: String, coords: Vector2i) -> String:
	return (
		world_seed
		+ ":encounter:"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
	)


static func ensure_npc_purpose(record: EntityRecord) -> String:
	var purpose := str(record.runtime.get("macro_purpose", ""))
	# Posted Central Guards must never wander, even if an older save stamped patrol.
	if _is_stationary_guard(record):
		purpose = GameEnums.NPC_PURPOSE_HOLD
		record.runtime["macro_purpose"] = purpose
		record.runtime["macro_purpose_label"] = "Hold"
		record.runtime["macro_target_coords"] = record.coords
		return purpose
	if not purpose.is_empty():
		return purpose
	var faction: GameEnums.Faction = record.definition.get(
		"faction",
		GameEnums.Faction.UNALIGNED
	)
	match faction:
		GameEnums.Faction.CRAVEN_HIVE:
			purpose = GameEnums.NPC_PURPOSE_HUNT
		GameEnums.Faction.ARCBORN_RESISTANCE:
			purpose = GameEnums.NPC_PURPOSE_PATROL
		GameEnums.Faction.SCAVENGER_CELL:
			purpose = GameEnums.NPC_PURPOSE_SCAVENGE
		_:
			purpose = GameEnums.NPC_PURPOSE_ROAM
	record.runtime["macro_purpose"] = purpose
	record.runtime["macro_purpose_label"] = purpose.capitalize()
	return purpose


static func _is_stationary_guard(record: EntityRecord) -> bool:
	if record == null:
		return false
	var template_id := str(record.definition.get("template_id", ""))
	if template_id.is_empty():
		template_id = str(record.runtime.get("template_id", ""))
	return template_id == "central_guard"


static func initialize_npc_runtime(
	record: EntityRecord,
	world_seed: String,
	macro_turn_index: int,
	player_coords: Vector2i,
	get_hex_at: Callable,
	has_ground_items: Callable,
	world_time_minutes: int = 0
) -> void:
	if record == null:
		return
	if not record.runtime.has("macro_origin_coords"):
		record.runtime["macro_origin_coords"] = record.coords
	role_descriptor(record)
	ensure_npc_memory(record)
	select_goal(record, player_coords, world_seed, macro_turn_index)
	var purpose := ensure_npc_purpose(record)
	if not record.runtime.has("macro_target_coords"):
		record.runtime["macro_target_coords"] = purpose_target_for(
			record,
			purpose,
			world_seed,
			macro_turn_index,
			player_coords,
			get_hex_at,
			has_ground_items,
			world_time_minutes
		)


static func purpose_target_for(
	record: EntityRecord,
	purpose: String,
	world_seed: String,
	macro_turn_index: int,
	player_coords: Vector2i,
	get_hex_at: Callable,
	has_ground_items: Callable,
	world_time_minutes: int = 0
) -> Vector2i:
	var existing = record.runtime.get("macro_target_coords", null)
	if existing is Vector2i:
		return existing
	var target := record.coords
	match purpose:
		GameEnums.NPC_PURPOSE_SCAVENGE:
			target = find_scavenge_target(
				record.coords,
				get_hex_at,
				has_ground_items,
				world_time_minutes
			)
		GameEnums.NPC_PURPOSE_PATROL:
			target = patrol_target(record, get_hex_at)
		GameEnums.NPC_PURPOSE_HUNT:
			target = player_coords
		GameEnums.NPC_PURPOSE_HOLD:
			target = record.coords
		_:
			target = roam_target(
				record,
				world_seed,
				macro_turn_index
			)
	record.runtime["macro_target_coords"] = target
	return target


static func find_scavenge_target(
	origin: Vector2i,
	get_hex_at: Callable,
	has_ground_items: Callable,
	now_minutes: int = 0
) -> Vector2i:
	var best := origin
	var best_score := -999999.0
	for coords in coords_in_radius(origin, 5):
		var hex_data: MacroHexData = get_hex_at.call(coords)
		if not hex_data.is_passable():
			continue
		var score := -float(hex_distance(origin, coords))
		if hex_data.is_poi:
			score += 12.0
		if hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE:
			score += 8.0
		if not hex_data.search_site_id.is_empty():
			var site_catalog := SearchSiteCatalog.data()
			var site := (
				site_catalog.get_site(hex_data.search_site_id)
				if site_catalog != null
				else null
			)
			score += 16.0
		# V3 objects are the physical source of truth. A generated rubble parcel
		# remains interesting even when its legacy search-site adapter is empty.
		for object_value in hex_data.world_objects:
			if not object_value is Dictionary:
				continue
			var object_components: Dictionary = object_value.get("components", {})
			if object_components.has("rubble") or object_components.has("container"):
				score += 10.0
			if object_components.has("repairable"):
				score += 4.0
		if has_ground_items.call(coords):
			score += 6.0
		for trace_value in hex_data.trace_records:
			if not trace_value is Dictionary:
				continue
			var trace_confidence := _Perception.track_confidence(trace_value, now_minutes, 1.0, 1.0)
			if trace_confidence > 0.1:
				score += 3.0 * trace_confidence
		if hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB:
			score -= 20.0
		if score > best_score:
			best = coords
			best_score = score
	return best


static func patrol_target(
	record: EntityRecord,
	get_hex_at: Callable = Callable()
) -> Vector2i:
	## Patrol is a utility bias, not a private route. Choose a reachable,
	## world-backed point near roads, structures, signals, or recent traces.
	## This keeps patrols meaningful when generation changes and avoids actors
	## walking toward a coordinate that has no physical reason to matter.
	if record == null:
		return Vector2i.ZERO
	var best := record.coords
	var best_score := -INF
	for coords in coords_in_radius(record.coords, 4):
		var hex: MacroHexData = null
		if get_hex_at.is_valid():
			hex = get_hex_at.call(coords) as MacroHexData
		if hex != null and not hex.is_passable():
			continue
		var distance := hex_distance(record.coords, coords)
		var score := -float(distance) * 0.65
		if hex != null:
			if hex.road_mask != 0:
				score += 5.0
			if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
				score += 2.5
			if not hex.world_objects.is_empty():
				score += 1.0
			if not hex.trace_records.is_empty():
				score += 2.0
		var jitter := float(absi((record.entity_id + ":patrol:" + str(coords)).hash()) % 1000) / 100000.0
		score += jitter
		if score > best_score:
			best_score = score
			best = coords
	return best


static func roam_target(
	record: EntityRecord,
	world_seed: String,
	macro_turn_index: int
) -> Vector2i:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":npc_roam:"
		+ record.entity_id
		+ ":"
		+ str(macro_turn_index / 4)
	).hash()
	var choices := coords_in_radius(record.coords, 3)
	if choices.is_empty():
		return record.coords
	return choices[rng.randi_range(0, choices.size() - 1)]


static func can_project_npc_record(
	record: EntityRecord,
	center_coords: Vector2i,
	active_radius: int,
	is_entity_alive: Callable
) -> bool:
	if (
		record == null
		or record.kind != GameEnums.RuntimeEntityKind.NPC
		or record.world_status == GameEnums.EntityWorldStatus.WITHDRAWN
		or not is_entity_alive.call(record.entity_id)
		or hex_distance(center_coords, record.coords) > active_radius
	):
		return false
	return true


static func projection_score(record: EntityRecord, center_coords: Vector2i) -> float:
	var distance := float(hex_distance(center_coords, record.coords))
	var score := 100.0 - (distance * 12.0)
	if record.world_status == GameEnums.EntityWorldStatus.HOSTILE:
		score += 20.0
	# Proximity ordering is a read-only projection. Purpose normalization writes
	# the supplied record, so isolate it from RuntimeStateStore-owned state.
	var projection_record := EntityRecord.from_dict(record.to_dict())
	var purpose := ensure_npc_purpose(projection_record)
	match purpose:
		GameEnums.NPC_PURPOSE_HUNT:
			score += 12.0
		GameEnums.NPC_PURPOSE_SCAVENGE:
			score += 6.0
		GameEnums.NPC_PURPOSE_PATROL:
			score += 4.0
	return score


static func projection_candidates(
	entity_records: Array,
	center_coords: Vector2i,
	active_radius: int,
	is_entity_alive: Callable
) -> Array:
	var candidates: Array = []
	for record in entity_records:
		if not record is EntityRecord:
			continue
		if not can_project_npc_record(
			record,
			center_coords,
			active_radius,
			is_entity_alive
		):
			continue
		candidates.append(record)
	candidates.sort_custom(func(a: EntityRecord, b: EntityRecord) -> bool:
		return projection_score(a, center_coords) > projection_score(b, center_coords)
	)
	return candidates


static func farthest_token_coords(
	active_coords: Array,
	center_coords: Vector2i
) -> Vector2i:
	var farthest := Vector2i.ZERO
	var farthest_distance := -1
	for coords in active_coords:
		var distance := hex_distance(center_coords, coords)
		if distance > farthest_distance:
			farthest = coords
			farthest_distance = distance
	return farthest


static func plan_macro_turn(
	entity_records: Array,
	player_coords: Vector2i,
	world_seed: String,
	macro_turn_index: int,
	npc_evaluation_radius: int,
	npc_wander_chance: float,
	npc_pursuit_radius: int,
	craven_pursuit_radius: int,
	get_hex_at: Callable,
	has_ground_items: Callable,
	get_occupying_entity_id: Callable
) -> Dictionary:
	var moves: Array = []
	var collision: Dictionary = {}
	var records: Array = entity_records.duplicate()
	records.sort_custom(func(a: EntityRecord, b: EntityRecord) -> bool:
		return (
			hex_distance(player_coords, a.coords)
			< hex_distance(player_coords, b.coords)
		)
	)

	for record_entry in records:
		var record := record_entry as EntityRecord
		if record == null:
			continue
		if (
			record.kind != GameEnums.RuntimeEntityKind.NPC
			or record.life_state != GameEnums.EntityLifeState.ALIVE
			or record.world_status == GameEnums.EntityWorldStatus.WITHDRAWN
			or hex_distance(player_coords, record.coords) > npc_evaluation_radius
		):
			continue
		var old_coords: Vector2i = record.coords
		var target_coords: Vector2i = evaluate_npc_step(
			record,
			player_coords,
			world_seed,
			macro_turn_index,
			npc_wander_chance,
			npc_pursuit_radius,
			craven_pursuit_radius,
			get_hex_at,
			has_ground_items,
			get_occupying_entity_id
		)
		if target_coords == old_coords:
			continue
		moves.append({
			"entity_id": record.entity_id,
			"from": old_coords,
			"to": target_coords,
		})
		if (
			target_coords == player_coords
			and record.world_status == GameEnums.EntityWorldStatus.HOSTILE
		):
			collision = {
				"enemy_id": record.entity_id,
				"coords": player_coords,
				"approach_from": old_coords,
			}
			break

	return {
		"moves": moves,
		"collision": collision,
		"moved_count": moves.size(),
	}


static func evaluate_npc_step(
	record: EntityRecord,
	player_coords: Vector2i,
	world_seed: String,
	macro_turn_index: int,
	npc_wander_chance: float,
	npc_pursuit_radius: int,
	craven_pursuit_radius: int,
	get_hex_at: Callable,
	has_ground_items: Callable,
	get_occupying_entity_id: Callable
) -> Vector2i:
	var current_coords := record.coords
	var distance_to_player := hex_distance(current_coords, player_coords)
	if distance_to_player <= 0:
		return current_coords

	var ai := ensure_npc_memory(record)
	var selected_turn := int(ai.get("goal_selected_turn", -999))
	if selected_turn < 0 or macro_turn_index - selected_turn >= 4:
		select_goal(record, player_coords, world_seed, macro_turn_index)
	var purpose := ensure_npc_purpose(record)
	if purpose == GameEnums.NPC_PURPOSE_HOLD:
		record.runtime["macro_target_coords"] = current_coords
		return current_coords

	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":npc_eval:"
		+ record.entity_id
		+ ":"
		+ str(macro_turn_index)
	).hash()

	if record.world_status != GameEnums.EntityWorldStatus.HOSTILE:
		var active_goal := str(ai.get("goal_id", "roam"))
		if active_goal == "evade" or distance_to_player <= 1:
			return best_npc_neighbor(
				record,
				player_coords,
				false,
				get_hex_at,
				get_occupying_entity_id
			)
		if purpose in [GameEnums.NPC_PURPOSE_SCAVENGE, GameEnums.NPC_PURPOSE_PATROL]:
			return evaluate_targeted_purpose_step(
				record,
				player_coords,
				purpose_target_for(
					record, purpose, world_seed, macro_turn_index,
					player_coords, get_hex_at, has_ground_items
				),
				rng,
				npc_wander_chance * 0.5,
				true,
				get_hex_at,
				get_occupying_entity_id
			)
		if rng.randf() <= npc_wander_chance * 0.5:
			return wander_npc_neighbor(
				record,
				player_coords,
				rng,
				get_hex_at,
				get_occupying_entity_id
			)
		return current_coords

	match purpose:
		GameEnums.NPC_PURPOSE_HUNT:
			return evaluate_hunt_step(
				record,
				player_coords,
				distance_to_player,
				rng,
				npc_wander_chance,
				npc_pursuit_radius,
				craven_pursuit_radius,
				get_hex_at,
				get_occupying_entity_id
			)
		GameEnums.NPC_PURPOSE_SCAVENGE:
			return evaluate_targeted_purpose_step(
				record,
				player_coords,
				purpose_target_for(
					record,
					purpose,
					world_seed,
					macro_turn_index,
					player_coords,
					get_hex_at,
					has_ground_items
				),
				rng,
				npc_wander_chance,
				true,
				get_hex_at,
				get_occupying_entity_id
			)
		GameEnums.NPC_PURPOSE_PATROL:
			return evaluate_targeted_purpose_step(
				record,
				player_coords,
				purpose_target_for(
					record,
					purpose,
					world_seed,
					macro_turn_index,
					player_coords,
					get_hex_at,
					has_ground_items
				),
				rng,
				npc_wander_chance,
				false,
				get_hex_at,
				get_occupying_entity_id
			)
		_:
			if rng.randf() <= npc_wander_chance:
				return wander_npc_neighbor(
					record,
					player_coords,
					rng,
					get_hex_at,
					get_occupying_entity_id
				)
			return current_coords


static func evaluate_hunt_step(
	record: EntityRecord,
	player_coords: Vector2i,
	distance_to_player: int,
	rng: RandomNumberGenerator,
	npc_wander_chance: float,
	npc_pursuit_radius: int,
	craven_pursuit_radius: int,
	get_hex_at: Callable,
	get_occupying_entity_id: Callable
) -> Vector2i:
	if record.world_status == GameEnums.EntityWorldStatus.HOSTILE:
		var pursuit_radius := pursuit_radius_for(
			record,
			npc_pursuit_radius,
			craven_pursuit_radius
		)
		var label := record_aggro_label(record)
		if distance_to_player == 1:
			print("[Aggro] ", label, " lunges at adjacent prey.")
			if npc_can_enter(
				record,
				player_coords,
				player_coords,
				get_hex_at,
				get_occupying_entity_id
			):
				return player_coords
			return record.coords
		if distance_to_player <= pursuit_radius:
			print(
				"[Aggro] ", label, " pursues (dist ", distance_to_player,
				" <= leash ", pursuit_radius, ")."
			)
			return best_npc_neighbor(
				record,
				player_coords,
				true,
				get_hex_at,
				get_occupying_entity_id
			)
		print(
			"[Aggro] ", label, " breaks off (dist ", distance_to_player,
			" > leash ", pursuit_radius, ")."
		)
		if rng.randf() <= npc_wander_chance:
			return wander_npc_neighbor(
				record,
				player_coords,
				rng,
				get_hex_at,
				get_occupying_entity_id
			)
		return record.coords
	return record.coords


static func pursuit_radius_for(
	record: EntityRecord,
	npc_pursuit_radius: int,
	craven_pursuit_radius: int
) -> int:
	var role := role_descriptor(record)
	if role.has("pursuit_radius"):
		return maxi(1, int(role.get("pursuit_radius", npc_pursuit_radius)))
	var faction: GameEnums.Faction = record.definition.get(
		"faction",
		GameEnums.Faction.UNALIGNED
	)
	if faction == GameEnums.Faction.CRAVEN_HIVE:
		return clampi(craven_pursuit_radius, 1, npc_pursuit_radius)
	return npc_pursuit_radius


static func record_aggro_label(record: EntityRecord) -> String:
	return (
		str(record.definition.get("archetype_name", "NPC"))
		+ " "
		+ str(record.entity_id)
	)


static func evaluate_targeted_purpose_step(
	record: EntityRecord,
	player_coords: Vector2i,
	target_coords: Vector2i,
	rng: RandomNumberGenerator,
	npc_wander_chance: float,
	avoid_player: bool,
	get_hex_at: Callable,
	get_occupying_entity_id: Callable
) -> Vector2i:
	var distance_to_player := hex_distance(record.coords, player_coords)
	if avoid_player and distance_to_player <= 1:
		return best_npc_neighbor(
			record,
			player_coords,
			false,
			get_hex_at,
			get_occupying_entity_id
		)
	if target_coords == record.coords:
		record.runtime.erase("macro_target_coords")
		if rng.randf() <= npc_wander_chance:
			return wander_npc_neighbor(
				record,
				player_coords,
				rng,
				get_hex_at,
				get_occupying_entity_id
			)
		return record.coords
	var next_step := best_step_toward(
		record,
		target_coords,
		player_coords,
		get_hex_at,
		get_occupying_entity_id
	)
	if next_step != record.coords:
		return next_step
	if rng.randf() <= npc_wander_chance:
		return wander_npc_neighbor(
			record,
			player_coords,
			rng,
			get_hex_at,
			get_occupying_entity_id
		)
	return record.coords


static func best_npc_neighbor(
	record: EntityRecord,
	player_coords: Vector2i,
	pursue: bool,
	get_hex_at: Callable,
	get_occupying_entity_id: Callable
) -> Vector2i:
	var best_coords := record.coords
	var best_distance := hex_distance(record.coords, player_coords)
	for direction in HEX_NEIGHBORS:
		var candidate: Vector2i = record.coords + direction
		if not npc_can_enter(
			record,
			candidate,
			player_coords,
			get_hex_at,
			get_occupying_entity_id
		):
			continue
		var candidate_distance := hex_distance(candidate, player_coords)
		if (
			(pursue and candidate_distance < best_distance)
			or (not pursue and candidate_distance > best_distance)
		):
			best_coords = candidate
			best_distance = candidate_distance
	return best_coords


static func best_step_toward(
	record: EntityRecord,
	target_coords: Vector2i,
	player_coords: Vector2i,
	get_hex_at: Callable,
	get_occupying_entity_id: Callable
) -> Vector2i:
	var best_coords := record.coords
	var best_distance := hex_distance(record.coords, target_coords)
	for direction in HEX_NEIGHBORS:
		var candidate: Vector2i = record.coords + direction
		if not npc_can_enter(
			record,
			candidate,
			player_coords,
			get_hex_at,
			get_occupying_entity_id
		):
			continue
		var candidate_distance := hex_distance(candidate, target_coords)
		if candidate_distance < best_distance:
			best_coords = candidate
			best_distance = candidate_distance
	return best_coords


static func wander_npc_neighbor(
	record: EntityRecord,
	player_coords: Vector2i,
	rng: RandomNumberGenerator,
	get_hex_at: Callable,
	get_occupying_entity_id: Callable
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for direction in HEX_NEIGHBORS:
		var candidate: Vector2i = record.coords + direction
		if npc_can_enter(
			record,
			candidate,
			player_coords,
			get_hex_at,
			get_occupying_entity_id
		):
			candidates.append(candidate)
	if candidates.is_empty():
		return record.coords
	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func npc_can_enter(
	record: EntityRecord,
	target_coords: Vector2i,
	player_coords: Vector2i,
	get_hex_at: Callable,
	get_occupying_entity_id: Callable
) -> bool:
	var target_hex: MacroHexData = get_hex_at.call(target_coords)
	if not target_hex.is_passable():
		return false
	if (
		record.world_status == GameEnums.EntityWorldStatus.HOSTILE
		and target_hex.region == GameEnums.MacroRegion.CENTRAL_HUB
	):
		return false
	if target_coords == player_coords:
		return record.world_status == GameEnums.EntityWorldStatus.HOSTILE
	var occupying_id: String = get_occupying_entity_id.call(target_coords)
	return occupying_id.is_empty() or occupying_id == record.entity_id


static func get_spawn_chance(
	hex_data: MacroHexData,
	base_enemy_spawn_chance: float
) -> float:
	if not hex_data.is_passable():
		return 0.0
	var chance := base_enemy_spawn_chance
	if hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		chance *= 1.15
	elif hex_data.terrain_tile == GameEnums.MacroTerrainTile.FOREST_SPARSE:
		chance *= 1.1
	elif hex_data.terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
		chance *= 0.9
	if hex_data.rock_layer == GameEnums.MacroRockLayer.HILLS:
		chance *= 0.9
	if hex_data.structure_layer != GameEnums.MacroStructureLayer.NONE:
		chance *= 1.2
	return chance


static func roll_faction(
	rng: RandomNumberGenerator,
	hex_data: MacroHexData
) -> GameEnums.Faction:
	var roll := rng.randf()
	if (
		hex_data.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW
		and roll < 0.35
	):
		return GameEnums.Faction.CRAVEN_HIVE
	if roll < 0.72:
		return GameEnums.Faction.SCAVENGER_CELL
	if roll < 0.92:
		return GameEnums.Faction.CRAVEN_HIVE
	return GameEnums.Faction.ARCBORN_RESISTANCE


static func plan_encounter_refresh(
	center_coords: Vector2i,
	world_seed: String,
	generation_radius: int,
	max_new_encounters_per_refresh: int,
	safe_start_radius: int,
	base_enemy_spawn_chance: float,
	fog_gated_spawning: bool,
	is_hex_visible: Callable,
	get_hex_at: Callable
) -> Array:
	var outcomes: Array = []
	var new_encounter_count := 0
	for coords in coords_in_radius(center_coords, generation_radius):
		if (
			max_new_encounters_per_refresh > 0
			and new_encounter_count >= max_new_encounters_per_refresh
		):
			break
		var hex_data: MacroHexData = get_hex_at.call(coords)
		if hex_data.encounter_evaluated:
			continue
		if fog_gated_spawning and is_hex_visible.call(coords):
			continue

		var outcome := {
			"coords": coords,
			"mark_evaluated": true,
			"spawn": null,
		}
		if (
			hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB
			or hex_distance(Vector2i.ZERO, coords) <= safe_start_radius
		):
			outcomes.append(outcome)
			continue

		var rng := RandomNumberGenerator.new()
		var key := encounter_key(world_seed, coords)
		rng.seed = key.hash()
		var spawn_chance := get_spawn_chance(hex_data, base_enemy_spawn_chance)
		if rng.randf() < spawn_chance:
			outcome["spawn"] = {
				"faction": roll_faction(rng, hex_data),
				"difficulty": mini(
					3,
					floori(float(hex_distance(Vector2i.ZERO, coords)) / 8.0)
				),
				"deterministic_key": key,
				"spawn_chance": spawn_chance,
			}
			new_encounter_count += 1
		outcomes.append(outcome)
	return outcomes
