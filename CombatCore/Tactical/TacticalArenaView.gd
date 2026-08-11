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
const HUMANOID_TOKEN_SCENE := PresentationSceneRegistry.HUMANOID_TOKEN_SCENE
const TOKEN_OVERLAY_SCRIPT := preload("res://CombatCore/Tactical/CombatTokenOverlay.gd")
const BULLET_TEXTURE := preload("res://Asset/Guns_Animation/Bullet.png")
const VISUAL_PROFILE = preload(
	"res://CombatCore/Tactical/readable_moody_visual_profile.tres"
)

const PROJECTILE_TRAIL_LENGTH := 24.0
const PROJECTILE_TRAIL_WIDTH := 1.25
const PROJECTILE_BULLET_SCALE := Vector2(0.95, 0.58)
const PROJECTILE_TRAIL_COLOR := Color(1.0, 0.78, 0.38, 0.56)
const PROJECTILE_BULLET_COLOR := Color(1.0, 0.92, 0.62, 0.94)
const BLOOD_FPS := 30.0
const BLOOD_SCALE := 1.35
const BLOOD_MAX_ACTIVE := 6
const BLOOD_VARIANT_COUNT := 9

var snapshot: Dictionary = {}
var selected_sector := Vector2i(-1, -1)
var hovered_sector := Vector2i(-1, -1)
var preview_quote: CombatActionQuote
var _texture_cache: Dictionary = {}
var _cue: CombatPresentationCue
var _cue_progress := 0.0
var _sequence: CombatPresentationSequence
var _sequence_weapon_cue: CombatPresentationCue
var _actor_slot_offsets: Dictionary = {}
var _actor_tokens: Dictionary = {}
var _presentation_positions: Dictionary = {}
var _last_path_segment := -1
var _view_zoom := CAMERA_ZOOM_MIN
var _view_pan := Vector2.ZERO
var _is_panning := false
var _pan_anchor := Vector2.ZERO
var _camera_safe_rect := Rect2()
var _projectile_trail: Line2D
var _projectile_sprite: Sprite2D
var _projectile_start := Vector2.ZERO
var _projectile_end := Vector2.ZERO
var _projectile_direction := Vector2.RIGHT
var _projectile_active := false
var _blood_vfx: Array[Dictionary] = []
var _blood_texture_cache: Dictionary = {}
var _blood_frame_count_cache: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	set_process(false)
	gui_input.connect(_on_gui_input)
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(func() -> void:
		queue_redraw()
		_sync_actor_tokens()
	)


func _process(delta: float) -> void:
	if _blood_vfx.is_empty():
		set_process(false)
		return
	for index in range(_blood_vfx.size() - 1, -1, -1):
		var effect: Dictionary = _blood_vfx[index]
		var sprite := effect.get("sprite") as Sprite2D
		if not is_instance_valid(sprite):
			_blood_vfx.remove_at(index)
			continue
		var elapsed := float(effect.get("elapsed", 0.0)) + delta
		var frame_count := int(effect.get("frame_count", 0))
		var frame_index := floori(elapsed * BLOOD_FPS)
		if frame_count <= 0 or frame_index >= frame_count:
			sprite.queue_free()
			_blood_vfx.remove_at(index)
			continue
		if frame_index != int(effect.get("frame_index", -1)):
			var texture := _blood_texture(int(effect.get("variant", 1)), frame_index)
			if texture != null:
				sprite.texture = texture
			effect["frame_index"] = frame_index
		effect["elapsed"] = elapsed
		_blood_vfx[index] = effect


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


func clear_presentation() -> void:
	_end_projectile()
	for effect in _blood_vfx:
		var sprite := effect.get("sprite") as Sprite2D
		if is_instance_valid(sprite):
			sprite.queue_free()
	_blood_vfx.clear()
	set_process(false)
	for actor_id in _actor_tokens:
		var token := _actor_tokens[actor_id] as HumanoidTokenView
		if token == null:
			continue
		token.set_action_equipment_suppressed(false)
		var top := token.get_meta("combat_top_overlay", null) as CombatTokenOverlay
		if top != null:
			top.set_weapon_cue(null)
	_cue = null
	_cue_progress = 0.0
	_sequence = null
	_sequence_weapon_cue = null
	scale = Vector2.ONE
	queue_redraw()


