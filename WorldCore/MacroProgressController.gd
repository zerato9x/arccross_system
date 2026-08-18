extends RefCounted
class_name MacroProgressController

## Owns disposable run graph state and directional node transitions. Cross-run
## unlocks are read from MetaProgressionStore; character state never enters it.

signal node_entered(node_id: String)
signal node_traversed(node_id: String)
signal nodes_unlocked(node_ids: Array)

var graph: MacroMapGraph
var zone_generator: MacroZoneGenerator
var active_node_id := ""
var world_seed := ""
var last_arrival_direction: GameEnums.MacroTravelDirection = GameEnums.MacroTravelDirection.SOUTH

var _world_state: RuntimeStateStore
var _meta_progress: Node
var _player_capabilities: PackedStringArray = []
var _newly_revealed_node_ids: PackedStringArray = []


func configure(world_state: RuntimeStateStore) -> void:
	_world_state = world_state
	_meta_progress = Engine.get_main_loop().root.get_node_or_null("MetaProgression")
	if zone_generator == null:
		zone_generator = MacroZoneGenerator.new()
	zone_generator.configure_services(world_state)


func begin_campaign(seed_value: String) -> MacroMapGraph:
	if _meta_progress != null and _meta_progress.has_method("evaluate_campaign_milestones"):
		_meta_progress.evaluate_campaign_milestones()
	world_seed = seed_value
	graph = MacroGraphGenerator.generate_web(seed_value, _meta_flags())
	_apply_meta_unlocks()
	active_node_id = ""
	last_arrival_direction = GameEnums.MacroTravelDirection.SOUTH
	if zone_generator == null:
		zone_generator = MacroZoneGenerator.new()
	zone_generator.configure_services(_world_state)
	zone_generator.configure_seed(seed_value)
	return graph


func set_player_capabilities(capability_ids: PackedStringArray) -> void:
	_player_capabilities = capability_ids.duplicate()


func load_campaign(graph_data: Dictionary, p_active_node_id: String = "") -> void:
	graph = MacroMapGraph.from_dict(graph_data)
	world_seed = graph.seed_value
	active_node_id = p_active_node_id
	if _world_state != null:
		last_arrival_direction = int(_world_state.active_arrival_direction) as GameEnums.MacroTravelDirection
	if zone_generator == null:
		zone_generator = MacroZoneGenerator.new()
	zone_generator.configure_services(_world_state)
	zone_generator.configure_seed(world_seed)
	_apply_meta_unlocks()
	if not active_node_id.is_empty() and graph.has_node(active_node_id):
		_restore_generator_projection(active_node_id, last_arrival_direction)


func get_available_nodes() -> Array[String]:
	var result: Array[String] = []
	if graph == null:
		return result
	for node_id in graph.node_ids_in_order():
		var node := graph.get_node(node_id)
		if (
			node != null
			and node.unlocked
			and (not node.hidden_until_discovered or node.discovered)
		):
			result.append(node_id)
	return result


func get_directional_destinations(exit_direction: int) -> Array[String]:
	var result: Array[String] = []
	if graph == null or active_node_id.is_empty():
		return result
	for edge in graph.get_directional_edges(active_node_id, exit_direction):
		var target_id := str(edge.get("to", ""))
		var target := graph.get_node(target_id)
		if target == null or not target.unlocked:
			continue
		if not bool(edge.get("revealed", edge.get("visible", true))):
			continue
		if (
			target_id == MacroGraphGenerator.CENTRAL_ID
			and _is_central_locked()
			and active_node_id != MacroGraphGenerator.CENTRAL_ID
		):
			continue
		if not _edge_unlocked(edge):
			continue
		if not bool(edge.get("visible", true)) and not target.discovered:
			continue
		result.append(target_id)
	return result


func can_enter_node(
	node_id: String,
	exit_direction: int = GameEnums.MacroTravelDirection.NONE
) -> bool:
	if graph == null:
		return false
	var node := graph.get_node(node_id)
	if node == null or not node.unlocked:
		return false
	if (
		node_id == MacroGraphGenerator.CENTRAL_ID
		and _is_central_locked()
		and not active_node_id.is_empty()
		and active_node_id != MacroGraphGenerator.CENTRAL_ID
	):
		return false
	if active_node_id.is_empty():
		return node_id == graph.hub_id or MacroGraphGenerator.allowed_start_node_ids().has(node_id)
	if exit_direction == GameEnums.MacroTravelDirection.NONE:
		return false
	return get_directional_destinations(exit_direction).has(node_id)


