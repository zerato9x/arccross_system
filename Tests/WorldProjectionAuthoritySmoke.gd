extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> bool:
	var store := RuntimeStateStore.new()
	store.begin_new_world("WORLD_PROJECTION_AUTHORITY")
	store.set_campaign_state({"seed": store.world_seed}, "node-a", 0)
	var canonical := HexRecord.new()
	canonical.is_explored = false
	store.set_hex_record(Vector2i.ZERO, canonical)
	var facade := HexWorldGenerator.new()
	facade.configure_services(store)
	facade.rebuild_projection_from_store()
	var projection := facade.get_hex_at(Vector2i.ZERO)
	projection.is_explored = true
	if store.get_hex_record(Vector2i.ZERO).is_explored:
		return _fail("Projection mutation leaked into canonical state.")
	facade.rebuild_projection_from_store()
	if facade.get_hex_at(Vector2i.ZERO).is_explored:
		return _fail("Projection rebuild did not restore canonical state.")

	var graph := MacroGraphGenerator.generate_web(store.world_seed)
	var node := graph.get_node("north_random_1") as MacroNodeData
	var zone := MacroZoneGenerator.new()
	zone.configure_services(store)
	zone.configure_seed(store.world_seed)
	var before_generation := store.capture_reconciliation_snapshot()
	zone.generate_node_zone(
		node,
		MacroGraphGenerator.arrival_direction_for_start(node.id),
		[]
	)
	if store.capture_reconciliation_snapshot() != before_generation:
		return _fail("Detached baseline generation mutated RuntimeStateStore.")
	if zone.build_baseline_records().size() != 469:
		return _fail("Detached baseline did not preserve the radius-12 output.")
	print("WORLD_PROJECTION_AUTHORITY_SMOKE: PASS")
	quit(0)
	return true


func _fail(message: String) -> bool:
	push_error("[WORLD_PROJECTION_AUTHORITY] " + message)
	quit(1)
	return false
