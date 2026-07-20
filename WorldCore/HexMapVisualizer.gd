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
@export var water_layer: TileMapLayer
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
## Explored polygons must be exact-size: translucent oversize overlaps create
## dark edge bands between known hexes.
const FOG_VISIBLE_COLOR := Color(0, 0, 0, 0)
const FOG_EXPLORED_COLOR := Color(0, 0, 0, 0.38)
const FOG_UNKNOWN_COLOR := Color(0, 0, 0, 0.94)
const FOG_HEX_OVERSIZE := 1.02
const FOG_HEX_EXACT := 1.0
const FOG_TRANSITION_SEC := 0.32
const SELECTION_FILL_COLOR := Color(0.98, 0.82, 0.28, 0.045)
const SELECTION_OUTLINE_COLOR := Color(0.98, 0.82, 0.28, 0.82)
const SELECTION_INSET := 0.90
const SELECTION_LINE_WIDTH := 7.0
const BOUNDARY_PREVIEW_RADIUS := GameEnums.MACRO_ZONE_RADIUS + 1
const BOUNDARY_LOCKED_COLOR := Color(0.07, 0.08, 0.07, 0.42)
const BOUNDARY_ROUTE_COLOR := Color(0.78, 0.58, 0.18, 0.16)
const BOUNDARY_HOVER_COLOR := Color(0.95, 0.72, 0.18, 0.28)

var rendered_cells: Dictionary = {}
var poi_markers: Dictionary = {}
var shrub_sprites: Dictionary = {}
var decor_sprites: Dictionary = {} # String key -> Sprite2D
var fog_overlays: Dictionary = {} # Vector2i -> Polygon2D
var fog_states: Dictionary = {} # Vector2i -> FogState
var fog_tweens: Dictionary = {} # Vector2i -> Tween
var selection_marker: Node2D
var selection_fill: Polygon2D
var selection_outline: Line2D
var selection_pulse: Tween
var fog_root: Node2D
var boundary_preview_root: Node2D
var boundary_hover_label: Label
var boundary_preview_polygons: Dictionary = {} # Vector2i -> Polygon2D
var boundary_preview_data: Dictionary = {} # direction -> destination summary
var boundary_hover_coords := Vector2i(999999, 999999)
var _zone_mode := false
var _cached_fog_polygon: PackedVector2Array = PackedVector2Array()
var _cached_exact_polygon: PackedVector2Array = PackedVector2Array()
var _cached_selection_polygon: PackedVector2Array = PackedVector2Array()
var _decor_texture_cache: Dictionary = {} # asset path -> Texture2D

func _ready() -> void:
	if not world_generator:
		push_error("Visualizer cannot see the Cartographer. Hook it up.")
		return
	if shrub_layer != null:
		shrub_layer.y_sort_enabled = true
	_load_generated_assets()
	_ensure_selection_marker()
	_ensure_fog_root()
	_ensure_boundary_preview_root()


func _process(_delta: float) -> void:
	if boundary_preview_root == null or not boundary_preview_root.visible:
		return
	update_boundary_hover(local_to_map(get_local_mouse_position()))


## Pointy-top hex vertices from TileSet cell size.
## oversize > 1 seals opaque unknown fog; exact 1.0 is required for translucent explored fog.
func _hex_polygon(size_scale: float) -> PackedVector2Array:
	var tile_px := Vector2(512.0, 512.0)
	if tile_set != null:
		tile_px = Vector2(tile_set.tile_size)
	var half_w := tile_px.x * 0.5 * size_scale
	var half_h := tile_px.y * 0.5 * size_scale
	var quarter_h := half_h * 0.5
	return PackedVector2Array([
		Vector2(0.0, -half_h),
		Vector2(half_w, -quarter_h),
		Vector2(half_w, quarter_h),
		Vector2(0.0, half_h),
		Vector2(-half_w, quarter_h),
		Vector2(-half_w, -quarter_h),
	])


## Opaque unknown fog seal polygon (slightly oversized).
func _hex_fog_polygon() -> PackedVector2Array:
	if not _cached_fog_polygon.is_empty():
		return _cached_fog_polygon
	_cached_fog_polygon = _hex_polygon(FOG_HEX_OVERSIZE)
	return _cached_fog_polygon


