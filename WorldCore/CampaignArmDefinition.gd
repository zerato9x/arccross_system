extends Resource
class_name CampaignArmDefinition

@export var prefix: String = ""
@export var display_name: String = ""
@export var axis: Vector2i = Vector2i.ZERO
@export var arm_direction: int = GameEnums.MacroArmDirection.NONE
@export var outward_direction: int = GameEnums.MacroTravelDirection.NONE
@export var inward_direction: int = GameEnums.MacroTravelDirection.NONE
@export_range(0, 3) var initial_open_depth: int = 1
@export var author_interior_clusters: bool = false
@export_range(0, 20) var route_2_min_nodes: int = 0
@export_range(0, 20) var route_2_max_nodes: int = 0
@export_range(0, 20) var route_2_min_hidden: int = 0
@export_range(0, 20) var route_2_max_hidden: int = 0
@export_range(0, 20) var route_3_min_nodes: int = 0
@export_range(0, 20) var route_3_max_nodes: int = 0
@export_range(0, 20) var route_3_min_hidden: int = 0
@export_range(0, 20) var route_3_max_hidden: int = 0


func node_count_range(tier: int) -> Vector2i:
	return (
		Vector2i(route_2_min_nodes, route_2_max_nodes)
		if tier == 2
		else Vector2i(route_3_min_nodes, route_3_max_nodes)
	)


func hidden_count_range(tier: int) -> Vector2i:
	return (
		Vector2i(route_2_min_hidden, route_2_max_hidden)
		if tier == 2
		else Vector2i(route_3_min_hidden, route_3_max_hidden)
	)
