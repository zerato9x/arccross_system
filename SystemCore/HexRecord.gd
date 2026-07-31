extends Resource
class_name HexRecord

## Typed neutral hex record. SystemCore's persistence representation of a hex.
## WorldCore's MacroHexData converts to/from this at the domain boundary.

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
@export var sleep_anchor: String = "ground"
@export var sleep_gear_instance_id: String = ""
@export var is_poi: bool = false
@export var poi_id: String = ""
@export var poi_name: String = ""
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
var rest_in_progress: bool = false
## Versioned, neutral tactical-site mutations. Combat regenerates a deterministic
## baseline from the hex and overlays only this persisted delta.
var combat_site_state: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"biome": biome,
		"terrain_tile": terrain_tile,
		"flora_layer": flora_layer,
		"rock_layer": rock_layer,
		"water_layer": water_layer,
		"structure_layer": structure_layer,
		"region": region,
		"arm_direction": arm_direction,
		"zone_id": zone_id,
		"biome_pack": biome_pack,
		"structure_pack": structure_pack,
		"landmark_id": landmark_id,
		"impassable": impassable,
		"terrain_sprite_path": terrain_sprite_path,
		"flora_sprite_path": flora_sprite_path,
		"rock_sprite_path": rock_sprite_path,
		"water_sprite_path": water_sprite_path,
		"structure_sprite_path": structure_sprite_path,
		"world_generation_version": world_generation_version,
		"terrain_asset_id": terrain_asset_id,
		"overlay_asset_ids": overlay_asset_ids.duplicate(),
		"composition_role": composition_role,
		"stamp_instance_id": stamp_instance_id,
		"road_mask": road_mask,
		"loot_tier_id": loot_tier_id,
		"search_site_id": search_site_id,
		"trace_records": trace_records.duplicate(true),
		"sleep_anchor": sleep_anchor,
		"sleep_gear_instance_id": sleep_gear_instance_id,
		"is_poi": is_poi,
		"poi_id": poi_id,
		"poi_name": poi_name,
		"is_explored": is_explored,
		"hazard_level": hazard_level,
		"visual_variant_hash": visual_variant_hash,
		"encounter_evaluated": encounter_evaluated,
		"encounter_entity_id": encounter_entity_id,
		"search_count": search_count,
		"searched_targets": searched_targets.duplicate(),
		"camp_item_states": camp_item_states.duplicate(true),
		"camp_rest_count": camp_rest_count,
		"camp_traps": camp_traps.duplicate(true),
		"rest_in_progress": rest_in_progress,
		"combat_site_state": combat_site_state.duplicate(true),
	}

