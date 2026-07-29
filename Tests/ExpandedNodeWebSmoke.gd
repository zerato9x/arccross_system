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
		var secret: Array[MacroNodeData] = []
		for node_value in graph.nodes.values():
			var node := node_value as MacroNodeData
			if node != null and node.region_id == region_id:
				interior.append(node)
				if _has_traverse_reveal(graph, node.id):
					secret.append(node)
		var expected_nodes := Vector2i(5, 7) if tier == 2 else Vector2i(7, 10)
		var expected_hidden := Vector2i(2, 3) if tier == 2 else Vector2i(3, 5)
		if interior.size() < expected_nodes.x or interior.size() > expected_nodes.y:
			return _fail("Route %d interior density out of range." % tier)
		if secret.size() < expected_hidden.x or secret.size() > expected_hidden.y:
			return _fail("Route %d hidden density out of range." % tier)
		for node in interior:
			if not node.hidden_until_discovered or node.discovered:
				return _fail("Interior must start undiscovered and gated: %s" % node.id)
			if node.neighbors.is_empty():
				return _fail("Orphan interior node: %s" % node.id)
		if not _cluster_is_connected(graph, region_id, interior):
			return _fail("Route %d interior cluster is disconnected." % tier)
		if graph.get_edge("north_random_%d" % tier, "north_random_%d" % (tier + 1)).is_empty() and tier == 2:
			return _fail("Hidden nodes became mandatory for main North progression.")
		var cluster_rule := _find_rule(graph, "cluster_reveal__%s" % region_id)
		if cluster_rule.is_empty():
			return _fail("Missing cluster reveal rule for %s." % region_id)
		if not Array(cluster_rule.get("trigger_ids", [])).has("node_entered:%s" % region_id):
			return _fail("Cluster reveal trigger mismatch for %s." % region_id)

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
	for spine_id in ["north_random_2", "north_random_3"]:
		if not _snapshot_has_node(progress, spine_id):
			return _fail("North spine missing from initial Node Map: %s" % spine_id)
	for node_value in graph.nodes.values():
		var interior_node := node_value as MacroNodeData
		if interior_node == null or not interior_node.region_id.begins_with("north_random_"):
			continue
		if _snapshot_has_node(progress, interior_node.id):
			return _fail("Interior leaked into Node Map before discovery: %s" % interior_node.id)
		if _snapshot_has_edge_for_node(progress, interior_node.id):
			return _fail("Interior edge leaked into Node Map before discovery: %s" % interior_node.id)

	for tier in [2, 3]:
		var anchor_id := "north_random_%d" % tier
		var cluster_rule := _find_rule(graph, "cluster_reveal__%s" % anchor_id)
		var main_ids: Array = Array(cluster_rule.get("reveal_node_ids", []))
		var revealed := progress.apply_discovery_trigger("node_entered:%s" % anchor_id)
		for main_id_value in main_ids:
			var main_id := str(main_id_value)
			if not revealed.has(main_id):
				return _fail("Cluster reveal did not return main node: %s" % main_id)
			if not graph.get_node(main_id).discovered:
				return _fail("Cluster reveal did not discover main node: %s" % main_id)
			if not _snapshot_has_node(progress, main_id):
				return _fail("Main cluster node missing from snapshot after reveal: %s" % main_id)
			if not _snapshot_has_edge_for_node(progress, main_id):
				return _fail("Main cluster edge missing from snapshot after reveal: %s" % main_id)

	var secret_node: MacroNodeData = null
	for node_value in graph.nodes.values():
		var candidate := node_value as MacroNodeData
		if candidate != null and _has_traverse_reveal(graph, candidate.id) and not candidate.discovered:
			secret_node = candidate
			break
	if secret_node == null:
		return _fail("No secret node was generated.")
	if _snapshot_has_node(progress, secret_node.id):
		return _fail("Secret node leaked into the Node Map before discovery.")
	if _snapshot_has_edge_for_node(progress, secret_node.id):
		return _fail("Secret edge leaked into the Node Map before discovery.")
	var reveal_rule: Dictionary = {}
	for rule_value in graph.discovery_rules:
		if rule_value is Dictionary and Array(rule_value.get("reveal_node_ids", [])).has(secret_node.id):
			if str(rule_value.get("id", "")).begins_with("traverse_reveal"):
				reveal_rule = rule_value
				break
	if reveal_rule.is_empty():
		return _fail("Secret node has no traversal reveal rule.")
	var trigger_id := str(Array(reveal_rule.get("trigger_ids", []))[0])
	var secret_revealed := progress.apply_discovery_trigger(trigger_id)
	if not secret_revealed.has(secret_node.id) or not secret_node.discovered:
		return _fail("Discovery trigger did not reveal its secret node.")
	if not _snapshot_has_node(progress, secret_node.id):
		return _fail("Revealed secret node did not enter the Node Map snapshot.")
	if not _snapshot_has_edge_for_node(progress, secret_node.id):
		return _fail("Revealed secret edge did not enter the Node Map snapshot.")
	var round_trip := MacroMapGraph.from_dict(graph.to_dict())
	if not round_trip.get_node(secret_node.id).discovered:
		return _fail("Graph serialization lost hidden-node discovery state.")
	print("ExpandedNodeWebSmoke PASSED")
	quit(0)


func _has_traverse_reveal(graph: MacroMapGraph, node_id: String) -> bool:
	return not _find_rule(graph, "traverse_reveal__%s" % node_id).is_empty()


func _find_rule(graph: MacroMapGraph, rule_id: String) -> Dictionary:
	for rule_value in graph.discovery_rules:
		if rule_value is Dictionary and str(rule_value.get("id", "")) == rule_id:
			return rule_value
	return {}


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
