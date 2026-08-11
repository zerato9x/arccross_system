extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var state := RuntimeStateStore.new()
	state.begin_new_world("GENERATOR_V2_PERSISTENCE")
	var graph := MacroGraphGenerator.generate_web(state.world_seed)
	var node := graph.get_node("north_random_1") as MacroNodeData
	var arrival := MacroGraphGenerator.arrival_direction_for_start(node.id)
	var zone := MacroZoneGenerator.new()
	zone.configure_services(state)
	zone.configure_seed(state.world_seed)
	zone.generate_node_zone(node, arrival, [arrival, HexCoordUtils.opposite_travel_direction(arrival)])

	var rubble_coords: Vector2i = zone.generated_plan.rubble_search_cells[0]
	var rubble := zone.get_hex_at(rubble_coords)
	rubble.search_count = 1
	rubble.searched_targets = ["wreckage"]
	state.set_hex_record(rubble_coords, rubble.to_state())
	var trace_coords := zone.generated_plan.settlement_coords
	var trace_hex := zone.get_hex_at(trace_coords)
	trace_hex.trace_records.append({
		"trace_id": "temporary_weather_mark",
		"type": "weather_mark",
		"created_minute": state.world_time_minutes,
		"expires_minute": state.world_time_minutes + 10,
	})
	state.set_hex_record(trace_coords, trace_hex.to_state())
	state.ground_item_records[rubble_coords] = [{"definition_id": "scrap", "quantity": 1}]
	state.capture_node_runtime(node.id)
	state.advance_world_time(20)
	state.hex_records.clear()
	state.ground_item_records.clear()
	if not state.restore_node_runtime(node.id):
		return _fail("Node snapshot did not restore.")
	var restored := state.get_hex_record(rubble_coords)
	if restored == null or restored.search_count != 1 or not restored.searched_targets.has("wreckage"):
		return _fail("Exhausted rubble became searchable after restore.")
	if state.get_ground_items(rubble_coords).is_empty():
		return _fail("Dropped items did not persist with the node snapshot.")
	var restored_trace_hex := state.get_hex_record(trace_coords)
	for trace in restored_trace_hex.trace_records:
		if str(trace.get("trace_id", "")) == "temporary_weather_mark":
			return _fail("Expired trace survived the enter-node checkpoint.")
	if RuntimeStateStore.SAVE_VERSION != 12 or int(state.run_flags.get("world_generation_version", 0)) != 3:
		return _fail("Run state was not migrated to the systemic Generator V3 contract.")
	var save_path := ProjectSettings.globalize_path(
		"res://.godot/test-logs/generator_v2_persistence_save.json"
	)
	if not state.save_to_disk(save_path):
		return _fail("Generator V2 state could not be written to disk.")
	var loaded := RuntimeStateStore.new()
	if not loaded.load_from_disk(save_path):
		return _fail("Generator V2 state could not be reloaded from disk.")
	var loaded_rubble := loaded.get_hex_record(rubble_coords)
	if loaded_rubble == null or not loaded_rubble.searched_targets.has("wreckage"):
		return _fail("Rubble depletion was lost across disk save/reload.")
	DirAccess.remove_absolute(save_path)
	print("[GeneratorV2PersistenceSmoke] PASSED")
	quit(0)


func _fail(message: String) -> bool:
	push_error("[GeneratorV2PersistenceSmoke] " + message)
	quit(1)
	return false
