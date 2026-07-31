extends Control
class_name TacticalArenaView

signal sector_selected(coords: Vector2i)
signal sector_hovered(coords: Vector2i)
signal sector_unhovered

const GRID_GAP := 6.0
const TOKEN_RADIUS := 22.0

var snapshot: Dictionary = {}
var selected_sector := Vector2i(-1, -1)
var hovered_sector := Vector2i(-1, -1)
var preview_quote: CombatActionQuote
var _texture_cache: Dictionary = {}
var _cue: CombatPresentationCue
var _cue_progress := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(queue_redraw)


func show_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	queue_redraw()


func show_quote(value: CombatActionQuote) -> void:
	preview_quote = value
	queue_redraw()


func clear_quote() -> void:
	preview_quote = null
	queue_redraw()


func select_sector(coords: Vector2i) -> void:
	selected_sector = coords
	queue_redraw()


func begin_cue(cue: CombatPresentationCue) -> void:
	_cue = cue
	_cue_progress = 0.0
	queue_redraw()


func update_cue(progress: float, cue: CombatPresentationCue) -> void:
	if cue != _cue:
		return
	_cue_progress = progress
	queue_redraw()


func end_cue(cue: CombatPresentationCue) -> void:
	if cue == _cue:
		_cue = null
		_cue_progress = 0.0
		queue_redraw()


func sector_center(coords: Vector2i) -> Vector2:
	var rect := _grid_rect()
	var cell := _cell_size(rect)
	return rect.position + Vector2(
		(float(coords.x) + 0.5) * cell.x,
		(float(coords.y) + 0.5) * cell.y
	)


func _draw() -> void:
	var rect := _grid_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color("101418"), true)
	_draw_backdrop()
	var sectors: Array = snapshot.get("sectors", [])
	for raw in sectors:
		if raw is Dictionary:
			_draw_sector(raw, rect)
	_draw_preview()
	_draw_actors()
	_draw_presentation()


func _draw_backdrop() -> void:
	var path := str(snapshot.get("backdrop_asset_path", ""))
	var texture := _texture(path)
	if texture != null:
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false, Color(0.42, 0.46, 0.42, 0.72))


func _draw_sector(data: Dictionary, rect: Rect2) -> void:
	var coords: Vector2i = data.get("coords", Vector2i.ZERO)
	var cell_rect := _sector_rect(coords, rect).grow(-GRID_GAP * 0.5)
	var ground := _texture(str(data.get("ground_asset", "")))
	var overlay := _texture(str(data.get("overlay_asset", "")))
	var tint := _surface_color(str(data.get("surface_id", "unresolved")))
	draw_rect(cell_rect, tint, true)
	if ground != null:
		draw_texture_rect(ground, cell_rect, false, Color(1, 1, 1, 0.78))
	if overlay != null:
		draw_texture_rect(overlay, cell_rect, false, Color.WHITE)
	if bool(data.get("blocked", false)):
		draw_rect(cell_rect, Color(0.08, 0.08, 0.08, 0.55), true)
	_draw_cover_edges(cell_rect, data.get("cover_edges", {}))
	if not data.get("hazards", {}).is_empty():
		draw_circle(cell_rect.position + Vector2(13, 13), 6.0, Color("d87343"))
	if bool(data.get("trap", {}).get("armed", false)):
		draw_string(ThemeDB.fallback_font, cell_rect.end - Vector2(20, 8), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("e0b75e"))
	var elevation := int(data.get("elevation", 0))
	if elevation != 0:
		draw_string(ThemeDB.fallback_font, cell_rect.position + Vector2(7, 17), "%+d" % elevation, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("d6d4c7"))
	if coords == selected_sector:
		draw_rect(cell_rect, Color("f0c66a"), false, 3.0)
	elif coords == hovered_sector:
		draw_rect(cell_rect, Color("9ac5c4"), false, 2.0)
	else:
		draw_rect(cell_rect, Color(0.45, 0.50, 0.49, 0.65), false, 1.0)


func _draw_preview() -> void:
	if preview_quote == null:
		return
	var color := Color("78c78c") if preview_quote.legal else Color("c86658")
	if preview_quote.path.size() > 1:
		var points := PackedVector2Array()
		for coords in preview_quote.path:
			points.append(sector_center(coords))
		if points.size() > 1:
			draw_polyline(points, color, 5.0, true)
	if CombatArenaState.contains_coords(preview_quote.target_sector):
		draw_circle(sector_center(preview_quote.target_sector), 28.0, Color(color, 0.22))
	var collision := preview_quote.collision_preview
	if collision.has("destination"):
		draw_circle(sector_center(collision.destination), 18.0, Color("d9824d"), false, 4.0)


