extends Resource
class_name KnowledgeEntryDefinition

## Immutable, mod-friendly lore and discovery definition. Effects are stable
## trigger IDs interpreted by WorldCore; this resource never imports it.

@export_group("Identity")
@export var id: String = ""
@export var title: String = ""
@export var region_id: String = ""
@export_range(0, 12) var era: int = 9
@export var tags: PackedStringArray = []

@export_group("Player-facing Copy")
@export_multiline var summary: String = ""
@export_multiline var body: String = ""

@export_group("Decode Contract")
## Extensible neutral requirements. Supported keys initially include
## any_capabilities, any_item_tags, and all_knowledge_ids.
@export var decode_requirements: Dictionary = {}
@export var discovery_trigger_ids: PackedStringArray = []


func to_descriptor() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"region_id": region_id,
		"era": era,
		"tags": Array(tags),
		"summary": summary,
		"body": body,
		"decode_requirements": decode_requirements.duplicate(true),
		"discovery_trigger_ids": Array(discovery_trigger_ids),
	}
