extends TileMapLayer
class_name HexMapVisualizer

signal fog_applied

enum FogState {
	UNKNOWN,
	EXPLORED,
	VISIBLE,
}

@export var world_generator: HexWorldGenerator
@export var tile_catalog: MacroTileCatalog
@export var overlay_layer: TileMapLayer
@export var flora_layer: TileMapLayer
@export var rock_layer: TileMapLayer
@export var structure_layer: TileMapLayer
@export var shrub_layer: Node2D

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

## Fog uses black + transparency only (no map chroma tint).
const FOG_VISIBLE_COLOR := Color(0, 0, 0, 0)
const FOG_EXPLORED_COLOR := Color(0, 0, 0, 0.52)
const FOG_UNKNOWN_COLOR := Color(0, 0, 0, 0.94)
const FOG_HEX_OVERSIZE := 1.05
const DECOR_LAYER_Z := {
	0: 1,
	1: 2,
	2: 3,
	3: 4,
}

var rendered_cells: Dictionary = {}
var poi_markers: Dictionary = {}
var shrub_sprites: Dictionary = {}
var decor_sprites: Dictionary = {} # String key -> Sprite2D
var fog_overlays: Dictionary = {} # Vector2i -> Polygon2D
var fog_states: Dictionary = {} # Vector2i -> FogState
var selection_marker: Polygon2D
var fog_root: Node2D
var _zone_mode := false
var _cached_fog_polygon: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	if not world_generator:
		push_error("Visualizer cannot see the Cartographer. Hook it up.")
		return
	_load_generated_assets()
	_ensure_selection_marker()
	_ensure_fog_root()


## Pointy-top hex vertices from TileSet cell size, oversized so tiles never peek.
func _hex_fog_polygon() -> PackedVector2Array:
	if not _cached_fog_polygon.is_empty():
		return _cached_fog_polygon
	var tile_px := Vector2(512.0, 512.0)
	if tile_set != null:
		tile_px = Vector2(tile_set.tile_size)
	var half_w := tile_px.x * 0.5 * FOG_HEX_OVERSIZE
	var half_h := tile_px.y * 0.5 * FOG_HEX_OVERSIZE
	var quarter_h := half_h * 0.5
	_cached_fog_polygon = PackedVector2Array([
		Vector2(0.0, -half_h),
		Vector2(half_w, -quarter_h),
		Vector2(half_w, quarter_h),
		Vector2(0.0, half_h),
		Vector2(-half_w, quarter_h),
		Vector2(-half_w, -quarter_h),
	])
	return _cached_fog_polygon


func _invalidate_fog_polygon_cache() -> void:
	_cached_fog_polygon = PackedVector2Array()


func _rebuild_fog_overlay_geometry() -> void:
	_invalidate_fog_polygon_cache()
	var poly := _hex_fog_polygon()
	for coords in fog_overlays.keys():
		var fog_poly := fog_overlays[coords] as Polygon2D
		if is_instance_valid(fog_poly):
			fog_poly.polygon = poly
			fog_poly.position = map_to_local(coords)
	if selection_marker != null and is_instance_valid(selection_marker):
		selection_marker.polygon = poly


func _load_generated_assets() -> void:
	if tile_catalog == null and ResourceLoader.exists(CATALOG_PATH):
		tile_catalog = load(CATALOG_PATH) as MacroTileCatalog
	if ResourceLoader.exists(TILESET_PATH):
		var generated_tile_set := load(TILESET_PATH) as TileSet
		if generated_tile_set != null:
			tile_set = generated_tile_set
			_assign_tileset_to_layers(generated_tile_set)
			_rebuild_fog_overlay_geometry()

func _assign_tileset_to_layers(generated_tile_set: TileSet) -> void:
	for layer in [
		overlay_layer,
		flora_layer,
		rock_layer,
		structure_layer,
	]:
		if layer != null:
			layer.tile_set = generated_tile_set


func _ensure_fog_root() -> void:
	if fog_root != null:
		return
	fog_root = Node2D.new()
	fog_root.name = "FogOverlays"
	# Above terrain/flora/structure, below player tokens (typically z >= 5).
	fog_root.z_index = 3
	add_child(fog_root)


## Paint every hex currently in the world generator cache (full 12×12 zone).
func render_zone() -> void:
	_zone_mode = true
	if world_generator == null:
		return
	_rebuild_fog_overlay_geometry()
	var cache: Dictionary = world_generator.world_hex_cache
	if cache.is_empty():
		return
	for coords in cache.keys():
		_paint_single_hex(coords)
	# Drop anything that left the active zone.
	for coords in rendered_cells.keys().duplicate():
		if cache.has(coords):
			continue
		_erase_hex_visual(coords)