func begin_sequence(sequence: CombatPresentationSequence) -> void:
	_sequence = sequence
	_sequence_weapon_cue = null
	if sequence == null:
		return
	for candidate in sequence.cues:
		if _is_firearm_cue(candidate):
			_sequence_weapon_cue = candidate
			break
	if _sequence_weapon_cue == null:
		return
	var token := _actor_tokens.get(_sequence_weapon_cue.actor_id) as HumanoidTokenView
	if token == null:
		return
	# The composited token weapon is the physical firearm. The overhead sheet is
	# an illustrative readout and must never replace the gun that fires the shot.
	token.set_action_equipment_suppressed(false)
	var top_overlay := token.get_meta("combat_top_overlay", null) as CombatTokenOverlay
	if top_overlay != null:
		top_overlay.set_weapon_cue(_sequence_weapon_cue, 0.0)


func end_sequence(_sequence_value: CombatPresentationSequence) -> void:
	clear_presentation()


func select_sector(coords: Vector2i) -> void:
	selected_sector = coords
	_focus_camera_on(coords)
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
	var target_token := _actor_tokens.get(cue.target_actor_id) as HumanoidTokenView
	if token != null:
		token.position = _presentation_positions.get(cue.actor_id, _actor_position(cue.actor_id, cue.start_sector))
		token.scale = Vector2.ONE
		token.rotation = 0.0
		var facing_vector := _facing_vector(cue.facing)
		if cue.facing.is_empty() and cue.start_sector != cue.end_sector:
			facing_vector = sector_center(cue.start_sector).direction_to(sector_center(cue.end_sector))
		token.face_direction(facing_vector)
	if cue.phase_id == "reaction":
		if token != null:
			token.play_animation("Idle", true)
	elif cue.phase_id == "impact":
		_play_cue_animation(token, cue)
		# Impact owns the one target animation start. Reaction is only a readable
		# hold/settle window and must not replay the same one-shot.
		if target_token != null and cue.target_animation_id != "neutral":
			target_token.play_timed_one_shot(cue.target_animation_id, "Idle", maxf(0.75, cue.duration_seconds + 0.40))
	else:
		_play_cue_animation(token, cue)
	if target_token != null:
		target_token.position = _presentation_positions.get(cue.target_actor_id, _actor_position(cue.target_actor_id, cue.end_sector))
		target_token.scale = Vector2.ONE
		target_token.rotation = 0.0
	if cue.phase_id == "transit" and cue.vfx_id == "projectile":
		_begin_projectile(cue)
	elif cue.phase_id == "impact" and _cue_has_blood(cue):
		_play_blood_vfx(_impact_position(cue), cue)
	queue_redraw()


