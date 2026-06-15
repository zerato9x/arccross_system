extends Control
class_name CombatLaneView

const CYAN := Color(0.28, 0.95, 0.88)
const CYAN_DIM := Color(0.08, 0.34, 0.32)
const CRIMSON := Color(1.0, 0.25, 0.34)
const CRIMSON_DIM := Color(0.38, 0.06, 0.09)
const AMBER := Color(1.0, 0.68, 0.25)
const MUTED := Color(0.34, 0.58, 0.55)
const VOID := Color(0.006, 0.018, 0.02, 0.98)
const LANE_MOVE_DURATION_SECONDS := 0.4

var _snapshot: Dictionary = {}
var _font: SystemFont
var _showing_melee_lock := false
var _last_player_lane := -1
var _last_enemy_lane := -1
var _player_move_tween: Tween
var _enemy_move_tween: Tween
var _player_uses_right_swing := true
var _enemy_uses_right_swing := true
var _player_uses_right_strafe := true
var _enemy_uses_right_strafe := true
@onready var _player_token: HumanoidTokenView = $PlayerHumanoidToken
@onready var _enemy_token: HumanoidTokenView = $EnemyHumanoidToken

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(620.0, 290.0)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	resized.connect(_on_resized)

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_showing_melee_lock = _find_lock_slot() >= 0
	_sync_tokens()
	queue_redraw()

func show_presentation_event(event: Dictionary) -> void:
	var side := str(event.get("side", ""))
	var token := _token_for_side(side)
	var data: Dictionary = _snapshot.get(side, {})
	if token == null or data.is_empty():
		return

	match str(event.get("type", "")):
		"death":
			token.play_animation("Die")
		"damage":
			if not data.get("is_dead", false):
				token.play_one_shot("TakeDamage", _token_pose(data))
		"action":
			var animation := _animation_for_action(
				side,
				int(event.get("action", -1))
			)
			if not animation.is_empty():
				token.play_one_shot(animation, _token_pose(data))

func is_showing_melee_lock() -> bool:
	return _showing_melee_lock

func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, VOID, true)
	draw_rect(frame.grow(-1.0), Color(MUTED, 0.65), false, 2.0)
	_draw_scanlines(frame)

	if _snapshot.is_empty():
		_player_token.visible = false
		_enemy_token.visible = false
		_draw_centered("NO TACTICAL FEED", size.y * 0.52, 20, MUTED)
		return

	if _showing_melee_lock:
		_draw_melee_lock()
	else:
		_draw_corridor()