func _is_central_locked() -> bool:
	if _meta_progress != null and _meta_progress.has_method("is_central_locked"):
		return bool(_meta_progress.is_central_locked())
	return bool(_meta_flags().get("central_locked", true))


func is_central_locked() -> bool:
	return _is_central_locked()


func enter_node(
	node_id: String,
	exit_direction: int = GameEnums.MacroTravelDirection.NONE
) -> bool:
	if not can_enter_node(node_id, exit_direction):
		return false
	var node := graph.get_node(node_id)
	if node == null:
		return false

	var arrival := GameEnums.MacroTravelDirection.SOUTH
	if not active_node_id.is_empty():
		var edge := graph.get_edge(active_node_id, node_id)
		arrival = int(edge.get(
			"arrival_direction",
			HexCoordUtils.opposite_travel_direction(exit_direction)
		)) as GameEnums.MacroTravelDirection
	elif MacroGraphGenerator.allowed_start_node_ids().has(node_id):
		arrival = MacroGraphGenerator.arrival_direction_for_start(node_id)
	return _enter_node_unchecked(node, arrival)


func enter_initial_node(node_id: String, arrival_direction: int) -> bool:
	if graph == null or not active_node_id.is_empty():
		return false
	if not MacroGraphGenerator.allowed_start_node_ids().has(node_id):
		return false
	var node := graph.get_node(node_id)
	if node == null or not node.unlocked:
		return false
	return _enter_node_unchecked(node, arrival_direction)


func _enter_node_unchecked(node: MacroNodeData, arrival: int) -> bool:
	var graph_before := graph.to_dict()
	if not active_node_id.is_empty():
		_capture_active_permanent_mutations()
		_mark_active_traversed()
	node.discovered = true
	node.details_revealed = true
	_generate_active_zone(node, arrival)
	if _world_state == null or not _world_state.transition_active_node(
		node.id,
		int(arrival),
		zone_generator.build_baseline_records(),
		graph.to_dict(),
		zone_generator.start_coords
	):
		graph = MacroMapGraph.from_dict(graph_before)
		_world_state.set_campaign_state(
			graph_before,
			active_node_id,
			int(last_arrival_direction)
		)
		_restore_generator_projection(active_node_id, last_arrival_direction)
		return false
	active_node_id = node.id
	last_arrival_direction = arrival
	_restore_generator_projection(active_node_id, last_arrival_direction)
	node_entered.emit(node.id)
	apply_discovery_trigger("node_entered:%s" % node.id)
	return true


func reveal_fetch_branch() -> void:
	reveal_nodes(PackedStringArray([MacroGraphGenerator.FETCH_BRANCH_ID]))


func apply_discovery_trigger(trigger_id: String) -> PackedStringArray:
	_newly_revealed_node_ids.clear()
	if graph == null or trigger_id.is_empty():
		return _newly_revealed_node_ids
	for rule_value in graph.discovery_rules:
		if not rule_value is Dictionary:
			continue
		var rule: Dictionary = rule_value
		if not Array(rule.get("trigger_ids", [])).has(trigger_id):
			continue
		if not _discovery_requirements_met(rule.get("requirements", {})):
			continue
		_reveal_rule(rule)
	if _world_state != null and not _newly_revealed_node_ids.is_empty():
		_world_state.set_campaign_state(
			graph.to_dict(), active_node_id, int(last_arrival_direction)
		)
	return _newly_revealed_node_ids.duplicate()


