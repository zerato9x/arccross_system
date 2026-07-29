extends RefCounted
class_name MacroGraphGenerator

const CAMPAIGN_DEFINITION_PATH := "res://WorldCore/campaign_graph.tres"
const CENTRAL_ID := "central_core"
const HUB_ID := CENTRAL_ID
const FETCH_BRANCH_ID := "east_component_site"
const META_FETCH_EVENT_ID := "meta_fetch_north_gateway"
const FETCH_ITEM_ID := "arc_core_component_north"
const NORTH_GATEWAY_FLAG := "gateway_north_unsealed"
const ARM_PREFIXES := ["north", "east", "south", "west"]

const _CLUSTER_OFFSETS := [
	Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-2, 1), Vector2i(2, 1),
	Vector2i(-3, -1), Vector2i(3, -1), Vector2i(-3, 2), Vector2i(3, 2),
	Vector2i(-1, 2), Vector2i(1, 2),
]


static func campaign_definition() -> CampaignGraphDefinition:
	return load(CAMPAIGN_DEFINITION_PATH) as CampaignGraphDefinition


static func allowed_start_node_ids() -> PackedStringArray:
	var definition := campaign_definition()
	return definition.allowed_start_node_ids() if definition != null else PackedStringArray()


static func arrival_direction_for_start(node_id: String) -> int:
	var definition := campaign_definition()
	return (
		definition.arrival_direction_for_start(node_id)
		if definition != null
		else GameEnums.MacroTravelDirection.SOUTH
	)


static func generate_web(seed_value: String, meta_flags: Dictionary = {}) -> MacroMapGraph:
	var definition := campaign_definition()
	if definition == null:
		push_error("[MacroGraphGenerator] Campaign definition is missing.")
		return MacroMapGraph.new()
	var graph := MacroMapGraph.new()
	graph.seed_value = seed_value
	graph.hub_id = definition.central_node_id

	var central := _def(
		definition.central_node_id,
		"Central Core",
		Vector2i.ZERO,
		GameEnums.MacroNodeType.HUB,
		GameEnums.MacroNodeRole.CENTRAL_CORE,
		GameEnums.MacroNodePersistence.PERMANENT_META,
		GameEnums.MacroArmDirection.NONE,
		0,
		"central_core"
	)
	central.unlocked = true
	central.discovered = true
	central.details_revealed = true
	central.meta_event_id = META_FETCH_EVENT_ID
	graph.add_node(central)

	for arm in definition.arms:
		if arm != null:
			_build_arm(graph, arm, definition.graph_spacing, meta_flags)

	if definition.open_inner_ring:
		_add_bidirectional(graph, "north_random_1", "east_random_1",
			GameEnums.MacroTravelDirection.SOUTHEAST, GameEnums.MacroTravelDirection.NORTHWEST)
		_add_bidirectional(graph, "east_random_1", "south_random_1",
			GameEnums.MacroTravelDirection.SOUTHWEST, GameEnums.MacroTravelDirection.NORTHEAST)
		_add_bidirectional(graph, "south_random_1", "west_random_1",
			GameEnums.MacroTravelDirection.NORTHWEST, GameEnums.MacroTravelDirection.SOUTHEAST)
		_add_bidirectional(graph, "west_random_1", "north_random_1",
			GameEnums.MacroTravelDirection.NORTHEAST, GameEnums.MacroTravelDirection.SOUTHWEST)

	_add_fetch_branch(graph, definition.graph_spacing)
	return graph


static func generate_north_path(seed_value: String) -> MacroMapGraph:
	return generate_web(seed_value)