func update_cue(progress: float, cue: CombatPresentationCue) -> void:
	if cue != _cue:
		return
	_cue_progress = progress
	if _sequence_weapon_cue != null:
		var cue_token := _actor_tokens.get(_sequence_weapon_cue.actor_id) as HumanoidTokenView
		if cue_token != null:
			var top_overlay := cue_token.get_meta("combat_top_overlay", null) as CombatTokenOverlay
			if top_overlay != null:
				top_overlay.set_cue_progress(lerpf(
					cue.sequence_progress_start,
					cue.sequence_progress_end,
					progress
				))
	var token := _actor_tokens.get(cue.actor_id) as HumanoidTokenView
	var target_token := _actor_tokens.get(cue.target_actor_id) as HumanoidTokenView
	var start := _actor_position(cue.actor_id, cue.start_sector)
	var finish := _actor_position(cue.actor_id, cue.end_sector)
	if cue.phase_id == "transit" and cue.vfx_id == "projectile":
		_update_projectile(progress)
	var direction := start.direction_to(finish)
	if token != null:
		if cue.phase_id == "transit" and cue.moves_actor:
			token.position = _path_position(cue.path, progress, cue.start_sector, cue.end_sector, cue.actor_id)
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
		var target_finish := _actor_position(cue.target_actor_id, cue.target_end_sector) if _contains(cue.target_end_sector) else target_start
		if cue.outcome_tag == "dodge":
			var perpendicular := Vector2(-direction.y, direction.x)
			target_token.position = target_start + perpendicular * 18.0 * sin(progress * PI)
		elif cue.outcome_tag not in ["miss", "neutral", "malfunction"]:
			var travel := target_start.lerp(target_finish, progress)
			var shake := direction * sin(progress * cue.shake_frequency) * cue.shake_amplitude * (1.0 - progress)
			target_token.position = travel + shake
	if cue.phase_id in ["contact", "impact"] and cue.camera_impulse_pixels > 0.0:
		var camera_punch := cue.camera_impulse_pixels * 0.0025 * sin(progress * PI)
		scale = Vector2.ONE * (1.0 + camera_punch)
	queue_redraw()


func end_cue(cue: CombatPresentationCue) -> void:
	if cue == _cue:
		var token := _actor_tokens.get(cue.actor_id) as HumanoidTokenView
		var target_token := _actor_tokens.get(cue.target_actor_id) as HumanoidTokenView
		if cue.phase_id == "transit" and cue.moves_actor:
			_presentation_positions[cue.actor_id] = _actor_position(cue.actor_id, cue.end_sector)
		if cue.phase_id == "impact" and target_token != null and _contains(cue.target_end_sector):
			_presentation_positions[cue.target_actor_id] = _actor_position(cue.target_actor_id, cue.target_end_sector)
		if token != null:
			token.position = _presentation_positions.get(cue.actor_id, _actor_position(cue.actor_id, cue.start_sector))
			token.scale = Vector2.ONE
			token.rotation = 0.0
			if cue.phase_id == "transit" and cue.moves_actor:
				token.play_animation("Idle", true)
		if target_token != null:
			target_token.position = _presentation_positions.get(cue.target_actor_id, _actor_position(cue.target_actor_id, cue.end_sector))
			target_token.scale = Vector2.ONE
			target_token.rotation = 0.0
		if cue.phase_id == "transit" and cue.vfx_id == "projectile":
			_end_projectile()
		_cue = null
		_cue_progress = 0.0
		scale = Vector2.ONE
		queue_redraw()


func _is_firearm_cue(cue: CombatPresentationCue) -> bool:
	return cue != null and cue.action_id in ["fire", "aimed_fire", "reload", "cycle", "clear_malfunction"]


func _path_position(path: Array[Vector2i], progress: float, start: Vector2i, finish: Vector2i, actor_id: String = "") -> Vector2:
	if path.size() < 2:
		return _actor_position(actor_id, start).lerp(_actor_position(actor_id, finish), progress)
	var scaled := clampf(progress, 0.0, 1.0) * float(path.size() - 1)
	var segment := mini(floori(scaled), path.size() - 2)
	var local_progress := scaled - float(segment)
	return _actor_position(actor_id, path[segment]).lerp(_actor_position(actor_id, path[segment + 1]), local_progress)


func sector_center(coords: Vector2i) -> Vector2:
	var rect := _grid_rect()
	var cell := _cell_size(rect)
	return rect.position + Vector2(
		(float(coords.x) + 0.5) * cell.x,
		(float(coords.y) + 0.5) * cell.y
	)


func _draw() -> void:
	var rect := _grid_rect()
	draw_rect(Rect2(Vector2.ZERO, size), VISUAL_PROFILE.arena_base_color, true)
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
		draw_texture_rect(texture, Rect2(Vector2.ZERO, size), false, VISUAL_PROFILE.backdrop_modulate)