func reveal_nodes(node_ids: PackedStringArray) -> PackedStringArray:
	_newly_revealed_node_ids.clear()
	if graph == null:
		return _newly_revealed_node_ids
	for node_id in node_ids:
		var node := graph.get_node(node_id)
		if node == null:
			continue
		if not node.discovered:
			node.discovered = true
			_newly_revealed_node_ids.append(node.id)
		for edge in graph.edges:
			if edge is Dictionary and (
				str(edge.get("from", "")) == node.id
				or str(edge.get("to", "")) == node.id
			):
				edge["revealed"] = true
	if _world_state != null and not _newly_revealed_node_ids.is_empty():
		_world_state.set_campaign_state(
			graph.to_dict(), active_node_id, int(last_arrival_direction)
		)
	return _newly_revealed_node_ids.duplicate()


func consume_newly_revealed_node_ids() -> PackedStringArray:
	var result := _newly_revealed_node_ids.duplicate()
	_newly_revealed_node_ids.clear()
	return result


func _reveal_rule(rule: Dictionary) -> void:
	for node_id_value in rule.get("reveal_node_ids", []):
		var node := graph.get_node(str(node_id_value))
		if node != null and not node.discovered:
			node.discovered = true
			_newly_revealed_node_ids.append(node.id)
	for node_id_value in rule.get("reveal_details_node_ids", []):
		var detail_node := graph.get_node(str(node_id_value))
		if detail_node != null and not detail_node.details_revealed:
			detail_node.details_revealed = true
			if not _newly_revealed_node_ids.has(detail_node.id):
				_newly_revealed_node_ids.append(detail_node.id)
	for node_id_value in rule.get("unlock_node_ids", []):
		var unlock_node := graph.get_node(str(node_id_value))
		if unlock_node != null and not unlock_node.unlocked:
			unlock_node.unlocked = true
			if not _newly_revealed_node_ids.has(unlock_node.id):
				_newly_revealed_node_ids.append(unlock_node.id)
			nodes_unlocked.emit([unlock_node.id])
	for region_id_value in rule.get("reveal_hidden_in_regions", []):
		_reveal_next_hidden_node_in_region(str(region_id_value))
	var edge_ids: Array = rule.get("reveal_edge_ids", [])
	for edge in graph.edges:
		if edge is Dictionary and edge_ids.has(str(edge.get("id", ""))):
			edge["revealed"] = true


func _reveal_next_hidden_node_in_region(region_id: String) -> void:
	var candidates: Array[MacroNodeData] = []
	for node_value in graph.nodes.values():
		var node := node_value as MacroNodeData
		if (
			node != null
			and node.region_id == region_id
			and node.hidden_until_discovered
			and not node.discovered
		):
			candidates.append(node)
	candidates.sort_custom(func(a: MacroNodeData, b: MacroNodeData) -> bool:
		return a.id < b.id
	)
	if candidates.is_empty():
		return
	var revealed := candidates[0]
	revealed.discovered = true
	revealed.details_revealed = true
	_newly_revealed_node_ids.append(revealed.id)
	for edge in graph.edges:
		if edge is Dictionary and (
			str(edge.get("from", "")) == revealed.id
			or str(edge.get("to", "")) == revealed.id
		):
			edge["revealed"] = true


func _discovery_requirements_met(requirements: Dictionary) -> bool:
	var any_capabilities: Array = requirements.get("any_capabilities", [])
	if any_capabilities.is_empty():
		return true
	for capability_id in any_capabilities:
		if _player_capabilities.has(str(capability_id)):
			return true
	return false


func refresh_meta_unlocks() -> Array[String]:
	var before: Array[String] = get_available_nodes()
	_apply_meta_unlocks()
	var newly: Array[String] = []
	for node_id in get_available_nodes():
		if not before.has(node_id):
			newly.append(node_id)
	if not newly.is_empty():
		nodes_unlocked.emit(newly)
	if _world_state != null and graph != null:
		_world_state.set_campaign_state(
			graph.to_dict(), active_node_id, int(last_arrival_direction)
		)
	return newly


func mark_node_completed(node_id: String) -> void:
	## Compatibility: ordinary nodes no longer own campaign completion.
	var node := graph.get_node(node_id) if graph != null else null
	if node != null and not node.traversed:
		node.traversed = true
		node_traversed.emit(node_id)


func evaluate_unlocks(_player_progress: Dictionary = {}) -> Array[String]:
	return refresh_meta_unlocks()


func get_active_node() -> MacroNodeData:
	if graph == null:
		return null
	return graph.get_node(active_node_id)