static func _build_arm(
	graph: MacroMapGraph,
	arm: CampaignArmDefinition,
	spacing: int,
	meta_flags: Dictionary
) -> void:
	var previous_id := CENTRAL_ID
	for tier in range(1, 4):
		var node_id := "%s_random_%d" % [arm.prefix, tier]
		var zone_profile_id := (
			"starter_route_1"
			if tier == 1
			else "%s_tier_%d" % [arm.prefix, tier]
		)
		var node := _def(
			node_id,
			"%s Route %d" % [arm.display_name, tier],
			arm.axis * tier * spacing,
			GameEnums.MacroNodeType.STANDARD,
			GameEnums.MacroNodeRole.RANDOM_ZONE,
			GameEnums.MacroNodePersistence.SEEDED_RANDOM,
			arm.arm_direction as GameEnums.MacroArmDirection,
			tier,
			zone_profile_id
		)
		node.unlocked = tier <= arm.initial_open_depth
		node.discovered = true
		node.details_revealed = tier == 1
		graph.add_node(node)
		_add_bidirectional(
			graph,
			previous_id,
			node_id,
			arm.outward_direction,
			arm.inward_direction
		)
		previous_id = node_id
		if arm.author_interior_clusters and tier in [2, 3]:
			_build_interior_cluster(graph, arm, tier, node, graph.seed_value)

	var gateway_id := "%s_gateway" % arm.prefix
	var gateway_flag := "gateway_%s_unsealed" % arm.prefix
	var gateway_open := bool(meta_flags.get(gateway_flag, false))
	var gateway := _def(
		gateway_id,
		"%s Gateway" % arm.display_name,
		arm.axis * 4 * spacing,
		GameEnums.MacroNodeType.LOCKED,
		GameEnums.MacroNodeRole.GATEWAY,
		GameEnums.MacroNodePersistence.PERMANENT_META,
		arm.arm_direction as GameEnums.MacroArmDirection,
		4,
		"%s_gateway" % arm.prefix
	)
	gateway.unlocked = gateway_open
	gateway.discovered = true
	gateway.details_revealed = true
	graph.add_node(gateway)
	_add_bidirectional(graph, previous_id, gateway_id, arm.outward_direction,
		arm.inward_direction, gateway_flag)

	var core_id := "%s_core" % arm.prefix
	var core := _def(
		core_id,
		"%s Arm Core" % arm.display_name,
		arm.axis * 5 * spacing,
		GameEnums.MacroNodeType.SPECIAL,
		GameEnums.MacroNodeRole.ARM_CORE,
		GameEnums.MacroNodePersistence.PERMANENT_META,
		arm.arm_direction as GameEnums.MacroArmDirection,
		5,
		"%s_arm_core" % arm.prefix
	)
	core.unlocked = gateway_open
	core.discovered = true
	core.details_revealed = true
	graph.add_node(core)
	_add_bidirectional(graph, gateway_id, core_id, arm.outward_direction,
		arm.inward_direction, gateway_flag)