func _draw_sector(data: Dictionary, rect: Rect2) -> void:
	var coords: Vector2i = data.get("coords", Vector2i.ZERO)
	var cell_rect := _sector_rect(coords, rect).grow(-GRID_GAP * 0.5)
	var ground := _texture(str(data.get("ground_asset", "")))
	var overlay := _texture(str(data.get("overlay_asset", "")))
	var tint := _surface_color(str(data.get("surface_id", "unresolved")))
	var scene_first := str(snapshot.get("presentation_style", "")) == "duel_lane"
	draw_rect(cell_rect, Color(tint, VISUAL_PROFILE.duel_surface_alpha) if scene_first else tint, true)
	if ground != null and not scene_first:
		draw_texture_rect(ground, cell_rect, false, Color(1, 1, 1, VISUAL_PROFILE.ground_texture_alpha))
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
		draw_rect(cell_rect, Color(0.62, 0.68, 0.64, VISUAL_PROFILE.grid_alpha), false, 1.0)


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
	_draw_offscreen_indicator(preview_quote.target_sector, color)
	if _contains(preview_quote.projected_origin):
		_draw_offscreen_indicator(preview_quote.projected_origin, Color("f0d487"))


func _draw_actors() -> void:
	# Actor presentation is owned by HumanoidTokenView and its overlays. Keeping
	# bars and facing in the arena's parent draw pass put them beneath token
	# children, which is how the old HUD managed to hide its own information.
	return


func _draw_vital_bar(origin: Vector2, width: float, value: float, color: Color) -> void:
	draw_rect(Rect2(origin, Vector2(width, 5.0)), Color(0.02, 0.025, 0.028, 0.92), true)
	draw_rect(Rect2(origin + Vector2.ONE, Vector2((width - 2.0) * clampf(value / GameEnums.SCALE_MAX, 0.0, 1.0), 3.0)), color, true)


func _draw_presentation() -> void:
	if _cue == null:
		return
	var start := sector_center(_cue.start_sector)
	var finish := sector_center(_cue.end_sector)
	if _cue.phase_id == "transit" and not _cue.vfx_id.is_empty() and _cue.vfx_id != "projectile":
		var point := start.lerp(finish, _cue_progress)
		draw_line(start, point, Color("f0d487"), 3.0, true)
		draw_circle(point, 4.0, Color.WHITE)
	elif _cue.phase_id == "contact" and _cue.action_id in ["fire", "aimed_fire"]:
		var muzzle := _projectile_start_for(_cue)
		var flash_radius := lerpf(2.0, 8.0, _cue_progress)
		draw_circle(muzzle, flash_radius, Color(1.0, 0.82, 0.36, _cue_progress))
		draw_circle(muzzle + Vector2(0.0, -4.0), lerpf(2.0, 7.0, _cue_progress), Color(0.72, 0.76, 0.72, 0.24 * _cue_progress), false, 2.0)
	elif _cue.phase_id == "impact" or (_cue.phase_id == "contact" and _cue.vfx_id != ""):
		var impact_color := Color("e7c56c") if _cue.outcome_tag in ["block", "shield_block", "cover", "cover_impact"] else Color("ef6f52")
		if _cue.outcome_tag == "miss":
			impact_color = Color("8ca4a1")
		draw_circle(finish, lerpf(8.0, 30.0, _cue_progress), Color(impact_color, 1.0 - _cue_progress), false, 4.0)
		if _cue.outcome_tag in ["object_collision", "actor_collision", "boundary"]:
			for index in range(5):
				var angle := float(index) * TAU / 5.0
				var debris := finish + Vector2.from_angle(angle) * lerpf(5.0, 24.0, _cue_progress)
				draw_rect(Rect2(debris - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), Color(0.68, 0.58, 0.43, 1.0 - _cue_progress), true)


func _play_cue_animation(token: HumanoidTokenView, cue: CombatPresentationCue) -> void:
	if token == null or not HumanoidVisualCatalog.supports_animation(cue.animation_id):
		return
	if HumanoidVisualCatalog.animation_loops(cue.animation_id):
		token.play_animation(cue.animation_id)
	else:
		token.play_timed_one_shot(cue.animation_id, "Idle", cue.duration_seconds)


