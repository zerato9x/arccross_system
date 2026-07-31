extends Resource
class_name MacroHexData

@export var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS
@export var terrain_tile: GameEnums.MacroTerrainTile = GameEnums.MacroTerrainTile.PLAINS_GRASS
@export var flora_layer: GameEnums.MacroFloraLayer = GameEnums.MacroFloraLayer.NONE
@export var rock_layer: GameEnums.MacroRockLayer = GameEnums.MacroRockLayer.NONE
@export var water_layer: GameEnums.MacroWaterLayer = GameEnums.MacroWaterLayer.NONE
@export var structure_layer: GameEnums.MacroStructureLayer = GameEnums.MacroStructureLayer.NONE
@export var region: GameEnums.MacroRegion = GameEnums.MacroRegion.WASTELAND
@export var arm_direction: GameEnums.MacroArmDirection = GameEnums.MacroArmDirection.NONE
@export var zone_id: String = ""
@export var biome_pack: String = GameEnums.BIOME_PACK_PLAINS
@export var structure_pack: String = GameEnums.BIOME_PACK_DEFAULT_ERA8
@export var landmark_id: String = ""
@export var impassable: bool = false
@export var terrain_sprite_path: String = ""
@export var flora_sprite_path: String = ""
@export var rock_sprite_path: String = ""
@export var water_sprite_path: String = ""
@export var structure_sprite_path: String = ""
@export var world_generation_version: int = 1
@export var terrain_asset_id: String = ""
@export var overlay_asset_ids: Array[String] = []
@export var composition_role: String = "legacy"
@export var stamp_instance_id: String = ""
@export_range(0, 63) var road_mask: int = 0
@export var loot_tier_id: String = ""
@export var search_site_id: String = ""
@export var trace_records: Array[Dictionary] = []

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
var searched_targets: Array = []
var camp_item_states: Array = []
var camp_rest_count: int = 0
var camp_traps: Array = []
var sleep_anchor: String = "ground"
var sleep_gear_instance_id: String = ""
var rest_in_progress: bool = false
var combat_site_state: Dictionary = {}

func to_state() -> HexRecord:
	var record := HexRecord.new()
	record.biome = biome
	record.terrain_tile = terrain_tile
	record.flora_layer = flora_layer
	record.rock_layer = rock_layer
	record.water_layer = water_layer
	record.structure_layer = structure_layer
	record.region = region
	record.arm_direction = arm_direction
	record.zone_id = zone_id
	record.biome_pack = biome_pack
	record.structure_pack = structure_pack
	record.landmark_id = landmark_id
	record.impassable = impassable
	record.terrain_sprite_path = terrain_sprite_path
	record.flora_sprite_path = flora_sprite_path
	record.rock_sprite_path = rock_sprite_path
	record.water_sprite_path = water_sprite_path
	record.structure_sprite_path = structure_sprite_path
	record.world_generation_version = world_generation_version
	record.terrain_asset_id = terrain_asset_id
	record.overlay_asset_ids = overlay_asset_ids.duplicate()
	record.composition_role = composition_role
	record.stamp_instance_id = stamp_instance_id
	record.road_mask = road_mask
	record.loot_tier_id = loot_tier_id
	record.search_site_id = search_site_id
	record.trace_records = trace_records.duplicate(true)
	record.is_poi = is_poi
	record.poi_id = poi_id
	record.poi_name = poi_name
	record.is_explored = is_explored
	record.hazard_level = hazard_level
	record.visual_variant_hash = visual_variant_hash
	record.encounter_evaluated = encounter_evaluated
	record.encounter_entity_id = encounter_entity_id
	record.search_count = search_count
	record.searched_targets = searched_targets.duplicate()
	record.camp_item_states = camp_item_states.duplicate(true)
	record.camp_rest_count = camp_rest_count
	record.camp_traps = camp_traps.duplicate(true)
	record.sleep_anchor = sleep_anchor
	record.sleep_gear_instance_id = sleep_gear_instance_id
	record.rest_in_progress = rest_in_progress
	record.combat_site_state = combat_site_state.duplicate(true)
	return record

func apply_state(state) -> void:
	var source: HexRecord
	if state is HexRecord:
		source = state
	elif state is Dictionary:
		source = HexRecord.from_dict(state)
	else:
		return
	biome = source.biome
	terrain_tile = source.terrain_tile
	flora_layer = source.flora_layer
	rock_layer = source.rock_layer
	water_layer = source.water_layer
	structure_layer = source.structure_layer
	region = source.region
	arm_direction = source.arm_direction
	zone_id = source.zone_id
	biome_pack = source.biome_pack
	structure_pack = source.structure_pack
	landmark_id = source.landmark_id
	impassable = source.impassable
	terrain_sprite_path = source.terrain_sprite_path
	flora_sprite_path = source.flora_sprite_path
	rock_sprite_path = source.rock_sprite_path
	water_sprite_path = source.water_sprite_path
	structure_sprite_path = source.structure_sprite_path
	world_generation_version = source.world_generation_version
	terrain_asset_id = source.terrain_asset_id
	overlay_asset_ids = source.overlay_asset_ids.duplicate()
	composition_role = source.composition_role
	stamp_instance_id = source.stamp_instance_id
	road_mask = source.road_mask
	loot_tier_id = source.loot_tier_id
	search_site_id = source.search_site_id
	trace_records = source.trace_records.duplicate(true)
	is_poi = source.is_poi
	poi_id = source.poi_id
	poi_name = source.poi_name
	is_explored = source.is_explored
	hazard_level = source.hazard_level
	visual_variant_hash = source.visual_variant_hash
	encounter_evaluated = source.encounter_evaluated
	encounter_entity_id = source.encounter_entity_id
	search_count = source.search_count
	searched_targets = source.searched_targets.duplicate()
	camp_item_states = source.camp_item_states.duplicate(true)
	camp_rest_count = source.camp_rest_count
	camp_traps = source.camp_traps.duplicate(true)
	sleep_anchor = source.sleep_anchor
	sleep_gear_instance_id = source.sleep_gear_instance_id
	rest_in_progress = source.rest_in_progress
	combat_site_state = source.combat_site_state.duplicate(true)


static func from_state(state) -> MacroHexData:
	var hex := MacroHexData.new()
	hex.apply_state(state)
	return hex

func is_passable() -> bool:
	if impassable:
		return false
	if water_layer == GameEnums.MacroWaterLayer.DEEP_WATER:
		return false
	return rock_layer != GameEnums.MacroRockLayer.ROCKS

func has_landmark() -> bool:
	return not landmark_id.is_empty() or (
		is_poi and coords_is_service_hub()
	)

func coords_is_service_hub() -> bool:
	return poi_id in ["alpha_central_hub", "central_core"]

func travel_time_multiplier() -> float:
	if rock_layer == GameEnums.MacroRockLayer.HILLS:
		return 2.0
	if water_layer == GameEnums.MacroWaterLayer.SHALLOW_RIVER:
		return 1.75
	if terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
		return 1.5
	if terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
		return 1.5
	if flora_layer == GameEnums.MacroFloraLayer.TREES and flora_sprite_path.is_empty():
		return 1.2
	return 1.0


func travel_exertion() -> float:
	# Fatigue tracks the same terrain multipliers as travel time.
	return travel_time_multiplier()
