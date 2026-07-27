extends Resource
class_name CampaignGraphDefinition

@export var central_node_id: String = "central_core"
@export var graph_spacing: int = 4
@export var arms: Array[CampaignArmDefinition] = []
@export var start_node_ids: PackedStringArray = []
@export var start_arrival_directions: Dictionary = {}
@export var open_inner_ring: bool = true
@export var central_unlock_milestone: CampaignMilestoneDefinition


func allowed_start_node_ids() -> PackedStringArray:
	return start_node_ids.duplicate()


func arrival_direction_for_start(node_id: String) -> int:
	return int(start_arrival_directions.get(
		node_id,
		GameEnums.MacroTravelDirection.SOUTH
	))


func validate() -> PackedStringArray:
	var failures := PackedStringArray()
	var prefixes: Dictionary = {}
	for arm in arms:
		if arm == null or arm.prefix.is_empty():
			failures.append("Campaign arm has no prefix.")
			continue
		if prefixes.has(arm.prefix):
			failures.append("Duplicate campaign arm: %s" % arm.prefix)
		prefixes[arm.prefix] = true
	for start_id in start_node_ids:
		if not start_arrival_directions.has(start_id):
			failures.append("Start node has no arrival direction: %s" % start_id)
	return failures
