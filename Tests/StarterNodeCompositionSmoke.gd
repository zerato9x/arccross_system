extends SceneTree

## Generator V2 contract for all four playable Route 1 nodes.

const SEED := "STARTER_NODE_COMPOSITION_V2"
const MobSpawnerScript := preload("res://SystemCore/MobSpawner.gd")
const _NpcSimulator := preload("res://WorldCore/MacroNpcSimulator.gd")
const STARTERS := {
	"north_random_1": "north",
	"east_random_1": "east",
	"south_random_1": "south",
	"west_random_1": "west",
}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graph := MacroGraphGenerator.generate_web(SEED)
	var settlement_count := 0
	for node_key in STARTERS.keys():
		var node_id: String = str(node_key)
		var node := graph.get_node(node_id) as MacroNodeData
		if node == null:
			return _fail("Missing starter node %s." % node_id)
		var arrival := MacroGraphGenerator.arrival_direction_for_start(node_id)
		var zone := _generate(node, arrival, SEED)
		var expects_settlement: bool = node_id == "north_random_1"
		if zone.generated_plan.has_settlement:
			settlement_count += 1
		if not _verify_zone(zone, str(STARTERS[node_id]), expects_settlement):
			return
		var copy := _generate(node, arrival, SEED)
		if JSON.stringify(zone.generated_plan.diagnostic_report()) != JSON.stringify(copy.generated_plan.diagnostic_report()):
			return _fail("%s plan is not deterministic." % node_id)
		for coords in zone.world_hex_cache.keys():
			if zone.get_hex_at(coords).to_state().to_dict() != copy.get_hex_at(coords).to_state().to_dict():
				return _fail("%s hex %s is not deterministic." % [node_id, coords])
	if settlement_count != 1:
		return _fail("Inner ring generated %d settlements; expected North only." % settlement_count)
	if not _different_seeds_preserve_logistics_and_vary_surroundings(graph):
		return
	print("[StarterNodeCompositionSmoke] PASSED")
	quit(0)


func _generate(node: MacroNodeData, arrival: int, seed_value: String) -> MacroZoneGenerator:
	var zone := MacroZoneGenerator.new()
	zone.configure_seed(seed_value)
	zone.generate_node_zone(node, arrival, [arrival, HexCoordUtils.opposite_travel_direction(arrival)])
	return zone


func _verify_zone(zone: MacroZoneGenerator, arm_id: String, expects_settlement: bool) -> bool:
	if zone.generated_plan == null or not zone.generated_plan.is_valid():
		return _fail("%s has no valid V2 plan." % arm_id)
	if zone.world_hex_cache.size() != 469:
		return _fail("%s has %d cells, expected 469." % [arm_id, zone.world_hex_cache.size()])
	var poi_count := 0
	var anchor_count := 0
	var stamp_count := 0
	var quiet_count := 0
	var snow_count := 0
	var forest_count := 0
	var terrain_assets: Dictionary = {}
	for coords in zone.world_hex_cache.keys():
		var hex := zone.get_hex_at(coords)
		if hex.world_generation_version != 2:
			return _fail("%s contains a legacy hex at %s." % [arm_id, coords])
		if hex.is_poi:
			poi_count += 1
		if hex.composition_role == "settlement_anchor":
			anchor_count += 1
		if not hex.stamp_instance_id.is_empty():
			stamp_count += 1
		if hex.composition_role == "quiet_plains":
			quiet_count += 1
		if hex.terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
			snow_count += 1
		if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
			forest_count += 1
		if not hex.terrain_asset_id.begins_with("terrain.plains.green."):
			return _fail("%s has a non-plains terrain ID at %s." % [arm_id, coords])
		terrain_assets[hex.terrain_asset_id] = true
	if expects_settlement:
		if poi_count != 1 or anchor_count != 1 or not zone.generated_plan.has_settlement:
			return _fail("%s must contain the alpha settlement/POI." % arm_id)
		if stamp_count < 13 or stamp_count > 17:
			return _fail("%s settlement footprint is %d cells." % [arm_id, stamp_count])
	else:
		if poi_count != 1 or anchor_count != 0 or zone.generated_plan.has_settlement:
			return _fail("%s contains a second starter settlement." % arm_id)
	if float(quiet_count) / 469.0 < 0.60:
		return _fail("%s quiet-landscape budget failed." % arm_id)
	if snow_count != 0:
		return _fail("%s starter contains snow terrain." % arm_id)
	if terrain_assets.size() != 54:
		return _fail("%s uses %d/54 approved plains variants." % [arm_id, terrain_assets.size()])
	if forest_count < 20:
		return _fail("%s has only %d forest cells; starter plains still read empty." % [arm_id, forest_count])
	if not zone.generated_plan.overflow_violations.is_empty():
		return _fail("%s has dressing overflow violations." % arm_id)
	if zone.generated_plan.rubble_search_cells.size() < 6 or zone.generated_plan.rubble_search_cells.size() > 10:
		return _fail("%s searchable rubble budget failed." % arm_id)
	if zone.generated_plan.visual_rubble_cells.size() < 12 or zone.generated_plan.visual_rubble_cells.size() > 20:
		return _fail("%s visual rubble budget failed." % arm_id)
	var saw_large_rock := false
	var saw_small_shrub := false
	var saw_frame_placement := false
	for coords in zone.generated_plan.rubble_search_cells:
		var rubble := zone.get_hex_at(coords)
		if rubble.loot_tier_id != "starter_poor" or rubble.is_poi:
			return _fail("%s rubble at %s is not poor/non-POI." % [arm_id, coords])
		if MacroInteractionResolver.build_search_options(SEED, coords, rubble).size() != 1:
			return _fail("%s rubble at %s is not singly exhaustible." % [arm_id, coords])
	for coords in zone.zone_decorations.keys():
		for decor in zone.get_decorations_at(coords):
			if str(decor.get("asset_id", "")).is_empty():
				return _fail("%s uses an unmanifested dressing asset at %s." % [arm_id, coords])
			if str(decor.get("footprint_class", "")) == "reserved_two_hex" and decor.get("reserved_cells", []).size() != 2:
				return _fail("%s large structure lacks a reserved neighbor." % arm_id)
			var kind := str(decor.get("kind", ""))
			var path := str(decor.get("sprite_path", "")).to_lower()
			var target_box: Vector2 = decor.get("target_box", Vector2.ZERO)
			var offset: Vector2 = decor.get("offset", Vector2.ZERO)
			if kind == "rock" and "sz2" in path and target_box.x >= 250.0:
				saw_large_rock = true
			if kind == "shrub" and target_box.x <= 60.0 and target_box.y <= 68.0:
				saw_small_shrub = true
			if absf(offset.x) >= 120.0 or absf(offset.y) >= 110.0:
				saw_frame_placement = true
	if not saw_large_rock or not saw_small_shrub or not saw_frame_placement:
		return _fail(
			"%s dressing hierarchy/placement failed (large rock=%s small shrub=%s frame=%s)."
			% [arm_id, str(saw_large_rock), str(saw_small_shrub), str(saw_frame_placement)]
		)
	if not _verify_authored_dressing_recipes(zone, arm_id):
		return false
	if arm_id == "north" and not _verify_truth_view(zone):
		return false
	if not _verify_road(zone, arm_id):
		return false
	if not _verify_reachability(zone, arm_id):
		return false
	if expects_settlement and not _verify_wayfinder(zone, arm_id):
		return false
	return true


