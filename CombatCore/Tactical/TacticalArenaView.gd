extends Control
class_name TacticalArenaView

signal sector_selected(coords: Vector2i)
signal sector_hovered(coords: Vector2i)
signal sector_unhovered

const GRID_GAP := 6.0
const TOKEN_RADIUS := 22.0
const CAMERA_ZOOM_MIN := 1.0
const CAMERA_ZOOM_MAX := 2.25
const CAMERA_ZOOM_STEP := 0.15
const HUMANOID_TOKEN_SCENE := preload("res://UI/Humanoid/HumanoidToken.tscn")
const WEAPON_PRESENTATION_CATALOG: CombatWeaponPresentationCatalog = preload(
	"res://CombatCore/Tactical/default_weapon_presentation_catalog.tres"
)

var snapshot: Dictionary = {}
var selected_sector := Vector2i(-1, -1)
var hovered_sector := Vector2i(-1, -1)
var preview_quote: CombatActionQuote
var _texture_cache: Dictionary = {}
var _cue: CombatPresentationCue
var _cue_progress := 0.0
var _actor_tokens: Dictionary = {}
var _presentation_positions: Dictionary = {}
var _last_path_segment := -1
var _view_zoom := CAMERA_ZOOM_MIN
var _view_pan := Vector2.ZERO
var _is_panning := false
var _pan_anchor := Vector2.ZERO
var _camera_safe_rect := Rect2()


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
	var topology_changed := (
		int(snapshot.get("width", 0)) != int(value.get("width", 0))
		or int(snapshot.get("height", 0)) != int(value.get("height", 0))
		or str(snapshot.get("presentation_style", "")) != str(value.get("presentation_style", ""))
	)
	snapshot = value.duplicate(true)
	if topology_changed:
		reset_camera_view()
	_presentation_positions.clear()
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


func reset_camera_view() -> void:
	_view_zoom = CAMERA_ZOOM_MIN
	_view_pan = Vector2.ZERO
	_refresh_camera_geometry()


func camera_zoom() -> float:
	return _view_zoom


func camera_pan() -> Vector2:
	return _view_pan


func set_camera_safe_rect(value: Rect2) -> void:
	_camera_safe_rect = value
	_clamp_camera_pan()
	_refresh_camera_geometry()


func begin_cue(cue: CombatPresentationCue) -> void:
	_cue = cue
	_cue_progress = 0.0
	_last_path_segment = -1
	scale = Vector2.ONE
	pivot_offset = sector_center(cue.end_sector) if _contains(cue.end_sector) else size * 0.5
	var token := _actor_tokens.get(cue.actor_id) as HumanoidTokenView
	if token != null:
		token.position = _presentation_positions.get(cue.actor_id, sector_center(cue.start_sector))
		token.scale = Vector2.ONE
		token.rotation = 0.0
		var facing_vector := _facing_vector(cue.facing)
		if cue.facing.is_empty() and cue.start_sector != cue.end_sector:
			facing_vector = sector_center(cue.start_sector).direction_to(sector_center(cue.end_sector))
		token.face_direction(facing_vector)
		if HumanoidVisualCatalog.supports_animation(cue.animation_id):
			if HumanoidVisualCatalog.animation_loops(cue.animation_id):
				token.play_animation(cue.animation_id)
			else:
				token.play_timed_one_shot(cue.animation_id, "Idle", cue.duration_seconds)
	var target_token := _actor_tokens.get(cue.target_actor_id) as HumanoidTokenView
	if target_token != null:
		target_token.position = _presentation_positions.get(cue.target_actor_id, sector_center(cue.end_sector))
		target_token.scale = Vector2.ONE
		target_token.rotation = 0.0
	queue_redraw()


