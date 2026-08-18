extends RefCounted
class_name MacroCampaignPopulationService

## Applies authored campaign population profiles to the active local zone.
## Entity registration remains RuntimeStateStore-owned; callbacks keep token
## projection and NPC runtime initialization behind the application shell.

const INVALID_COORDS := Vector2i(9999, 9999)
const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
const _RoutePopulationCatalog := preload("res://WorldCore/RoutePopulationCatalog.gd")


func ensure_central_rim_guards(
	campaign: MacroProgressController,
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	mob_spawner: Node,
	active_enemy_coords: Dictionary,
	player_coords: Vector2i,
	initialize_npc_runtime: Callable,
	spawn_enemy_token: Callable,
	log_message: Callable
) -> bool:
	if campaign == null or world_state == null or world_generator == null or mob_spawner == null:
		return false
	var node_id := str(campaign.active_node_id)
	if not _is_route_one_node(node_id) or _has_central_guard_pair(world_state, node_id):
		return false
	var toward_central := _central_facing_direction_for_route_one(campaign, node_id)
	if toward_central == GameEnums.MacroTravelDirection.NONE:
		return false
	var pair_coords := _pick_central_rim_pair_coords(
		toward_central,
		world_state,
		world_generator,
		active_enemy_coords,
		player_coords
	)
	if pair_coords.size() < 2:
		push_warning(
			"[MacroCampaignPopulationService] Could not place Central Guard pair on %s rim."
			% node_id
		)
		return false

	var squad_id := "central_guard_pair_%s" % node_id
	var seed_base := "%s:%s:central_guard" % [world_state.world_seed, node_id]
	var variants := [false, true] # AK-47, then Kar98k
	for i in range(2):
		var coords: Vector2i = pair_coords[i]
		var record: EntityRecord = mob_spawner.generate_central_guard_record(
			coords,
			bool(variants[i]),
			squad_id,
			"%s:%d" % [seed_base, i]
		)
		if initialize_npc_runtime.is_valid():
			initialize_npc_runtime.call(record)
		# Posted rim pair: hold hex, never wander.
		record.runtime["macro_purpose"] = GameEnums.NPC_PURPOSE_HOLD
		record.runtime["macro_purpose_label"] = "Hold"
		record.runtime["macro_origin_coords"] = coords
		record.runtime["macro_target_coords"] = coords
		var entity_id := world_state.register_entity(record)
		var hex_data := world_generator.get_hex_at(coords)
		hex_data.encounter_entity_id = entity_id
		hex_data.encounter_evaluated = true
		world_generator.commit_hex_projection(coords, hex_data)
		if spawn_enemy_token.is_valid():
			spawn_enemy_token.call(record)
		if log_message.is_valid():
			log_message.call("Posted Central Guard %s @%s facing Central." % [entity_id, str(coords)])
	return true


func ensure_route_one_population(
	campaign: MacroProgressController,
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	mob_spawner: Node,
	initialize_npc_runtime: Callable,
	spawn_enemy_token: Callable
) -> void:
	if campaign == null or world_state == null or world_generator == null or mob_spawner == null:
		return
	if not _is_route_one_node(campaign.active_node_id):
		return
	var population_catalog: Variant = _RoutePopulationCatalog.data()
	var profile: RoutePopulationProfile = (
		population_catalog.for_node(campaign.active_node_id)
		if population_catalog != null
		else null
	)
	if profile == null:
		return
	var existing_templates: Dictionary = {}
	for entity_snapshot in world_state.get_all_entity_snapshots():
		if entity_snapshot is Dictionary:
			existing_templates[str(entity_snapshot.get("runtime", {}).get("template_id", ""))] = true
	var used_coords: Dictionary = {}
	for entry_value in profile.entries():
		var entry: Dictionary = entry_value
		for index in range(int(entry.get("count", 1))):
			var template_id := "%s_%d" % [str(entry.get("template_prefix", "route_npc")), index]
			if existing_templates.has(template_id):
				continue
			var coords := _pick_route_population_coords(
				str(entry.get("placement", "search_near")),
				used_coords,
				campaign,
				world_state,
				world_generator
			)
			if coords == INVALID_COORDS:
				continue
			var record: EntityRecord = mob_spawner.generate_role_record(
				coords,
				str(entry.get("role_id", "salvager")),
				int(entry.get("faction", GameEnums.Faction.UNALIGNED)),
				int(entry.get("world_status", GameEnums.EntityWorldStatus.CEASEFIRE)),
				template_id,
				"%s:%s:%s" % [world_state.world_seed, campaign.active_node_id, template_id]
			)
			if initialize_npc_runtime.is_valid():
				initialize_npc_runtime.call(record)
			var entity_id := world_state.register_entity(record)
			var hex_data := world_generator.get_hex_at(coords)
			hex_data.encounter_entity_id = entity_id
			hex_data.encounter_evaluated = true
			world_generator.commit_hex_projection(coords, hex_data)
			used_coords[coords] = true
			if spawn_enemy_token.is_valid():
				spawn_enemy_token.call(record)