func _verify_truth_view(zone: MacroZoneGenerator) -> bool:
	var cells := 0
	var road_cells := 0
	var service_spur_cells := 0
	var quiet_landscape := 0
	var forest_cells := 0
	for coords in zone.world_hex_cache.keys():
		if HexCoordUtils.distance(coords, zone.starter_settlement_coords) > 3:
			continue
		cells += 1
		var hex := zone.get_hex_at(coords)
		if hex.road_mask > 0:
			road_cells += 1
		if hex.composition_role == "dirt_service_spur":
			service_spur_cells += 1
		if hex.stamp_instance_id.is_empty() and hex.composition_role not in ["rubble_search", "rubble_visual"]:
			quiet_landscape += 1
		if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
			forest_cells += 1
	if cells != 37 or road_cells < 7 or service_spur_cells < 1 or quiet_landscape < 16 or forest_cells < 5:
		return _fail(
			"North radius-3 truth view failed: cells=%d road=%d spur=%d quiet=%d forest=%d."
			% [cells, road_cells, service_spur_cells, quiet_landscape, forest_cells]
		)
	return true


func _verify_authored_dressing_recipes(zone: MacroZoneGenerator, arm_id: String) -> bool:
	var rubble_cells: Array[Vector2i] = []
	for coords in zone.generated_plan.stamp_cells.keys():
		var role := zone.generated_plan.role_at(coords)
		if role == "settlement_tent":
			var tent_count := 0
			var detail_count := 0
			for decor in zone.get_decorations_at(coords):
				var kind := str(decor.get("kind", ""))
				tent_count += 1 if kind == "tent" else 0
				detail_count += 1 if kind == "prop" else 0
			if tent_count < 2 or detail_count < 2:
				return _fail("%s tent cell %s is not a camp cluster." % [arm_id, str(coords)])
		elif role == "settlement_rubble":
			rubble_cells.append(coords)
	rubble_cells.append_array(zone.generated_plan.rubble_search_cells)
	rubble_cells.append_array(zone.generated_plan.visual_rubble_cells)
	for coords in rubble_cells:
		var large_rubble := false
		var shrub_count := 0
		for decor in zone.get_decorations_at(coords):
			var kind := str(decor.get("kind", ""))
			var path := str(decor.get("sprite_path", "")).to_lower()
			var box: Vector2 = decor.get("target_box", Vector2.ZERO)
			if kind == "rock" and "rubble" in path and box.x >= 260.0:
				large_rubble = true
			if kind == "shrub":
				shrub_count += 1
		if not large_rubble or shrub_count < 2:
			return _fail("%s rubble cell %s lacks a large pile/scrub frame." % [arm_id, str(coords)])
	return true


