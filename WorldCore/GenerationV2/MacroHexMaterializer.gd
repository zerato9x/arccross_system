extends RefCounted
class_name MacroHexMaterializer

## Applies an authored GeneratedZonePlan to neutral hex runtime records.
## Terrain assignment remains supplied by the zone profile/catalog boundary.

func apply_starter_plan(
	world_hex_cache: Dictionary,
	plan: GeneratedZonePlan,
	terrain_assignments: Dictionary,
	trail_hexes: Dictionary
) -> void:
	plan.terrain_asset_usage.clear()
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		hex.world_generation_version = GeneratedZonePlan.VERSION
		hex.terrain_asset_id = str(terrain_assignments.get(
			coords,
			"terrain.plains.green.5"
		))
		plan.terrain_asset_usage[hex.terrain_asset_id] = int(
			plan.terrain_asset_usage.get(hex.terrain_asset_id, 0)
		) + 1
		hex.overlay_asset_ids.clear()
		hex.composition_role = plan.role_at(coords)
		hex.stamp_instance_id = ""
		hex.road_mask = plan.road_mask_at(coords)
		hex.loot_tier_id = ""
		hex.search_site_id = ""
		hex.trace_records.clear()
		hex.biome = GameEnums.GridBiome.PLAINS
		hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
		hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
		hex.structure_layer = GameEnums.MacroStructureLayer.NONE
		hex.structure_sprite_path = ""
		hex.is_poi = false
		hex.poi_id = ""
		hex.poi_name = ""
		hex.landmark_id = ""
		if plan.road_cells.has(coords):
			trail_hexes[coords] = true
			var road_surface := (
				"dirt" if hex.composition_role == "dirt_service_spur" else "paved"
			)
			hex.overlay_asset_ids.append(
				"overlay.road.%s.%02d" % [road_surface, hex.road_mask]
			)
			hex.impassable = false
			hex.rock_layer = GameEnums.MacroRockLayer.NONE
			hex.flora_layer = GameEnums.MacroFloraLayer.NONE
			hex.hazard_level = minf(hex.hazard_level, 1.25)
			hex.encounter_evaluated = true
		if plan.stamp_cells.has(coords):
			var stamp_cell: Dictionary = plan.stamp_cells[coords]
			hex.stamp_instance_id = str(stamp_cell.get("stamp_instance_id", ""))
			hex.impassable = false
			hex.rock_layer = GameEnums.MacroRockLayer.NONE
			hex.flora_layer = GameEnums.MacroFloraLayer.NONE
			hex.hazard_level = minf(hex.hazard_level, 0.75)
			if hex.composition_role in ["settlement_structure", "settlement_tent"]:
				hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
			elif hex.composition_role == "settlement_rubble":
				hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS


func apply_starter_truth_grove(
	world_hex_cache: Dictionary,
	plan: GeneratedZonePlan,
	settlement_coords: Vector2i,
	zone_seed: String
) -> void:
	## Guarantee one readable woodland mass near the reference settlement view.
	## The seed ranks the first eligible cell; adjacency grows the authored patch.
	if plan == null:
		return
	var candidates: Array[Vector2i] = []
	for coords in world_hex_cache.keys():
		var distance := HexCoordUtils.distance(coords, settlement_coords)
		if distance < 2 or distance > 3:
			continue
		if not _is_quiet_grove_cell(world_hex_cache, plan, coords):
			continue
		candidates.append(coords)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (
			(zone_seed + ":truth_grove:" + str(a)).hash()
			< (zone_seed + ":truth_grove:" + str(b)).hash()
		)
	)
	if candidates.is_empty():
		return
	var selected: Array[Vector2i] = [candidates[0]]
	var frontier: Array[Vector2i] = [candidates[0]]
	while not frontier.is_empty() and selected.size() < 5:
		var current: Vector2i = frontier.pop_front()
		for direction in HexCoordUtils.AXIAL_DIRECTIONS:
			var neighbor: Vector2i = current + Vector2i(direction)
			if HexCoordUtils.distance(neighbor, settlement_coords) > 3:
				continue
			if selected.has(neighbor) or not _is_quiet_grove_cell(world_hex_cache, plan, neighbor):
				continue
			selected.append(neighbor)
			frontier.append(neighbor)
			if selected.size() >= 5:
				break
	for coords in selected:
		var hex: MacroHexData = world_hex_cache[coords]
		hex.flora_layer = GameEnums.MacroFloraLayer.TREES
		hex.rock_layer = GameEnums.MacroRockLayer.NONE
		hex.impassable = false


func apply_route_signature_landmark(
	world_hex_cache: Dictionary,
	plan: GeneratedZonePlan,
	definition: Route1LandmarkDefinition,
	include_settlement: bool
) -> Vector2i:
	if plan == null or definition == null:
		return plan.gameplay_anchor_coords if plan != null else Vector2i.ZERO
	var signature_coords := plan.gameplay_anchor_coords
	if not include_settlement:
		var spur_cells: Array[Vector2i] = []
		for coords in plan.road_cells.keys():
			if plan.role_at(coords) == "dirt_service_spur":
				spur_cells.append(coords)
		spur_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var a_distance := HexCoordUtils.distance(a, Vector2i.ZERO)
			var b_distance := HexCoordUtils.distance(b, Vector2i.ZERO)
			if a_distance == b_distance:
				return str(a) < str(b)
			return a_distance < b_distance
		)
		if not spur_cells.is_empty():
			signature_coords = spur_cells[0]
	if not world_hex_cache.has(signature_coords):
		return signature_coords
	var anchor: MacroHexData = world_hex_cache[signature_coords]
	anchor.is_poi = true
	anchor.poi_id = definition.poi_id
	anchor.poi_name = definition.display_name
	anchor.landmark_id = definition.landmark_id
	anchor.sleep_anchor = definition.sleep_anchor
	anchor.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	anchor.structure_pack = GameEnums.BIOME_PACK_DEFAULT_ERA8
	anchor.impassable = false
	anchor.encounter_evaluated = true
	return signature_coords


func _is_quiet_grove_cell(
	world_hex_cache: Dictionary,
	plan: GeneratedZonePlan,
	coords: Vector2i
) -> bool:
	if not world_hex_cache.has(coords):
		return false
	if plan == null or plan.role_at(coords) != "quiet_plains":
		return false
	if plan.road_cells.has(coords) or plan.stamp_cells.has(coords):
		return false
	if plan.rubble_search_cells.has(coords) or plan.visual_rubble_cells.has(coords):
		return false
	var hex: MacroHexData = world_hex_cache[coords]
	return hex.rock_layer == GameEnums.MacroRockLayer.NONE
