extends Control
class_name MacroMinimapView

signal hex_selected(coords: Vector2i)

const UNKNOWN_COLOR := Color("#080b0b")
const PLAINS_COLOR := Color("#667347")
const FOREST_COLOR := Color("#2f5b3d")
const MUD_COLOR := Color("#80652f")
const SNOW_COLOR := Color("#a7bbc0")
const CONCRETE_COLOR := Color("#69777b")
const HILLS_COLOR := Color("#6f6857")
const ROCKS_COLOR := Color("#47494a")
const SHALLOW_WATER_COLOR := Color("#397b8b")
const DEEP_WATER_COLOR := Color("#244b68")
const GRID_COLOR := Color(0.04, 0.07, 0.07, 0.92)
const EXPLORED_DARKEN := 0.32
const PLAYER_COLOR := Color("#f6d05e")
const POI_COLOR := Color("#6fd6cf")
const HOSTILE_COLOR := Color("#ef5961")
const EXIT_COLOR := Color("#8edbe0")
const SELECTED_COLOR := Color("#f6d05e")
const HOVER_COLOR := Color(1.0, 1.0, 1.0, 0.70)
const LEGEND_HEIGHT := 15.0
const MAP_PADDING := 4.0

var _snapshot: Dictionary = {}
var _cells: Dictionary = {} # Vector2i -> cell descriptor
var _centers: Dictionary = {} # Vector2i -> local pixel center
var _hostiles: Dictionary = {} # Vector2i -> true
var _exits: Dictionary = {} # Vector2i -> direction
var _player_coords := Vector2i.ZERO
var _selected_coords := Vector2i.ZERO
var _hovered_coords := Vector2i(999999, 999999)
var _hex_polygon := PackedVector2Array()
var _drawn_bounds := Rect2()
var _hex_scale := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(_rebuild_geometry)
	_rebuild_geometry()


func set_minimap_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_cells.clear()
	for value in _snapshot.get("cells", []):
		if value is Dictionary:
			var coords: Variant = value.get("coords", Vector2i(999999, 999999))
			if coords is Vector2i:
				_cells[coords] = value
	_player_coords = _snapshot.get("player_coords", Vector2i.ZERO)
	_selected_coords = _snapshot.get("selected_coords", _player_coords)
	_hostiles.clear()
	for coords in _snapshot.get("visible_hostiles", []):
		if coords is Vector2i:
			_hostiles[coords] = true
	_exits.clear()
	for value in _snapshot.get("exits", []):
		if not value is Dictionary:
			continue
		var coords: Variant = value.get("coords", Vector2i(999999, 999999))
		if coords is Vector2i:
			_exits[coords] = int(value.get("direction", GameEnums.MacroTravelDirection.NONE))
	_rebuild_geometry()


func get_cell_count() -> int:
	return _cells.size()


func get_drawn_bounds() -> Rect2:
	return _drawn_bounds


func get_cell_screen_center(coords: Vector2i) -> Vector2:
	return _centers.get(coords, Vector2(-1.0, -1.0))


func get_cell_color(coords: Vector2i) -> Color:
	var cell: Dictionary = _cells.get(coords, {})
	if cell.is_empty() or not bool(cell.get("explored", false)):
		return UNKNOWN_COLOR
	var color := _terrain_color(cell)
	return color if bool(cell.get("visible", false)) else color.darkened(EXPLORED_DARKEN)


func has_poi_symbol_at(coords: Vector2i) -> bool:
	var cell: Dictionary = _cells.get(coords, {})
	return (
		bool(cell.get("explored", false))
		and (bool(cell.get("is_poi", false)) or bool(cell.get("has_landmark", false)))
	)


func has_hostile_symbol_at(coords: Vector2i) -> bool:
	return (
		bool((_cells.get(coords, {}) as Dictionary).get("explored", false))
		and _hostiles.has(coords)
	)


func has_exit_symbol_at(coords: Vector2i) -> bool:
	return (
		bool((_cells.get(coords, {}) as Dictionary).get("explored", false))
		and _exits.has(coords)
	)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


