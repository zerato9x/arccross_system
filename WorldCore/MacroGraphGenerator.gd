extends RefCounted
class_name MacroGraphGenerator

## Builds the first-loop campaign graph: Hub → 3 plains RNG → unique hex-event.
## Strictly linear north path (one outgoing edge per non-end node).

const HUB_ID := "hub"
const PLAINS_1 := "plains_rng_1"
const PLAINS_2 := "plains_rng_2"
const PLAINS_3 := "plains_rng_3"
const EVENT_END := "unique_hex_event_end"

const NORTH_PATH := [HUB_ID, PLAINS_1, PLAINS_2, PLAINS_3, EVENT_END]


static func generate_north_path(seed_value: String) -> MacroMapGraph:
	var graph := MacroMapGraph.new()
	graph.seed_value = seed_value
	graph.hub_id = HUB_ID

	var defs := [
		_def(HUB_ID, "Alpha Hub", Vector2i(0, 0), GameEnums.MacroNodeType.HUB,
			GameEnums.MacroZoneKind.BIOME_RNG, "exit", ""),
		_def(PLAINS_1, "North Plains I", Vector2i(0, 1), GameEnums.MacroNodeType.STANDARD,
			GameEnums.MacroZoneKind.BIOME_RNG, "exit", ""),
		_def(PLAINS_2, "North Plains II", Vector2i(0, 2), GameEnums.MacroNodeType.STANDARD,
			GameEnums.MacroZoneKind.BIOME_RNG, "exit", ""),
		_def(PLAINS_3, "North Plains III", Vector2i(0, 3), GameEnums.MacroNodeType.ELITE,
			GameEnums.MacroZoneKind.BIOME_RNG, "exit", ""),
		_def(EVENT_END, "Locked Treatment Outpost", Vector2i(0, 4), GameEnums.MacroNodeType.SPECIAL,
			GameEnums.MacroZoneKind.UNIQUE_EVENT, "event",
			MacroEventResolver.EVENT_LOCKED_TREATMENT_ROOM),
	]

	for i in defs.size():
		var node: MacroNodeData = defs[i]
		node.biome = GameEnums.GridBiome.PLAINS
		# Hub starts unlocked + discovered; the rest unlock by objective completion.
		if node.id == HUB_ID:
			node.unlocked = true
			node.discovered = true
		else:
			node.unlocked = false
			node.discovered = false
		graph.add_node(node)

	for i in range(NORTH_PATH.size() - 1):
		graph.add_edge(NORTH_PATH[i], NORTH_PATH[i + 1], false)

	return graph


static func _def(
	id: String,
	display_name: String,
	graph_pos: Vector2i,
	node_type: GameEnums.MacroNodeType,
	zone_kind: GameEnums.MacroZoneKind,
	objective_id: String,
	event_id: String
) -> MacroNodeData:
	var node := MacroNodeData.new()
	node.id = id
	node.display_name = display_name
	node.graph_pos = graph_pos
	node.type = node_type
	node.zone_kind = zone_kind
	node.objective_id = objective_id
	node.event_id = event_id
	return node