func _begin_projectile(cue: CombatPresentationCue) -> void:
	_end_projectile()
	var start := _projectile_start_for(cue)
	var finish := _projectile_end_for(cue)
	var direction := start.direction_to(finish)
	if direction.length_squared() <= 0.001:
		direction = _facing_vector(cue.facing)
	if cue.outcome_tag == "miss":
		finish += direction * minf(30.0, _cell_size(_grid_rect()).x * 0.34)
	_projectile_start = start
	_projectile_end = finish
	_projectile_direction = direction.normalized()
	_projectile_trail = Line2D.new()
	_projectile_trail.name = "ProjectileTrail"
	_projectile_trail.z_index = 16
	_projectile_trail.width = PROJECTILE_TRAIL_WIDTH
	_projectile_trail.default_color = PROJECTILE_TRAIL_COLOR
	_projectile_trail.texture_mode = Line2D.LINE_TEXTURE_NONE
	_projectile_trail.antialiased = true
	_projectile_trail.points = PackedVector2Array([start, start])
	add_child(_projectile_trail)
	_projectile_sprite = Sprite2D.new()
	_projectile_sprite.name = "ProjectileBullet"
	_projectile_sprite.z_index = 17
	_projectile_sprite.texture = BULLET_TEXTURE
	_projectile_sprite.centered = true
	_projectile_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_projectile_sprite.position = start
	_projectile_sprite.rotation = _projectile_direction.angle()
	_projectile_sprite.scale = PROJECTILE_BULLET_SCALE
	_projectile_sprite.modulate = PROJECTILE_BULLET_COLOR
	add_child(_projectile_sprite)
	_projectile_active = true


func _projectile_start_for(cue: CombatPresentationCue) -> Vector2:
	var start := sector_center(cue.start_sector)
	var shooter := _actor_tokens.get(cue.actor_id) as HumanoidTokenView
	if shooter != null:
		return shooter.position + shooter.combat_weapon_muzzle_anchor(cue.weapon_id)
	var direction := _facing_vector(cue.facing)
	return start + Vector2(0.0, -10.0) + direction * 10.0


func _projectile_end_for(cue: CombatPresentationCue) -> Vector2:
	var finish := sector_center(cue.end_sector)
	var target := _actor_tokens.get(cue.target_actor_id) as HumanoidTokenView
	if target == null:
		return finish + Vector2(0.0, -10.0)
	var region := cue.target_body_region
	if region < 0:
		region = GameEnums.LimbRegion.UPPER_TORSO
	return target.position + target.combat_body_region_anchor(region)


func _update_projectile(progress: float) -> void:
	if not _projectile_active or not is_instance_valid(_projectile_sprite) or not is_instance_valid(_projectile_trail):
		return
	var eased := 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 1.35)
	var current := _projectile_start.lerp(_projectile_end, eased)
	_projectile_sprite.position = current
	_projectile_trail.points = _projectile_trace_points(
		_projectile_start,
		current,
		_projectile_direction
	)


func _end_projectile() -> void:
	_projectile_active = false
	if is_instance_valid(_projectile_trail):
		_projectile_trail.queue_free()
	if is_instance_valid(_projectile_sprite):
		_projectile_sprite.queue_free()
	_projectile_trail = null
	_projectile_sprite = null


func _projectile_trace_points(start: Vector2, current: Vector2, direction: Vector2) -> PackedVector2Array:
	var travelled := start.distance_to(current)
	if travelled <= 0.1 or direction.length_squared() <= 0.001:
		return PackedVector2Array([start, current])
	var tail_distance := minf(PROJECTILE_TRAIL_LENGTH, travelled)
	return PackedVector2Array([current - direction * tail_distance, current])


