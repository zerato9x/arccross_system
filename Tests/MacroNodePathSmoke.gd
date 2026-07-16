extends SceneTree

## Smoke test for the north-path campaign node graph + 12x12 plains zones.

const SEED := "MACRO_NODE_PATH_SMOKE"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_state := RuntimeStateStore.new()
	world_state.name = "WorldState"
	root.add_child(world_state)

	var progress := MacroProgressController.new()
	progress.configure(world_state)
	var graph := progress.begin_campaign(SEED)

	if not _verify_linear_north_graph(graph):
		return
	if not _verify_gate_before_complete(progress):
		return
	if not _verify_zone_bounds_and_plains(progress, world_state):
		return
	if not _verify_objective_unlocks_next(progress):
		return
	if not _verify_loot_persists_across_nodes(progress, world_state):
		return
	if not _verify_unique_event_completion(progress):
		return
	if not _verify_debug_print(progress):
		return

	print("MacroNodePathSmoke PASSED")
	quit(0)


func _verify_linear_north_graph(graph: MacroMapGraph) -> bool:
	var expected := MacroGraphGenerator.NORTH_PATH
	if graph.nodes.size() != expected.size():
		return _fail(
			"Expected %d campaign nodes, got %d."
			% [expected.size(), graph.nodes.size()]
		)
	for i in range(expected.size() - 1):
		var from_id: String = expected[i]
		var to_id: String = expected[i + 1]
		var node := graph.get_node(from_id)
		if node == null:
			return _fail("Missing node " + from_id)
		if node.neighbors.size() != 1 or node.neighbors[0] != to_id:
			return _fail(
				"Node %s must have exactly one north edge to %s (got %s)."
				% [from_id, to_id, str(node.neighbors)]
			)
	var end_node := graph.get_node(MacroGraphGenerator.EVENT_END)
	if end_node == null or not end_node.neighbors.is_empty():
		return _fail("End node must have no outgoing edges.")
	if end_node.zone_kind != GameEnums.MacroZoneKind.UNIQUE_EVENT:
		return _fail("End node must be UNIQUE_EVENT.")
	if not graph.get_node(MacroGraphGenerator.HUB_ID).unlocked:
		return _fail("Hub must start unlocked.")
	if graph.get_node(MacroGraphGenerator.PLAINS_1).unlocked:
		return _fail("First plains node must start locked.")
	return true


func _verify_gate_before_complete(progress: MacroProgressController) -> bool:
	var available := progress.get_available_nodes()
	if available != [MacroGraphGenerator.HUB_ID]:
		# Only unlocked nodes appear; hub is the only one initially.
		if not available.has(MacroGraphGenerator.HUB_ID):
			return _fail("Hub missing from available nodes.")
		if available.has(MacroGraphGenerator.PLAINS_1):
			return _fail("Plains_1 must not be available before hub completes.")
	if progress.can_enter_node(MacroGraphGenerator.PLAINS_1):
		return _fail("Must not enter plains_1 before unlock.")
	if not progress.enter_node(MacroGraphGenerator.HUB_ID):
		return _fail("Failed to enter hub.")
	return true


func _verify_zone_bounds_and_plains(
	progress: MacroProgressController,
	world_state: RuntimeStateStore
) -> bool:
	var zone := progress.zone_generator
	if zone.hex_count() != GameEnums.MACRO_ZONE_SIZE * GameEnums.MACRO_ZONE_SIZE:
		return _fail(
			"Zone must contain %d hexes, got %d."
			% [
				GameEnums.MACRO_ZONE_SIZE * GameEnums.MACRO_ZONE_SIZE,
				zone.hex_count(),
			]
		)
	for y in range(GameEnums.MACRO_ZONE_SIZE):
		for x in range(GameEnums.MACRO_ZONE_SIZE):
			var coords := Vector2i(x, y)
			var hex := zone.get_hex_at(coords)
			if hex.biome != GameEnums.GridBiome.PLAINS:
				return _fail("Hub/plains zone cell %s must be PLAINS." % str(coords))
			if hex.biome_pack != GameEnums.BIOME_PACK_PLAINS and hex.biome_pack != GameEnums.BIOME_PACK_CENTRALCORE:
				return _fail("Unexpected biome_pack at %s." % str(coords))
	if not zone.is_in_bounds(zone.start_coords):
		return _fail("Start coords out of bounds.")
	if not zone.is_in_bounds(zone.objective_coords):
		return _fail("Objective coords out of bounds.")

	# Determinism: regenerate same node seed → same variant hash at a cell.
	var sample := Vector2i(4, 4)
	var hash_a := zone.get_hex_at(sample).visual_variant_hash
	progress.enter_node(MacroGraphGenerator.HUB_ID)
	var hash_b := progress.zone_generator.get_hex_at(sample).visual_variant_hash
	if hash_a != hash_b:
		return _fail("Zone visual_variant_hash not deterministic for fixed seed.")
	if world_state.active_node_id != MacroGraphGenerator.HUB_ID:
		return _fail("WorldState.active_node_id not synced.")
	return true


