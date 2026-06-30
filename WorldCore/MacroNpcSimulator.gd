extends RefCounted

## Neutral NPC macro AI, projection scoring, and encounter roll planning.
## MacroGameManager applies moves, spawns tokens, and handles collisions.

const HEX_NEIGHBORS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]


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


static func initialize_npc_runtime(
	record: EntityRecord,
	world_seed: String,
	macro_turn_index: int,
	player_coords: Vector2i,
	get_hex_at: Callable,
	has_ground_items: Callable
) -> void:
	if record == null:
		return
	if not record.runtime.has("macro_origin_coords"):
		record.runtime["macro_origin_coords"] = record.coords
	var purpose := ensure_npc_purpose(record)
	if not record.runtime.has("macro_target_coords"):
		record.runtime["macro_target_coords"] = purpose_target_for(
			record,
			purpose,
			world_seed,
			macro_turn_index,
			player_coords,
			get_hex_at,
			has_ground_items
		)


static func purpose_target_for(
	record: EntityRecord,
	purpose: String,
	world_seed: String,
	macro_turn_index: int,
	player_coords: Vector2i,
	get_hex_at: Callable,
	has_ground_items: Callable
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
				has_ground_items
			)
		GameEnums.NPC_PURPOSE_PATROL:
			target = patrol_target(record)
		GameEnums.NPC_PURPOSE_HUNT:
			target = player_coords
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
	has_ground_items: Callable
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
		if has_ground_items.call(coords):
			score += 6.0
		if hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB:
			score -= 20.0
		if score > best_score:
			best = coords
			best_score = score
	return best


static func patrol_target(record: EntityRecord) -> Vector2i:
	var patrol_points := [
		Vector2i(3, 0),
		Vector2i(3, -2),
		Vector2i(1, -3),
		Vector2i(-2, -1),
		Vector2i(-1, 3),
		Vector2i(2, 2),
	]
	var index := absi((record.entity_id + ":patrol").hash()) % patrol_points.size()
	return patrol_points[index]


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
	var purpose := ensure_npc_purpose(record)
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

	var purpose := ensure_npc_purpose(record)
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":npc_eval:"
		+ record.entity_id
		+ ":"
		+ str(macro_turn_index)
	).hash()

	if record.world_status != GameEnums.EntityWorldStatus.HOSTILE:
		if distance_to_player <= 2:
			return best_npc_neighbor(
				record,
				player_coords,
				false,
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
