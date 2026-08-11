@tool
extends Node
class_name AuthoredWorldMapBaker

## Bakes painted TileMap layers plus HexMapMarker children into an
## AuthoredWorldMap resource. Each layer stores the exact tile you painted
## so structures, flora, rocks, and props appear exactly as authored.

@export var terrain_layer: TileMapLayer
@export var water_layer: TileMapLayer
@export var flora_layer: TileMapLayer
@export var rock_layer: TileMapLayer
@export var structure_layer: TileMapLayer
@export var props_layer: TileMapLayer
@export var decor_root: Node2D
@export var marker_root: Node
@export var socket_root: Node
@export var tile_catalog: MacroTileCatalog
@export var output_map: Resource
@export_file("*.tres") var output_path: String = (
	"res://WorldCore/Maps/phase2_east_arm.tres"
)
## Legacy authored templates can contain water source IDs that predate the
## generated catalog. Keep the fallback authored as a presentation resource
## value so the bake remains deterministic while those IDs are migrated.
@export_file("*.png") var water_fallback_sprite_path: String = (
	"res://Asset/HexTiles/_BIOMES/biome_plains/water_default/"
	+ "Waterway 1 - Open Water.png"
)
@export var map_id: String = "phase2_east"
@export var display_name: String = "Phase 2 East Arm"
@export var playable_arm: GameEnums.MacroArmDirection = (
	GameEnums.MacroArmDirection.EAST
)
@export var start_coords: Vector2i = Vector2i(3, 0)
@export var core_coords: Vector2i = Vector2i.ZERO

const CATALOG_PATH := "res://Asset/MacroTileCatalog.tres"
const _AuthoredWorldMap := preload("res://WorldCore/AuthoredWorldMap.gd")


func _ready() -> void:
	if tile_catalog == null and ResourceLoader.exists(CATALOG_PATH):
		tile_catalog = load(CATALOG_PATH) as MacroTileCatalog
	if Engine.is_editor_hint():
		_auto_wire_references()


func _auto_wire_references() -> void:
	var editor_root := get_parent()
	if editor_root == null:
		return
	if terrain_layer == null:
		terrain_layer = editor_root.get_node_or_null("TerrainLayer") as TileMapLayer
	if water_layer == null:
		water_layer = editor_root.get_node_or_null("WaterLayer") as TileMapLayer
	if flora_layer == null:
		flora_layer = editor_root.get_node_or_null("FloraLayer") as TileMapLayer
	if rock_layer == null:
		rock_layer = editor_root.get_node_or_null("RockLayer") as TileMapLayer
	if structure_layer == null:
		structure_layer = editor_root.get_node_or_null("StructureLayer") as TileMapLayer
	if props_layer == null:
		props_layer = editor_root.get_node_or_null("PropsLayer") as TileMapLayer
	if decor_root == null:
		decor_root = editor_root.get_node_or_null("Decorations") as Node2D
	if marker_root == null:
		marker_root = editor_root.get_node_or_null("Markers")
	if socket_root == null:
		socket_root = editor_root.get_node_or_null("Sockets")


func _editor_bake_authored_map() -> void:
	if Engine.is_editor_hint():
		bake_to_resource(true)


@export var bake_now: bool = false:
	set(value):
		if not value:
			bake_now = false
			return
		if Engine.is_editor_hint():
			bake_to_resource(true)
		bake_now = false


func bake_to_resource(save_to_disk: bool = true) -> Resource:
	var baked: Resource = _AuthoredWorldMap.new()
	baked.map_id = map_id
	baked.display_name = display_name
	baked.playable_arm = playable_arm
	baked.start_coords = start_coords
	baked.core_coords = core_coords

	var marker_entries := _collect_marker_entries()
	baked.sockets = _collect_sockets()
	var coords_set: Dictionary = {}
	for layer in [
		terrain_layer,
		water_layer,
		flora_layer,
		rock_layer,
		structure_layer,
		props_layer,
	]:
		if layer == null:
			continue
		for coords in layer.get_used_cells():
			coords_set[coords] = true
	for coords in marker_entries.keys():
		coords_set[coords] = true

	var decorations := _collect_decorations()
	for decor in decorations:
		var decor_coords: Variant = decor.get("coords")
		if decor_coords is Vector2i:
			coords_set[decor_coords] = true
	baked.decorations = decorations

	for coords in coords_set.keys():
		var entry := _build_entry(coords, marker_entries.get(coords, {}))
		if not entry.is_empty():
			baked.set_entry(coords, entry)

	baked.rebuild_index()
	output_map = baked
	if save_to_disk and not output_path.is_empty():
		var err := ResourceSaver.save(baked, output_path)
		if err != OK:
			push_error(
				"[AuthoredWorldMapBaker] Failed to save %s (error %d)."
				% [output_path, err]
			)
	return baked