func _verify_objective_unlocks_next(progress: MacroProgressController) -> bool:
	var before := progress.get_available_nodes()
	if before.has(MacroGraphGenerator.PLAINS_1):
		return _fail("Plains_1 already available before objective.")
	if not progress.try_complete_objective_at(progress.zone_generator.objective_coords):
		return _fail("try_complete_objective_at failed on hub exit.")
	var hub := progress.graph.get_node(MacroGraphGenerator.HUB_ID)
	if not hub.completed:
		return _fail("Hub not marked completed.")
	var newly := progress.get_available_nodes()
	if not newly.has(MacroGraphGenerator.PLAINS_1):
		return _fail("Completing hub did not unlock plains_1.")
	if newly.has(MacroGraphGenerator.PLAINS_2):
		return _fail("Plains_2 unlocked too early.")
	if not progress.enter_node(MacroGraphGenerator.PLAINS_1):
		return _fail("Failed to enter plains_1 after unlock.")
	if progress.zone_generator.hex_count() != 144:
		return _fail("Plains_1 zone size incorrect.")
	if progress.zone_generator.zone_kind != GameEnums.MacroZoneKind.BIOME_RNG:
		return _fail("Plains_1 must be BIOME_RNG.")
	return true


func _verify_loot_persists_across_nodes(
	progress: MacroProgressController,
	world_state: RuntimeStateStore
) -> bool:
	# Simulate player inventory surviving a node swap.
	var fake_player := EntityRecord.new()
	fake_player.entity_id = "player"
	fake_player.kind = GameEnums.RuntimeEntityKind.PLAYER
	fake_player.life_state = GameEnums.EntityLifeState.ALIVE
	fake_player.runtime = {
		"inventory": {
			"backpack": [{"instance_id": "loot_keep_1", "template_path": "res://ItemCore/Items/mre.tres"}],
		},
	}
	world_state.player_record = fake_player
	world_state.player_coords = progress.zone_generator.start_coords

	progress.mark_node_completed(MacroGraphGenerator.PLAINS_1)
	if not progress.enter_node(MacroGraphGenerator.PLAINS_2):
		return _fail("Failed to enter plains_2.")

	if world_state.player_record == null:
		return _fail("Player record wiped on node enter.")
	var backpack: Array = (
		world_state.player_record.runtime
		.get("inventory", {})
		.get("backpack", [])
	)
	if backpack.is_empty():
		return _fail("Player loot did not persist across enter_node.")
	if str(backpack[0].get("instance_id", "")) != "loot_keep_1":
		return _fail("Persisted loot instance_id mismatch.")
	return true


func _verify_unique_event_completion(progress: MacroProgressController) -> bool:
	progress.mark_node_completed(MacroGraphGenerator.PLAINS_2)
	progress.mark_node_completed(MacroGraphGenerator.PLAINS_3)
	if not progress.get_available_nodes().has(MacroGraphGenerator.EVENT_END):
		return _fail("Event end not unlocked after plains_3.")
	if not progress.enter_node(MacroGraphGenerator.EVENT_END):
		return _fail("Failed to enter unique event node.")
	if progress.zone_generator.zone_kind != GameEnums.MacroZoneKind.UNIQUE_EVENT:
		return _fail("End zone kind mismatch.")
	# Arrival alone must NOT complete unique event nodes.
	if progress.try_complete_objective_at(progress.zone_generator.objective_coords):
		return _fail("Unique event completed by mere arrival.")
	if not progress.complete_active_event_objective():
		return _fail("complete_active_event_objective failed.")
	var end_node := progress.graph.get_node(MacroGraphGenerator.EVENT_END)
	if not end_node.completed:
		return _fail("Event end not completed.")
	return true


func _verify_debug_print(progress: MacroProgressController) -> bool:
	var text := progress.debug_print_map()
	if text.find("MacroMapGraph") < 0:
		return _fail("debug_print_map missing graph header.")
	if text.find(MacroGraphGenerator.HUB_ID) < 0:
		return _fail("debug_print_map missing hub id.")
	if text.find("Zone") < 0:
		return _fail("debug_print_map missing zone ASCII.")
	print(text)
	return true


func _fail(message: String) -> bool:
	push_error("MacroNodePathSmoke FAILED: " + message)
	quit(1)
	return false