## Exact-footprint polygon for translucent explored fog (no edge banding).
func _hex_exact_polygon() -> PackedVector2Array:
	if not _cached_exact_polygon.is_empty():
		return _cached_exact_polygon
	_cached_exact_polygon = _hex_polygon(FOG_HEX_EXACT)
	return _cached_exact_polygon


func _hex_selection_polygon() -> PackedVector2Array:
	if not _cached_selection_polygon.is_empty():
		return _cached_selection_polygon
	_cached_selection_polygon = _hex_polygon(SELECTION_INSET)
	return _cached_selection_polygon


func _invalidate_fog_polygon_cache() -> void:
	_cached_fog_polygon = PackedVector2Array()
	_cached_exact_polygon = PackedVector2Array()
	_cached_selection_polygon = PackedVector2Array()


func _rebuild_fog_overlay_geometry() -> void:
	_invalidate_fog_polygon_cache()
	for coords in fog_overlays.keys():
		var fog_poly := fog_overlays[coords] as Polygon2D
		if not is_instance_valid(fog_poly):
			continue
		fog_poly.position = map_to_local(coords)
		_set_fog_polygon_shape(fog_poly, int(fog_states.get(coords, FogState.UNKNOWN)))
	_refresh_selection_geometry()


func _set_fog_polygon_shape(poly: Polygon2D, state: int) -> void:
	if poly == null:
		return
	# Only opaque unknown fog needs oversize; explored must stay exact.
	if state == FogState.UNKNOWN:
		poly.polygon = _hex_fog_polygon()
	else:
		poly.polygon = _hex_exact_polygon()


func _fog_color_for_state(state: int) -> Color:
	match state:
		FogState.VISIBLE:
			return FOG_VISIBLE_COLOR
		FogState.EXPLORED:
			return FOG_EXPLORED_COLOR
	return FOG_UNKNOWN_COLOR


func _load_generated_assets() -> void:
	if tile_catalog == null and ResourceLoader.exists(CATALOG_PATH):
		tile_catalog = load(CATALOG_PATH) as MacroTileCatalog
	if ResourceLoader.exists(TILESET_PATH):
		var generated_tile_set := load(TILESET_PATH) as TileSet
		if generated_tile_set != null:
			_align_overlay_sources_to_hex_base(generated_tile_set)
			tile_set = generated_tile_set
			_assign_tileset_to_layers(generated_tile_set)
			_rebuild_fog_overlay_geometry()


func _align_overlay_sources_to_hex_base(generated_tile_set: TileSet) -> void:
	if tile_catalog == null:
		return
	var source_ids: Dictionary = {}
	for source_dict in [
		tile_catalog.flora_source_ids,
		tile_catalog.rock_source_ids,
		tile_catalog.structure_source_ids,
		tile_catalog.poi_source_ids,
	]:
		_collect_source_ids(source_dict, source_ids)
	for pack_data in tile_catalog.pack_layer_ids.values():
		if not pack_data is Dictionary:
			continue
		for layer_name in ["flora", "rock", "structure", "poi"]:
			_collect_source_ids(pack_data.get(layer_name, {}), source_ids)
	for source_id in source_ids.keys():
		var source := generated_tile_set.get_source(int(source_id)) as TileSetAtlasSource
		if source == null or not source.has_tile(Vector2i.ZERO):
			continue
		var tile_data := source.get_tile_data(Vector2i.ZERO, 0)
		if tile_data == null:
			continue
		var vertical_offset := int(round(
			(float(generated_tile_set.tile_size.y) - float(source.texture_region_size.y)) * 0.5
		))
		tile_data.texture_origin = Vector2i(0, vertical_offset)


func _collect_source_ids(value: Variant, output: Dictionary) -> void:
	if value is Dictionary:
		for nested in value.values():
			_collect_source_ids(nested, output)
	elif value is PackedInt32Array or value is Array:
		for source_id in value:
			output[int(source_id)] = true

