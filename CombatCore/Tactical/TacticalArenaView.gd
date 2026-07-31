extends Control
class_name TacticalArenaView

signal sector_selected(coords: Vector2i)
signal sector_hovered(coords: Vector2i)
signal sector_unhovered

const GRID_GAP := 6.0
const TOKEN_RADIUS := 22.0
const HUMANOID_TOKEN_SCENE := preload("res://UI/Humanoid/HumanoidToken.tscn")

var snapshot: Dictionary = {}
var selected_sector := Vector2i(-1, -1)
var hovered_sector := Vector2i(-1, -1)
var preview_quote: CombatActionQuote
var _texture_cache: Dictionary = {}
var _cue: CombatPresentationCue
var _cue_progress := 0.0
var _actor_tokens: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(func() -> void:
		queue_redraw()
		_sync_actor_tokens()
	)


func show_snapshot(value: Dictionary) -> void:
	snapshot = value.duplicate(true)
	_sync_actor_tokens()
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
	var token := _actor_tokens.get(cue.actor_id) as HumanoidTokenView
	if token != null:
		token.position = sector_center(cue.start_sector)
		token.face_direction(_facing_vector(cue.facing))
		if HumanoidVisualCatalog.supports_animation(cue.animation_id):
			if HumanoidVisualCatalog.animation_loops(cue.animation_id):
				token.play_animation(cue.animation_id)
			else:
				token.play_timed_one_shot(cue.animation_id, "Idle", cue.duration_seconds)
	queue_redraw()


func update_cue(progress: float, cue: CombatPresentationCue) -> void:
	if cue != _cue:
		return
	_cue_progress = progress
	var token := _actor_tokens.get(cue.actor_id) as HumanoidTokenView
	if token != null and cue.phase_id == "transit":
		token.position = sector_center(cue.start_sector).lerp(sector_center(cue.end_sector), progress)
	queue_redraw()


func end_cue(cue: CombatPresentationCue) -> void:
	if cue == _cue:
		_cue = null
		_cue_progress = 0.0
		_sync_actor_tokens()
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
	if CombatArenaState.contains_coords(preview_quote.origin_sector) and CombatArenaState.contains_coords(preview_quote.target_sector):
		draw_line(
			sector_center(preview_quote.origin_sector),
			sector_center(preview_quote.target_sector),
			Color(color, 0.55) if preview_quote.has_line_of_sight else Color("c86658"),
			2.0,
			true
		)
	if preview_quote.path.size() > 1:
		var points := PackedVector2Array()
		for coords in preview_quote.path:
			points.append(sector_center(coords))
			draw_circle(sector_center(coords), 16.0, Color(color, 0.20))
		if points.size() > 1:
			draw_polyline(points, color, 5.0, true)
	if CombatArenaState.contains_coords(preview_quote.target_sector):
		var target_center := sector_center(preview_quote.target_sector)
		draw_circle(target_center, 28.0, Color(color, 0.22))
		draw_string(ThemeDB.fallback_font, target_center + Vector2(-28.0, -34.0), "%d AP" % preview_quote.ap_cost, HORIZONTAL_ALIGNMENT_CENTER, 56.0, 13, color)
		if not preview_quote.final_facing.is_empty():
			draw_line(target_center, target_center + _facing_vector(preview_quote.final_facing) * 34.0, Color("f0d487"), 4.0, true)
	var collision := preview_quote.collision_preview
	if collision.has("destination"):
		draw_circle(sector_center(collision.destination), 18.0, Color("d9824d"), false, 4.0)
	for threat_id in preview_quote.reaction_threat_ids:
		var threat_coords := _actor_coords(str(threat_id))
		if CombatArenaState.contains_coords(threat_coords):
			draw_string(ThemeDB.fallback_font, sector_center(threat_coords) + Vector2(-8.0, -32.0), "!", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 20, Color("ef6f5b"))


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
		var radius := TOKEN_RADIUS if posture == "standing" else TOKEN_RADIUS * 0.82
		draw_circle(center, radius, Color(0.04, 0.05, 0.05, 0.90))
		draw_circle(center, radius, color, false, 4.0)
		_draw_facing(center, str(facings.get(actor_id, "east")), color)
		if bool(tactics.get(actor_id, {}).get("off_balance", false)):
			draw_arc(center, radius + 6.0, 0.0, TAU, 18, Color("e0b75e"), 2.0)
		draw_string(ThemeDB.fallback_font, center + Vector2(-radius, radius + 18.0), actor_id.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 10, Color("d9dfdc"))


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