func _draw() -> void:
	if _cells.is_empty() or _hex_polygon.is_empty():
		return
	_draw_legend()
	for coords in _cells.keys():
		var center: Vector2 = _centers.get(coords, Vector2.ZERO)
		draw_colored_polygon(_translated_polygon(center), get_cell_color(coords))
		draw_polyline(_closed_polygon(center), GRID_COLOR, 1.0, true)
	for coords in _cells.keys():
		var cell: Dictionary = _cells[coords]
		if not bool(cell.get("explored", false)):
			continue
		var center: Vector2 = _centers.get(coords, Vector2.ZERO)
		if coords == _selected_coords:
			draw_polyline(_closed_polygon(center, 0.82), SELECTED_COLOR, 1.5, true)
		if _exits.has(coords):
			_draw_exit(center, int(_exits[coords]))
		if bool(cell.get("is_poi", false)) or bool(cell.get("has_landmark", false)):
			_draw_diamond(center, POI_COLOR, maxf(1.8, _hex_scale * 0.18))
		if _hostiles.has(coords):
			_draw_hostile(center)
	if _cells.has(_player_coords):
		_draw_player(_centers.get(_player_coords, Vector2.ZERO))
	if _centers.has(_hovered_coords):
		draw_polyline(
			_closed_polygon(_centers[_hovered_coords], 0.70),
			HOVER_COLOR,
			1.0,
			true
		)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var coords := _cell_at_position(event.position)
		if coords != _hovered_coords:
			_hovered_coords = coords
			_update_hover_tooltip(coords)
			queue_redraw()
		return
	if (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and event.pressed
	):
		var coords := _cell_at_position(event.position)
		if (
			_cells.has(coords)
			and bool((_cells[coords] as Dictionary).get("explored", false))
		):
			hex_selected.emit(coords)
		accept_event()


func _rebuild_geometry() -> void:
	_centers.clear()
	_hex_polygon = PackedVector2Array()
	_drawn_bounds = Rect2()
	if _cells.is_empty() or size.x <= 1.0 or size.y <= LEGEND_HEIGHT + 2.0:
		queue_redraw()
		return
	var raw_min := Vector2(INF, INF)
	var raw_max := Vector2(-INF, -INF)
	for coords in _cells.keys():
		var raw := HexCoordUtils.axial_to_visual_vector(coords)
		raw_min = raw_min.min(raw + Vector2(-0.5, -0.5))
		raw_max = raw_max.max(raw + Vector2(0.5, 0.5))
	var available := Rect2(
		Vector2(MAP_PADDING, LEGEND_HEIGHT + MAP_PADDING),
		Vector2(
			maxf(1.0, size.x - MAP_PADDING * 2.0),
			maxf(1.0, size.y - LEGEND_HEIGHT - MAP_PADDING * 2.0)
		)
	)
	var raw_size := raw_max - raw_min
	_hex_scale = minf(available.size.x / raw_size.x, available.size.y / raw_size.y)
	var fitted_size := raw_size * _hex_scale
	var origin := available.position + (available.size - fitted_size) * 0.5 - raw_min * _hex_scale
	_hex_polygon = PackedVector2Array([
		Vector2(0.0, -0.5), Vector2(0.5, -0.25), Vector2(0.5, 0.25),
		Vector2(0.0, 0.5), Vector2(-0.5, 0.25), Vector2(-0.5, -0.25),
	])
	for index in range(_hex_polygon.size()):
		_hex_polygon[index] *= _hex_scale
	for coords in _cells.keys():
		_centers[coords] = origin + HexCoordUtils.axial_to_visual_vector(coords) * _hex_scale
	_drawn_bounds = Rect2(available.position + (available.size - fitted_size) * 0.5, fitted_size)
	queue_redraw()


