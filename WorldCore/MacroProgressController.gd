extends RefCounted
class_name MacroProgressController

## Owns campaign graph progression: available nodes, enter, complete, unlocks.
## Local 12x12 hex sessions are generated through MacroZoneGenerator.

signal node_entered(node_id: String)
signal node_completed(node_id: String)
signal nodes_unlocked(node_ids: Array)

var graph: MacroMapGraph
var zone_generator: MacroZoneGenerator
var active_node_id: String = ""
var world_seed: String = ""

var _world_state: RuntimeStateStore


func configure(world_state: RuntimeStateStore) -> void:
	_world_state = world_state
	if zone_generator == null:
		zone_generator = MacroZoneGenerator.new()
	zone_generator.configure_services(world_state)


func begin_campaign(seed_value: String) -> MacroMapGraph:
	world_seed = seed_value
	graph = MacroGraphGenerator.generate_north_path(seed_value)
	active_node_id = ""
	if zone_generator == null:
		zone_generator = MacroZoneGenerator.new()
	zone_generator.configure_services(_world_state)
	zone_generator.configure_seed(seed_value)
	return graph


func load_campaign(graph_data: Dictionary, p_active_node_id: String = "") -> void:
	graph = MacroMapGraph.from_dict(graph_data)
	world_seed = graph.seed_value
	active_node_id = p_active_node_id
	if zone_generator == null:
		zone_generator = MacroZoneGenerator.new()
	zone_generator.configure_services(_world_state)
	zone_generator.configure_seed(world_seed)
	if not active_node_id.is_empty() and graph.has_node(active_node_id):
		_generate_active_zone(graph.get_node(active_node_id))


func get_available_nodes() -> Array[String]:
	var result: Array[String] = []
	if graph == null:
		return result
	for node_id in graph.nodes.keys():
		var node: MacroNodeData = graph.get_node(node_id)
		if node == null:
			continue
		if not node.unlocked:
			continue
		if not node.discovered and node.id != graph.hub_id:
			# Undiscovered locked content stays hidden until unlock reveals it.
			if node.type == GameEnums.MacroNodeType.LOCKED:
				continue
		result.append(node.id)
	return result


func can_enter_node(node_id: String) -> bool:
	if graph == null:
		return false
	var node := graph.get_node(node_id)
	if node == null or not node.unlocked:
		return false
	if node.id == graph.hub_id:
		return true
	# Linear gate: may enter if unlocked (previous objective completed).
	return true


func enter_node(node_id: String) -> bool:
	if not can_enter_node(node_id):
		return false
	var node := graph.get_node(node_id)
	if node == null:
		return false

	# Preserve player inventory across swaps — only local hex/entity state resets.
	_clear_local_zone_runtime()

	node.discovered = true
	active_node_id = node_id
	_generate_active_zone(node)

	if _world_state != null:
		_world_state.active_node_id = node_id
		_world_state.campaign_graph = graph.to_dict()

	node_entered.emit(node_id)
	return true


func mark_node_completed(node_id: String) -> void:
	if graph == null:
		return
	var node := graph.get_node(node_id)
	if node == null:
		return
	if node.completed:
		evaluate_unlocks()
		return
	node.completed = true
	node.discovered = true
	node_completed.emit(node_id)
	evaluate_unlocks()
	if _world_state != null:
		_world_state.campaign_graph = graph.to_dict()


