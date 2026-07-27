extends SceneTree

const SEED := "EXPANDED_NODE_WEB_SMOKE"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var graph := MacroGraphGenerator.generate_web(SEED)
	var graph_again := MacroGraphGenerator.generate_web(SEED)
	if graph.to_dict() != graph_again.to_dict():
		return _fail("Expanded graph is not deterministic for the same seed.")
	var occupied_positions: Dictionary = {}
	for node_value in graph.nodes.values():
		var positioned := node_value as MacroNodeData
		if positioned == null:
			continue
		if occupied_positions.has(positioned.graph_pos):
			return _fail("Overlapping graph slot at %s." % str(positioned.graph_pos))
		occupied_positions[positioned.graph_pos] = positioned.id
	var edge_ids: Dictionary = {}
	for edge_value in graph.edges:
		var edge: Dictionary = edge_value
		var edge_id := str(edge.get("id", ""))
		if edge_id.is_empty() or edge_ids.has(edge_id):
			return _fail("Graph edge ID is empty or duplicated: %s" % edge_id)
		edge_ids[edge_id] = true
	for start_id in MacroGraphGenerator.allowed_start_node_ids():
		var start := graph.get_node(start_id)
		if start == null or not start.unlocked or not start.discovered:
			return _fail("Start node is not visible and open: %s" % start_id)
	for node_id in ["north_random_2", "north_random_3"]:
		if not graph.get_node(node_id).unlocked:
			return _fail("North depth must start fully open: %s" % node_id)
	for prefix in ["east", "south", "west"]:
		for tier in [2, 3]:
			if graph.get_node("%s_random_%d" % [prefix, tier]).unlocked:
				return _fail("Side-arm depth started open: %s tier %d" % [prefix, tier])
	for link in [
		["north_random_1", "east_random_1"],
		["east_random_1", "south_random_1"],
		["south_random_1", "west_random_1"],
		["west_random_1", "north_random_1"],
	]:
		if graph.get_edge(link[0], link[1]).is_empty():
			return _fail("Route 1 inner-ring link is missing: %s" % str(link))

	for tier in [2, 3]:
		var region_id := "north_random_%d" % tier
		var interior: Array[MacroNodeData] = []
		var hidden: Array[MacroNodeData] = []
		for node_value in graph.nodes.values():
			var node := node_value as MacroNodeData
			if node != null and node.region_id == region_id:
				interior.append(node)
				if node.hidden_until_discovered:
					hidden.append(node)
		var expected_nodes := Vector2i(5, 7) if tier == 2 else Vector2i(7, 10)
		var expected_hidden := Vector2i(2, 3) if tier == 2 else Vector2i(3, 5)
		if interior.size() < expected_nodes.x or interior.size() > expected_nodes.y:
			return _fail("Route %d interior density out of range." % tier)
		if hidden.size() < expected_hidden.x or hidden.size() > expected_hidden.y:
			return _fail("Route %d hidden density out of range." % tier)
		for node in interior:
			if node.neighbors.is_empty():
				return _fail("Orphan interior node: %s" % node.id)
		if not _cluster_is_connected(graph, region_id, interior):
			return _fail("Route %d interior cluster is disconnected." % tier)
		if graph.get_edge("north_random_%d" % tier, "north_random_%d" % (tier + 1)).is_empty() and tier == 2:
			return _fail("Hidden nodes became mandatory for main North progression.")

	var state_store := RuntimeStateStore.new()
	var progress := MacroProgressController.new()
	progress.configure(state_store)
	progress.graph = graph
	progress.world_seed = SEED
	var locked_snapshot := MacroNodeMapSnapshot.build(
		progress,
		GameEnums.MacroTravelDirection.NONE
	)
	for node_entry in locked_snapshot.get("nodes", []):
		if (
			node_entry is Dictionary
			and str(node_entry.get("id", "")) == MacroGraphGenerator.CENTRAL_ID
			and bool(node_entry.get("unlocked", true))
		):
			return _fail("Node Map presents locked Central as unlocked.")
	var hidden_node: MacroNodeData = null
	for node_value in graph.nodes.values():
		var candidate := node_value as MacroNodeData
		if candidate != null and candidate.hidden_until_discovered:
			hidden_node = candidate
			break
	if hidden_node == null:
		return _fail("No hidden node was generated.")
	if _snapshot_has_node(progress, hidden_node.id):
		return _fail("Hidden node leaked into the Node Map before discovery.")
	if _snapshot_has_edge_for_node(progress, hidden_node.id):
		return _fail("Hidden edge leaked into the Node Map before discovery.")
	var reveal_rule: Dictionary = {}
	for rule_value in graph.discovery_rules:
		if rule_value is Dictionary and Array(rule_value.get("reveal_node_ids", [])).has(hidden_node.id):
			if str(rule_value.get("id", "")).begins_with("traverse_reveal"):
				reveal_rule = rule_value
				break
	if reveal_rule.is_empty():
		return _fail("Hidden node has no traversal reveal rule.")
	var trigger_id := str(Array(reveal_rule.get("trigger_ids", []))[0])
	var revealed := progress.apply_discovery_trigger(trigger_id)
	if not revealed.has(hidden_node.id) or not hidden_node.discovered:
		return _fail("Discovery trigger did not reveal its node.")
	if not _snapshot_has_node(progress, hidden_node.id):
		return _fail("Revealed node did not enter the Node Map snapshot.")
	if not _snapshot_has_edge_for_node(progress, hidden_node.id):
		return _fail("Revealed edge did not enter the Node Map snapshot.")
	var round_trip := MacroMapGraph.from_dict(graph.to_dict())
	if not round_trip.get_node(hidden_node.id).discovered:
		return _fail("Graph serialization lost hidden-node discovery state.")
	print("ExpandedNodeWebSmoke PASSED")
	quit(0)


func _snapshot_has_node(progress: MacroProgressController, node_id: String) -> bool:
	var snapshot := MacroNodeMapSnapshot.build(progress, GameEnums.MacroTravelDirection.NONE)
	for entry in snapshot.get("nodes", []):
		if entry is Dictionary and str(entry.get("id", "")) == node_id:
			return true
	return false


func _snapshot_has_edge_for_node(progress: MacroProgressController, node_id: String) -> bool:
	var snapshot := MacroNodeMapSnapshot.build(progress, GameEnums.MacroTravelDirection.NONE)
	for entry in snapshot.get("edges", []):
		if entry is Dictionary and (
			str(entry.get("from", "")) == node_id or str(entry.get("to", "")) == node_id
		):
			return true
	return false


func _cluster_is_connected(
	graph: MacroMapGraph,
	anchor_id: String,
	interior: Array[MacroNodeData]
) -> bool:
	var allowed := {anchor_id: true}
	for node in interior:
		allowed[node.id] = true
	var visited := {anchor_id: true}
	var frontier: Array[String] = [anchor_id]
	while not frontier.is_empty():
		var current: String = frontier.pop_front()
		var current_node := graph.get_node(current)
		for neighbor in current_node.neighbors:
			if allowed.has(neighbor) and not visited.has(neighbor):
				visited[neighbor] = true
				frontier.append(neighbor)
	return visited.size() == allowed.size()


func _fail(message: String) -> void:
	push_error("ExpandedNodeWebSmoke: " + message)
	quit(1)
