extends Resource
class_name MacroMapGraph

## Campaign node graph: adjacency list of MacroNodeData resources.

@export var nodes: Dictionary = {} # String id -> MacroNodeData
@export var edges: Array = [] # Array of { "from": String, "to": String }
@export var hub_id: String = ""
@export var seed_value: String = ""


func clear() -> void:
	nodes.clear()
	edges.clear()
	hub_id = ""
	seed_value = ""


func add_node(node: MacroNodeData) -> void:
	if node == null or node.id.is_empty():
		return
	nodes[node.id] = node


func get_node(node_id: String) -> MacroNodeData:
	if not nodes.has(node_id):
		return null
	return nodes[node_id]


func has_node(node_id: String) -> bool:
	return nodes.has(node_id)


func add_edge(from_id: String, to_id: String, bidirectional: bool = false) -> void:
	if from_id.is_empty() or to_id.is_empty():
		return
	if not _has_edge(from_id, to_id):
		edges.append({"from": from_id, "to": to_id})
	_ensure_neighbor(from_id, to_id)
	if bidirectional:
		if not _has_edge(to_id, from_id):
			edges.append({"from": to_id, "to": from_id})
		_ensure_neighbor(to_id, from_id)


func _has_edge(from_id: String, to_id: String) -> bool:
	for edge in edges:
		if str(edge.get("from", "")) == from_id and str(edge.get("to", "")) == to_id:
			return true
	return false


func _ensure_neighbor(from_id: String, to_id: String) -> void:
	var node: MacroNodeData = get_node(from_id)
	if node == null:
		return
	if not node.neighbors.has(to_id):
		node.neighbors.append(to_id)


func get_outgoing(node_id: String) -> Array[String]:
	var result: Array[String] = []
	var node := get_node(node_id)
	if node == null:
		return result
	for neighbor_id in node.neighbors:
		result.append(neighbor_id)
	return result


func node_ids_in_order() -> Array[String]:
	## Prefer north-path order by graph_pos.y descending (north = higher y in UI).
	var ids: Array[String] = []
	for node_id in nodes.keys():
		ids.append(str(node_id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		var na := get_node(a)
		var nb := get_node(b)
		if na == null or nb == null:
			return a < b
		if na.graph_pos.y != nb.graph_pos.y:
			return na.graph_pos.y < nb.graph_pos.y
		return na.graph_pos.x < nb.graph_pos.x
	)
	return ids


func to_dict() -> Dictionary:
	var node_dicts: Dictionary = {}
	for node_id in nodes.keys():
		var node: MacroNodeData = nodes[node_id]
		node_dicts[node_id] = node.to_dict()
	return {
		"hub_id": hub_id,
		"seed_value": seed_value,
		"nodes": node_dicts,
		"edges": edges.duplicate(true),
	}


static func from_dict(data: Dictionary) -> MacroMapGraph:
	var graph := MacroMapGraph.new()
	graph.hub_id = str(data.get("hub_id", ""))
	graph.seed_value = str(data.get("seed_value", ""))
	var node_dicts: Dictionary = data.get("nodes", {})
	for node_id in node_dicts.keys():
		graph.add_node(MacroNodeData.from_dict(node_dicts[node_id]))
	for edge in data.get("edges", []):
		if edge is Dictionary:
			graph.add_edge(str(edge.get("from", "")), str(edge.get("to", "")), false)
	return graph


func debug_print() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== MacroMapGraph seed=%s hub=%s ===" % [seed_value, hub_id])
	for node_id in node_ids_in_order():
		var node := get_node(node_id)
		if node == null:
			continue
		var flags: PackedStringArray = PackedStringArray()
		if node.unlocked:
			flags.append("unlocked")
		if node.discovered:
			flags.append("discovered")
		if node.completed:
			flags.append("completed")
		lines.append(
			"%s [%s] pos=%s type=%s zone=%s biome=%s neighbors=%s {%s}"
			% [
				node.id,
				node.display_name,
				str(node.graph_pos),
				str(node.type),
				str(node.zone_kind),
				str(node.biome),
				str(node.neighbors),
				",".join(flags),
			]
		)
	for edge in edges:
		lines.append("  edge %s -> %s" % [str(edge.get("from", "")), str(edge.get("to", ""))])
	return "\n".join(lines)
