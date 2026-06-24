extends Node2D
class_name CombatLaneView

signal slot_hovered(slot_data: Dictionary, global_position: Vector2)
signal slot_unhovered

const LANE_MOVE_DURATION_SECONDS := 0.4

var _snapshot: Dictionary = {}
var _showing_melee_lock := false
var _last_player_lane := -1
var _last_enemy_lane := -1
var _player_move_tween: Tween
var _enemy_move_tween: Tween
var _player_uses_right_swing := true
var _enemy_uses_right_swing := true
var _player_uses_right_strafe := true
var _enemy_uses_right_strafe := true
var _slot_nodes: Array = []
var _slot_data_by_index: Dictionary = {}
var _hovered_slot_index := -1
var _stage_size := Vector2(1280.0, 720.0)

@onready var _slots_root: Node2D = %Slots
@onready var _actor_root: Node2D = %ActorPawns
@onready var _stage_backdrop: Polygon2D = %StageBackdrop
@onready var _player_token: HumanoidTokenView = %PlayerHumanoidToken
@onready var _enemy_token: HumanoidTokenView = %EnemyHumanoidToken
@onready var _melee_lock_banner: Label = %MeleeLockBanner

func _ready() -> void:
	_collect_slots()
	_player_token.visible = false
	_enemy_token.visible = false
	_melee_lock_banner.visible = false

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_showing_melee_lock = _find_lock_slot() >= 0
	_sync_slots()
	_sync_tokens()
	_melee_lock_banner.visible = _showing_melee_lock

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

func layout_for_viewport(viewport_size: Vector2) -> void:
	_stage_size = viewport_size
	_resize_stage_backdrop(viewport_size)
	var lane_y := viewport_size.y * 0.52
	var usable_width := maxf(720.0, viewport_size.x - 64.0)
	var cell_step := usable_width / 12.0
	var start_x := viewport_size.x * 0.5 - usable_width * 0.5 + cell_step * 0.5
	var slot_size := Vector2(cell_step - 8.0, clampf(viewport_size.y * 0.115, 72.0, 108.0))
	for index in range(_slot_nodes.size()):
		var slot = _slot_nodes[index]
		slot.set_slot_size(slot_size)
		slot.position = Vector2(start_x + cell_step * index, lane_y)
	_layout_tokens()

func is_showing_melee_lock() -> bool:
	return _showing_melee_lock

func get_actor_anchor_global(side: String) -> Vector2:
	var token := _token_for_side(side)
	if token != null and token.visible:
		return token.global_position
	var lane := int(_snapshot.get(side, {}).get("lane", -1))
	if lane >= 0 and lane < _slot_nodes.size():
		return _slot_nodes[lane].global_position
	return global_position + _stage_size * 0.5

func get_slot_center_global(slot_index: int) -> Vector2:
	if slot_index >= 0 and slot_index < _slot_nodes.size():
		return _slot_nodes[slot_index].global_position
	return global_position + _stage_size * 0.5

func get_combat_focus_global() -> Vector2:
	if _showing_melee_lock:
		var lock_slot := _find_lock_slot()
		if lock_slot >= 0 and lock_slot < _slot_nodes.size():
			return _slot_nodes[lock_slot].global_position
	var player_lane := int(_snapshot.get("player", {}).get("lane", -1))
	var enemy_lane := int(_snapshot.get("enemy", {}).get("lane", -1))
	if (
		player_lane >= 0
		and player_lane < _slot_nodes.size()
		and enemy_lane >= 0
		and enemy_lane < _slot_nodes.size()
	):
		return (
			_slot_nodes[player_lane].global_position
			+ _slot_nodes[enemy_lane].global_position
		) * 0.5
	return global_position + _stage_size * 0.5

func get_focus_zoom() -> float:
	return 1.55 if _showing_melee_lock else 1.0

func _collect_slots() -> void:
	_slot_nodes.clear()
	for child in _slots_root.get_children():
		var slot = child
		if not slot.has_method("show_slot_data"):
			continue
		_slot_nodes.append(slot)
		if not slot.hovered.is_connected(_on_slot_hovered):
			slot.hovered.connect(_on_slot_hovered)
		if not slot.unhovered.is_connected(_on_slot_unhovered):
			slot.unhovered.connect(_on_slot_unhovered)
	_slot_nodes.sort_custom(
		func(a, b) -> bool:
			return a.slot_index < b.slot_index
	)

