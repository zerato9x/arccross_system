extends SceneTree

const SEED := "MACRO_DIRECTIONAL_WEB_SMOKE"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_state := RuntimeStateStore.new()
	world_state.name = "DirectionalWebTestState"
	root.add_child(world_state)
	world_state.begin_new_world(SEED)

	var progress := MacroProgressController.new()
	progress.configure(world_state)
	var graph := progress.begin_campaign(SEED)
	if not _verify_graph(graph):
		return
	if not _verify_geometry_and_direction(progress):
		return
	if not _verify_run_snapshot_backtracking(progress, world_state):
		return
	if not _verify_meta_gateway(progress):
		return
	if not _verify_seed_contracts():
		return
	print("MacroNodePathSmoke PASSED")
	quit(0)


func _verify_graph(graph: MacroMapGraph) -> bool:
	if graph.nodes.size() < 33 or graph.nodes.size() > 38:
		return _fail("Expected the North-only 33-38 node web, got %d." % graph.nodes.size())
	if graph.get_node(MacroGraphGenerator.CENTRAL_ID) == null:
		return _fail("Missing Central Core.")
	for prefix in MacroGraphGenerator.ARM_PREFIXES:
		for tier in range(1, 4):
			var node := graph.get_node("%s_random_%d" % [prefix, tier])
			if node == null or node.persistence != GameEnums.MacroNodePersistence.SEEDED_RANDOM:
				return _fail("Missing seeded slot %s tier %d." % [prefix, tier])
		var gateway := graph.get_node("%s_gateway" % prefix)
		var core := graph.get_node("%s_core" % prefix)
		if gateway == null or core == null:
			return _fail("Missing permanent %s gateway/core." % prefix)
		if (
			gateway.persistence != GameEnums.MacroNodePersistence.PERMANENT_META
			or core.persistence != GameEnums.MacroNodePersistence.PERMANENT_META
		):
			return _fail("%s gateway/core must be permanent." % prefix)
	if graph.get_node(MacroGraphGenerator.FETCH_BRANCH_ID) != null:
		return _fail("Legacy fetch branch leaked into the North-only build.")
	if graph.get_edge("north_random_1", "east_random_1").is_empty():
		return _fail("Inner-ring north/east Act 1 link missing.")
	if graph.get_edge("west_random_1", "north_random_1").is_empty():
		return _fail("Inner-ring west/north Act 1 link missing.")
	return true


func _verify_geometry_and_direction(progress: MacroProgressController) -> bool:
	if not progress.enter_node(MacroGraphGenerator.CENTRAL_ID):
		return _fail("Failed initial Central Core entry.")
	var zone := progress.zone_generator
	if zone.hex_count() != GameEnums.MACRO_ZONE_CELL_COUNT:
		return _fail("Expected 469 cells, got %d." % zone.hex_count())
	if HexCoordUtils.cells_in_ring(GameEnums.MACRO_ZONE_RADIUS).size() != 72:
		return _fail("Radius-12 ring must contain 72 cells.")
	if HexCoordUtils.cells_in_ring(GameEnums.MACRO_ZONE_RADIUS + 1).size() != 78:
		return _fail("Radius-13 preview ring must contain 78 cells.")
	for direction in [
		GameEnums.MacroTravelDirection.NORTH,
		GameEnums.MacroTravelDirection.NORTHEAST,
		GameEnums.MacroTravelDirection.EAST,
		GameEnums.MacroTravelDirection.SOUTHEAST,
		GameEnums.MacroTravelDirection.SOUTH,
		GameEnums.MacroTravelDirection.SOUTHWEST,
		GameEnums.MacroTravelDirection.WEST,
		GameEnums.MacroTravelDirection.NORTHWEST,
	]:
		var preview_anchor := HexCoordUtils.rim_anchor(direction, 13)
		if HexCoordUtils.travel_direction_for_boundary_target(preview_anchor) != direction:
			return _fail("Preview anchor classified into the wrong visual sector.")
	var south_anchor := HexCoordUtils.rim_anchor(
		GameEnums.MacroTravelDirection.SOUTH,
		GameEnums.MACRO_ZONE_RADIUS
	)
	if not zone.is_in_bounds(south_anchor) or zone.is_in_bounds(
		HexCoordUtils.rim_anchor(GameEnums.MacroTravelDirection.SOUTH, 13)
	):
		return _fail("Radius bounds accept/reject contract failed.")
	if zone.start_coords != south_anchor:
		return _fail("Initial entry must start on south rim, got %s." % str(zone.start_coords))
	var north := progress.get_directional_destinations(GameEnums.MacroTravelDirection.NORTH)
	if north != ["north_random_1"]:
		return _fail("Central north exit mismatch: %s." % str(north))
	if progress.can_enter_node("east_random_1", GameEnums.MacroTravelDirection.NORTH):
		return _fail("North exit illegally permits east arm.")
	if not progress.enter_node("north_random_1", GameEnums.MacroTravelDirection.NORTH):
		return _fail("Could not travel north from Central Core.")
	if progress.last_arrival_direction != GameEnums.MacroTravelDirection.SOUTH:
		return _fail("North travel must arrive from south.")
	if progress.zone_generator.start_coords != south_anchor:
		return _fail("Destination did not spawn on south rim.")
	var southeast := progress.get_directional_destinations(
		GameEnums.MacroTravelDirection.SOUTHEAST
	)
	if not southeast.has("east_random_1"):
		return _fail("Inner-ring East route is not available from North.")
	return true