func _cue_has_blood(cue: CombatPresentationCue) -> bool:
	return cue.vfx_id in ["projectile", "melee_contact", "heavy_contact"] and cue.outcome_tag in [
		"hit", "wound", "damage", "collateral_hit"
	]


func _impact_position(cue: CombatPresentationCue) -> Vector2:
	if cue != null and not cue.target_actor_id.is_empty():
		var target := _actor_tokens.get(cue.target_actor_id) as HumanoidTokenView
		if target != null:
			var region := cue.target_body_region
			if region < 0:
				region = GameEnums.LimbRegion.UPPER_TORSO
			return target.position + target.combat_body_region_anchor(region)
	var sector := cue.target_end_sector if _contains(cue.target_end_sector) else cue.end_sector
	return sector_center(sector)


func _play_blood_vfx(impact_position: Vector2, cue: CombatPresentationCue) -> void:
	var variant := _blood_variant(cue)
	var frame_count := _blood_frame_count(variant)
	if frame_count <= 0:
		return
	while _blood_vfx.size() >= BLOOD_MAX_ACTIVE:
		var oldest: Dictionary = _blood_vfx.pop_front()
		var old_sprite := oldest.get("sprite") as Sprite2D
		if is_instance_valid(old_sprite):
			old_sprite.queue_free()
	var sprite := Sprite2D.new()
	sprite.name = "BloodImpact"
	sprite.z_index = 25
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = impact_position
	sprite.scale = Vector2.ONE * BLOOD_SCALE
	sprite.modulate = Color(1.0, 0.92, 0.90, 0.92)
	sprite.texture = _blood_texture(variant, 0)
	add_child(sprite)
	_blood_vfx.append({
		"sprite": sprite,
		"variant": variant,
		"frame_count": frame_count,
		"frame_index": 0,
		"elapsed": 0.0,
	})
	set_process(true)


func _blood_variant(cue: CombatPresentationCue) -> int:
	var variant_seed: int = int(abs(
		cue.start_sector.x * 31
		+ cue.start_sector.y * 17
		+ cue.end_sector.x * 13
		+ cue.end_sector.y * 7
		+ cue.target_actor_id.length()
	))
	return posmod(variant_seed, BLOOD_VARIANT_COUNT) + 1


func _blood_frame_count(variant: int) -> int:
	if _blood_frame_count_cache.has(variant):
		return int(_blood_frame_count_cache[variant])
	var count := 0
	while count < 64:
		var path := "res://Asset/VFX/BLOOD VFX/%d/1_%03d.png" % [variant, count]
		if not ResourceLoader.exists(path):
			break
		count += 1
	_blood_frame_count_cache[variant] = count
	return count


func _blood_texture(variant: int, frame_index: int) -> Texture2D:
	var key := "%d:%d" % [variant, frame_index]
	if _blood_texture_cache.has(key):
		return _blood_texture_cache[key] as Texture2D
	var path := "res://Asset/VFX/BLOOD VFX/%d/1_%03d.png" % [variant, frame_index]
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	_blood_texture_cache[key] = texture
	return texture


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


func _draw_facing(center: Vector2, facing: String, color: Color, length: float = 31.0) -> void:
	var direction: Vector2 = {"north": Vector2.UP, "east": Vector2.RIGHT, "south": Vector2.DOWN, "west": Vector2.LEFT}.get(facing, Vector2.RIGHT)
	draw_line(center, center + direction * length, color, minf(5.0, maxf(1.5, length * 0.18)), true)


func _actor_side(actor_id: String) -> String:
	for actor in get_meta("actor_snapshot", []):
		if str(actor.get("actor_id", "")) == actor_id:
			return str(actor.get("team_id", ""))
	return "player" if actor_id == "player" else "enemy"