func ensure_shelter_ecology(
	campaign: MacroProgressController,
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	mob_spawner: Node,
	shelter_profile: ShelterProgressionProfile,
	initialize_npc_runtime: Callable,
	spawn_enemy_token: Callable
) -> void:
	## Shelter pressure is authored as nearby inhabitants, not a repair callback.
	if campaign == null or world_state == null or world_generator == null or mob_spawner == null:
		return
	if shelter_profile == null:
		return
	var node_id := str(campaign.active_node_id)
	var offsets := shelter_profile.ecology_for_node(node_id)
	if offsets.is_empty():
		return
	for index in range(offsets.size()):
		var coords: Vector2i = offsets[index]
		var hex := world_generator.get_hex_at(coords)
		if not hex.is_passable() or world_state.has_entity_at(coords):
			continue
		var template_id := "%s_%d" % [shelter_profile.ecology_template_prefix, index]
		var already := false
		for existing_snapshot in world_state.get_all_entity_snapshots():
			if (
				existing_snapshot is Dictionary
				and str(existing_snapshot.get("runtime", {}).get("template_id", "")) == template_id
			):
				already = true
				break
		if already:
			continue
		var record: EntityRecord = mob_spawner.generate_mob_record(
			coords,
			GameEnums.Faction.CRAVEN_HIVE,
			0,
			"%s:%s:%s" % [world_state.world_seed, node_id, template_id]
		)
		record.definition["template_id"] = template_id
		record.runtime = {
			"template_id": template_id,
			"squad_id": "%s_%s" % [shelter_profile.ecology_squad_prefix, index / 2],
			"macro_purpose": GameEnums.NPC_PURPOSE_HUNT,
			"macro_purpose_label": "Circle the shelter",
			"macro_origin_coords": coords,
			"macro_target_coords": Vector2i.ZERO,
			"npc_role_id": "stalker",
		}
		record.last_simulated_minute = world_state.world_time_minutes
		if initialize_npc_runtime.is_valid():
			initialize_npc_runtime.call(record)
		var entity_id := world_state.register_entity(record)
		hex.encounter_entity_id = entity_id
		hex.encounter_evaluated = true
		world_generator.commit_hex_projection(coords, hex)
		if spawn_enemy_token.is_valid():
			spawn_enemy_token.call(record)


func _is_route_one_node(node_id: String) -> bool:
	var population_catalog: RoutePopulationCatalog = _RoutePopulationCatalog.data()
	return population_catalog != null and population_catalog.for_node(node_id) != null


func _central_facing_direction_for_route_one(
	campaign: MacroProgressController,
	node_id: String
) -> int:
	if campaign == null or campaign.graph == null:
		return GameEnums.MacroTravelDirection.NONE
	var node := campaign.graph.get_node(node_id)
	if node == null or node.arm_direction == GameEnums.MacroArmDirection.NONE:
		return GameEnums.MacroTravelDirection.NONE
	return HexCoordUtils.opposite_travel_direction(int(node.arm_direction))


