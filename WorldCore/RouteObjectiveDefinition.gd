extends Resource
class_name RouteObjectiveDefinition

@export var objective_id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var active_node_ids: PackedStringArray = []
@export var required_item_ids: PackedStringArray = []
@export var turn_in_poi_id: String = ""
@export var turn_in_fixture_id: String = ""
@export var completion_event_id: String = ""
@export var completion_trigger_ids: PackedStringArray = []
@export var consumes_items: bool = true
@export_multiline var incomplete_text: String = "The physical leads or services required for this route are still unresolved."
@export_multiline var completion_text: String = "The route objective is complete."


func to_descriptor() -> Dictionary:
	return {
		"objective_id": objective_id,
		"display_name": display_name,
		"description": description,
		"active_node_ids": Array(active_node_ids),
		"required_item_ids": Array(required_item_ids),
		"turn_in_poi_id": turn_in_poi_id,
		"turn_in_fixture_id": turn_in_fixture_id,
		"completion_event_id": completion_event_id,
		"completion_trigger_ids": Array(completion_trigger_ids),
		"consumes_items": consumes_items,
		"incomplete_text": incomplete_text,
		"completion_text": completion_text,
	}