func _sync_actor_tokens() -> void:
	if not is_node_ready():
		return
	var active_ids: Array[String] = []
	_actor_slot_offsets.clear()
	var tactics: Dictionary = snapshot.get("tactics", {})
	var facings: Dictionary = snapshot.get("facings", {})
	for sector in snapshot.get("sectors", []):
		var occupant_ids: Array = sector.get("occupant_ids", [])
		if occupant_ids.is_empty():
			var legacy_id := str(sector.get("occupant_id", ""))
			if not legacy_id.is_empty():
				occupant_ids = [legacy_id]
		for slot in range(occupant_ids.size()):
			var actor_id := str(occupant_ids[slot])
			if actor_id.is_empty():
				continue
			active_ids.append(actor_id)
			_actor_slot_offsets[actor_id] = _shared_sector_offset(slot, occupant_ids.size())
			var token := _actor_tokens.get(actor_id) as HumanoidTokenView
			if token == null:
				token = PresentationSceneRegistry.instantiate_scene(HUMANOID_TOKEN_SCENE) as HumanoidTokenView
				token.name = "Token_%s" % actor_id
				token.z_index = 10
				add_child(token)
				_actor_tokens[actor_id] = token
				_ensure_token_overlays(token)
			var slot_items: Dictionary = {}
			for item in _actor_snapshot(actor_id).get("items", []):
				if str(item.get("location", "")) == "equipped":
					slot_items[int(item.get("equipped_slot", GameEnums.EquipmentSlot.NONE))] = str(item.get("definition_id", ""))
			# Equipment is authoritative snapshot data and may change after reload,
			# disarm, strip, or a persistent inventory transfer.
			token.set_slot_item_ids(slot_items)
			token.visible = true
			token.modulate = VISUAL_PROFILE.token_modulate
			token.position = _actor_position(actor_id, sector.coords)
			var cell := _cell_size(_grid_rect())
			var display_scale := clampf(minf(cell.x, cell.y) / 96.0, 0.55, 1.5)
			token.set_display_scale(display_scale)
			token.face_direction(_facing_vector(str(facings.get(actor_id, "east"))))
			_configure_token_overlays(token, actor_id, sector.coords, display_scale, cell.x * 0.80)
			var posture := str(tactics.get(actor_id, {}).get("posture", "standing"))
			var idle := "CrouchIdle" if posture == "crouched" and HumanoidVisualCatalog.supports_animation("CrouchIdle") else "Idle"
			if _cue == null or _cue.actor_id != actor_id:
				token.play_animation(idle, false)
	for actor_id in _actor_tokens:
		var token := _actor_tokens[actor_id] as HumanoidTokenView
		if token != null:
			token.visible = str(actor_id) in active_ids


func _ensure_token_overlays(token: HumanoidTokenView) -> void:
	if token.get_meta("combat_overlays_ready", false):
		return
	var ground := TOKEN_OVERLAY_SCRIPT.new() as CombatTokenOverlay
	ground.name = "GroundFootprint"
	ground.mode = CombatTokenOverlay.Mode.GROUND
	ground.z_index = -20
	token.add_child(ground)
	var top := TOKEN_OVERLAY_SCRIPT.new() as CombatTokenOverlay
	top.name = "CombatTopOverlay"
	top.mode = CombatTokenOverlay.Mode.TOP
	top.z_index = 40
	token.add_child(top)
	token.set_meta("combat_ground_overlay", ground)
	token.set_meta("combat_top_overlay", top)
	token.set_meta("combat_overlays_ready", true)


func _configure_token_overlays(
	token: HumanoidTokenView,
	actor_id: String,
	coords: Vector2i,
	display_scale: float,
	footprint_width: float
) -> void:
	var actor := _actor_snapshot(actor_id)
	var side := _actor_side(actor_id)
	var color := Color("67a7c8") if side == "player" else Color("c76c5b")
	var threat_ids: Array = preview_quote.reaction_threat_ids if preview_quote != null else []
	var ground := token.get_meta("combat_ground_overlay", null) as CombatTokenOverlay
	if ground != null:
		ground.configure_ground(
			actor,
			color,
			coords == selected_sector,
			str(snapshot.get("active_actor_id", "")) == actor_id,
			actor_id in threat_ids,
			str(snapshot.get("facings", {}).get(actor_id, "east")),
			maxf(34.0, footprint_width),
			display_scale
		)
	var top := token.get_meta("combat_top_overlay", null) as CombatTokenOverlay
	if top != null:
		top.configure_top(
			actor,
			maxf(34.0, footprint_width),
			display_scale,
			token.combat_head_top_anchor(),
			str(snapshot.get("facings", {}).get(actor_id, "east"))
		)
		if _sequence_weapon_cue != null and _sequence_weapon_cue.actor_id == actor_id:
			top.set_weapon_cue(_sequence_weapon_cue, _sequence_progress_for_current_cue())
		else:
			top.set_weapon_cue(null)