func evaluate_unlocks(player_progress: Dictionary = {}) -> Array[String]:
	var newly: Array[String] = []
	if graph == null:
		return newly

	# v1 linear rule: completing a node unlocks its outgoing neighbors.
	for node_id in graph.nodes.keys():
		var node: MacroNodeData = graph.get_node(node_id)
		if node == null or not node.completed:
			continue
		for neighbor_id in node.neighbors:
			var neighbor := graph.get_node(neighbor_id)
			if neighbor == null:
				continue
			if not neighbor.unlocked:
				neighbor.unlocked = true
				neighbor.discovered = true
				newly.append(neighbor_id)

	# Extensible rule hooks (future branching / corrupted unlocks).
	var completed_count := 0
	var completed_types: Dictionary = {}
	for node_id in graph.nodes.keys():
		var node: MacroNodeData = graph.get_node(node_id)
		if node == null or not node.completed:
			continue
		completed_count += 1
		var type_key := int(node.type)
		completed_types[type_key] = int(completed_types.get(type_key, 0)) + 1

	var progress := player_progress.duplicate(true)
	progress["completed_count"] = completed_count
	progress["completed_types"] = completed_types
	progress["active_node_id"] = active_node_id

	for node_id in graph.nodes.keys():
		var node: MacroNodeData = graph.get_node(node_id)
		if node == null:
			continue
		for rule in node.unlock_rules:
			if not rule is Dictionary:
				continue
			if _rule_satisfied(rule, progress) and not node.unlocked:
				node.unlocked = true
				node.discovered = true
				if not newly.has(node_id):
					newly.append(node_id)
				var connect_from := str(rule.get("connect_from", ""))
				if not connect_from.is_empty() and graph.has_node(connect_from):
					graph.add_edge(connect_from, node_id, false)

	if not newly.is_empty():
		nodes_unlocked.emit(newly)
	if _world_state != null and graph != null:
		_world_state.campaign_graph = graph.to_dict()
	return newly


func get_active_node() -> MacroNodeData:
	if graph == null:
		return null
	return graph.get_node(active_node_id)


func try_complete_objective_at(coords: Vector2i) -> bool:
	## Called when the player interacts with / reaches the objective hex.
	if zone_generator == null or active_node_id.is_empty():
		return false
	if coords != zone_generator.objective_coords:
		return false
	var node := get_active_node()
	if node == null or node.completed:
		return false
	# Unique event nodes complete via event resolution, not mere arrival.
	if node.zone_kind == GameEnums.MacroZoneKind.UNIQUE_EVENT:
		return false
	mark_node_completed(active_node_id)
	return true


func complete_active_event_objective() -> bool:
	var node := get_active_node()
	if node == null or node.completed:
		return false
	if node.zone_kind != GameEnums.MacroZoneKind.UNIQUE_EVENT:
		return false
	mark_node_completed(active_node_id)
	return true


func debug_print_map() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if graph != null:
		parts.append(graph.debug_print())
	else:
		parts.append("(no campaign graph)")
	parts.append("active_node_id=%s" % active_node_id)
	parts.append("available=%s" % str(get_available_nodes()))
	if zone_generator != null and not zone_generator.node_id.is_empty():
		parts.append(zone_generator.debug_ascii())
	return "\n".join(parts)


func _generate_active_zone(node: MacroNodeData) -> void:
	zone_generator.configure_seed(world_seed)
	zone_generator.generate_zone(
		node.id,
		node.zone_kind,
		node.biome,
		node.event_id
	)


func _clear_local_zone_runtime() -> void:
	## Drop local hex / entity / ground state so the next zone starts clean.
	## Player record + inventory are intentionally left intact.
	if _world_state == null:
		return
	_world_state.hex_records.clear()
	_world_state.entity_records.clear()
	_world_state.entity_ids_by_coords.clear()
	_world_state.ground_item_records.clear()
	if zone_generator != null:
		zone_generator.world_hex_cache.clear()


func _rule_satisfied(rule: Dictionary, progress: Dictionary) -> bool:
	var when := str(rule.get("when", ""))
	match when:
		"complete_type":
			var type_key := int(rule.get("type", -1))
			var needed := int(rule.get("count", 1))
			var completed_types: Dictionary = progress.get("completed_types", {})
			return int(completed_types.get(type_key, 0)) >= needed
		"complete_count":
			return int(progress.get("completed_count", 0)) >= int(rule.get("count", 1))
		"complete_node":
			var target := str(rule.get("node_id", ""))
			if graph == null or target.is_empty():
				return false
			var target_node := graph.get_node(target)
			return target_node != null and target_node.completed
		_:
			return false