## Legacy chunked render for non-zone / infinite wedge paths.
func render_radius(center_coords: Vector2i, radius: int) -> void:
	_zone_mode = false
	for q in range(-radius, radius + 1):
		for r in range(max(-radius, -q - radius), min(radius, -q + radius) + 1):
			var check_coord := center_coords + Vector2i(q, r)
			_paint_single_hex(check_coord)
	_prune_outside_radius(center_coords, radius + 2)


## Apply explored / visible fog. visible_hexes: Dictionary Vector2i -> true.
## Explored is read from MacroHexData.is_explored on each rendered cell.
func apply_fog(visible_hexes: Dictionary) -> void:
	_ensure_fog_root()
	for coords in rendered_cells.keys():
		var state := FogState.UNKNOWN
		if visible_hexes.has(coords):
			state = FogState.VISIBLE
		elif _is_explored(coords):
			state = FogState.EXPLORED
		fog_states[coords] = state
		_apply_fog_to_hex(coords, state)
	fog_applied.emit()


func get_fog_state(coords: Vector2i) -> int:
	return int(fog_states.get(coords, FogState.UNKNOWN))


func show_selection(coords: Vector2i) -> void:
	_ensure_selection_marker()
	selection_marker.position = map_to_local(coords)
	selection_marker.visible = true
	selection_marker.z_index = 5

func _ensure_selection_marker() -> void:
	if selection_marker != null:
		return
	selection_marker = Polygon2D.new()
	selection_marker.name = "HexSelectionMarker"
	selection_marker.polygon = _hex_fog_polygon()
	selection_marker.color = Color(0.98, 0.86, 0.28, 0.22)
	selection_marker.z_index = 5
	selection_marker.visible = false
	add_child(selection_marker)

func _paint_single_hex(coords: Vector2i) -> void:
	var hex_data: MacroHexData = world_generator.get_hex_at(coords)
	var fog_state: int = int(fog_states.get(coords, FogState.UNKNOWN))
	var is_unknown := fog_state == FogState.UNKNOWN and _zone_mode

	# Background always paints so the zone is not an empty void.
	var bg_source_id := _resolve_bg_source_id(hex_data)
	set_cell(coords, bg_source_id, SINGLE_TILE_COORD)

	var target_flora_layer := flora_layer if flora_layer != null else overlay_layer
	var target_rock_layer := rock_layer if rock_layer != null else overlay_layer
	var target_structure_layer := (
		structure_layer if structure_layer != null else overlay_layer
	)

	if is_unknown:
		_paint_optional_layer(target_flora_layer, coords, -1)
		_paint_optional_layer(target_rock_layer, coords, -1)
		_paint_optional_layer(target_structure_layer, coords, -1)
		_clear_shrub(coords)
		_clear_decorations(coords)
		_hide_poi_marker(coords)
	else:
		if hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS and hex_data.flora_sprite_path.is_empty():
			_paint_optional_layer(target_flora_layer, coords, -1)
			_paint_shrub(coords, hex_data)
		else:
			_clear_shrub(coords)
			var flora_source := _resolve_flora_source_id(hex_data)
			_paint_optional_layer(target_flora_layer, coords, flora_source)
		var rock_source := _resolve_rock_source_id(hex_data)
		_paint_optional_layer(target_rock_layer, coords, rock_source)
		var structure_source := _resolve_structure_source_id(hex_data)
		_paint_optional_layer(target_structure_layer, coords, structure_source)
		_paint_decorations(coords)
		if hex_data.is_poi or not hex_data.landmark_id.is_empty():
			_mark_poi_visually(
				coords,
				hex_data.poi_name if hex_data.is_poi else hex_data.landmark_id
			)
		else:
			_hide_poi_marker(coords)

	rendered_cells[coords] = true
	_ensure_fog_overlay(coords)
	_apply_fog_to_hex(coords, fog_state)

func _resolve_bg_source_id(hex_data: MacroHexData) -> int:
	var authored := _resolve_authored_path(hex_data.terrain_sprite_path, hex_data)
	if authored >= 0:
		return authored
	if tile_catalog != null:
		var catalog_source := tile_catalog.resolve_terrain_id(
			hex_data.terrain_tile,
			hex_data.visual_variant_hash,
			hex_data.biome_pack
		)
		if catalog_source >= 0:
			return catalog_source
	return LEGACY_BIOME_TO_SOURCE_ID.get(hex_data.biome, 0)

func _resolve_flora_source_id(hex_data: MacroHexData) -> int:
	var authored := _resolve_authored_path(hex_data.flora_sprite_path, hex_data)
	if authored >= 0:
		return authored
	if tile_catalog != null:
		return tile_catalog.resolve_flora_id(
			hex_data.flora_layer,
			hex_data.visual_variant_hash,
			hex_data.biome_pack
		)
	return -1