func _sequence_progress_for_current_cue() -> float:
	if _cue == null:
		return 0.0
	return lerpf(_cue.sequence_progress_start, _cue.sequence_progress_end, _cue_progress)


func _actor_snapshot(actor_id: String) -> Dictionary:
	for actor in get_meta("actor_snapshot", []):
		if str(actor.get("actor_id", "")) == actor_id:
			return actor
	return {}


func _shared_sector_offset(slot: int, count: int) -> Vector2:
	if count <= 1:
		return Vector2.ZERO
	var cell := _cell_size(_grid_rect())
	var spacing := minf(cell.x, cell.y) * 0.24
	return Vector2((float(slot) - float(count - 1) * 0.5) * spacing, 0.0)


func _actor_position(actor_id: String, coords: Vector2i) -> Vector2:
	return sector_center(coords) + _actor_slot_offsets.get(actor_id, Vector2.ZERO)


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
		var lane_width := maxi(1, _arena_width())
		var logical_cell_width := clampf(rect.size.x / float(lane_width), 64.0, 112.0)
		var logical_width := logical_cell_width * float(lane_width)
		if rect.size.x < logical_width:
			rect.size.x = logical_width
			rect.position.x = available.get_center().x - rect.size.x * 0.5
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
	var base := _base_grid_rect()
	var viewport_size := _camera_safe_rect.size if _camera_safe_rect.size.x > 0.0 else size
	var allowance := (base.size * _view_zoom - viewport_size) * 0.5
	allowance.x = maxf(0.0, allowance.x)
	allowance.y = maxf(0.0, allowance.y)
	_view_pan.x = clampf(_view_pan.x, -allowance.x, allowance.x)
	_view_pan.y = clampf(_view_pan.y, -allowance.y, allowance.y)


func _focus_camera_on(coords: Vector2i) -> void:
	if str(snapshot.get("presentation_style", "")) != "duel_lane" or not _contains(coords):
		return
	var base := _base_grid_rect()
	var cell := _cell_size(base)
	var point := base.position + Vector2((float(coords.x) + 0.5) * cell.x, (float(coords.y) + 0.5) * cell.y)
	var viewport_center := _camera_safe_rect.get_center() if _camera_safe_rect.size.x > 0.0 else size * 0.5
	_view_pan = viewport_center - point
	_clamp_camera_pan()


func _draw_offscreen_indicator(coords: Vector2i, color: Color) -> void:
	if not _contains(coords):
		return
	var point := sector_center(coords)
	var bounds := Rect2(Vector2(18.0, 18.0), size - Vector2(36.0, 36.0))
	if bounds.has_point(point):
		return
	var edge := Vector2(clampf(point.x, bounds.position.x, bounds.end.x), clampf(point.y, bounds.position.y, bounds.end.y))
	draw_circle(edge, 7.0, Color(0.04, 0.05, 0.05, 0.9))
	draw_circle(edge, 5.0, color)


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
			cursor = Vector2i(floori(float(_arena_width()) / 2.0), floori(float(_arena_height()) / 2.0))
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
		var ids: Array = sector.get("occupant_ids", [])
		if ids.is_empty() and not str(sector.get("occupant_id", "")).is_empty():
			ids = [str(sector.get("occupant_id", ""))]
		if actor_id in ids:
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
