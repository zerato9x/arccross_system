extends Resource
class_name MacroNodeData

## One campaign-map node. Local gameplay lives in a bounded 12x12 hex zone
## generated (or authored) when the player enters this node.

@export var id: String = ""
@export var display_name: String = ""
## UI layout only — not local hex coordinates.
@export var graph_pos: Vector2i = Vector2i.ZERO
@export var type: GameEnums.MacroNodeType = GameEnums.MacroNodeType.STANDARD
@export var zone_kind: GameEnums.MacroZoneKind = GameEnums.MacroZoneKind.BIOME_RNG
@export var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS
@export var neighbors: Array[String] = []
@export var discovered: bool = false
@export var unlocked: bool = false
@export var completed: bool = false
@export var objective_id: String = "exit"
## Unique-event nodes: MacroEventResolver event id.
@export var event_id: String = ""
## Rule dicts evaluated by MacroProgressController.evaluate_unlocks.
@export var unlock_rules: Array = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"graph_pos": graph_pos,
		"type": int(type),
		"zone_kind": int(zone_kind),
		"biome": int(biome),
		"neighbors": neighbors.duplicate(),
		"discovered": discovered,
		"unlocked": unlocked,
		"completed": completed,
		"objective_id": objective_id,
		"event_id": event_id,
		"unlock_rules": unlock_rules.duplicate(true),
	}


static func from_dict(data: Dictionary) -> MacroNodeData:
	var node := MacroNodeData.new()
	node.id = str(data.get("id", ""))
	node.display_name = str(data.get("display_name", node.id))
	node.graph_pos = data.get("graph_pos", Vector2i.ZERO)
	node.type = int(data.get("type", GameEnums.MacroNodeType.STANDARD)) as GameEnums.MacroNodeType
	node.zone_kind = int(data.get("zone_kind", GameEnums.MacroZoneKind.BIOME_RNG)) as GameEnums.MacroZoneKind
	node.biome = int(data.get("biome", GameEnums.GridBiome.PLAINS)) as GameEnums.GridBiome
	node.neighbors.clear()
	for neighbor_id in data.get("neighbors", []):
		node.neighbors.append(str(neighbor_id))
	node.discovered = bool(data.get("discovered", false))
	node.unlocked = bool(data.get("unlocked", false))
	node.completed = bool(data.get("completed", false))
	node.objective_id = str(data.get("objective_id", "exit"))
	node.event_id = str(data.get("event_id", ""))
	node.unlock_rules = data.get("unlock_rules", []).duplicate(true)
	return node