func _collect_marker_entries() -> Dictionary:
	var entries: Dictionary = {}
	if marker_root == null:
		return entries
	for child in marker_root.get_children():
		if child is HexMapMarker:
			var marker := child as HexMapMarker
			entries[marker.hex_coords] = marker.to_entry()
	return entries


func _collect_decorations() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if decor_root == null:
		return records
	for child in decor_root.get_children():
		if child is HexDecorProp:
			var prop := child as HexDecorProp
			if prop.sprite_path.is_empty():
				continue
			records.append(prop.to_record())
	return records


func _collect_sockets() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if socket_root == null:
		return records
	for child in socket_root.get_children():
		if child is HexMapSocket:
			records.append((child as HexMapSocket).to_record())
	return records


func _build_entry(coords: Vector2i, marker_entry: Dictionary) -> Dictionary:
	var entry := marker_entry.duplicate(true)
	entry["coords"] = coords

	_apply_layer_tile(entry, terrain_layer, coords, "terrain")
	_apply_layer_tile(entry, water_layer, coords, "water")
	_apply_layer_tile(entry, flora_layer, coords, "flora")
	_apply_layer_tile(entry, rock_layer, coords, "rock")
	_apply_layer_tile(entry, structure_layer, coords, "structure")
	_apply_layer_tile(entry, props_layer, coords, "props")

	_apply_defaults(entry)
	return entry


func _apply_layer_tile(
	entry: Dictionary,
	layer: TileMapLayer,
	coords: Vector2i,
	layer_kind: String
) -> void:
	if layer == null or layer.get_cell_source_id(coords) < 0:
		return
	var source_id := layer.get_cell_source_id(coords)
	var asset_path := _path_for_source_id(source_id)
	if asset_path.is_empty() and layer_kind == "water":
		asset_path = water_fallback_sprite_path
	if asset_path.is_empty():
		return

	match layer_kind:
		"terrain":
			entry["terrain_sprite_path"] = asset_path
			entry["terrain_tile"] = _terrain_for_path(asset_path)
			entry["biome_pack"] = _pack_for_path(asset_path)
		"water":
			entry["water_sprite_path"] = asset_path
			if int(entry.get("water_layer", GameEnums.MacroWaterLayer.NONE)) == GameEnums.MacroWaterLayer.NONE:
				entry["water_layer"] = GameEnums.MacroWaterLayer.SHALLOW_RIVER
		"flora":
			entry["flora_sprite_path"] = asset_path
			entry["flora_layer"] = _flora_for_path(asset_path)
		"rock":
			entry["rock_sprite_path"] = asset_path
			entry["rock_layer"] = _rock_for_path(asset_path)
			if entry["rock_layer"] == GameEnums.MacroRockLayer.ROCKS:
				entry["impassable"] = true
		"structure", "props":
			if entry.get("structure_sprite_path", "").is_empty():
				entry["structure_sprite_path"] = asset_path
			if _is_gameplay_structure_path(asset_path):
				entry["structure_layer"] = _structure_for_path(asset_path)


