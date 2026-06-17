extends TileMapLayer
class_name HexMapVisualizer

@export var world_generator: HexWorldGenerator
@export var tile_catalog: MacroTileCatalog
@export var overlay_layer: TileMapLayer
@export var flora_layer: TileMapLayer
@export var rock_layer: TileMapLayer
@export var structure_layer: TileMapLayer

const LEGACY_BIOME_TO_SOURCE_ID := {
	GameEnums.GridBiome.PLAINS: 0,
	GameEnums.GridBiome.FOREST: 1,
	GameEnums.GridBiome.HILLS: 2,
	GameEnums.GridBiome.MUD: 3,
	GameEnums.GridBiome.SWAMP: 4,
}

const SINGLE_TILE_COORD := Vector2i(0, 0)
const CATALOG_PATH := "res://Asset/MacroTileCatalog.tres"
const TILESET_PATH := "res://Asset/MacroTileSet.tres"

var rendered_cells: Dictionary = {}
var poi_markers: Dictionary = {}

func _ready() -> void:
	if not world_generator:
		push_error("Visualizer cannot see the Cartographer. Hook it up.")
		return
	_load_generated_assets()

func _load_generated_assets() -> void:
	if tile_catalog == null and ResourceLoader.exists(CATALOG_PATH):
		tile_catalog = load(CATALOG_PATH) as MacroTileCatalog
	if ResourceLoader.exists(TILESET_PATH):
		var generated_tile_set := load(TILESET_PATH) as TileSet
		if generated_tile_set != null:
			tile_set = generated_tile_set
			_assign_tileset_to_layers(generated_tile_set)

func _assign_tileset_to_layers(generated_tile_set: TileSet) -> void:
	for layer in [
		overlay_layer,
		flora_layer,
		rock_layer,
		structure_layer,
	]:
		if layer != null:
			layer.tile_set = generated_tile_set

## Call this to render a "Chunk" of the map around the player
func render_radius(center_coords: Vector2i, radius: int) -> void:
	for q in range(-radius, radius + 1):
		for r in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
			var check_coord := center_coords + Vector2i(q, r)
			_paint_single_hex(check_coord)
	_prune_outside_radius(center_coords, radius + 2)

func _paint_single_hex(coords: Vector2i) -> void:
	var hex_data: MacroHexData = world_generator.get_hex_at(coords)
	
	# Background
	var bg_source_id := _resolve_bg_source_id(hex_data)
	set_cell(coords, bg_source_id, SINGLE_TILE_COORD)

	var target_flora_layer := flora_layer if flora_layer != null else overlay_layer
	var target_rock_layer := rock_layer if rock_layer != null else overlay_layer
	var target_structure_layer := (
		structure_layer if structure_layer != null else overlay_layer
	)
	_paint_optional_layer(
		target_flora_layer,
		coords,
		_resolve_flora_source_id(hex_data)
	)
	_paint_optional_layer(
		target_rock_layer,
		coords,
		_resolve_rock_source_id(hex_data)
	)
	_paint_optional_layer(
		target_structure_layer,
		coords,
		_resolve_structure_source_id(hex_data)
	)
			
	rendered_cells[coords] = true

	if hex_data.is_poi:
		_mark_poi_visually(coords, hex_data.poi_name)

func _resolve_bg_source_id(hex_data: MacroHexData) -> int:
	if tile_catalog != null:
		var catalog_source := tile_catalog.resolve_terrain_id(
			hex_data.terrain_tile,
			hex_data.visual_variant_hash
		)
		if catalog_source >= 0:
			return catalog_source
	return LEGACY_BIOME_TO_SOURCE_ID.get(hex_data.biome, 0)

func _resolve_flora_source_id(hex_data: MacroHexData) -> int:
	if tile_catalog != null:
		return tile_catalog.resolve_flora_id(
			hex_data.flora_layer,
			hex_data.visual_variant_hash
		)
	return -1

func _resolve_rock_source_id(hex_data: MacroHexData) -> int:
	if tile_catalog != null:
		return tile_catalog.resolve_rock_id(
			hex_data.rock_layer,
			hex_data.visual_variant_hash
		)
	return -1

func _resolve_structure_source_id(hex_data: MacroHexData) -> int:
	if tile_catalog != null:
		if hex_data.is_poi:
			# Use specific POI ID if it exists in catalog.
			var id := tile_catalog.resolve_poi_id(
				hex_data.poi_id,
				hex_data.visual_variant_hash
			)
			if id >= 0:
				return id
		var id := tile_catalog.resolve_poi_id(
			_structure_layer_key(hex_data.structure_layer),
			hex_data.visual_variant_hash
		)
		if id >= 0:
			return id
		return tile_catalog.resolve_structure_id(
			hex_data.structure_layer,
			hex_data.visual_variant_hash
		)
	return -1

func _paint_optional_layer(
	layer: TileMapLayer,
	coords: Vector2i,
	source_id: int
) -> void:
	if layer == null:
		return
	if source_id >= 0:
		layer.set_cell(coords, source_id, SINGLE_TILE_COORD)
	else:
		layer.erase_cell(coords)

func _structure_layer_key(
	structure: GameEnums.MacroStructureLayer
) -> String:
	if structure == GameEnums.MacroStructureLayer.REMNANTS:
		return "remnants"
	if structure == GameEnums.MacroStructureLayer.STRUCTURES:
		return "structures"
	return ""

func _mark_poi_visually(coords: Vector2i, poi_name: String) -> void:
	if poi_markers.has(coords):
		poi_markers[coords].text = "[ " + poi_name + " ]"
		return

	var pixel_pos := map_to_local(coords)

	var label := Label.new()
	label.text = "[ " + poi_name + " ]"
	label.position = pixel_pos - Vector2(50, 10)
	add_child(label)
	poi_markers[coords] = label

func _prune_outside_radius(center_coords: Vector2i, radius: int) -> void:
	for coords in rendered_cells.keys().duplicate():
		if _hex_distance(center_coords, coords) <= radius:
			continue
		erase_cell(coords)
		if overlay_layer != null:
			overlay_layer.erase_cell(coords)
		if flora_layer != null:
			flora_layer.erase_cell(coords)
		if rock_layer != null:
			rock_layer.erase_cell(coords)
		if structure_layer != null:
			structure_layer.erase_cell(coords)
		rendered_cells.erase(coords)
		if poi_markers.has(coords):
			poi_markers[coords].queue_free()
			poi_markers.erase(coords)

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))