func _sync_slots() -> void:
	_slot_data_by_index.clear()
	for raw_slot in _snapshot.get("lane_slots", []):
		var data: Dictionary = raw_slot
		_slot_data_by_index[int(data.get("index", -1))] = data
	for slot in _slot_nodes:
		slot.show_slot_data(_slot_data_by_index.get(slot.slot_index, {}))
		slot.set_highlighted(slot.slot_index == _hovered_slot_index)

func _resize_stage_backdrop(viewport_size: Vector2) -> void:
	if _stage_backdrop == null:
		return
	var pad := maxf(viewport_size.x, viewport_size.y)
	_stage_backdrop.polygon = PackedVector2Array([
		Vector2(-pad, -pad),
		Vector2(viewport_size.x + pad, -pad),
		Vector2(viewport_size.x + pad, viewport_size.y + pad),
		Vector2(-pad, viewport_size.y + pad),
	])

func _on_slot_hovered(slot_index: int) -> void:
	_hovered_slot_index = slot_index
	for slot in _slot_nodes:
		slot.set_highlighted(slot.slot_index == _hovered_slot_index)
	var slot_data: Dictionary = _slot_data_by_index.get(slot_index, {})
	if slot_data.is_empty():
		slot_unhovered.emit()
		return
	slot_hovered.emit(slot_data, get_slot_center_global(slot_index))

func _on_slot_unhovered(slot_index: int) -> void:
	if _hovered_slot_index != slot_index:
		return
	_hovered_slot_index = -1
	for slot in _slot_nodes:
		slot.set_highlighted(false)
	slot_unhovered.emit()

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

	_sync_token(_player_token, _snapshot.get("player", {}), true)
	_sync_token(_enemy_token, _snapshot.get("enemy", {}), false)
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
	if _snapshot.is_empty() or _slot_nodes.is_empty():
		return

	if _showing_melee_lock:
		var lock_lane := _find_lock_slot()
		var shared_lane := lock_lane >= 0 and lock_lane < _slot_nodes.size()
		var lock_anchor: Vector2 = (
			_slot_nodes[lock_lane].global_position
			if shared_lane
			else global_position + _stage_size * 0.5
		)
		_player_token.set_display_scale(1.65)
		_enemy_token.set_display_scale(1.65)
		_move_or_place_token(
			_player_token,
			to_local(
				_slot_nodes[lock_lane].get_actor_anchor("player", true)
				if shared_lane
				else lock_anchor + Vector2(-22.0, -12.0)
			),
			int(_snapshot.get("player", {}).get("lane", -1)),
			true
		)
		_move_or_place_token(
			_enemy_token,
			to_local(
				_slot_nodes[lock_lane].get_actor_anchor("enemy", true)
				if shared_lane
				else lock_anchor + Vector2(22.0, -12.0)
			),
			int(_snapshot.get("enemy", {}).get("lane", -1)),
			false
		)
		_store_current_lanes()
		return

	var player_lane := int(_snapshot.get("player", {}).get("lane", -1))
	var enemy_lane := int(_snapshot.get("enemy", {}).get("lane", -1))
	var shared_lane := player_lane >= 0 and player_lane == enemy_lane

	_player_token.set_display_scale(1.25)
	_enemy_token.set_display_scale(1.25)
	if player_lane >= 0 and player_lane < _slot_nodes.size():
		_move_or_place_token(
			_player_token,
			to_local(_slot_nodes[player_lane].get_actor_anchor("player", shared_lane)),
			player_lane,
			true
		)
	if enemy_lane >= 0 and enemy_lane < _slot_nodes.size():
		_move_or_place_token(
			_enemy_token,
			to_local(_slot_nodes[enemy_lane].get_actor_anchor("enemy", shared_lane)),
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
	var previous_lane := _last_player_lane if is_player else _last_enemy_lane
	if previous_lane < 0 or previous_lane == lane:
		if not _token_is_moving(is_player):
			token.position = target
		return

	var active_tween := _player_move_tween if is_player else _enemy_move_tween
	if active_tween and active_tween.is_valid():
		active_tween.kill()

	var side := "player" if is_player else "enemy"
	var opponent_side := "enemy" if is_player else "player"
	var data: Dictionary = _snapshot.get(side, {})
	var opponent_lane := int(_snapshot.get(opponent_side, {}).get("lane", -1))
	token.play_animation(
		_movement_animation(data, previous_lane, lane, opponent_lane)
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
	var tween := _player_move_tween if is_player else _enemy_move_tween
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
		if absi(lane - opponent_lane) < absi(previous_lane - opponent_lane)
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
	_last_player_lane = int(_snapshot.get("player", {}).get("lane", -1))
	_last_enemy_lane = int(_snapshot.get("enemy", {}).get("lane", -1))