static func from_dict(data: Dictionary) -> HexRecord:
	var record := HexRecord.new()
	record.biome = data.get("biome", GameEnums.GridBiome.PLAINS)
	record.terrain_tile = data.get(
		"terrain_tile",
		_legacy_terrain_for_biome(record.biome)
	)
	record.flora_layer = data.get(
		"flora_layer",
		_legacy_flora_for_biome(record.biome)
	)
	record.rock_layer = data.get(
		"rock_layer",
		_legacy_rock_for_biome(record.biome)
	)
	record.water_layer = data.get(
		"water_layer",
		GameEnums.MacroWaterLayer.NONE
	)
	record.structure_layer = data.get(
		"structure_layer",
		GameEnums.MacroStructureLayer.NONE
	)
	record.region = data.get(
		"region",
		GameEnums.MacroRegion.WASTELAND
	)
	record.arm_direction = data.get(
		"arm_direction",
		GameEnums.MacroArmDirection.NONE
	)
	record.zone_id = data.get("zone_id", "")
	record.biome_pack = data.get("biome_pack", GameEnums.BIOME_PACK_PLAINS)
	record.structure_pack = data.get(
		"structure_pack",
		GameEnums.BIOME_PACK_DEFAULT_ERA8
	)
	record.landmark_id = data.get("landmark_id", "")
	record.impassable = data.get("impassable", false)
	record.terrain_sprite_path = data.get("terrain_sprite_path", "")
	record.flora_sprite_path = data.get("flora_sprite_path", "")
	record.rock_sprite_path = data.get("rock_sprite_path", "")
	record.water_sprite_path = data.get("water_sprite_path", "")
	record.structure_sprite_path = data.get("structure_sprite_path", "")
	record.world_generation_version = int(data.get("world_generation_version", 1))
	record.terrain_asset_id = str(data.get("terrain_asset_id", ""))
	for asset_id in data.get("overlay_asset_ids", []):
		record.overlay_asset_ids.append(str(asset_id))
	record.composition_role = str(data.get("composition_role", "legacy"))
	record.stamp_instance_id = str(data.get("stamp_instance_id", ""))
	record.road_mask = clampi(int(data.get("road_mask", 0)), 0, 63)
	record.loot_tier_id = str(data.get("loot_tier_id", ""))
	record.search_site_id = str(data.get("search_site_id", ""))
	for trace in data.get("trace_records", []):
		if trace is Dictionary:
			record.trace_records.append(trace.duplicate(true))
	record.sleep_anchor = data.get("sleep_anchor", "ground")
	record.sleep_gear_instance_id = data.get("sleep_gear_instance_id", "")
	record.is_poi = data.get("is_poi", false)
	record.poi_id = data.get("poi_id", "")
	record.poi_name = data.get("poi_name", "")
	if record.is_poi and record.structure_layer == GameEnums.MacroStructureLayer.NONE:
		record.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	record.is_explored = data.get("is_explored", false)
	record.hazard_level = clampf(
		float(data.get("hazard_level", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)
	record.visual_variant_hash = int(data.get("visual_variant_hash", 0))
	record.encounter_evaluated = data.get("encounter_evaluated", false)
	record.encounter_entity_id = data.get("encounter_entity_id", "")
	record.search_count = data.get("search_count", 0)
	record.searched_targets = data.get("searched_targets", []).duplicate()
	record.camp_item_states = data.get("camp_item_states", []).duplicate(true)
	record.camp_rest_count = data.get("camp_rest_count", 0)
	record.camp_traps = data.get("camp_traps", []).duplicate(true)
	record.rest_in_progress = data.get("rest_in_progress", false)
	record.combat_site_state = data.get("combat_site_state", {}).duplicate(true)
	return record

static func _legacy_terrain_for_biome(
	biome_value: GameEnums.GridBiome
) -> GameEnums.MacroTerrainTile:
	match biome_value:
		GameEnums.GridBiome.FOREST:
			return GameEnums.MacroTerrainTile.FOREST_SPARSE
		GameEnums.GridBiome.MUD, GameEnums.GridBiome.SWAMP:
			return GameEnums.MacroTerrainTile.MUD_YELLOW
		GameEnums.GridBiome.HILLS, GameEnums.GridBiome.MOUNTAIN:
			return GameEnums.MacroTerrainTile.SNOW_TRANSITION
		_:
			return GameEnums.MacroTerrainTile.PLAINS_GRASS

static func _legacy_flora_for_biome(
	biome_value: GameEnums.GridBiome
) -> GameEnums.MacroFloraLayer:
	if biome_value == GameEnums.GridBiome.FOREST:
		return GameEnums.MacroFloraLayer.TREES
	if biome_value == GameEnums.GridBiome.PLAINS:
		return GameEnums.MacroFloraLayer.NONE
	return GameEnums.MacroFloraLayer.NONE

static func _legacy_rock_for_biome(
	biome_value: GameEnums.GridBiome
) -> GameEnums.MacroRockLayer:
	if biome_value == GameEnums.GridBiome.MOUNTAIN:
		return GameEnums.MacroRockLayer.ROCKS
	if biome_value == GameEnums.GridBiome.HILLS:
		return GameEnums.MacroRockLayer.HILLS
	return GameEnums.MacroRockLayer.NONE