static func _build_interior_cluster(
	graph: MacroMapGraph,
	arm: CampaignArmDefinition,
	tier: int,
	anchor: MacroNodeData,
	seed_value: String
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|route_%d|interior" % [seed_value, arm.prefix, tier])
	var count_range := arm.node_count_range(tier)
	var hidden_range := arm.hidden_count_range(tier)
	var node_count := rng.randi_range(count_range.x, count_range.y)
	var hidden_count := mini(node_count - 1, rng.randi_range(hidden_range.x, hidden_range.y))
	var visible_count := node_count - hidden_count
	var visible_ids: Array[String] = []
	var main_edge_ids: Array[String] = []

	for index in range(node_count):
		var node_id := "%s_route_%d_interior_%02d" % [arm.prefix, tier, index + 1]
		var is_secret := index >= visible_count
		var node := _def(
			node_id,
			"%s Interior %02d" % [arm.display_name, index + 1],
			anchor.graph_pos + _CLUSTER_OFFSETS[index],
			GameEnums.MacroNodeType.STANDARD,
			GameEnums.MacroNodeRole.RANDOM_ZONE,
			GameEnums.MacroNodePersistence.SEEDED_RANDOM,
			arm.arm_direction as GameEnums.MacroArmDirection,
			tier,
			"%s_tier_%d_interior" % [arm.prefix, tier]
		)
		node.region_id = anchor.id
		node.unlocked = true
		node.discovered = false
		node.details_revealed = false
		node.hidden_until_discovered = true
		graph.add_node(node)
		if not is_secret:
			visible_ids.append(node_id)

	for index in range(visible_ids.size()):
		var from_id := anchor.id if index == 0 else visible_ids[index - 1]
		var edge_ids := _connect_by_layout(graph, from_id, visible_ids[index], false)
		for edge_id in edge_ids:
			main_edge_ids.append(edge_id)

	graph.discovery_rules.append({
		"id": "cluster_reveal__%s" % anchor.id,
		"trigger_ids": ["node_entered:%s" % anchor.id],
		"reveal_node_ids": visible_ids.duplicate(),
		"reveal_edge_ids": main_edge_ids.duplicate(),
		"requirements": {},
	})

	for hidden_index in range(hidden_count):
		var node_index := visible_count + hidden_index
		var hidden_id := "%s_route_%d_interior_%02d" % [arm.prefix, tier, node_index + 1]
		var parent_id := visible_ids[hidden_index % visible_ids.size()]
		var edge_ids := _connect_by_layout(graph, parent_id, hidden_id, false)
		graph.discovery_rules.append({
			"id": "traverse_reveal__%s" % hidden_id,
			"trigger_ids": ["node_traversed:%s" % parent_id, "intel:%s" % hidden_id],
			"reveal_node_ids": [hidden_id],
			"reveal_edge_ids": edge_ids,
			"requirements": {},
		})
		graph.discovery_rules.append({
			"id": "field_sense_reveal__%s" % hidden_id,
			"trigger_ids": ["node_entered:%s" % parent_id],
			"reveal_node_ids": [hidden_id],
			"reveal_edge_ids": edge_ids,
			"requirements": {"any_capabilities": ["survey_routes"]},
		})


static func _connect_by_layout(
	graph: MacroMapGraph,
	from_id: String,
	to_id: String,
	revealed: bool
) -> PackedStringArray:
	var from_node := graph.get_node(from_id)
	var to_node := graph.get_node(to_id)
	if from_node == null or to_node == null:
		return PackedStringArray()
	var direction := _direction_for_delta(to_node.graph_pos - from_node.graph_pos)
	var arrival := HexCoordUtils.opposite_travel_direction(direction)
	var forward_id := "%s__%s" % [from_id, to_id]
	_add_bidirectional(graph, from_id, to_id, direction, arrival, "", true, revealed)
	return PackedStringArray([forward_id, "%s__%s" % [to_id, from_id]])


static func _direction_for_delta(delta: Vector2i) -> int:
	var angle := Vector2(delta.x, -delta.y).angle()
	var octant := posmod(int(round(angle / (PI / 4.0))), 8)
	return [
		GameEnums.MacroTravelDirection.EAST,
		GameEnums.MacroTravelDirection.NORTHEAST,
		GameEnums.MacroTravelDirection.NORTH,
		GameEnums.MacroTravelDirection.NORTHWEST,
		GameEnums.MacroTravelDirection.WEST,
		GameEnums.MacroTravelDirection.SOUTHWEST,
		GameEnums.MacroTravelDirection.SOUTH,
		GameEnums.MacroTravelDirection.SOUTHEAST,
	][octant]


static func _add_fetch_branch(graph: MacroMapGraph, spacing: int) -> void:
	var fetch_branch := _def(
		FETCH_BRANCH_ID,
		"Forgotten Component Site",
		Vector2i(spacing * 2, spacing),
		GameEnums.MacroNodeType.SPECIAL,
		GameEnums.MacroNodeRole.META_BRANCH,
		GameEnums.MacroNodePersistence.PERMANENT_META,
		GameEnums.MacroArmDirection.EAST,
		2,
		"meta_component_site"
	)
	fetch_branch.unlocked = true
	fetch_branch.discovered = false
	fetch_branch.details_revealed = false
	fetch_branch.hidden_until_discovered = true
	graph.add_node(fetch_branch)
	_add_bidirectional(graph, "east_random_2", FETCH_BRANCH_ID,
		GameEnums.MacroTravelDirection.NORTH, GameEnums.MacroTravelDirection.SOUTH,
		"", true, false)


static func _add_bidirectional(
	graph: MacroMapGraph,
	from_id: String,
	to_id: String,
	from_direction: int,
	arrival_direction: int,
	unlock_flag: String = "",
	visible: bool = true,
	revealed: bool = true
) -> void:
	graph.add_edge(from_id, to_id, from_direction, arrival_direction,
		unlock_flag, visible, true, "", revealed)


static func _def(
	id: String,
	display_name: String,
	graph_pos: Vector2i,
	node_type: GameEnums.MacroNodeType,
	role: GameEnums.MacroNodeRole,
	persistence: GameEnums.MacroNodePersistence,
	arm_direction: GameEnums.MacroArmDirection,
	arm_tier: int,
	zone_profile_id: String
) -> MacroNodeData:
	var node := MacroNodeData.new()
	node.id = id
	node.display_name = display_name
	node.graph_pos = graph_pos
	node.type = node_type
	node.role = role
	node.persistence = persistence
	node.arm_direction = arm_direction
	node.arm_tier = arm_tier
	node.zone_profile_id = zone_profile_id
	node.zone_kind = GameEnums.MacroZoneKind.BIOME_RNG
	node.objective_id = ""
	return node