func _sync_actor_tokens() -> void:
	if not is_node_ready():
		return
	var active_ids: Array[String] = []
	var tactics: Dictionary = snapshot.get("tactics", {})
	var facings: Dictionary = snapshot.get("facings", {})
	for sector in snapshot.get("sectors", []):
		var actor_id := str(sector.get("occupant_id", ""))
		if actor_id.is_empty():
			continue
		active_ids.append(actor_id)
		var token := _actor_tokens.get(actor_id) as HumanoidTokenView
		if token == null:
			token = HUMANOID_TOKEN_SCENE.instantiate()
			token.name = "Token_%s" % actor_id
			token.z_index = 10
			add_child(token)
			_actor_tokens[actor_id] = token
			var slot_items: Dictionary = {}
			for item in _actor_snapshot(actor_id).get("items", []):
				if str(item.get("location", "")) == "equipped":
					slot_items[int(item.get("equipped_slot", GameEnums.EquipmentSlot.NONE))] = str(item.get("definition_id", ""))
			token.set_slot_item_ids(slot_items)
		token.visible = true
		token.position = sector_center(sector.coords)
		token.set_display_scale(clampf(minf(_cell_size(_grid_rect()).x, _cell_size(_grid_rect()).y) / 38.0, 1.1, 2.0))
		token.face_direction(_facing_vector(str(facings.get(actor_id, "east"))))
		var posture := str(tactics.get(actor_id, {}).get("posture", "standing"))
		var idle := "CrouchIdle" if posture == "crouched" and HumanoidVisualCatalog.supports_animation("CrouchIdle") else "Idle"
		if _cue == null or _cue.actor_id != actor_id:
			token.play_animation(idle, false)
	for actor_id in _actor_tokens:
		var token := _actor_tokens[actor_id] as HumanoidTokenView
		if token != null:
			token.visible = str(actor_id) in active_ids


func _actor_snapshot(actor_id: String) -> Dictionary:
	for actor in get_meta("actor_snapshot", []):
		if str(actor.get("actor_id", "")) == actor_id:
			return actor
	return {}


func _facing_vector(facing: String) -> Vector2:
	return {
		"north": Vector2.UP,
		"east": Vector2.RIGHT,
		"south": Vector2.DOWN,
		"west": Vector2.LEFT,
	}.get(facing, Vector2.RIGHT)


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
		grab_focus()
		var coords := _coords_at(event.position)
		if CombatArenaState.contains_coords(coords):
			select_sector(coords)
			sector_selected.emit(coords)
	elif event is InputEventKey and event.pressed:
		var cursor := hovered_sector if CombatArenaState.contains_coords(hovered_sector) else selected_sector
		if not CombatArenaState.contains_coords(cursor):
			cursor = Vector2i(3, 2)
		var delta := Vector2i.ZERO
		if event.is_action("ui_left"):
			delta = Vector2i.LEFT
		elif event.is_action("ui_right"):
			delta = Vector2i.RIGHT
		elif event.is_action("ui_up"):
			delta = Vector2i.UP
		elif event.is_action("ui_down"):
			delta = Vector2i.DOWN
		if delta != Vector2i.ZERO:
			hovered_sector = Vector2i(clampi(cursor.x + delta.x, 0, CombatArenaState.WIDTH - 1), clampi(cursor.y + delta.y, 0, CombatArenaState.HEIGHT - 1))
			sector_hovered.emit(hovered_sector)
			queue_redraw()
			accept_event()
		elif event.is_action("ui_accept"):
			select_sector(cursor)
			sector_selected.emit(cursor)
			accept_event()


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


func _actor_coords(actor_id: String) -> Vector2i:
	for sector in snapshot.get("sectors", []):
		if str(sector.get("occupant_id", "")) == actor_id:
			return sector.get("coords", Vector2i(-1, -1))
	return Vector2i(-1, -1)
