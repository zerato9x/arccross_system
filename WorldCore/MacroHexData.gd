extends Resource
class_name MacroHexData

@export var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS
@export var terrain_tile: GameEnums.MacroTerrainTile = GameEnums.MacroTerrainTile.PLAINS_GRASS
@export var flora_layer: GameEnums.MacroFloraLayer = GameEnums.MacroFloraLayer.NONE
@export var rock_layer: GameEnums.MacroRockLayer = GameEnums.MacroRockLayer.NONE
@export var structure_layer: GameEnums.MacroStructureLayer = GameEnums.MacroStructureLayer.NONE
@export var region: GameEnums.MacroRegion = GameEnums.MacroRegion.WASTELAND
@export var arm_direction: GameEnums.MacroArmDirection = GameEnums.MacroArmDirection.NONE
@export var zone_id: String = ""
@export var biome_pack: String = GameEnums.BIOME_PACK_PLAINS
@export var landmark_id: String = ""
@export var impassable: bool = false
@export var terrain_sprite_path: String = ""
@export var flora_sprite_path: String = ""
@export var rock_sprite_path: String = ""
@export var structure_sprite_path: String = ""

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
var camp_traps: Array = []
var sleep_anchor: String = "ground"
var sleep_gear_instance_id: String = ""
var rest_in_progress: bool = false

func to_state() -> HexRecord:
	var record := HexRecord.new()
	record.biome = biome
	record.terrain_tile = terrain_tile
	record.flora_layer = flora_layer
	record.rock_layer = rock_layer
	record.structure_layer = structure_layer
	record.region = region
	record.arm_direction = arm_direction
	record.zone_id = zone_id
	record.biome_pack = biome_pack
	record.landmark_id = landmark_id
	record.impassable = impassable
	record.terrain_sprite_path = terrain_sprite_path
	record.flora_sprite_path = flora_sprite_path
	record.rock_sprite_path = rock_sprite_path
	record.structure_sprite_path = structure_sprite_path
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
	record.camp_traps = camp_traps.duplicate(true)
	record.sleep_anchor = sleep_anchor
	record.sleep_gear_instance_id = sleep_gear_instance_id
	record.rest_in_progress = rest_in_progress
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
	hex.region = source.region
	hex.arm_direction = source.arm_direction
	hex.zone_id = source.zone_id
	hex.biome_pack = source.biome_pack
	hex.landmark_id = source.landmark_id
	hex.impassable = source.impassable
	hex.terrain_sprite_path = source.terrain_sprite_path
	hex.flora_sprite_path = source.flora_sprite_path
	hex.rock_sprite_path = source.rock_sprite_path
	hex.structure_sprite_path = source.structure_sprite_path
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
	hex.camp_traps = source.camp_traps.duplicate(true)
	hex.sleep_anchor = source.sleep_anchor
	hex.sleep_gear_instance_id = source.sleep_gear_instance_id
	hex.rest_in_progress = source.rest_in_progress
	return hex

func is_passable() -> bool:
	if impassable:
		return false
	return rock_layer != GameEnums.MacroRockLayer.ROCKS

func has_landmark() -> bool:
	return not landmark_id.is_empty() or (
		is_poi and coords_is_service_hub()
	)

func coords_is_service_hub() -> bool:
	return poi_id == "alpha_central_hub"

func travel_exertion() -> float:
	if rock_layer == GameEnums.MacroRockLayer.HILLS:
		return 2.5
	if terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		return 2.0
	if terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
		return 2.0
	if flora_layer == GameEnums.MacroFloraLayer.TREES and flora_sprite_path.is_empty():
		return 1.25
	return 1.0
