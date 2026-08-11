extends SceneTree

const SEED := "STARTER_NODE_COMPOSITION_V3"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graph := MacroGraphGenerator.generate_web(SEED)
	for node_id in ["north_random_1", "east_random_1", "south_random_1", "west_random_1"]:
		var node := graph.get_node(node_id) as MacroNodeData
		if node == null:
			return _fail("Missing Route 1 node: " + node_id)
		var state := RuntimeStateStore.new()
		state.begin_new_world(SEED)
		var zone := MacroZoneGenerator.new()
		zone.configure_services(state)
		zone.configure_seed(SEED)
		zone.generate_node_zone(node, MacroGraphGenerator.arrival_direction_for_start(node_id), [])
		if zone.world_hex_cache.size() != 469:
			return _fail("Route 1 node is not a deterministic radius-12 zone: " + node_id)
		var physical_count := 0
		for value in zone.world_hex_cache.values():
			var hex := value as MacroHexData
			if hex.world_generation_version != 3:
				return _fail("Legacy generation version leaked into " + node_id)
			physical_count += hex.world_objects.size()
		if physical_count <= 0:
			return _fail("Generated Route 1 node has no component-backed objects: " + node_id)
		if zone.generated_plan.has_settlement:
			return _fail("Route 1 still contains the retired authored settlement stamp.")
	if not _deterministic(SEED, graph.get_node("north_random_1")):
		return
	print("[StarterNodeCompositionSmoke] PASSED")
	quit(0)


func _deterministic(seed_value: String, node: MacroNodeData) -> bool:
	var first := MacroZoneGenerator.new()
	first.configure_seed(seed_value)
	first.generate_node_zone(node, MacroGraphGenerator.arrival_direction_for_start(node.id), [])
	var second := MacroZoneGenerator.new()
	second.configure_seed(seed_value)
	second.generate_node_zone(node, MacroGraphGenerator.arrival_direction_for_start(node.id), [])
	for coords in first.world_hex_cache.keys():
		if first.get_hex_at(coords).to_state().to_dict() != second.get_hex_at(coords).to_state().to_dict():
			return _fail("Route 1 composition is not deterministic at %s." % str(coords))
	return true


func _fail(message: String) -> bool:
	push_error("[StarterNodeCompositionSmoke] " + message)
	quit(1)
	return false
