extends RefCounted
class_name NewRunDepartureSnapshot


static func build(seed_value: String) -> Dictionary:
	var graph := MacroGraphGenerator.generate_web(seed_value)
	var starts := MacroGraphGenerator.allowed_start_node_ids()
	var visible_ids := PackedStringArray([MacroGraphGenerator.CENTRAL_ID])
	for start_id in starts:
		visible_ids.append(start_id)
	visible_ids.append("north_random_2")
	visible_ids.append("north_random_3")
	for prefix in ["east", "south", "west"]:
		visible_ids.append("%s_random_2" % prefix)
		visible_ids.append("%s_random_3" % prefix)

	var nodes: Array = []
	for node_id in visible_ids:
		var node := graph.get_node(node_id)
		if node == null:
			continue
		var entry := node.to_dict()
		if node.role == GameEnums.MacroNodeRole.CENTRAL_CORE:
			entry["unlocked"] = false
		entry["can_enter"] = starts.has(node_id)
		entry["is_active"] = false
		entry["is_next"] = starts.has(node_id)
		entry["detail_hidden"] = false
		entry["display_name"] = node.display_name
		nodes.append(entry)

	var edges: Array = []
	for edge_value in graph.edges:
		if not edge_value is Dictionary:
			continue
		var edge: Dictionary = edge_value
		if visible_ids.has(str(edge.get("from", ""))) and visible_ids.has(str(edge.get("to", ""))):
			var entry := edge.duplicate(true)
			entry["eligible"] = false
			edges.append(entry)
	return {
		"active_node_id": "",
		"travel_mode": false,
		"nodes": nodes,
		"edges": edges,
	}