func _has_central_guard_pair(world_state: RuntimeStateStore, node_id: String) -> bool:
	var count := 0
	var expected_squad := "central_guard_pair_%s" % node_id
	for snapshot in world_state.get_all_entity_snapshots():
		if not snapshot is Dictionary:
			continue
		if int(snapshot.get("kind", GameEnums.RuntimeEntityKind.NPC)) != GameEnums.RuntimeEntityKind.NPC:
			continue
		var template_id := str(snapshot.get("definition", {}).get("template_id", ""))
		if template_id.is_empty():
			template_id = str(snapshot.get("runtime", {}).get("template_id", ""))
		if (
			template_id == "central_guard"
			and str(snapshot.get("runtime", {}).get("squad_id", "")) == expected_squad
		):
			count += 1
	return count >= 2


func _pick_route_population_coords(
	placement: String,
	used_coords: Dictionary,
	campaign: MacroProgressController,
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator
) -> Vector2i:
	var candidates: Array[Vector2i] = []
	var poi_coords := INVALID_COORDS
	for coords_value in world_generator.world_hex_cache.keys():
		var coords: Vector2i = coords_value
		var hex_data: MacroHexData = world_generator.get_hex_at(coords)
		if hex_data.is_poi:
			poi_coords = coords
		if (
			not hex_data.search_site_id.is_empty()
			and hex_data.is_passable()
			and not world_state.has_entity_at(coords)
			and not used_coords.has(coords)
		):
			candidates.append(coords)
	if placement == "poi_neighbor" and poi_coords != INVALID_COORDS:
		for offset_value in _NpcSimulator.HEX_NEIGHBORS:
			var coords: Vector2i = poi_coords + Vector2i(offset_value)
			var hex_data := world_generator.get_hex_at(coords)
			if hex_data.is_passable() and not world_state.has_entity_at(coords) and not used_coords.has(coords):
				return coords
	if candidates.is_empty():
		return INVALID_COORDS
	var start_coords := campaign.zone_generator.start_coords
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _NpcSimulator.hex_distance(start_coords, a) < _NpcSimulator.hex_distance(start_coords, b)
	)
	return candidates.back() if placement == "search_far" else candidates.front()


func _pick_central_rim_pair_coords(
	toward_central: int,
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	active_enemy_coords: Dictionary,
	player_coords: Vector2i
) -> Array[Vector2i]:
	var radius := MacroZoneGenerator.ZONE_RADIUS
	var primary := HexCoordUtils.rim_anchor(toward_central, radius)
	var candidates: Array[Vector2i] = []
	if _is_guard_spawn_hex(primary, world_state, world_generator, active_enemy_coords, player_coords):
		candidates.append(primary)
	for neighbor in HexCoordUtils.AXIAL_DIRECTIONS:
		var coords: Vector2i = primary + neighbor
		if HexCoordUtils.distance_from_origin(coords) != radius:
			continue
		if not _is_guard_spawn_hex(coords, world_state, world_generator, active_enemy_coords, player_coords):
			continue
		if not candidates.has(coords):
			candidates.append(coords)
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			var target := HexCoordUtils.travel_direction_vector(toward_central)
			var score_a := HexCoordUtils.axial_to_visual_vector(a).normalized().dot(target)
			var score_b := HexCoordUtils.axial_to_visual_vector(b).normalized().dot(target)
			return score_a > score_b
	)
	var pair: Array[Vector2i] = []
	for coords in candidates:
		if pair.size() >= 2:
			break
		pair.append(coords)
	if pair.size() >= 2:
		return pair
	for coords in HexCoordUtils.cells_in_ring(radius):
		if HexCoordUtils.distance(primary, coords) > 2:
			continue
		if not _is_guard_spawn_hex(coords, world_state, world_generator, active_enemy_coords, player_coords):
			continue
		if not pair.has(coords):
			pair.append(coords)
		if pair.size() >= 2:
			break
	return pair


func _is_guard_spawn_hex(
	coords: Vector2i,
	world_state: RuntimeStateStore,
	world_generator: HexWorldGenerator,
	active_enemy_coords: Dictionary,
	player_coords: Vector2i
) -> bool:
	var hex_data := world_generator.get_hex_at(coords)
	if hex_data == null or not hex_data.is_passable():
		return false
	if world_state.has_entity_at(coords) or active_enemy_coords.has(coords):
		return false
	return player_coords != coords
