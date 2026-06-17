extends Resource
class_name MacroHexData

# Pulled straight from our GameEnums[cite: 1]
@export var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS

# POI Variables
@export var is_poi: bool = false
@export var poi_id: String = ""
@export var poi_name: String = ""

# Fog of War / Exploration
@export var is_explored: bool = false
@export_range(0.0, 12.0) var hazard_level: float = 0.0
@export var visual_variant_hash: int = 0
var encounter_evaluated: bool = false
var encounter_entity_id: String = ""
var search_count: int = 0
var camp_item_states: Array = []
var camp_rest_count: int = 0

func to_state() -> HexRecord:
	var record := HexRecord.new()
	record.biome = biome
	record.is_poi = is_poi
	record.poi_id = poi_id
	record.poi_name = poi_name
	record.is_explored = is_explored
	record.hazard_level = hazard_level
	record.visual_variant_hash = visual_variant_hash
	record.encounter_evaluated = encounter_evaluated
	record.encounter_entity_id = encounter_entity_id
	record.search_count = search_count
	record.camp_item_states = camp_item_states.duplicate(true)
	record.camp_rest_count = camp_rest_count
	return record

static func from_state(state) -> MacroHexData:
	var hex := MacroHexData.new()
	var source: HexRecord
	if state is HexRecord:
		source = state
	elif state is Dictionary:
		source = HexRecord.from_dict(state)
	else:
		return hex
	hex.biome = source.biome
	hex.is_poi = source.is_poi
	hex.poi_id = source.poi_id
	hex.poi_name = source.poi_name
	hex.is_explored = source.is_explored
	hex.hazard_level = source.hazard_level
	hex.visual_variant_hash = source.visual_variant_hash
	hex.encounter_evaluated = source.encounter_evaluated
	hex.encounter_entity_id = source.encounter_entity_id
	hex.search_count = source.search_count
	hex.camp_item_states = source.camp_item_states.duplicate(true)
	hex.camp_rest_count = source.camp_rest_count
	return hex