func try_complete_objective_at(_coords: Vector2i) -> bool:
	return false


func complete_active_event_objective() -> bool:
	return false


func debug_print_map() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(graph.debug_print() if graph != null else "(no campaign graph)")
	parts.append("active_node_id=%s arrival=%s" % [active_node_id, str(last_arrival_direction)])
	if zone_generator != null and not zone_generator.node_id.is_empty():
		parts.append(zone_generator.debug_ascii())
	return "\n".join(parts)


func _generate_active_zone(node: MacroNodeData, arrival_direction: int) -> void:
	zone_generator.configure_seed(world_seed)
	zone_generator.generate_node_zone(
		node,
		arrival_direction,
		_connected_directions(node.id)
	)


func _restore_generator_projection(node_id: String, arrival_direction: int) -> void:
	if graph == null or node_id.is_empty():
		return
	var active_node := graph.get_node(node_id)
	if active_node == null:
		return
	zone_generator.configure_seed(world_seed)
	zone_generator.generate_node_zone(
		active_node,
		arrival_direction,
		_connected_directions(node_id)
	)
	if _world_state == null:
		return
	zone_generator.world_hex_cache.clear()
	for coords in _world_state.get_hex_coordinates():
		var snapshot := _world_state.get_hex_snapshot(coords)
		if not snapshot.is_empty():
			zone_generator.world_hex_cache[coords] = MacroHexData.from_state(
				HexRecord.from_dict(snapshot)
			)


func _connected_directions(node_id: String) -> Array[int]:
	var result: Array[int] = []
	if graph == null:
		return result
	for edge in graph.edges:
		if not edge is Dictionary or str(edge.get("from", "")) != node_id:
			continue
		if not bool(edge.get("revealed", edge.get("visible", true))):
			continue
		var direction := int(edge.get(
			"from_direction", GameEnums.MacroTravelDirection.NONE
		))
		if direction != GameEnums.MacroTravelDirection.NONE and not result.has(direction):
			result.append(direction)
	return result


func _mark_active_traversed() -> void:
	var active := get_active_node()
	if active == null or active.traversed:
		return
	active.traversed = true
	node_traversed.emit(active.id)
	apply_discovery_trigger("node_traversed:%s" % active.id)


func _capture_active_permanent_mutations() -> void:
	if _world_state == null or active_node_id.is_empty():
		return
	var node := get_active_node()
	if (
		node != null
		and node.persistence == GameEnums.MacroNodePersistence.PERMANENT_META
		and _meta_progress != null
		and _meta_progress.has_method("capture_node_mutations")
	):
		_meta_progress.capture_node_mutations(
			node.id,
			zone_generator.permanent_baseline_records,
			_world_state.get_hex_records_snapshot()
		)


func _edge_unlocked(edge: Dictionary) -> bool:
	var flag := str(edge.get("unlock_flag", ""))
	if flag.is_empty():
		return true
	return bool(_meta_flags().get(flag, false))


func _apply_meta_unlocks() -> void:
	if graph == null:
		return
	var flags := _meta_flags()
	for node_id in graph.nodes.keys():
		var node := graph.get_node(node_id)
		if node == null:
			continue
		var profile_patch: Dictionary = (
			_meta_progress.get_node_profile_patch(node_id)
			if _meta_progress != null and _meta_progress.has_method("get_node_profile_patch")
			else {}
		)
		for field_name in [
			"zone_profile_id",
			"biome",
			"zone_kind",
			"type",
			"details_revealed",
		]:
			if profile_patch.has(field_name):
				node.set(field_name, profile_patch[field_name])
	for prefix in MacroGraphGenerator.ARM_PREFIXES:
		var flag := "gateway_%s_unsealed" % prefix
		var open := bool(flags.get(flag, false))
		var gateway := graph.get_node("%s_gateway" % prefix)
		var core := graph.get_node("%s_core" % prefix)
		if gateway != null:
			gateway.unlocked = open
		if core != null:
			core.unlocked = open


func _meta_flags() -> Dictionary:
	if _meta_progress != null and _meta_progress.has_method("get_meta_flags"):
		return _meta_progress.get_meta_flags()
	return {}
