extends Resource
class_name MacroHexData

@export var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS
@export var terrain_tile: GameEnums.MacroTerrainTile = GameEnums.MacroTerrainTile.PLAINS_GRASS
@export var flora_layer: GameEnums.MacroFloraLayer = GameEnums.MacroFloraLayer.SHRUBS
@export var rock_layer: GameEnums.MacroRockLayer = GameEnums.MacroRockLayer.NONE
@export var structure_layer: GameEnums.MacroStructureLayer = GameEnums.MacroStructureLayer.NONE

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
	record.terrain_tile = terrain_tile
	record.flora_layer = flora_layer
	record.rock_layer = rock_layer
	record.structure_layer = structure_layer
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
	hex.terrain_tile = source.terrain_tile
	hex.flora_layer = source.flora_layer
	hex.rock_layer = source.rock_layer
	hex.structure_layer = source.structure_layer
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

func is_passable() -> bool:
	return rock_layer != GameEnums.MacroRockLayer.ROCKS

func travel_exertion() -> float:
	if rock_layer == GameEnums.MacroRockLayer.HILLS:
		return 2.5
	if terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		return 2.0
	if terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
		return 2.0
	if flora_layer == GameEnums.MacroFloraLayer.TREES:
		return 1.25
	return 1.0