func update_cue(progress: float, cue: CombatPresentationCue) -> void:
	if cue != _cue:
		return
	_cue_progress = progress
	var token := _actor_tokens.get(cue.actor_id) as HumanoidTokenView
	var target_token := _actor_tokens.get(cue.target_actor_id) as HumanoidTokenView
	var start := sector_center(cue.start_sector)
	var finish := sector_center(cue.end_sector)
	var direction := start.direction_to(finish)
	if token != null:
		if cue.phase_id == "transit" and cue.moves_actor:
			token.position = _path_position(cue.path, progress, cue.start_sector, cue.end_sector)
			if cue.path.size() >= 2:
				var scaled := clampf(progress, 0.0, 1.0) * float(cue.path.size() - 1)
				var segment := mini(floori(scaled), cue.path.size() - 2)
				token.face_direction(sector_center(cue.path[segment]).direction_to(sector_center(cue.path[segment + 1])))
				if segment != _last_path_segment:
					_last_path_segment = segment
					token.footstep_taken.emit()
					var event_bus := get_node_or_null("/root/GameEventBus")
					if event_bus != null:
						event_bus.emit_humanoid_footstep(null, _surface_footstep(cue.path[segment + 1]))
		elif cue.phase_id == "wind_up":
			token.position = start - direction * cue.recoil_pixels * sin(progress * PI * 0.5)
		elif cue.phase_id == "contact":
			token.position = start + direction * cue.lunge_pixels * sin(progress * PI)
		elif cue.phase_id == "impact" and cue.recoil_pixels > 0.0:
			token.position = start - direction * cue.recoil_pixels * sin(progress * PI)
	var reacts_now := cue.phase_id == "reaction" and cue.outcome_tag in ["dodge", "block"]
	var impacts_now := cue.phase_id == "impact" and cue.outcome_tag not in ["miss", "neutral", "malfunction"]
	if target_token != null and (reacts_now or impacts_now):
		var target_start: Vector2 = _presentation_positions.get(cue.target_actor_id, finish)
		var target_finish := sector_center(cue.target_end_sector) if _contains(cue.target_end_sector) else target_start
		if cue.outcome_tag == "dodge":
			var perpendicular := Vector2(-direction.y, direction.x)
			target_token.position = target_start + perpendicular * 18.0 * sin(progress * PI)
		elif cue.outcome_tag not in ["miss", "neutral", "malfunction"]:
			var travel := target_start.lerp(target_finish, progress)
			var shake := direction * sin(progress * cue.shake_frequency) * cue.shake_amplitude * (1.0 - progress)
			target_token.position = travel + shake
			target_token.scale = Vector2(1.0 - cue.impact_scale * sin(progress * PI), 1.0 + cue.impact_scale * sin(progress * PI))
			target_token.rotation = deg_to_rad(cue.impact_rotation_degrees) * sin(progress * PI)
	if cue.phase_id in ["contact", "impact"] and cue.camera_impulse_pixels > 0.0:
		var camera_punch := cue.camera_impulse_pixels * 0.0025 * sin(progress * PI)
		scale = Vector2.ONE * (1.0 + camera_punch)
	queue_redraw()


func end_cue(cue: CombatPresentationCue) -> void:
	if cue == _cue:
		var token := _actor_tokens.get(cue.actor_id) as HumanoidTokenView
		var target_token := _actor_tokens.get(cue.target_actor_id) as HumanoidTokenView
		if cue.phase_id == "transit" and cue.moves_actor:
			_presentation_positions[cue.actor_id] = sector_center(cue.end_sector)
		if cue.phase_id == "impact" and target_token != null and _contains(cue.target_end_sector):
			_presentation_positions[cue.target_actor_id] = sector_center(cue.target_end_sector)
		if token != null:
			token.position = _presentation_positions.get(cue.actor_id, sector_center(cue.start_sector))
			token.scale = Vector2.ONE
			token.rotation = 0.0
			if cue.phase_id == "transit" and cue.moves_actor:
				token.play_animation("Idle", true)
		if target_token != null:
			target_token.position = _presentation_positions.get(cue.target_actor_id, sector_center(cue.end_sector))
			target_token.scale = Vector2.ONE
			target_token.rotation = 0.0
		_cue = null
		_cue_progress = 0.0
		scale = Vector2.ONE
		queue_redraw()


func _path_position(path: Array[Vector2i], progress: float, start: Vector2i, finish: Vector2i) -> Vector2:
	if path.size() < 2:
		return sector_center(start).lerp(sector_center(finish), progress)
	var scaled := clampf(progress, 0.0, 1.0) * float(path.size() - 1)
	var segment := mini(floori(scaled), path.size() - 2)
	var local_progress := scaled - float(segment)
	return sector_center(path[segment]).lerp(sector_center(path[segment + 1]), local_progress)


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
	var scene_first := str(snapshot.get("presentation_style", "")) == "duel_lane"
	draw_rect(cell_rect, Color(tint, 0.20) if scene_first else tint, true)
	if ground != null and not scene_first:
		draw_texture_rect(ground, cell_rect, false, Color(1, 1, 1, 0.78))
	if overlay != null and not scene_first:
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
		draw_rect(cell_rect, Color(0.45, 0.50, 0.49, 0.22), false, 1.0)