func _draw_actors() -> void:
	var tactics: Dictionary = snapshot.get("tactics", {})
	var facings: Dictionary = snapshot.get("facings", {})
	for sector in snapshot.get("sectors", []):
		var actor_id := str(sector.get("occupant_id", ""))
		if actor_id.is_empty():
			continue
		var center := sector_center(sector.coords)
		var side := _actor_side(actor_id)
		var color := Color("67a7c8") if side == "player" else Color("c76c5b")
		var posture := str(tactics.get(actor_id, {}).get("posture", "standing"))
		var radius := TOKEN_RADIUS if posture == "standing" else TOKEN_RADIUS * (0.82 if posture == "crouched" else 0.64)
		draw_circle(center, radius, Color(0.04, 0.05, 0.05, 0.90))
		draw_circle(center, radius, color, false, 4.0)
		_draw_facing(center, str(facings.get(actor_id, "east")), color)
		if bool(tactics.get(actor_id, {}).get("off_balance", false)):
			draw_arc(center, radius + 6.0, 0.0, TAU, 18, Color("e0b75e"), 2.0)
		if bool(tactics.get(actor_id, {}).get("restrained", false)):
			draw_line(center - Vector2(radius, radius), center + Vector2(radius, radius), Color("d083a2"), 3.0)


func _draw_presentation() -> void:
	if _cue == null:
		return
	var start := sector_center(_cue.start_sector)
	var finish := sector_center(_cue.end_sector)
	if _cue.phase_id == "transit" and not _cue.vfx_id.is_empty():
		var point := start.lerp(finish, _cue_progress)
		draw_line(start, point, Color("f0d487"), 3.0, true)
		draw_circle(point, 4.0, Color.WHITE)
	elif _cue.phase_id in ["contact", "impact"]:
		draw_circle(finish, lerpf(8.0, 30.0, _cue_progress), Color(0.95, 0.45, 0.28, 1.0 - _cue_progress), false, 4.0)


func _draw_cover_edges(rect: Rect2, edges: Dictionary) -> void:
	for edge in edges:
		var strength := float(edges[edge])
		if strength <= 0.0:
			continue
		var width := 2.0 + strength * 5.0
		match str(edge):
			"north": draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("d7d0b2"), width)
			"south": draw_line(Vector2(rect.position.x, rect.end.y), rect.end, Color("d7d0b2"), width)
			"west": draw_line(rect.position, Vector2(rect.position.x, rect.end.y), Color("d7d0b2"), width)
			"east": draw_line(Vector2(rect.end.x, rect.position.y), rect.end, Color("d7d0b2"), width)


func _draw_facing(center: Vector2, facing: String, color: Color) -> void:
	var direction: Vector2 = {"north": Vector2.UP, "east": Vector2.RIGHT, "south": Vector2.DOWN, "west": Vector2.LEFT}.get(facing, Vector2.RIGHT)
	draw_line(center, center + direction * 31.0, color, 5.0, true)


func _actor_side(actor_id: String) -> String:
	for actor in get_meta("actor_snapshot", []):
		if str(actor.get("actor_id", "")) == actor_id:
			return str(actor.get("team_id", ""))
	return "player" if actor_id == "player" else "enemy"


func _grid_rect() -> Rect2:
	var margin := 12.0
	return Rect2(Vector2(margin, margin), size - Vector2(margin * 2.0, margin * 2.0))


func _cell_size(rect: Rect2) -> Vector2:
	return Vector2(rect.size.x / CombatArenaState.WIDTH, rect.size.y / CombatArenaState.HEIGHT)


func _sector_rect(coords: Vector2i, rect: Rect2) -> Rect2:
	var cell := _cell_size(rect)
	return Rect2(rect.position + Vector2(coords.x * cell.x, coords.y * cell.y), cell)


func _coords_at(local_position: Vector2) -> Vector2i:
	var rect := _grid_rect()
	if not rect.has_point(local_position):
		return Vector2i(-1, -1)
	var cell := _cell_size(rect)
	return Vector2i(floori((local_position.x - rect.position.x) / cell.x), floori((local_position.y - rect.position.y) / cell.y))


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var coords := _coords_at(event.position)
		if coords != hovered_sector:
			hovered_sector = coords
			if CombatArenaState.contains_coords(coords):
				sector_hovered.emit(coords)
			else:
				sector_unhovered.emit()
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var coords := _coords_at(event.position)
		if CombatArenaState.contains_coords(coords):
			select_sector(coords)
			sector_selected.emit(coords)


func _on_mouse_exited() -> void:
	hovered_sector = Vector2i(-1, -1)
	sector_unhovered.emit()
	queue_redraw()


func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path) as Texture2D
	return _texture_cache[path]


func _surface_color(surface_id: String) -> Color:
	return {
		"plains": Color("344236"),
		"forest": Color("253c32"),
		"mud": Color("514636"),
		"snow": Color("849092"),
		"concrete": Color("4b5053"),
		"hills": Color("4f4b36"),
		"road": Color("625b4d"),
		"shallow_water": Color("335467"),
		"deep_water": Color("213d55"),
	}.get(surface_id, Color("252a2d"))