func _resolve_rock_source_id(hex_data: MacroHexData) -> int:
	var authored := _resolve_authored_path(hex_data.rock_sprite_path, hex_data)
	if authored >= 0:
		return authored
	if tile_catalog != null:
		return tile_catalog.resolve_rock_id(
			hex_data.rock_layer,
			hex_data.visual_variant_hash,
			hex_data.biome_pack
		)
	return -1

func _resolve_structure_source_id(hex_data: MacroHexData) -> int:
	if tile_catalog != null:
		if not hex_data.structure_sprite_path.is_empty():
			var asset_id := tile_catalog.resolve_asset_path(
				hex_data.structure_sprite_path,
				hex_data.visual_variant_hash
			)
			if asset_id >= 0:
				return asset_id
		var id := tile_catalog.resolve_poi_id(
			_structure_layer_key(hex_data.structure_layer),
			hex_data.visual_variant_hash,
			hex_data.biome_pack
		)
		if id >= 0:
			return id
		return tile_catalog.resolve_structure_id(
			hex_data.structure_layer,
			hex_data.visual_variant_hash,
			hex_data.biome_pack
		)
	return -1

func _resolve_authored_path(asset_path: String, hex_data: MacroHexData) -> int:
	if asset_path.is_empty() or tile_catalog == null:
		return -1
	return tile_catalog.resolve_asset_path(asset_path, hex_data.visual_variant_hash)

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

func _paint_shrub(coords: Vector2i, hex_data: MacroHexData) -> void:
	if shrub_sprites.has(coords):
		var existing := shrub_sprites[coords] as Sprite2D
		if is_instance_valid(existing):
			existing.visible = true
			return
	if shrub_layer == null or tile_set == null:
		return
	var source_id := _resolve_flora_source_id(hex_data)
	if source_id < 0:
		return
	var atlas := tile_set.get_source(source_id) as TileSetAtlasSource
	if atlas == null or atlas.texture == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = ("shrub-visual:" + str(hex_data.visual_variant_hash)).hash()
	var shrub := Sprite2D.new()
	shrub.texture = atlas.texture
	shrub.scale = Vector2.ONE * rng.randf_range(0.12, 0.20)
	shrub.position = map_to_local(coords) + Vector2(
		rng.randf_range(-96.0, 96.0),
		rng.randf_range(-56.0, 56.0)
	)
	shrub.z_index = 0
	shrub_layer.add_child(shrub)
	shrub_sprites[coords] = shrub

func _paint_decorations(coords: Vector2i) -> void:
	_clear_decorations(coords)
	if world_generator == null or not world_generator.has_method("get_decorations_at"):
		return
	var props: Array = world_generator.get_decorations_at(coords)
	if props.is_empty():
		return
	if shrub_layer == null:
		return
	var hex_center := map_to_local(coords)
	for index in range(props.size()):
		var prop: Dictionary = props[index]
		var path := str(prop.get("sprite_path", ""))
		if path.is_empty():
			continue
		var texture := load(path) as Texture2D
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		var prop_scale: Variant = prop.get("scale", Vector2.ONE)
		if prop_scale is Vector2:
			sprite.scale = prop_scale
		else:
			var uniform := float(prop.get("uniform_scale", 0.18))
			sprite.scale = Vector2.ONE * uniform
		var offset: Variant = prop.get("offset", Vector2.ZERO)
		if offset is Vector2:
			sprite.position = hex_center + offset
		else:
			sprite.position = hex_center
		var layer_index := int(prop.get("layer", 3))
		sprite.z_index = DECOR_LAYER_Z.get(layer_index, 3)
		shrub_layer.add_child(sprite)
		decor_sprites[_decor_key(coords, index)] = sprite


func _decor_key(coords: Vector2i, index: int) -> String:
	return "%d,%d#%d" % [coords.x, coords.y, index]


func _clear_decorations(coords: Vector2i) -> void:
	var prefix := "%d,%d#" % [coords.x, coords.y]
	for key in decor_sprites.keys().duplicate():
		if not str(key).begins_with(prefix):
			continue
		var sprite := decor_sprites[key] as Sprite2D
		if is_instance_valid(sprite):
			sprite.queue_free()
		decor_sprites.erase(key)


func _clear_shrub(coords: Vector2i) -> void:
	if not shrub_sprites.has(coords):
		return
	var shrub := shrub_sprites[coords] as Sprite2D
	if is_instance_valid(shrub):
		shrub.queue_free()
	shrub_sprites.erase(coords)

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
		var existing := poi_markers[coords] as Label
		if is_instance_valid(existing):
			existing.text = "[ " + poi_name + " ]"
			existing.visible = true
			return

	var pixel_pos := map_to_local(coords)
	var label := Label.new()
	label.text = "[ " + poi_name + " ]"
	label.position = pixel_pos - Vector2(50, 10)
	label.z_index = 4
	add_child(label)
	poi_markers[coords] = label