func _draw_preview() -> void:
	if preview_quote == null:
		return
	var color := Color("78c78c") if preview_quote.legal else Color("c86658")
	if _contains(preview_quote.origin_sector) and _contains(preview_quote.target_sector):
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
	if _contains(preview_quote.target_sector):
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
		if _contains(threat_coords):
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
		var actor := _actor_snapshot(actor_id)
		var display_name := str(actor.get("name", actor_id)).to_upper()
		draw_string(ThemeDB.fallback_font, center + Vector2(-radius - 8.0, radius + 18.0), display_name, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0 + 16.0, 10, Color("d9dfdc"))
		_draw_vital_bar(center + Vector2(-28.0, radius + 24.0), 56.0, float(actor.get("blood", 0.0)), Color("c85f55"))
		_draw_vital_bar(center + Vector2(-28.0, radius + 31.0), 56.0, float(actor.get("consciousness", 0.0)), Color("d6b85e"))


func _draw_vital_bar(origin: Vector2, width: float, value: float, color: Color) -> void:
	draw_rect(Rect2(origin, Vector2(width, 5.0)), Color(0.02, 0.025, 0.028, 0.92), true)
	draw_rect(Rect2(origin + Vector2.ONE, Vector2((width - 2.0) * clampf(value / GameEnums.SCALE_MAX, 0.0, 1.0), 3.0)), color, true)


