extends RefCounted
class_name CombatBodyStatusPresenter

## Limb bars, condition tokens, and portrait sync extracted from CombatLaneHUD.

const BODY_BAR_SIZE := Vector2(150.0, 10.0)
const BODY_BAR_GAP := 8.0
const BODY_LIMB_ORDER := ["HD", "UT", "LT", "LA", "RA", "LL", "RL"]
const COLOR_ACTION_BORDER := Color(0.73, 0.62, 0.45, 0.88)
const COLOR_BODY_BAR_BACK := Color(0.08, 0.04, 0.035, 0.86)
const COLOR_BODY_BAR_HEALTH := Color(0.72, 0.18, 0.18, 0.92)
const COLOR_BODY_BAR_DAMAGED := Color(0.88, 0.46, 0.16, 0.94)
const COLOR_BODY_BAR_CRITICAL := Color(0.86, 0.08, 0.12, 0.98)
const CONDITION_ANIMATION_FPS := 0.0

var player_status_rows: Array[Dictionary] = []
var enemy_status_rows: Array[Dictionary] = []

var _camera: Camera2D
var _player_command_rail: Node2D
var _enemy_status_rail: Node2D
var _player_status_label: Label
var _enemy_status_label: Label
var _player_condition_sprite: Sprite2D
var _enemy_condition_sprite: Sprite2D
var _player_portrait_model: PaperDollModel
var _enemy_portrait_model: PaperDollModel
var _player_actor_hud: CombatActorFloatHUD
var _enemy_actor_hud: CombatActorFloatHUD

var _hud_density_scale := 1.0
var _targeted_limb := -1
var _snapshot: Dictionary = {}
var _condition_animation_time := 0.0
var _player_condition_state: Dictionary = {}
var _enemy_condition_state: Dictionary = {}

var _player_portrait_rect := Rect2()
var _enemy_portrait_rect := Rect2()
var _player_command_rect := Rect2()
var _enemy_status_rect := Rect2()


func configure(
	camera: Camera2D,
	player_command_rail: Node2D,
	enemy_status_rail: Node2D,
	player_status_label: Label,
	enemy_status_label: Label,
	player_condition_sprite: Sprite2D,
	enemy_condition_sprite: Sprite2D,
	player_portrait_model: PaperDollModel,
	enemy_portrait_model: PaperDollModel,
	player_actor_hud: CombatActorFloatHUD = null,
	enemy_actor_hud: CombatActorFloatHUD = null
) -> void:
	_camera = camera
	_player_command_rail = player_command_rail
	_enemy_status_rail = enemy_status_rail
	_player_status_label = player_status_label
	_enemy_status_label = enemy_status_label
	_player_condition_sprite = player_condition_sprite
	_enemy_condition_sprite = enemy_condition_sprite
	_player_portrait_model = player_portrait_model
	_enemy_portrait_model = enemy_portrait_model
	_player_actor_hud = player_actor_hud
	_enemy_actor_hud = enemy_actor_hud


func collect_limb_rows() -> void:
	player_status_rows = _collect_limb_rows(_player_command_rail)
	enemy_status_rows = _collect_limb_rows(_enemy_status_rail)


func set_density_scale(density: float) -> void:
	_hud_density_scale = density


func set_targeted_limb(limb: int) -> void:
	_targeted_limb = limb


func set_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot


func set_layout_rects(
	player_command_rect: Rect2,
	enemy_status_rect: Rect2,
	player_portrait_rect: Rect2,
	enemy_portrait_rect: Rect2
) -> void:
	_player_command_rect = player_command_rect
	_enemy_status_rect = enemy_status_rect
	_player_portrait_rect = player_portrait_rect
	_enemy_portrait_rect = enemy_portrait_rect


