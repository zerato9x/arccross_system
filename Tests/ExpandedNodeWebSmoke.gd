extends SceneTree

const SEED := "EXPANDED_NODE_WEB_SYSTEMIC_SMOKE"

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graph := MacroGraphGenerator.generate_web(SEED)
	var again := MacroGraphGenerator.generate_web(SEED)
	if graph.to_dict() != again.to_dict():
		return _fail("Campaign graph is not deterministic for the same seed.")
	var occupied: Dictionary = {}
	for value in graph.nodes.values():
		var node := value as MacroNodeData
		if node == null:
			continue
		if occupied.has(node.graph_pos):
			return _fail("Overlapping graph slot at %s." % str(node.graph_pos))
		occupied[node.graph_pos] = node.id
	for start_id in MacroGraphGenerator.allowed_start_node_ids():
		var start := graph.get_node(start_id)
		if start == null or not start.unlocked:
			return _fail("Route 1 start is not open: " + start_id)
	var north_two := graph.get_node("north_random_2")
	if north_two == null or not north_two.unlocked:
		return _fail("North Route 2 is still using the retired objective gate.")
	var shelter := graph.get_node("north_r2_shelter")
	if shelter == null or not shelter.unlocked:
		return _fail("Permanent shelter node is missing or locked.")
	if graph.get_edge("north_random_2", "north_r2_shelter").is_empty():
		return _fail("Shelter is not attached to North Route 2.")
	var north_to_two := graph.get_edge("north_random_1", "north_random_2")
	if not north_to_two.is_empty() and str(north_to_two.get("unlock_flag", "")).begins_with("objective:"):
		return _fail("North Route 2 still depends on a quest objective flag.")
	var shelter_edge := graph.get_edge("north_random_2", "north_r2_shelter")
	if not shelter_edge.is_empty() and str(shelter_edge.get("unlock_flag", "")).begins_with("objective:"):
		return _fail("The permanent shelter still depends on a quest objective flag.")
	print("[TEST PASS] Directional graph is deterministic and North progression is physical, not quest-gated.")
	quit(0)


func _fail(message: String) -> void:
	push_error("[ExpandedNodeWebSmoke] " + message)
	quit(1)
