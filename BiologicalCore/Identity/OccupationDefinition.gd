extends Resource
class_name OccupationDefinition

@export var id: String = ""
@export var display_name: String = ""
@export var summary: String = ""
@export var grants_capability_ids: PackedStringArray = []
@export var rule_tag_ids: PackedStringArray = []
@export_multiline var exile_text: String = ""
@export var starting_items: Array[ItemData] = []