func _assign_tileset_to_layers(generated_tile_set: TileSet) -> void:
	for layer in [
		overlay_layer,
		water_layer,
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


func _ensure_boundary_preview_root() -> void:
	if boundary_preview_root != null:
		return
	boundary_preview_root = Node2D.new()
	boundary_preview_root.name = "BoundaryRoutePreviews"
	boundary_preview_root.z_index = 2
	add_child(boundary_preview_root)
	boundary_hover_label = Label.new()
	boundary_hover_label.name = "BoundaryHoverLabel"
	boundary_hover_label.visible = false
	boundary_hover_label.z_index = 3
	boundary_hover_label.add_theme_font_size_override("font_size", 18)
	boundary_hover_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	boundary_hover_label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.02))
	boundary_hover_label.add_theme_constant_override("outline_size", 8)
	boundary_preview_root.add_child(boundary_hover_label)


func configure_boundary_previews(previews: Dictionary) -> void:
	_ensure_boundary_preview_root()
	boundary_preview_data = previews.duplicate(true)
	var ring_cells := HexCoordUtils.cells_in_ring(BOUNDARY_PREVIEW_RADIUS)
	for coords in ring_cells:
		var direction := HexCoordUtils.travel_direction_for_coords(coords)
		var data: Dictionary = boundary_preview_data.get(direction, {})
		var polygon := _ensure_boundary_preview_polygon(coords)
		polygon.color = _boundary_preview_color(data)
		polygon.visible = true
	for coords in boundary_preview_polygons.keys().duplicate():
		if ring_cells.has(coords):
			continue
		var stale := boundary_preview_polygons[coords] as Polygon2D
		if is_instance_valid(stale):
			stale.queue_free()
		boundary_preview_polygons.erase(coords)
	update_boundary_hover(Vector2i(999999, 999999))


func _ensure_boundary_preview_polygon(coords: Vector2i) -> Polygon2D:
	if boundary_preview_polygons.has(coords):
		var existing := boundary_preview_polygons[coords] as Polygon2D
		if is_instance_valid(existing):
			existing.position = map_to_local(coords)
			existing.polygon = _hex_selection_polygon()
			return existing
	var polygon := Polygon2D.new()
	polygon.name = "RoutePreview_%d_%d" % [coords.x, coords.y]
	polygon.position = map_to_local(coords)
	polygon.polygon = _hex_selection_polygon()
	boundary_preview_root.add_child(polygon)
	boundary_preview_polygons[coords] = polygon
	return polygon


func _boundary_preview_color(data: Dictionary) -> Color:
	return (
		BOUNDARY_ROUTE_COLOR
		if not data.get("node_ids", []).is_empty()
		else BOUNDARY_LOCKED_COLOR
	)


func update_boundary_hover(coords: Vector2i) -> void:
	if coords == boundary_hover_coords:
		return
	if boundary_preview_polygons.has(boundary_hover_coords):
		var old_direction := HexCoordUtils.travel_direction_for_coords(boundary_hover_coords)
		var old_data: Dictionary = boundary_preview_data.get(old_direction, {})
		var old_polygon := boundary_preview_polygons[boundary_hover_coords] as Polygon2D
		if is_instance_valid(old_polygon):
			old_polygon.color = _boundary_preview_color(old_data)
	boundary_hover_coords = coords
	if boundary_hover_label == null:
		return
	if not boundary_preview_polygons.has(coords):
		boundary_hover_label.visible = false
		return
	var direction := HexCoordUtils.travel_direction_for_coords(coords)
	var data: Dictionary = boundary_preview_data.get(direction, {})
	var polygon := boundary_preview_polygons[coords] as Polygon2D
	if is_instance_valid(polygon):
		polygon.color = BOUNDARY_HOVER_COLOR
	var direction_name := str(data.get(
		"direction_name",
		GameEnums.MacroTravelDirection.keys()[direction]
	)).replace("_", " ")
	var node_names: Array = data.get("node_names", [])
	boundary_hover_label.text = (
		"%s  >  %s\nClick from the rim to travel"
		% [direction_name, " / ".join(PackedStringArray(node_names))]
		if not node_names.is_empty()
		else "%s  >  NO CONNECTED ROUTE" % direction_name
	)
	var inward := -HexCoordUtils.travel_direction_vector(direction) * 310.0
	boundary_hover_label.position = map_to_local(coords) + inward + Vector2(-145.0, -28.0)
	boundary_hover_label.visible = true


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
func apply_fog(visible_hexes: Dictionary, animate: bool = true) -> void:
	_ensure_fog_root()
	for coords in rendered_cells.keys():
		var state := FogState.UNKNOWN
		if visible_hexes.has(coords):
			state = FogState.VISIBLE
		elif _is_explored(coords):
			state = FogState.EXPLORED
		_apply_fog_to_hex(coords, state, animate)
	fog_applied.emit()