func _verify_road(zone: MacroZoneGenerator, arm_id: String) -> bool:
	var plan := zone.generated_plan
	var inward_direction := HexCoordUtils.opposite_travel_direction(int(zone.node_arm_direction))
	var inward := HexCoordUtils.rim_anchor(inward_direction, MacroZoneGenerator.ZONE_RADIUS)
	var outward := HexCoordUtils.rim_anchor(int(zone.node_arm_direction), MacroZoneGenerator.ZONE_RADIUS)
	if not plan.road_cells.has(inward) or not plan.road_cells.has(outward):
		return _fail("%s road misses a required rim." % arm_id)
	if plan.has_settlement and not plan.road_cells.has(plan.gameplay_anchor_coords):
		return _fail("%s road misses the settlement anchor." % arm_id)
	var dirt_count := 0
	for coords in plan.road_cells.keys():
		if plan.role_at(coords) == "dirt_service_spur":
			dirt_count += 1
		var mask := int(plan.road_cells[coords])
		if mask <= 0 or mask > 63:
			return _fail("%s has invalid road mask at %s." % [arm_id, coords])
		for index in range(HexCoordUtils.AXIAL_DIRECTIONS.size()):
			if mask & (1 << index) == 0:
				continue
			var neighbor: Vector2i = Vector2i(coords) + Vector2i(HexCoordUtils.AXIAL_DIRECTIONS[index])
			var neighbor_mask := int(plan.road_cells.get(neighbor, 0))
			var opposite := (index + 3) % 6
			if neighbor_mask & (1 << opposite) == 0:
				return _fail("%s road socket at %s is not reciprocal." % [arm_id, coords])
	if dirt_count < 2:
		return _fail("%s fixed logistics skeleton has no dirt service spur." % arm_id)
	return true


func _verify_reachability(zone: MacroZoneGenerator, arm_id: String) -> bool:
	var visited := {zone.start_coords: true}
	var frontier: Array[Vector2i] = [zone.start_coords]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		for direction in HexCoordUtils.AXIAL_DIRECTIONS:
			var next: Vector2i = current + direction
			if visited.has(next) or not zone.world_hex_cache.has(next):
				continue
			if not zone.get_hex_at(next).is_passable():
				continue
			visited[next] = true
			frontier.append(next)
	var required: Array = [zone.generated_plan.gameplay_anchor_coords]
	required.append_array(zone.generated_plan.rubble_search_cells)
	for coords in required:
		if not visited.has(coords):
			return _fail("%s required cell %s is unreachable." % [arm_id, coords])
	return true


func _verify_wayfinder(zone: MacroZoneGenerator, arm_id: String) -> bool:
	var spawner: Node = MobSpawnerScript.new()
	var guide: EntityRecord = spawner.generate_starter_wayfinder_record(zone.starter_npc_coords, arm_id, SEED + arm_id)
	if not bool(guide.runtime.get("stationary", false)):
		return _fail("%s wayfinder lacks stationary authority." % arm_id)
	var step := _NpcSimulator.evaluate_npc_step(
		guide, guide.coords + Vector2i(1, 0), SEED, 1, 1.0, 5, 3,
		func(_coords: Vector2i) -> MacroHexData: return MacroHexData.new(),
		func(_coords: Vector2i) -> bool: return false,
		func(_coords: Vector2i) -> String: return ""
	)
	if step != guide.coords:
		return _fail("%s wayfinder abandoned HOLD behavior." % arm_id)
	return true


func _different_seeds_preserve_logistics_and_vary_surroundings(graph: MacroMapGraph) -> bool:
	var node := graph.get_node("north_random_1") as MacroNodeData
	var arrival := MacroGraphGenerator.arrival_direction_for_start(node.id)
	var first := _generate(node, arrival, "SURROUNDINGS_A")
	var second := _generate(node, arrival, "SURROUNDINGS_B")
	var alternate_arrival := _generate(
		node, GameEnums.MacroTravelDirection.NORTHEAST, "SURROUNDINGS_A"
	)
	if first.starter_settlement_coords != second.starter_settlement_coords:
		return _fail("Seed changed the fixed alpha settlement location.")
	if first.generated_plan.road_cells != second.generated_plan.road_cells:
		return _fail("Seed changed the main-node logistics skeleton.")
	if first.generated_plan.road_cells != alternate_arrival.generated_plan.road_cells:
		return _fail("Discovery direction changed the main-node logistics skeleton.")
	var changed_terrain := 0
	var changed_ecology := 0
	for coords in first.world_hex_cache.keys():
		var a := first.get_hex_at(coords)
		var b := second.get_hex_at(coords)
		changed_terrain += 1 if a.terrain_asset_id != b.terrain_asset_id else 0
		changed_ecology += 1 if a.flora_layer != b.flora_layer or a.rock_layer != b.rock_layer else 0
	if changed_terrain < 100 or changed_ecology < 10:
		return _fail(
			"Different seeds did not materially vary surroundings (terrain=%d ecology=%d)."
			% [changed_terrain, changed_ecology]
		)
	return true


func _fail(message: String) -> bool:
	push_error("[StarterNodeCompositionSmoke] " + message)
	quit(1)
	return false