func _draw_corridor() -> void:
	var slots: Array = _snapshot.get("lane_slots", [])
	if slots.size() != 12:
		_draw_centered("LANE RECORD INVALID", size.y * 0.52, 20, CRIMSON)
		return

	_draw_centered("12-SLOT ENGAGEMENT CORRIDOR", 30.0, 15, MUTED)
	var left := 24.0
	var right := size.x - 24.0
	var center_y := size.y * 0.56
	var cell_width := (right - left) / 12.0

	draw_line(
		Vector2(left, center_y),
		Vector2(right, center_y),
		Color(MUTED, 0.22),
		1.0
	)

	for index in range(12):
		var descriptor: Dictionary = slots[index]
		var x0 := left + cell_width * index
		var x1 := x0 + cell_width
		var edge_factor_0: float = absf(
			(float(index) / 11.0) - 0.5
		) * 2.0
		var edge_factor_1: float = absf(
			(float(index + 1) / 11.0) - 0.5
		) * 2.0
		var half_0 := lerpf(size.y * 0.19, size.y * 0.34, edge_factor_0)
		var half_1 := lerpf(size.y * 0.19, size.y * 0.34, edge_factor_1)
		var polygon := PackedVector2Array([
			Vector2(x0, center_y - half_0),
			Vector2(x1, center_y - half_1),
			Vector2(x1, center_y + half_1),
			Vector2(x0, center_y + half_0),
		])

		var fill := _slot_fill(descriptor)
		draw_colored_polygon(polygon, fill)
		draw_polyline(
			PackedVector2Array([
				polygon[0],
				polygon[1],
				polygon[2],
				polygon[3],
				polygon[0],
			]),
			_slot_border(descriptor),
			2.0
		)

		var label_y := minf(polygon[0].y, polygon[1].y) - 9.0
		_draw_text(
			"%02d" % index,
			Vector2(x0, label_y),
			cell_width,
			13,
			MUTED,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_draw_slot_contents(descriptor, x0, x1, center_y)

func _draw_slot_contents(
	descriptor: Dictionary,
	x0: float,
	x1: float,
	center_y: float
) -> void:
	var width := x1 - x0
	if descriptor.get("is_escape", false):
		_draw_text(
			"EX",
			Vector2(x0, center_y + size.y * 0.23),
			width,
			13,
			AMBER,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	var terrain := _terrain_glyph(descriptor)
	if not terrain.is_empty():
		_draw_text(
			terrain,
			Vector2(x0, center_y + size.y * 0.12),
			width,
			16,
			AMBER,
			HORIZONTAL_ALIGNMENT_CENTER
		)

	var occupants: Array = descriptor.get("occupants", [])
	if occupants.is_empty():
		return

	var marker_y := center_y - 23.0
	if occupants.size() == 1:
		_draw_occupant(occupants[0], x0 + width * 0.5, marker_y)
		return

	_draw_occupant(occupants[0], x0 + width * 0.32, marker_y)
	_draw_occupant(occupants[1], x0 + width * 0.68, marker_y)

func _draw_occupant(data: Dictionary, center_x: float, top: float) -> void:
	var side := str(data.get("side", "other"))
	var color := CYAN if side == "player" else CRIMSON
	var marker := "P" if side == "player" else "E"
	var rect := Rect2(Vector2(center_x - 15.0, top), Vector2(30.0, 36.0))
	draw_rect(rect, Color(color.r, color.g, color.b, 0.16), true)
	draw_rect(rect, color, false, 2.0 if data.get("is_active", false) else 1.0)
	_draw_text(
		marker,
		Vector2(rect.position.x, rect.position.y + 19.0),
		rect.size.x,
		11,
		color,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	if data.get("is_active", false):
		draw_line(
			Vector2(rect.position.x, rect.end.y + 4.0),
			Vector2(rect.end.x, rect.end.y + 4.0),
			color,
			3.0
		)

func _draw_melee_lock() -> void:
	var lock_slot := _find_lock_slot()
	var player: Dictionary = _snapshot.get("player", {})
	var enemy: Dictionary = _snapshot.get("enemy", {})

	draw_rect(
		Rect2(Vector2(28.0, 34.0), size - Vector2(56.0, 68.0)),
		Color(0.025, 0.055, 0.045, 0.88),
		true
	)
	draw_rect(
		Rect2(Vector2(28.0, 34.0), size - Vector2(56.0, 68.0)),
		AMBER,
		false,
		2.0
	)
	_draw_centered("MELEE LOCK ACTIVE", 68.0, 28, CYAN)
	_draw_centered("STANCE STRUGGLE // SLOT %02d" % lock_slot, 99.0, 17, AMBER)

	var mid_x := size.x * 0.5
	draw_line(
		Vector2(mid_x, 122.0),
		Vector2(mid_x, size.y - 54.0),
		Color(AMBER, 0.45),
		1.0
	)

	_draw_lock_combatant(
		player,
		Rect2(48.0, 126.0, mid_x - 70.0, size.y - 194.0),
		"P",
		CYAN
	)
	_draw_lock_combatant(
		enemy,
		Rect2(mid_x + 22.0, 126.0, size.x - mid_x - 70.0, size.y - 194.0),
		"E",
		CRIMSON
	)
	_draw_centered("<<  LOCK  >>", size.y - 48.0, 20, AMBER)

func _draw_lock_combatant(
	data: Dictionary,
	rect: Rect2,
	marker: String,
	color: Color
) -> void:
	draw_rect(rect, Color(color.r, color.g, color.b, 0.07), true)
	draw_rect(rect, Color(color, 0.7), false, 1.0)
	_draw_text(
		marker,
		rect.position + Vector2(8.0, 16.0),
		28.0,
		18,
		color
	)
	_draw_text(
		str(data.get("archetype", data.get("name", "UNKNOWN"))).to_upper(),
		Vector2(rect.position.x, rect.end.y - 70.0),
		rect.size.x,
		15,
		color
	)
	_draw_text(
		"STANCE %02d/12  %s" % [
			int(data.get("stance", 0)),
			str(data.get("stance_state", "UNKNOWN")),
		],
		Vector2(rect.position.x, rect.end.y - 45.0),
		rect.size.x,
		14,
		AMBER
	)
	_draw_text(
		"BLOOD %04.1f  AP-R %02d" % [
			float(data.get("blood", 0.0)),
			int(data.get("reserved_ap", 0)),
		],
		Vector2(rect.position.x, rect.end.y - 20.0),
		rect.size.x,
		14,
		color
	)
	if data.get("is_active", false):
		_draw_text(
			"ACTIVE",
			rect.position + Vector2(rect.size.x - 70.0, 16.0),
			62.0,
			15,
			color
		)

func _slot_fill(descriptor: Dictionary) -> Color:
	var occupants: Array = descriptor.get("occupants", [])
	if occupants.is_empty():
		if descriptor.get("is_escape", false):
			return Color(AMBER.r, AMBER.g, AMBER.b, 0.07)
		return Color(0.02, 0.075, 0.07, 0.42)

	var has_player := false
	var has_enemy := false
	for occupant in occupants:
		has_player = has_player or occupant.get("side", "") == "player"
		has_enemy = has_enemy or occupant.get("side", "") == "enemy"
	if has_player and has_enemy:
		return Color(AMBER.r, AMBER.g, AMBER.b, 0.16)
	if has_player:
		return Color(CYAN_DIM, 0.8)
	if has_enemy:
		return Color(CRIMSON_DIM, 0.8)
	return Color(0.08, 0.08, 0.08, 0.7)

func _slot_border(descriptor: Dictionary) -> Color:
	if descriptor.get("is_melee_locked", false):
		return AMBER
	var occupants: Array = descriptor.get("occupants", [])
	for occupant in occupants:
		if occupant.get("is_active", false):
			return CYAN if occupant.get("side", "") == "player" else CRIMSON
	return Color(MUTED, 0.78)

func _terrain_glyph(descriptor: Dictionary) -> String:
	var cover := str(descriptor.get("cover", "NONE"))
	match cover:
		"COVER":
			return "#"
		"OBSTACLE":
			return "X"
		"TRAP":
			return "^"
	var background := str(descriptor.get("background", "NONE"))
	match background:
		"TREES":
			return "T"
		"MUD":
			return "~"
	return ""

func _find_lock_slot() -> int:
	for descriptor in _snapshot.get("lane_slots", []):
		if descriptor.get("is_melee_locked", false):
			return int(descriptor.get("index", -1))
	return -1

func _sync_tokens() -> void:
	if _snapshot.is_empty():
		_player_token.visible = false
		_enemy_token.visible = false
		return

	_sync_token(
		_player_token,
		_snapshot.get("player", {}),
		true
	)
	_sync_token(
		_enemy_token,
		_snapshot.get("enemy", {}),
		false
	)
	_layout_tokens()

func _sync_token(
	token: HumanoidTokenView,
	data: Dictionary,
	is_player: bool
) -> void:
	token.visible = not data.is_empty()
	if not token.visible:
		return

	token.set_appearance(data.get(
		"appearance",
		HumanoidVisualCatalog.appearance_from_slot_item_ids({})
	))
	token.set_direction_row(
		HumanoidVisualCatalog.DIRECTION_RIGHT
		if is_player
		else HumanoidVisualCatalog.DIRECTION_LEFT
	)
	var pose := _token_pose(data)
	if data.get("is_dead", false):
		token.play_animation("Die", false)
	elif token.is_playing_one_shot():
		token.set_return_animation(pose)
	elif not _token_is_moving(is_player):
		token.play_animation(pose, false)

func _layout_tokens() -> void:
	if not _player_token or not _enemy_token:
		return
	if _snapshot.is_empty():
		return

	if _showing_melee_lock:
		_player_token.set_display_scale(2.0)
		_enemy_token.set_display_scale(2.0)
		_move_or_place_token(
			_player_token,
			Vector2(size.x * 0.27, size.y * 0.43),
			int(_snapshot.get("player", {}).get("lane", -1)),
			true
		)
		_move_or_place_token(
			_enemy_token,
			Vector2(size.x * 0.73, size.y * 0.43),
			int(_snapshot.get("enemy", {}).get("lane", -1)),
			false
		)
		_store_current_lanes()
		return

	var left := 24.0
	var right := size.x - 24.0
	var center_y := size.y * 0.56
	var cell_width := (right - left) / 12.0
	var player_lane := int(_snapshot.get("player", {}).get("lane", -1))
	var enemy_lane := int(_snapshot.get("enemy", {}).get("lane", -1))
	var shared_lane := player_lane >= 0 and player_lane == enemy_lane

	_player_token.set_display_scale(1.25)
	_enemy_token.set_display_scale(1.25)
	if player_lane >= 0:
		_move_or_place_token(
			_player_token,
			Vector2(
			left + cell_width * (float(player_lane) + 0.5)
				- (8.0 if shared_lane else 0.0),
			center_y - 10.0
			),
			player_lane,
			true
		)
	if enemy_lane >= 0:
		_move_or_place_token(
			_enemy_token,
			Vector2(
			left + cell_width * (float(enemy_lane) + 0.5)
				+ (8.0 if shared_lane else 0.0),
			center_y - 10.0
			),
			enemy_lane,
			false
		)
	_store_current_lanes()

func _move_or_place_token(
	token: HumanoidTokenView,
	target: Vector2,
	lane: int,
	is_player: bool
) -> void:
	var previous_lane := (
		_last_player_lane if is_player else _last_enemy_lane
	)
	if previous_lane < 0 or previous_lane == lane:
		if not _token_is_moving(is_player):
			token.position = target
		return

	var active_tween := (
		_player_move_tween if is_player else _enemy_move_tween
	)
	if active_tween and active_tween.is_valid():
		active_tween.kill()

	var side := "player" if is_player else "enemy"
	var opponent_side := "enemy" if is_player else "player"
	var data: Dictionary = _snapshot.get(side, {})
	var opponent_lane := int(
		_snapshot.get(opponent_side, {}).get("lane", -1)
	)
	token.play_animation(
		_movement_animation(
			data,
			previous_lane,
			lane,
			opponent_lane
		)
	)
	var tween := create_tween()
	tween.tween_property(
		token,
		"position",
		target,
		LANE_MOVE_DURATION_SECONDS
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_finish_token_move.bind(is_player))
	if is_player:
		_player_move_tween = tween
	else:
		_enemy_move_tween = tween

func _finish_token_move(is_player: bool) -> void:
	var token := _player_token if is_player else _enemy_token
	var side := "player" if is_player else "enemy"
	var data: Dictionary = _snapshot.get(side, {})
	var pose := _token_pose(data)
	if (
		not data.get("is_dead", false)
		and not _token_is_impaired(data)
		and data.get("has_firearm", false)
	):
		token.play_one_shot("Taunt", pose)
	else:
		token.play_animation(pose)

func _token_is_moving(is_player: bool) -> bool:
	var tween := (
		_player_move_tween if is_player else _enemy_move_tween
	)
	return tween != null and tween.is_valid() and tween.is_running()

func _token_pose(data: Dictionary) -> String:
	if data.get("is_dead", false):
		return "Die"
	if _token_is_impaired(data):
		return "CrouchIdle"
	return "Idle2"

func _token_is_impaired(data: Dictionary) -> bool:
	return (
		int(data.get("stance", int(GameEnums.SCALE_MAX))) <= 6
		or data.get("both_legs_broken", false)
	)

func _movement_animation(
	data: Dictionary,
	previous_lane: int,
	lane: int,
	opponent_lane: int
) -> String:
	if _token_is_impaired(data):
		return "CrouchRun"
	if previous_lane < 0 or opponent_lane < 0:
		return "Run"
	return (
		"Run"
		if absi(lane - opponent_lane) < absi(
			previous_lane - opponent_lane
		)
		else "RunBackwards"
	)

func _animation_for_action(side: String, action: int) -> String:
	match action:
		GameEnums.ActionType.SHOOT, GameEnums.ActionType.AIMED_SHOT:
			return "Attack1"
		GameEnums.ActionType.GRAPPLE, GameEnums.ActionType.BREAK, \
		GameEnums.ActionType.PUSH_STAY, GameEnums.ActionType.PUSH_FOLLOW, \
		GameEnums.ActionType.PULL_FOLLOW, GameEnums.ActionType.TRIP, \
		GameEnums.ActionType.EXECUTE, GameEnums.ActionType.BLOCK:
			return "Attack2"
		GameEnums.ActionType.STRIKE:
			return _next_swing_animation(side)
		GameEnums.ActionType.TAKE_COVER, GameEnums.ActionType.DODGE:
			return _next_strafe_animation(side)
		GameEnums.ActionType.GET_UP, GameEnums.ActionType.RELOAD, \
		GameEnums.ActionType.CYCLE, GameEnums.ActionType.USE_ITEM:
			return "Taunt"
	return ""

func _next_swing_animation(side: String) -> String:
	var use_right := (
		_player_uses_right_swing
		if side == "player"
		else _enemy_uses_right_swing
	)
	if side == "player":
		_player_uses_right_swing = not _player_uses_right_swing
	else:
		_enemy_uses_right_swing = not _enemy_uses_right_swing
	return "Attack3" if use_right else "Attack4"

func _next_strafe_animation(side: String) -> String:
	var use_right := (
		_player_uses_right_strafe
		if side == "player"
		else _enemy_uses_right_strafe
	)
	if side == "player":
		_player_uses_right_strafe = not _player_uses_right_strafe
	else:
		_enemy_uses_right_strafe = not _enemy_uses_right_strafe
	return "StrafeRight" if use_right else "StrafeLeft"

func _token_for_side(side: String) -> HumanoidTokenView:
	if side == "player":
		return _player_token
	if side == "enemy":
		return _enemy_token
	return null

func _store_current_lanes() -> void:
	_last_player_lane = int(
		_snapshot.get("player", {}).get("lane", -1)
	)
	_last_enemy_lane = int(
		_snapshot.get("enemy", {}).get("lane", -1)
	)

func _on_resized() -> void:
	_layout_tokens()
	queue_redraw()

func _draw_scanlines(rect: Rect2) -> void:
	var y := rect.position.y + 3.0
	while y < rect.end.y:
		draw_line(
			Vector2(rect.position.x, y),
			Vector2(rect.end.x, y),
			Color(0.2, 0.55, 0.48, 0.025),
			1.0
		)
		y += 4.0

func _draw_centered(text: String, y: float, font_size: int, color: Color) -> void:
	_draw_text(
		text,
		Vector2(0.0, y),
		size.x,
		font_size,
		color,
		HORIZONTAL_ALIGNMENT_CENTER
	)

func _draw_text(
	text: String,
	position: Vector2,
	width: float,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
) -> void:
	draw_string(
		_font,
		position,
		text,
		alignment,
		width,
		font_size,
		color
	)