func get_fog_state(coords: Vector2i) -> int:
	return int(fog_states.get(coords, FogState.UNKNOWN))


func show_selection(coords: Vector2i) -> void:
	_ensure_selection_marker()
	selection_marker.position = map_to_local(coords)
	selection_marker.visible = true
	selection_marker.z_index = 5
	_start_selection_pulse()


func hide_selection() -> void:
	if selection_marker != null:
		selection_marker.visible = false
	_stop_selection_pulse()


func _ensure_selection_marker() -> void:
	if selection_marker != null and is_instance_valid(selection_marker):
		_refresh_selection_geometry()
		return
	selection_marker = Node2D.new()
	selection_marker.name = "HexSelectionMarker"
	selection_marker.z_index = 5
	selection_marker.visible = false
	selection_fill = Polygon2D.new()
	selection_fill.name = "SelectionFill"
	selection_fill.color = SELECTION_FILL_COLOR
	selection_outline = Line2D.new()
	selection_outline.name = "SelectionOutline"
	selection_outline.width = SELECTION_LINE_WIDTH
	selection_outline.default_color = SELECTION_OUTLINE_COLOR
	selection_outline.joint_mode = Line2D.LINE_JOINT_ROUND
	selection_outline.begin_cap_mode = Line2D.LINE_CAP_ROUND
	selection_outline.end_cap_mode = Line2D.LINE_CAP_ROUND
	selection_outline.antialiased = true
	selection_marker.add_child(selection_fill)
	selection_marker.add_child(selection_outline)
	add_child(selection_marker)
	_refresh_selection_geometry()


func _refresh_selection_geometry() -> void:
	if selection_marker == null or not is_instance_valid(selection_marker):
		return
	var poly := _hex_selection_polygon()
	if selection_fill != null:
		selection_fill.polygon = poly
		selection_fill.color = SELECTION_FILL_COLOR
	if selection_outline != null:
		var points := PackedVector2Array(poly)
		if not points.is_empty():
			points.append(points[0])
		selection_outline.points = points
		selection_outline.default_color = SELECTION_OUTLINE_COLOR
		selection_outline.width = SELECTION_LINE_WIDTH


func _start_selection_pulse() -> void:
	_stop_selection_pulse()
	if selection_outline == null:
		return
	selection_outline.modulate = Color(1, 1, 1, 1)
	selection_pulse = create_tween().set_loops()
	selection_pulse.tween_property(selection_outline, "modulate:a", 0.45, 0.55)
	selection_pulse.tween_property(selection_outline, "modulate:a", 1.0, 0.55)


func _stop_selection_pulse() -> void:
	if selection_pulse != null and selection_pulse.is_valid():
		selection_pulse.kill()
	selection_pulse = null
	if selection_outline != null:
		selection_outline.modulate = Color(1, 1, 1, 1)

