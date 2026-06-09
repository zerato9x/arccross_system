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
@export var hazard_level: float = 0.0 # High values equal intense Red Mist zones
var encounter_evaluated: bool = false
var encounter_entity_id: String = ""
var search_count: int = 0
var camp_item_states: Array = []
var camp_rest_count: int = 0

func to_state() -> Dictionary:
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

static func from_state(state: Dictionary) -> MacroHexData:
	var hex := MacroHexData.new()
	hex.biome = state.get("biome", GameEnums.GridBiome.PLAINS)
	hex.is_poi = state.get("is_poi", false)
	hex.poi_id = state.get("poi_id", "")
	hex.poi_name = state.get("poi_name", "")
	hex.is_explored = state.get("is_explored", false)
	hex.hazard_level = state.get("hazard_level", 0.0)
	hex.encounter_evaluated = state.get("encounter_evaluated", false)
	hex.encounter_entity_id = state.get("encounter_entity_id", "")
	hex.search_count = state.get("search_count", 0)
	hex.camp_item_states = state.get("camp_item_states", []).duplicate(true)
	hex.camp_rest_count = state.get("camp_rest_count", 0)
	return hex