func layout_panels(viewport_size: Vector2, ui_scale: Vector2) -> void:
	_layout_body_status_panel(
		_player_command_rail,
		_player_status_label,
		player_status_rows,
		_player_command_rect,
		_snapshot.get("player", {}),
		"YOU",
		viewport_size,
		ui_scale
	)
	_layout_body_status_panel(
		_enemy_status_rail,
		_enemy_status_label,
		enemy_status_rows,
		_enemy_status_rect,
		_snapshot.get("enemy", {}),
		"HOSTILE",
		viewport_size,
		ui_scale
	)
	_layout_condition_token(
		_player_condition_sprite,
		_player_portrait_rect,
		_snapshot.get("player", {}),
		viewport_size,
		ui_scale
	)
	_layout_condition_token(
		_enemy_condition_sprite,
		_enemy_portrait_rect,
		_snapshot.get("enemy", {}),
		viewport_size,
		ui_scale
	)


func update_condition_animations(delta: float) -> void:
	if _snapshot.is_empty():
		return
	if CONDITION_ANIMATION_FPS <= 0.0:
		return
	_condition_animation_time = fmod(
		_condition_animation_time + delta,
		120.0
	)
	_apply_condition_frame(_player_condition_sprite, _snapshot.get("player", {}))
	_apply_condition_frame(_enemy_condition_sprite, _snapshot.get("enemy", {}))


func sync_actor_huds(viewport_size: Vector2) -> void:
	if _snapshot.is_empty():
		return
	if _player_actor_hud:
		_player_actor_hud.visible = false
	if _enemy_actor_hud:
		_enemy_actor_hud.visible = false
	sync_duel_portraits(viewport_size)


func sync_duel_portraits(viewport_size: Vector2) -> void:
	if _snapshot.is_empty() or _player_portrait_model == null:
		if _player_portrait_model:
			_player_portrait_model.visible = false
		if _enemy_portrait_model:
			_enemy_portrait_model.visible = false
		return
	var ui_scale := Vector2.ONE / CombatHudGeometry.camera_zoom_value(_camera)
	_sync_portrait_model(
		_player_portrait_model,
		_snapshot.get("player", {}),
		_player_portrait_rect,
		true,
		viewport_size,
		ui_scale
	)
	_sync_portrait_model(
		_enemy_portrait_model,
		_snapshot.get("enemy", {}),
		_enemy_portrait_rect,
		false,
		viewport_size,
		ui_scale
	)


func limb_code(limb: int) -> String:
	return _limb_code(limb)