func _apply_defaults(entry: Dictionary) -> void:
	if not entry.has("terrain_tile"):
		entry["terrain_tile"] = GameEnums.MacroTerrainTile.PLAINS_GRASS
	if not entry.has("flora_layer"):
		entry["flora_layer"] = GameEnums.MacroFloraLayer.NONE
	if not entry.has("rock_layer"):
		entry["rock_layer"] = GameEnums.MacroRockLayer.NONE
	if not entry.has("water_layer"):
		entry["water_layer"] = GameEnums.MacroWaterLayer.NONE
	if not entry.has("structure_layer"):
		entry["structure_layer"] = GameEnums.MacroStructureLayer.NONE
	if not entry.has("biome"):
		entry["biome"] = GameEnums.GridBiome.PLAINS
	if not entry.has("biome_pack"):
		entry["biome_pack"] = GameEnums.BIOME_PACK_PLAINS
	if not entry.has("region"):
		entry["region"] = GameEnums.MacroRegion.WASTELAND
	if not entry.has("arm_direction"):
		entry["arm_direction"] = GameEnums.MacroArmDirection.NONE
	if not entry.has("zone_id"):
		entry["zone_id"] = ""
	if not entry.has("hazard_level"):
		entry["hazard_level"] = 0.0
	if not entry.has("impassable"):
		entry["impassable"] = (
			int(entry.get("rock_layer", GameEnums.MacroRockLayer.NONE))
			== GameEnums.MacroRockLayer.ROCKS
		)


func _path_for_source_id(source_id: int) -> String:
	if tile_catalog == null:
		return ""
	for path in tile_catalog.path_to_source_id.keys():
		if int(tile_catalog.path_to_source_id[path]) == source_id:
			return str(path)
	return ""


func _pack_for_path(path: String) -> String:
	var lowered := path.to_lower()
	if lowered.find("biome_centralcore") >= 0:
		return GameEnums.BIOME_PACK_CENTRALCORE
	if lowered.find("biome_north") >= 0 or lowered.find("snow_tiles") >= 0:
		return GameEnums.BIOME_PACK_NORTH
	if lowered.find("default_era8") >= 0:
		return GameEnums.BIOME_PACK_DEFAULT_ERA8
	return GameEnums.BIOME_PACK_PLAINS


func _terrain_for_path(path: String) -> GameEnums.MacroTerrainTile:
	var lowered := path.to_lower()
	if lowered.find("concrete") >= 0:
		return GameEnums.MacroTerrainTile.HUB_CONCRETE
	if lowered.find("forest") >= 0 or lowered.find("sparse green") >= 0:
		return GameEnums.MacroTerrainTile.FOREST_SPARSE
	if lowered.find("mud") >= 0 or lowered.find("yellow") >= 0:
		return GameEnums.MacroTerrainTile.MUD_YELLOW
	if lowered.find("snow") >= 0:
		return GameEnums.MacroTerrainTile.SNOW_TRANSITION
	return GameEnums.MacroTerrainTile.PLAINS_GRASS


func _flora_for_path(path: String) -> GameEnums.MacroFloraLayer:
	var lowered := path.to_lower()
	if (
		lowered.find("/flora/") >= 0
		or lowered.find("temperate trees") >= 0
		or lowered.find("trees 2x2") >= 0
	):
		if lowered.find("tree") >= 0:
			return GameEnums.MacroFloraLayer.TREES
	if lowered.find("shrub") >= 0:
		return GameEnums.MacroFloraLayer.SHRUBS
	return GameEnums.MacroFloraLayer.NONE


func _rock_for_path(path: String) -> GameEnums.MacroRockLayer:
	var lowered := path.to_lower()
	if lowered.find("rocky hill") >= 0 or lowered.find("/hills") >= 0:
		return GameEnums.MacroRockLayer.HILLS
	if (
		lowered.find("rock") >= 0
		or lowered.find("mountain") >= 0
		or lowered.find("earth patch") >= 0
	):
		return GameEnums.MacroRockLayer.ROCKS
	return GameEnums.MacroRockLayer.NONE


func _structure_for_path(path: String) -> GameEnums.MacroStructureLayer:
	var lowered := path.to_lower()
	if lowered.find("remnant") >= 0 or lowered.find("wreck") >= 0 or lowered.find("crater") >= 0:
		return GameEnums.MacroStructureLayer.REMNANTS
	if _is_gameplay_structure_path(path):
		return GameEnums.MacroStructureLayer.STRUCTURES
	return GameEnums.MacroStructureLayer.NONE


func _is_gameplay_structure_path(path: String) -> bool:
	var lowered := path.to_lower()
	if lowered.find("/structures/") >= 0:
		return true
	if (
		lowered.find("homestead") >= 0
		or lowered.find("warehouse") >= 0
		or lowered.find("prefab building") >= 0
		or lowered.find("silo") >= 0
	):
		return true
	return false
