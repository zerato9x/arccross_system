extends RefCounted
class_name MacroGraphGenerator

## Builds the first directional campaign web. Stable slot IDs survive seed
## changes; only SEEDED_RANDOM zone contents are regenerated per run.

const CENTRAL_ID := "central_core"
const HUB_ID := CENTRAL_ID # Compatibility handle for older call sites.
const FETCH_BRANCH_ID := "east_component_site"
const META_FETCH_EVENT_ID := "meta_fetch_north_gateway"
const FETCH_ITEM_ID := "arc_core_component_north"
const NORTH_GATEWAY_FLAG := "gateway_north_unsealed"

const ARM_PREFIXES := ["north", "east", "south", "west"]


static func generate_web(seed_value: String, meta_flags: Dictionary = {}) -> MacroMapGraph:
	var graph := MacroMapGraph.new()
	graph.seed_value = seed_value
	graph.hub_id = CENTRAL_ID

	var central := _def(
		CENTRAL_ID,
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

	var arm_defs := [
		{
			"prefix": "north", "label": "North", "axis": Vector2i(0, 1),
			"arm": GameEnums.MacroArmDirection.NORTH,
			"out": GameEnums.MacroTravelDirection.NORTH,
			"in": GameEnums.MacroTravelDirection.SOUTH,
		},
		{
			"prefix": "east", "label": "East", "axis": Vector2i(1, 0),
			"arm": GameEnums.MacroArmDirection.EAST,
			"out": GameEnums.MacroTravelDirection.EAST,
			"in": GameEnums.MacroTravelDirection.WEST,
		},
		{
			"prefix": "south", "label": "South", "axis": Vector2i(0, -1),
			"arm": GameEnums.MacroArmDirection.SOUTH,
			"out": GameEnums.MacroTravelDirection.SOUTH,
			"in": GameEnums.MacroTravelDirection.NORTH,
		},
		{
			"prefix": "west", "label": "West", "axis": Vector2i(-1, 0),
			"arm": GameEnums.MacroArmDirection.WEST,
			"out": GameEnums.MacroTravelDirection.WEST,
			"in": GameEnums.MacroTravelDirection.EAST,
		},
	]

	for arm_def in arm_defs:
		_build_arm(graph, arm_def, meta_flags)

	# The four nearest random nodes form a traversable inner ring.
	_add_bidirectional(graph, "north_random_1", "east_random_1",
		GameEnums.MacroTravelDirection.SOUTHEAST, GameEnums.MacroTravelDirection.NORTHWEST)
	_add_bidirectional(graph, "east_random_1", "south_random_1",
		GameEnums.MacroTravelDirection.SOUTHWEST, GameEnums.MacroTravelDirection.NORTHEAST)
	_add_bidirectional(graph, "south_random_1", "west_random_1",
		GameEnums.MacroTravelDirection.NORTHWEST, GameEnums.MacroTravelDirection.SOUTHEAST)
	_add_bidirectional(graph, "west_random_1", "north_random_1",
		GameEnums.MacroTravelDirection.NORTHEAST, GameEnums.MacroTravelDirection.SOUTHWEST)

	var fetch_branch := _def(
		FETCH_BRANCH_ID,
		"Forgotten Component Site",
		Vector2i(2, 1),
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
	graph.add_node(fetch_branch)
	_add_bidirectional(
		graph,
		"east_random_2",
		FETCH_BRANCH_ID,
		GameEnums.MacroTravelDirection.NORTH,
		GameEnums.MacroTravelDirection.SOUTH,
		"",
		false
	)
	return graph


static func generate_north_path(seed_value: String) -> MacroMapGraph:
	## Compatibility entry point now returns the complete web.
	return generate_web(seed_value)


static func _build_arm(
	graph: MacroMapGraph,
	arm_def: Dictionary,
	meta_flags: Dictionary
) -> void:
	var prefix := str(arm_def["prefix"])
	var label := str(arm_def["label"])
	var axis: Vector2i = arm_def["axis"]
	var arm := int(arm_def["arm"])
	var outward := int(arm_def["out"])
	var inward := int(arm_def["in"])
	var previous_id := CENTRAL_ID

	for tier in range(1, 4):
		var node_id := "%s_random_%d" % [prefix, tier]
		var node := _def(
			node_id,
			"%s Route %d" % [label, tier],
			axis * tier,
			GameEnums.MacroNodeType.STANDARD,
			GameEnums.MacroNodeRole.RANDOM_ZONE,
			GameEnums.MacroNodePersistence.SEEDED_RANDOM,
			arm,
			tier,
			"%s_tier_%d" % [prefix, tier]
		)
		node.unlocked = true
		node.discovered = false
		node.details_revealed = false
		graph.add_node(node)
		_add_bidirectional(graph, previous_id, node_id, outward, inward)
		previous_id = node_id

	var gateway_id := "%s_gateway" % prefix
	var gateway_flag := "gateway_%s_unsealed" % prefix
	var gateway_open := bool(meta_flags.get(gateway_flag, false))
	var gateway := _def(
		gateway_id,
		"%s Gateway" % label,
		axis * 4,
		GameEnums.MacroNodeType.LOCKED,
		GameEnums.MacroNodeRole.GATEWAY,
		GameEnums.MacroNodePersistence.PERMANENT_META,
		arm,
		4,
		"%s_gateway" % prefix
	)
	gateway.unlocked = gateway_open
	gateway.discovered = true
	gateway.details_revealed = true
	graph.add_node(gateway)
	_add_bidirectional(
		graph,
		previous_id,
		gateway_id,
		outward,
		inward,
		gateway_flag
	)

	var core_id := "%s_core" % prefix
	var core := _def(
		core_id,
		"%s Arm Core" % label,
		axis * 5,
		GameEnums.MacroNodeType.SPECIAL,
		GameEnums.MacroNodeRole.ARM_CORE,
		GameEnums.MacroNodePersistence.PERMANENT_META,
		arm,
		5,
		"%s_arm_core" % prefix
	)
	core.unlocked = gateway_open
	core.discovered = true
	core.details_revealed = true
	graph.add_node(core)
	_add_bidirectional(
		graph,
		gateway_id,
		core_id,
		outward,
		inward,
		gateway_flag
	)


static func _add_bidirectional(
	graph: MacroMapGraph,
	from_id: String,
	to_id: String,
	from_direction: int,
	arrival_direction: int,
	unlock_flag: String = "",
	visible: bool = true
) -> void:
	graph.add_edge(
		from_id,
		to_id,
		from_direction,
		arrival_direction,
		unlock_flag,
		visible,
		true
	)


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