func _paint_single_hex(coords: Vector2i) -> void:
	var hex_data: MacroHexData = world_generator.get_hex_at(coords)
	var fog_state: int = int(fog_states.get(coords, FogState.UNKNOWN))
	var is_unknown := fog_state == FogState.UNKNOWN and _zone_mode

	# Background always paints so the zone is not an empty void.
	var bg_source_id := _resolve_bg_source_id(hex_data)
	set_cell(coords, bg_source_id, SINGLE_TILE_COORD)

	var target_flora_layer := flora_layer if flora_layer != null else overlay_layer
	var target_water_layer := water_layer if water_layer != null else overlay_layer
	var target_rock_layer := rock_layer if rock_layer != null else overlay_layer
	var target_structure_layer := (
		structure_layer if structure_layer != null else overlay_layer
	)

	if is_unknown:
		_paint_optional_layer(target_water_layer, coords, -1)
		_paint_optional_layer(target_flora_layer, coords, -1)
		_paint_optional_layer(target_rock_layer, coords, -1)
		_paint_optional_layer(target_structure_layer, coords, -1)
		_clear_shrub(coords)
		_clear_decorations(coords)
		_hide_poi_marker(coords)
	else:
		_paint_optional_layer(
			target_water_layer,
			coords,
			_resolve_water_source_id(hex_data)
		)
		if (
			_zone_mode
			and hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS
			and hex_data.flora_sprite_path.is_empty()
		):
			# Radius zones render shrub recipes through zone_decorations. Painting
			# the legacy single shrub as well duplicated and mis-scaled every patch.
			_clear_shrub(coords)
			_paint_optional_layer(target_flora_layer, coords, -1)
		elif hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS and hex_data.flora_sprite_path.is_empty():
			_paint_optional_layer(target_flora_layer, coords, -1)
			_paint_shrub(coords, hex_data)
		else:
			_clear_shrub(coords)
			var flora_source := _resolve_flora_source_id(hex_data)
			_paint_optional_layer(target_flora_layer, coords, flora_source)
		# Local zones use normalized rock clusters. The raw rock atlas entries
		# have wildly different footprints and create overlapping full-hex rings.
		var rock_source := -1 if _zone_mode else _resolve_rock_source_id(hex_data)
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


func _resolve_water_source_id(hex_data: MacroHexData) -> int:
	if (
		hex_data.water_layer == GameEnums.MacroWaterLayer.NONE
		or hex_data.water_sprite_path.is_empty()
		or tile_catalog == null
	):
		return -1
	return tile_catalog.resolve_asset_path(
		hex_data.water_sprite_path,
		hex_data.visual_variant_hash
	)

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
	var texture_size := atlas.texture.get_size()
	var fit_scale := minf(76.0 / texture_size.x, 88.0 / texture_size.y)
	shrub.scale = Vector2.ONE * fit_scale * rng.randf_range(0.88, 1.08)
	shrub.offset = Vector2(0.0, -texture_size.y * 0.5)
	shrub.position = map_to_local(coords) + Vector2(
		rng.randf_range(-72.0, 72.0),
		rng.randf_range(-42.0, 42.0)
	)
	shrub.z_index = 1
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
		var texture: Texture2D = _decor_texture_cache.get(path)
		if texture == null:
			texture = load(path) as Texture2D
			if texture != null:
				_decor_texture_cache[path] = texture
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		var target_box: Variant = prop.get("target_box", Vector2.ZERO)
		if target_box is Vector2 and not target_box.is_zero_approx():
			var texture_size := texture.get_size()
			var fit_scale := minf(target_box.x / texture_size.x, target_box.y / texture_size.y)
			sprite.scale = Vector2.ONE * fit_scale * float(prop.get("scale_multiplier", 1.0))
			sprite.offset = Vector2(0.0, -texture_size.y * 0.5)
		else:
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
		# These isometric sprites have a shared light direction and ground plane.
		# Arbitrary rotation makes them look drunk, floating, or both.
		sprite.rotation = 0.0
		sprite.flip_h = bool(prop.get("flip_h", false))
		sprite.z_index = 1
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
			_style_poi_label(existing)
			return

	var pixel_pos := map_to_local(coords)
	var label := Label.new()
	label.text = "[ " + poi_name + " ]"
	label.position = pixel_pos - Vector2(50, 10)
	label.z_index = 4
	_style_poi_label(label)
	add_child(label)
	poi_markers[coords] = label


func _style_poi_label(label: Label) -> void:
	if label == null:
		return
	HUDAssetLibrary.apply_label(label, "discovery")
	label.add_theme_font_size_override("font_size", 11)


func _hide_poi_marker(coords: Vector2i) -> void:
	if not poi_markers.has(coords):
		return
	var label := poi_markers[coords] as Label
	if is_instance_valid(label):
		label.visible = false