func _hide_poi_marker(coords: Vector2i) -> void:
	if not poi_markers.has(coords):
		return
	var label := poi_markers[coords] as Label
	if is_instance_valid(label):
		label.visible = false


func _ensure_fog_overlay(coords: Vector2i) -> void:
	_ensure_fog_root()
	var poly_shape := _hex_fog_polygon()
	if fog_overlays.has(coords):
		var existing := fog_overlays[coords] as Polygon2D
		if is_instance_valid(existing):
			existing.polygon = poly_shape
			existing.position = map_to_local(coords)
			return
	var poly := Polygon2D.new()
	poly.polygon = poly_shape
	poly.position = map_to_local(coords)
	poly.z_index = 0
	fog_root.add_child(poly)
	fog_overlays[coords] = poly


func _apply_fog_to_hex(coords: Vector2i, state: int) -> void:
	_ensure_fog_overlay(coords)
	var poly := fog_overlays[coords] as Polygon2D
	if not is_instance_valid(poly):
		return
	match state:
		FogState.VISIBLE:
			poly.color = FOG_VISIBLE_COLOR
			poly.visible = false
		FogState.EXPLORED:
			poly.color = FOG_EXPLORED_COLOR
			poly.visible = true
		_:
			poly.color = FOG_UNKNOWN_COLOR
			poly.visible = true
	# Re-apply layer hide/show for unknown vs known without full repaint cost
	# when fog updates after initial zone paint.
	if rendered_cells.has(coords):
		_sync_detail_visibility(coords, state)


func _sync_detail_visibility(coords: Vector2i, state: int) -> void:
	var is_unknown := state == FogState.UNKNOWN
	var hex_data: MacroHexData = world_generator.get_hex_at(coords)
	var target_flora_layer := flora_layer if flora_layer != null else overlay_layer
	var target_rock_layer := rock_layer if rock_layer != null else overlay_layer
	var target_structure_layer := (
		structure_layer if structure_layer != null else overlay_layer
	)
	if is_unknown:
		_paint_optional_layer(target_flora_layer, coords, -1)
		_paint_optional_layer(target_rock_layer, coords, -1)
		_paint_optional_layer(target_structure_layer, coords, -1)
		if shrub_sprites.has(coords):
			var shrub := shrub_sprites[coords] as Sprite2D
			if is_instance_valid(shrub):
				shrub.visible = false
		_hide_poi_marker(coords)
		return

	# Restored visibility: repaint details if missing.
	if hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS and hex_data.flora_sprite_path.is_empty():
		_paint_optional_layer(target_flora_layer, coords, -1)
		_paint_shrub(coords, hex_data)
	else:
		_clear_shrub(coords)
		_paint_optional_layer(target_flora_layer, coords, _resolve_flora_source_id(hex_data))
	_paint_optional_layer(target_rock_layer, coords, _resolve_rock_source_id(hex_data))
	_paint_optional_layer(target_structure_layer, coords, _resolve_structure_source_id(hex_data))
	if shrub_sprites.has(coords):
		var shrub_vis := shrub_sprites[coords] as Sprite2D
		if is_instance_valid(shrub_vis):
			shrub_vis.visible = true
	if hex_data.is_poi or not hex_data.landmark_id.is_empty():
		_mark_poi_visually(
			coords,
			hex_data.poi_name if hex_data.is_poi else hex_data.landmark_id
		)


func _is_explored(coords: Vector2i) -> bool:
	if world_generator == null:
		return false
	return world_generator.get_hex_at(coords).is_explored


func _erase_hex_visual(coords: Vector2i) -> void:
	erase_cell(coords)
	if overlay_layer != null:
		overlay_layer.erase_cell(coords)
	if flora_layer != null:
		flora_layer.erase_cell(coords)
	if rock_layer != null:
		rock_layer.erase_cell(coords)
	if structure_layer != null:
		structure_layer.erase_cell(coords)
	_clear_shrub(coords)
	_clear_decorations(coords)
	rendered_cells.erase(coords)
	fog_states.erase(coords)
	if fog_overlays.has(coords):
		var poly := fog_overlays[coords] as Polygon2D
		if is_instance_valid(poly):
			poly.queue_free()
		fog_overlays.erase(coords)
	if poi_markers.has(coords):
		poi_markers[coords].queue_free()
		poi_markers.erase(coords)


func _prune_outside_radius(center_coords: Vector2i, radius: int) -> void:
	if _zone_mode:
		return
	for coords in rendered_cells.keys().duplicate():
		if _hex_distance(center_coords, coords) <= radius:
			continue
		_erase_hex_visual(coords)

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))