func _verify_run_snapshot_backtracking(
	progress: MacroProgressController,
	world_state: RuntimeStateStore
) -> bool:
	world_state.add_ground_items(Vector2i.ZERO, [{
		"id": "snapshot_probe",
		"instance_id": "snapshot_probe_1",
	}])
	var meta := root.get_node_or_null("MetaProgression")
	var prior_lock := true
	if meta != null and meta.has_method("is_central_locked"):
		prior_lock = bool(meta.is_central_locked())
		meta.set_central_locked(false, false)
	if not progress.enter_node(
		MacroGraphGenerator.CENTRAL_ID,
		GameEnums.MacroTravelDirection.SOUTH
	):
		if meta != null and meta.has_method("set_central_locked"):
			meta.set_central_locked(prior_lock, false)
		return _fail("Could not backtrack south to Central Core.")
	if meta != null and meta.has_method("set_central_locked"):
		meta.set_central_locked(prior_lock, false)
	if not progress.enter_node(
		"north_random_1",
		GameEnums.MacroTravelDirection.NORTH
	):
		return _fail("Could not re-enter north_random_1.")
	var restored := false
	for item in world_state.get_ground_items(Vector2i.ZERO):
		if str(item.get("id", "")) == "snapshot_probe":
			restored = true
	if not restored:
		return _fail("Backtracking reset run-local ground state.")
	if not progress.graph.get_node("north_random_1").traversed:
		return _fail("Departed random node was not marked traversed.")
	return true


func _verify_meta_gateway(progress: MacroProgressController) -> bool:
	if progress.graph.get_node("north_gateway").unlocked:
		return _fail("North gateway started unsealed.")
	var meta := root.get_node_or_null("MetaProgression")
	if meta == null:
		return _fail("MetaProgression autoload missing.")
	meta.set_gateway_unsealed("north", true, false)
	var newly := progress.refresh_meta_unlocks()
	if not progress.graph.get_node("north_gateway").unlocked:
		return _fail("Meta flag did not unlock north gateway.")
	if not newly.has("north_gateway"):
		return _fail("Gateway unlock was not reported.")
	return true


func _verify_seed_contracts() -> bool:
	var permanent := MacroNodeData.new()
	permanent.id = MacroGraphGenerator.FETCH_BRANCH_ID
	permanent.persistence = GameEnums.MacroNodePersistence.PERMANENT_META
	permanent.role = GameEnums.MacroNodeRole.META_BRANCH
	var random_node := MacroNodeData.new()
	random_node.id = "east_random_2"
	random_node.persistence = GameEnums.MacroNodePersistence.SEEDED_RANDOM
	random_node.role = GameEnums.MacroNodeRole.RANDOM_ZONE

	var zone_a := MacroZoneGenerator.new()
	zone_a.configure_seed("SEED_A")
	zone_a.generate_node_zone(permanent, GameEnums.MacroTravelDirection.SOUTH, [])
	var permanent_hash_a := zone_a.get_hex_at(Vector2i(2, 2)).visual_variant_hash
	zone_a.configure_seed("SEED_B")
	zone_a.generate_node_zone(permanent, GameEnums.MacroTravelDirection.SOUTH, [])
	if permanent_hash_a != zone_a.get_hex_at(Vector2i(2, 2)).visual_variant_hash:
		return _fail("Permanent node baseline changed across run seeds.")

	var zone_b := MacroZoneGenerator.new()
	zone_b.configure_seed("SEED_A")
	zone_b.generate_node_zone(random_node, GameEnums.MacroTravelDirection.SOUTH, [])
	var random_hash_a := zone_b.get_hex_at(Vector2i(2, 2)).visual_variant_hash
	zone_b.configure_seed("SEED_B")
	zone_b.generate_node_zone(random_node, GameEnums.MacroTravelDirection.SOUTH, [])
	if random_hash_a == zone_b.get_hex_at(Vector2i(2, 2)).visual_variant_hash:
		return _fail("Seeded-random node did not vary across seeds.")
	return true


func _fail(message: String) -> bool:
	push_error("MacroNodePathSmoke: " + message)
	quit(1)
	return false