func _ensure_fog_overlay(coords: Vector2i) -> void:
	_ensure_fog_root()
	if fog_overlays.has(coords):
		var existing := fog_overlays[coords] as Polygon2D
		if is_instance_valid(existing):
			existing.position = map_to_local(coords)
			_set_fog_polygon_shape(existing, int(fog_states.get(coords, FogState.UNKNOWN)))
			return
	var poly := Polygon2D.new()
	poly.polygon = _hex_exact_polygon()
	poly.position = map_to_local(coords)
	poly.z_index = 0
	fog_root.add_child(poly)
	fog_overlays[coords] = poly


func _kill_fog_tween(coords: Vector2i) -> void:
	if not fog_tweens.has(coords):
		return
	var tween: Tween = fog_tweens[coords]
	if tween != null and tween.is_valid():
		tween.kill()
	fog_tweens.erase(coords)


func _apply_fog_to_hex(coords: Vector2i, state: int, animate: bool = true) -> void:
	_ensure_fog_overlay(coords)
	var poly := fog_overlays[coords] as Polygon2D
	if not is_instance_valid(poly):
		return
	var previous := int(fog_states.get(coords, FogState.UNKNOWN))
	fog_states[coords] = state
	_set_fog_polygon_shape(poly, state)
	var target := _fog_color_for_state(state)
	_kill_fog_tween(coords)
	if not animate or previous == state:
		poly.color = target
		poly.visible = state != FogState.VISIBLE
		if rendered_cells.has(coords):
			_sync_detail_visibility(coords, state)
		return

	# Reveal / dim transitions: keep polygon visible while alpha tweens.
	poly.visible = true
	if previous == FogState.VISIBLE:
		poly.color = Color(target.r, target.g, target.b, 0.0)
	var from_alpha := poly.color.a
	var to_alpha := target.a
	var tween := create_tween()
	fog_tweens[coords] = tween
	tween.tween_method(
		func(alpha: float) -> void:
			if is_instance_valid(poly):
				poly.color = Color(target.r, target.g, target.b, alpha),
		from_alpha,
		to_alpha,
		FOG_TRANSITION_SEC
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.finished.connect(
		func() -> void:
			fog_tweens.erase(coords)
			if not is_instance_valid(poly):
				return
			poly.color = target
			poly.visible = state != FogState.VISIBLE
			if rendered_cells.has(coords):
				_sync_detail_visibility(coords, state)
	)
	# Detail layers update immediately so reveal doesn't wait for fog fade.
	if rendered_cells.has(coords):
		_sync_detail_visibility(coords, state)


func _sync_detail_visibility(coords: Vector2i, state: int) -> void:
	var is_unknown := state == FogState.UNKNOWN
	var hex_data: MacroHexData = world_generator.get_hex_at(coords)
	var target_flora_layer := flora_layer if flora_layer != null else overlay_layer
	var target_water_layer := water_layer if water_layer != null else overlay_layer
	var target_rock_layer := rock_layer if rock_layer != null else overlay_layer
	var target_structure_layer := (
		structure_layer if structure_layer != null else overlay_layer
	)
	if is_unknown:
		_paint_optional_layer(target_water_layer, coords, -1)
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
	_paint_optional_layer(
		target_water_layer,
		coords,
		_resolve_water_source_id(hex_data)
	)
	if (
		_zone_mode
		and hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS
		and hex_data.flora_sprite_path.is_empty()
	):
		_clear_shrub(coords)
		_paint_optional_layer(target_flora_layer, coords, -1)
	elif hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS and hex_data.flora_sprite_path.is_empty():
		_paint_optional_layer(target_flora_layer, coords, -1)
		_paint_shrub(coords, hex_data)
	else:
		_clear_shrub(coords)
		_paint_optional_layer(target_flora_layer, coords, _resolve_flora_source_id(hex_data))
	_paint_optional_layer(
		target_rock_layer,
		coords,
		-1 if _zone_mode else _resolve_rock_source_id(hex_data)
	)
	_paint_optional_layer(target_structure_layer, coords, _resolve_structure_source_id(hex_data))
	if shrub_sprites.has(coords):
		var shrub_vis := shrub_sprites[coords] as Sprite2D
		if is_instance_valid(shrub_vis):
			shrub_vis.visible = true
	_paint_decorations(coords)
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
	if water_layer != null:
		water_layer.erase_cell(coords)
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