func _layout_body_status_panel(
	root: Node2D,
	title_label: Label,
	rows: Array[Dictionary],
	rect: Rect2,
	data: Dictionary,
	heading: String,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	if root == null:
		return
	root.global_position = CombatHudGeometry.screen_to_world(
		_camera,
		rect.position,
		viewport_size
	)
	root.scale = ui_scale * _hud_density_scale
	root.visible = not data.is_empty()
	if not root.visible:
		return
	if title_label:
		title_label.position = Vector2.ZERO
		title_label.text = _body_status_title(data, heading)
	var limbs: Array = data.get("limbs", [])
	var row_y := 45.0
	for index in range(rows.size()):
		var row := rows[index]
		var limb: Dictionary = limbs[index] if index < limbs.size() else {}
		_layout_limb_row(row, limb, Vector2(0.0, row_y))
		row_y += BODY_BAR_SIZE.y + BODY_BAR_GAP


func _layout_limb_row(row: Dictionary, limb: Dictionary, row_position: Vector2) -> void:
	var root := row.get("root") as Node2D
	var track := row.get("track") as Polygon2D
	var fill := row.get("fill") as Polygon2D
	var meter_frame := row.get("meter_frame") as Sprite2D
	var outline := row.get("outline") as Line2D
	var label := row.get("label") as Label
	if root == null or track == null or fill == null or outline == null or label == null:
		return
	root.position = row_position
	var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
	var current := clampf(float(limb.get("current", 0.0)), 0.0, maximum)
	var ratio := current / maximum
	var trauma := str(limb.get("trauma", "NONE"))
	var code := str(limb.get("code", row.get("code", "??")))
	var trauma_text := ""
	if trauma != "NONE":
		trauma_text = " " + trauma.replace("_", " ")
	CombatHudGeometry.set_box(track, BODY_BAR_SIZE)
	CombatHudGeometry.set_box(
		fill,
		Vector2(maxf(2.0, BODY_BAR_SIZE.x * ratio), BODY_BAR_SIZE.y)
	)
	CombatHudGeometry.set_outline(outline, BODY_BAR_SIZE)
	fill.color = _limb_bar_color(ratio, trauma)
	var is_targeted: bool = _targeted_limb >= 0 and code == _limb_code(_targeted_limb)
	CombatHudGeometry.layout_meter_frame(
		meter_frame,
		BODY_BAR_SIZE,
		HUDAssetLibrary.COLOR_CAUTION if is_targeted else Color(0.86, 0.82, 0.72, 0.68)
	)
	outline.default_color = (
		HUDAssetLibrary.COLOR_CAUTION
		if is_targeted
		else Color(COLOR_ACTION_BORDER, 0.52)
	)
	outline.width = 2.0 if is_targeted else 1.0
	label.text = "%s %s/%s%s" % [
		code,
		CombatHudGeometry.compact_number(current),
		CombatHudGeometry.compact_number(maximum),
		trauma_text,
	]



func _layout_condition_token(
	sprite: Sprite2D,
	rect: Rect2,
	data: Dictionary,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	if sprite == null:
		return
	sprite.visible = not data.is_empty()
	if not sprite.visible:
		return
	sprite.global_position = CombatHudGeometry.screen_to_world(
		_camera,
		rect.position
			+ Vector2(
				rect.size.x - 20.0 * _hud_density_scale,
				20.0 * _hud_density_scale
			),
		viewport_size
	)
	sprite.scale = ui_scale * 1.55 * _hud_density_scale
	sprite.z_index = 54
	_apply_condition_frame(sprite, data)


func _apply_condition_frame(sprite: Sprite2D, data: Dictionary) -> void:
	if sprite == null or data.is_empty():
		if sprite != null:
			sprite.visible = false
		return
	var condition := _condition_state_for(data)
	var state := _condition_state_for_sprite(sprite)
	var texture: Texture2D = state.get("texture", null) as Texture2D
	var condition_changed := str(state.get("condition", "")) != condition
	if condition_changed or texture == null:
		texture = HUDAssetLibrary.condition_icon(condition)
		state = {
			"condition": condition,
			"texture": texture,
		}
		_set_condition_state_for_sprite(sprite, state)
	if texture == null:
		sprite.visible = false
		return
	if sprite.texture != texture:
		sprite.texture = texture
	sprite.visible = true
	sprite.region_enabled = false


func _condition_state_for_sprite(sprite: Sprite2D) -> Dictionary:
	if sprite == _enemy_condition_sprite:
		return _enemy_condition_state
	return _player_condition_state


func _set_condition_state_for_sprite(sprite: Sprite2D, state: Dictionary) -> void:
	if sprite == _enemy_condition_sprite:
		_enemy_condition_state = state
	else:
		_player_condition_state = state


func _condition_state_for(data: Dictionary) -> String:
	if bool(data.get("stance_recovery_guard", false)):
		return "healing"
	var blood_ratio := clampf(
		float(data.get("blood", GameEnums.SCALE_MAX)) / GameEnums.SCALE_MAX,
		0.0,
		1.0
	)
	var has_bleeding := false
	var has_serious_trauma := false
	var worst_limb_ratio := 1.0
	for limb in data.get("limbs", []):
		var limb_data: Dictionary = limb
		var maximum := maxf(1.0, float(limb_data.get("maximum", 1.0)))
		var current := clampf(float(limb_data.get("current", maximum)), 0.0, maximum)
		worst_limb_ratio = minf(worst_limb_ratio, current / maximum)
		var trauma := str(limb_data.get("trauma", "NONE"))
		if trauma == "BLEEDING":
			has_bleeding = true
		if trauma in ["SHATTERED_LIMB", "ORGAN_FAILURE", "BURNT"]:
			has_serious_trauma = true
	if blood_ratio <= 0.35 or worst_limb_ratio <= 0.25 or has_serious_trauma:
		return "danger"
	if has_bleeding:
		return "precaution_o"
	if blood_ratio <= 0.75 or worst_limb_ratio <= 0.70:
		return "precaution_y"
	return "fine"


func _body_status_title(data: Dictionary, heading: String) -> String:
	var active := " ACTIVE" if data.get("is_active", false) else ""
	var guard := " GUARD" if data.get("stance_recovery_guard", false) else ""
	return "%s%s // BLOOD %04.1f\nSTANCE %02d %s%s" % [
		heading,
		active,
		float(data.get("blood", 0.0)),
		int(data.get("stance", 0)),
		str(data.get("stance_state", "UNKNOWN")),
		guard,
	]


func _limb_bar_color(ratio: float, trauma: String) -> Color:
	if ratio <= 0.0 or trauma == "SHATTERED_LIMB":
		return Color(0.42, 0.05, 0.08, 0.98)
	if trauma != "NONE" or ratio <= 0.35:
		return COLOR_BODY_BAR_CRITICAL
	if ratio <= 0.7:
		return COLOR_BODY_BAR_DAMAGED
	return COLOR_BODY_BAR_HEALTH


func _limb_code(limb: int) -> String:
	match limb:
		GameEnums.LimbRegion.HEAD:
			return "HD"
		GameEnums.LimbRegion.UPPER_TORSO:
			return "UT"
		GameEnums.LimbRegion.LOWER_TORSO:
			return "LT"
		GameEnums.LimbRegion.LEFT_ARM:
			return "LA"
		GameEnums.LimbRegion.RIGHT_ARM:
			return "RA"
		GameEnums.LimbRegion.LEFT_LEG:
			return "LL"
		GameEnums.LimbRegion.RIGHT_LEG:
			return "RL"
	return "??"


func _collect_limb_rows(parent: Node) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if parent == null:
		return rows
	for code in BODY_LIMB_ORDER:
		var row_root := parent.get_node_or_null("%sRow" % code) as Node2D
		if row_root == null:
			push_warning(
				"CombatBodyStatusPresenter missing limb row %s under %s."
				% [code, parent.name]
			)
			continue
		var track := row_root.get_node("Track") as Polygon2D
		var fill := row_root.get_node("Fill") as Polygon2D
		var meter_frame := row_root.get_node("OfficialMeterFrame") as Sprite2D
		var outline := row_root.get_node("Outline") as Line2D
		var label := row_root.get_node("Label") as Label
		track.color = COLOR_BODY_BAR_BACK
		fill.color = COLOR_BODY_BAR_HEALTH
		meter_frame.texture = HUDAssetLibrary.meter_frame_texture("segmented")
		outline.default_color = Color(COLOR_ACTION_BORDER, 0.52)
		outline.width = 1.0
		rows.append({
			"code": code,
			"root": row_root,
			"track": track,
			"fill": fill,
			"meter_frame": meter_frame,
			"outline": outline,
			"label": label,
		})
	return rows


func _sync_portrait_model(
	model: PaperDollModel,
	data: Dictionary,
	rect: Rect2,
	is_player: bool,
	viewport_size: Vector2,
	ui_scale: Vector2
) -> void:
	if model == null:
		return
	model.visible = not data.is_empty()
	if not model.visible:
		return
	var model_size := rect.size * 2.18
	model.set_anchors_preset(Control.PRESET_TOP_LEFT)
	model.size = model_size
	model.clip_contents = true
	model.scale = (
		ui_scale * Vector2(-1.0, 1.0)
		if not is_player
		else ui_scale
	)
	var paperdoll_origin := Vector2(
		rect.position.x + rect.size.x * 0.5 - model_size.x * 0.5,
		rect.position.y + rect.size.y * 0.54 - model_size.y * 0.5
	)
	paperdoll_origin.x += rect.size.x * (0.10 if is_player else -0.10)
	if not is_player:
		paperdoll_origin.x += model_size.x
	model.global_position = CombatHudGeometry.screen_to_world(
		_camera,
		paperdoll_origin,
		viewport_size
	)
	model.update_model(data.get("equipment", []))
	model.update_wounds(data.get("limbs", []))