func _terrain_color(cell: Dictionary) -> Color:
	var water := int(cell.get("water", GameEnums.MacroWaterLayer.NONE))
	if water == GameEnums.MacroWaterLayer.DEEP_WATER:
		return DEEP_WATER_COLOR
	if water == GameEnums.MacroWaterLayer.SHALLOW_RIVER:
		return SHALLOW_WATER_COLOR
	var rock := int(cell.get("rock", GameEnums.MacroRockLayer.NONE))
	if rock == GameEnums.MacroRockLayer.ROCKS:
		return ROCKS_COLOR
	if rock == GameEnums.MacroRockLayer.HILLS:
		return HILLS_COLOR
	var terrain := int(cell.get("terrain", GameEnums.MacroTerrainTile.PLAINS_GRASS))
	if terrain == GameEnums.MacroTerrainTile.HUB_CONCRETE:
		return CONCRETE_COLOR
	if terrain == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
		return SNOW_COLOR
	if terrain == GameEnums.MacroTerrainTile.MUD_YELLOW:
		return MUD_COLOR
	if (
		terrain == GameEnums.MacroTerrainTile.FOREST_SPARSE
		or int(cell.get("flora", GameEnums.MacroFloraLayer.NONE)) == GameEnums.MacroFloraLayer.TREES
	):
		return FOREST_COLOR
	return PLAINS_COLOR


func _translated_polygon(center: Vector2, scale_factor: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in _hex_polygon:
		points.append(center + point * scale_factor)
	return points


func _closed_polygon(center: Vector2, scale_factor: float = 1.0) -> PackedVector2Array:
	var points := _translated_polygon(center, scale_factor)
	if not points.is_empty():
		points.append(points[0])
	return points


func _cell_at_position(local_position: Vector2) -> Vector2i:
	var best := Vector2i(999999, 999999)
	var best_distance := INF
	for coords in _centers.keys():
		var distance := local_position.distance_squared_to(_centers[coords])
		if distance < best_distance:
			best_distance = distance
			best = coords
	if best_distance <= pow(_hex_scale * 0.58, 2.0):
		return best
	return Vector2i(999999, 999999)


func _update_hover_tooltip(coords: Vector2i) -> void:
	if not _cells.has(coords):
		tooltip_text = ""
		return
	var cell: Dictionary = _cells[coords]
	if not bool(cell.get("explored", false)):
		tooltip_text = "Unknown territory"
		return
	var label := str(cell.get("label", "Hex %d, %d" % [coords.x, coords.y]))
	tooltip_text = "%s  [%d, %d]" % [label, coords.x, coords.y]


func _draw_legend() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 9
	var y := 10.0
	draw_circle(Vector2(8.0, 7.0), 2.4, PLAYER_COLOR)
	draw_string(
		font, Vector2(13.0, y), "YOU", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, PLAYER_COLOR
	)
	_draw_diamond(Vector2(50.0, 7.0), POI_COLOR, 2.4)
	draw_string(
		font, Vector2(56.0, y), "POI", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, POI_COLOR
	)
	_draw_hostile(Vector2(91.0, 7.0), 2.4)
	draw_string(
		font, Vector2(97.0, y), "HOSTILE", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, HOSTILE_COLOR
	)
	draw_string(
		font, Vector2(151.0, y), "> EXIT", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, EXIT_COLOR
	)


func _draw_player(center: Vector2) -> void:
	var radius := maxf(2.5, _hex_scale * 0.24)
	draw_circle(center, radius + 1.5, Color(0.03, 0.04, 0.03, 0.9))
	draw_circle(center, radius, PLAYER_COLOR)
	draw_line(
		center + Vector2(0.0, radius),
		center + Vector2(0.0, radius + 2.5),
		PLAYER_COLOR,
		1.5,
		true
	)


func _draw_diamond(center: Vector2, color: Color, radius: float) -> void:
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
		center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
	]), color)


func _draw_hostile(center: Vector2, radius: float = -1.0) -> void:
	var resolved := radius if radius > 0.0 else maxf(2.2, _hex_scale * 0.22)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(0.0, -resolved),
		center + Vector2(resolved, resolved),
		center + Vector2(-resolved, resolved),
	]), HOSTILE_COLOR)


func _draw_exit(center: Vector2, direction: int) -> void:
	var vector := HexCoordUtils.travel_direction_vector(direction)
	if vector.is_zero_approx():
		return
	var tangent := Vector2(-vector.y, vector.x)
	var tip := center + vector * maxf(2.4, _hex_scale * 0.28)
	var rear := center - vector * maxf(1.0, _hex_scale * 0.10)
	var wing := maxf(1.8, _hex_scale * 0.16)
	draw_polyline(PackedVector2Array([
		rear + tangent * wing, tip, rear - tangent * wing,
	]), EXIT_COLOR, 1.5, true)
