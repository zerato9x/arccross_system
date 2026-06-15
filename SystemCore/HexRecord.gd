extends Resource
class_name HexRecord

## Typed neutral hex record. SystemCore's persistence representation of a hex.
## WorldCore's MacroHexData converts to/from this at the domain boundary.

@export var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS
@export var is_poi: bool = false
@export var poi_id: String = ""
@export var poi_name: String = ""
@export var is_explored: bool = false
@export_range(0.0, 12.0) var hazard_level: float = 0.0
var encounter_evaluated: bool = false
var encounter_entity_id: String = ""
var search_count: int = 0
var camp_item_states: Array = []
var camp_rest_count: int = 0

func to_dict() -> Dictionary:
	return {
		"biome": biome,
		"is_poi": is_poi,
		"poi_id": poi_id,
		"poi_name": poi_name,
		"is_explored": is_explored,
		"hazard_level": hazard_level,
		"encounter_evaluated": encounter_evaluated,
		"encounter_entity_id": encounter_entity_id,
		"search_count": search_count,
		"camp_item_states": camp_item_states.duplicate(true),
		"camp_rest_count": camp_rest_count,
	}

static func from_dict(data: Dictionary) -> HexRecord:
	var record := HexRecord.new()
	record.biome = data.get("biome", GameEnums.GridBiome.PLAINS)
	record.is_poi = data.get("is_poi", false)
	record.poi_id = data.get("poi_id", "")
	record.poi_name = data.get("poi_name", "")
	record.is_explored = data.get("is_explored", false)
	record.hazard_level = clampf(
		float(data.get("hazard_level", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)
	record.encounter_evaluated = data.get("encounter_evaluated", false)
	record.encounter_entity_id = data.get("encounter_entity_id", "")
	record.search_count = data.get("search_count", 0)
	record.camp_item_states = data.get("camp_item_states", []).duplicate(true)
	record.camp_rest_count = data.get("camp_rest_count", 0)
	return record