func _draw_presentation() -> void:
	if _cue == null:
		return
	_draw_weapon_sheet_frame()
	var start := sector_center(_cue.start_sector)
	var finish := sector_center(_cue.end_sector)
	if _cue.phase_id == "transit" and not _cue.vfx_id.is_empty():
		var point := start.lerp(finish, _cue_progress)
		draw_line(start, point, Color("f0d487"), 3.0, true)
		draw_circle(point, 4.0, Color.WHITE)
	elif _cue.phase_id in ["contact", "impact"]:
		var impact_color := Color("e7c56c") if _cue.outcome_tag in ["block", "cover"] else Color("ef6f52")
		if _cue.outcome_tag == "miss":
			impact_color = Color("8ca4a1")
		draw_circle(finish, lerpf(8.0, 30.0, _cue_progress), Color(impact_color, 1.0 - _cue_progress), false, 4.0)
		if _cue.outcome_tag in ["object_collision", "actor_collision", "boundary"]:
			for index in range(5):
				var angle := float(index) * TAU / 5.0
				var debris := finish + Vector2.from_angle(angle) * lerpf(5.0, 24.0, _cue_progress)
				draw_rect(Rect2(debris - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(0.68, 0.58, 0.43, 1.0 - _cue_progress), true)


func _draw_weapon_sheet_frame() -> void:
	var definition := WEAPON_PRESENTATION_CATALOG.definition_for(_cue.weapon_id)
	if definition == null:
		return
	var sheet := definition.sheet_for_action(_cue.action_id)
	var frame_size := definition.frame_size_for_action(_cue.action_id)
	var fps := definition.fps_for_action(_cue.action_id)
	if sheet == null or frame_size.x <= 0 or frame_size.y <= 0 or fps <= 0.0:
		return
	var columns := maxi(1, sheet.get_width() / frame_size.x)
	var rows := maxi(1, sheet.get_height() / frame_size.y)
	var frame_count := columns * rows
	var sequence_progress := lerpf(
		_cue.sequence_progress_start,
		_cue.sequence_progress_end,
		_cue_progress
	)
	var frame_index := clampi(floori(sequence_progress * float(frame_count)), 0, frame_count - 1)
	var source := Rect2(
		Vector2((frame_index % columns) * frame_size.x, (frame_index / columns) * frame_size.y),
		Vector2(frame_size)
	)
	var actor_position: Vector2 = _presentation_positions.get(_cue.actor_id, sector_center(_cue.start_sector))
	var display_scale := clampf(minf(_cell_size(_grid_rect()).x, _cell_size(_grid_rect()).y) / 44.0, 1.0, 2.2)
	var display_size := Vector2(frame_size) * display_scale
	var facing := _facing_vector(_cue.facing)
	var rotation_angle := facing.angle()
	var flip_y := facing.x < -0.5
	draw_set_transform(actor_position, rotation_angle, Vector2(1.0, -1.0 if flip_y else 1.0))
	draw_texture_rect_region(sheet, Rect2(-display_size * 0.5, display_size), source)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
		token.set_display_scale(clampf(minf(_cell_size(_grid_rect()).x, _cell_size(_grid_rect()).y) / 32.0, 1.1, 2.8))
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
	var base := _base_grid_rect()
	var scaled_size := base.size * _view_zoom
	return Rect2(base.get_center() - scaled_size * 0.5 + _view_pan, scaled_size)


func _base_grid_rect() -> Rect2:
	var margin := 12.0
	var available := _camera_safe_rect if _camera_safe_rect.size.x > 0.0 and _camera_safe_rect.size.y > 0.0 else Rect2(Vector2.ZERO, size)
	var rect := available.grow(-margin)
	if rect.size.x > 1440.0:
		rect.position.x += (rect.size.x - 1440.0) * 0.5
		rect.size.x = 1440.0
	if str(snapshot.get("presentation_style", "")) == "duel_lane":
		var lane_height := clampf(size.y * 0.34, 96.0, 220.0)
		rect.position.y = size.y * 0.57 - lane_height * 0.5
		rect.size.y = lane_height
	return rect


func _set_camera_zoom(next_zoom: float, focus: Vector2) -> void:
	var old_rect := _grid_rect()
	var normalized := Vector2(0.5, 0.5)
	if old_rect.size.x > 0.0 and old_rect.size.y > 0.0:
		normalized = (focus - old_rect.position) / old_rect.size
	_view_zoom = clampf(next_zoom, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	if is_equal_approx(_view_zoom, CAMERA_ZOOM_MIN):
		_view_pan = Vector2.ZERO
	else:
		var next_rect := _grid_rect()
		_view_pan += focus - (next_rect.position + normalized * next_rect.size)
	_clamp_camera_pan()
	_refresh_camera_geometry()


func _clamp_camera_pan() -> void:
	if _view_zoom <= CAMERA_ZOOM_MIN:
		_view_pan = Vector2.ZERO
		return
	var base := _base_grid_rect()
	var allowance := (base.size * _view_zoom - base.size) * 0.5
	_view_pan.x = clampf(_view_pan.x, -allowance.x, allowance.x)
	_view_pan.y = clampf(_view_pan.y, -allowance.y, allowance.y)


func _refresh_camera_geometry() -> void:
	_presentation_positions.clear()
	_sync_actor_tokens()
	queue_redraw()


func _cell_size(rect: Rect2) -> Vector2:
	return Vector2(rect.size.x / float(_arena_width()), rect.size.y / float(_arena_height()))


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
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			_set_camera_zoom(_view_zoom + CAMERA_ZOOM_STEP, mouse_button.position)
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			_set_camera_zoom(_view_zoom - CAMERA_ZOOM_STEP, mouse_button.position)
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE:
			_is_panning = mouse_button.pressed
			_pan_anchor = mouse_button.position
			mouse_default_cursor_shape = Control.CURSOR_DRAG if _is_panning else Control.CURSOR_POINTING_HAND
			accept_event()
			return
	if event is InputEventMouseMotion:
		if _is_panning:
			var motion := event as InputEventMouseMotion
			_view_pan += motion.position - _pan_anchor
			_pan_anchor = motion.position
			_clamp_camera_pan()
			_refresh_camera_geometry()
			accept_event()
			return
		var coords := _coords_at(event.position)
		if coords != hovered_sector:
			hovered_sector = coords
			if _contains(coords):
				sector_hovered.emit(coords)
			else:
				sector_unhovered.emit()
			queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		var coords := _coords_at(event.position)
		if _contains(coords):
			select_sector(coords)
			sector_selected.emit(coords)
	elif event is InputEventKey and event.pressed:
		var cursor := hovered_sector if _contains(hovered_sector) else selected_sector
		if not _contains(cursor):
			cursor = Vector2i(_arena_width() / 2, _arena_height() / 2)
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
			hovered_sector = Vector2i(clampi(cursor.x + delta.x, 0, _arena_width() - 1), clampi(cursor.y + delta.y, 0, _arena_height() - 1))
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


func _surface_footstep(coords: Vector2i) -> String:
	for sector in snapshot.get("sectors", []):
		if sector.get("coords", Vector2i(-1, -1)) == coords:
			return {
				"mud": "MUD",
				"forest": "TREES",
				"plains": "DIRT",
			}.get(str(sector.get("surface_id", "")), "CONCRETE")
	return "CONCRETE"


func _actor_coords(actor_id: String) -> Vector2i:
	for sector in snapshot.get("sectors", []):
		if str(sector.get("occupant_id", "")) == actor_id:
			return sector.get("coords", Vector2i(-1, -1))
	return Vector2i(-1, -1)


func _arena_width() -> int:
	return maxi(1, int(snapshot.get("width", 12)))


func _arena_height() -> int:
	return maxi(1, int(snapshot.get("height", 1)))


func _contains(coords: Vector2i) -> bool:
	if coords.x < 0 or coords.x >= _arena_width() or coords.y < 0 or coords.y >= _arena_height():
		return false
	var sectors: Array = snapshot.get("sectors", [])
	if sectors.is_empty():
		return true
	for sector in sectors:
		if sector.get("coords", Vector2i(-1, -1)) == coords:
			return true
	return false
