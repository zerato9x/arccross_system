extends Node2D
class_name CombatLaneView

signal slot_hovered(slot_data: Dictionary, global_position: Vector2)
signal slot_unhovered

const DEFAULT_LANE_MOVE_DURATION_SECONDS := 1.2
# Compatibility for the turn-based presentation smoke and older scene callers.
const LANE_MOVE_DURATION_SECONDS := DEFAULT_LANE_MOVE_DURATION_SECONDS
const MOTION_WAIT_FRAME_LIMIT := 210
const TOKEN_PRESENTATION_FRAME_LIMIT := 240
const FINAL_BLOW_SETTLE_FRACTION := 0.58
const STAGE_GROUND_ASSET := "res://Asset/HexTiles/_BIOMES/biome_plains/bg_plains.png"
const STAGE_MIN_SIZE := Vector2(1680.0, 920.0)
const CAMERA_BLEED_X_RATIO := 0.4
# The source plains plate is deliberately muddy (about 0.23 average luminance).
# Keep combat readable without involving the global shader stack.
const STAGE_BASE_TINT := Color(1.42, 1.36, 1.20, 1.0)
const STAGE_DUEL_FOCUS_TINT := Color(1.16, 1.12, 1.02, 1.0)

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
var _last_player_appearance: Dictionary = {}
var _last_enemy_appearance: Dictionary = {}
var _slot_nodes: Array = []
var _slot_data_by_index: Dictionary = {}
var _hovered_slot_index := -1
var _stage_size := Vector2(1280.0, 720.0)
var _camera_bleed := Vector2.ZERO
var _realtime_animation_speed_scale := 1.0
var _lane_move_duration_seconds := DEFAULT_LANE_MOVE_DURATION_SECONDS
var _player_realtime_target_lane := -1
var _enemy_realtime_target_lane := -1
var _duel_focus_slot := -1

@onready var _slots_root: Node2D = %Slots
@onready var _actor_root: Node2D = %ActorPawns
@onready var _stage_backdrop: Polygon2D = %StageBackdrop
@onready var _stage_grass: Sprite2D = %StageGrass
@onready var _player_token: HumanoidTokenView = %PlayerHumanoidToken
@onready var _enemy_token: HumanoidTokenView = %EnemyHumanoidToken
@onready var _melee_lock_banner: Label = %MeleeLockBanner

func _ready() -> void:
	_collect_slots()
	_stage_grass.texture = load(STAGE_GROUND_ASSET) as Texture2D
	_stage_grass.modulate = STAGE_BASE_TINT
	_player_token.visible = false
	_enemy_token.visible = false
	_melee_lock_banner.visible = false
	
	_player_token.footstep_taken.connect(_on_token_footstep.bind(true))
	_enemy_token.footstep_taken.connect(_on_token_footstep.bind(false))

func _on_token_footstep(is_player: bool) -> void:
	var side := "player" if is_player else "enemy"
	var lane := int(_snapshot.get(side, {}).get("lane", -1))
	if lane >= 0 and lane < _slot_nodes.size():
		var slot_data: Dictionary = _slot_data_by_index.get(lane, {})
		var background := str(slot_data.get("background", "NONE"))
		var bus = get_node_or_null("/root/GameEventBus")
		if bus:
			bus.emit_humanoid_footstep(self, background)

func show_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_duel_focus_slot = _find_lock_slot()
	_showing_melee_lock = _duel_focus_slot >= 0
	_sync_slots()
	_sync_tokens()
	set_duel_focus(_showing_melee_lock, _duel_focus_slot)
	# Lock state belongs in the responsive HUD. This fixed-width world label was
	# mostly useful for demonstrating why fixed-width world labels are a bad idea.
	_melee_lock_banner.visible = false

func set_duel_focus(active: bool, lock_slot: int = -1) -> void:
	_duel_focus_slot = lock_slot if active else -1
	for slot in _slot_nodes:
		if slot.has_method("set_duel_focus"):
			slot.set_duel_focus(active, _duel_focus_slot)
	_stage_grass.modulate = (
		STAGE_DUEL_FOCUS_TINT
		if active
		else STAGE_BASE_TINT
	)

func get_duel_focus_slot() -> int:
	return _duel_focus_slot

func show_presentation_event(event: Dictionary) -> void:
	play_presentation_event(event)

func show_realtime_event(event: Dictionary) -> void:
	var side := str(event.get("side", ""))
	var token := _token_for_side(side)
	if token == null:
		return
	match str(event.get("type", "")):
		"action_timeline":
			var animation := str(event.get("animation", ""))
			var action := int(event.get("action", GameEnums.DuelActionType.NONE))
			if action in [GameEnums.DuelActionType.MOVE, GameEnums.DuelActionType.FOLLOW]:
				_start_realtime_move(
					side,
					int(event.get("to_lane", -1)),
					maxf(0.2, float(event.get("duration", DEFAULT_LANE_MOVE_DURATION_SECONDS))),
					animation
				)
			elif not animation.is_empty():
				token.play_timed_one_shot(
					animation,
					_token_pose(_snapshot.get(side, {})),
					maxf(0.2, float(event.get("duration", 1.0)))
				)
		"aim_started":
			token.play_animation("CrouchIdle")
		"parry":
			token.play_timed_one_shot("StrafeRight" if side == "player" else "StrafeLeft", _token_pose(_snapshot.get(side, {})), 0.7)
		"block":
			token.play_timed_one_shot("StrafeLeft" if side == "player" else "StrafeRight", _token_pose(_snapshot.get(side, {})), 0.65)
		"heavy_cancel":
			token.play_timed_one_shot("StrafeLeft" if side == "player" else "StrafeRight", _token_pose(_snapshot.get(side, {})), 0.55)
		"push":
			_start_realtime_move(
				str(event.get("target_side", "")),
				int(event.get("to_lane", -1)),
				maxf(0.35, float(event.get("move_duration", 0.67))),
				"RunBackwards"
			)
		"damage":
			if not bool(_snapshot.get(side, {}).get("is_dead", false)):
				token.play_timed_one_shot("TakeDamage", _token_pose(_snapshot.get(side, {})), 0.65)

func configure_realtime_pacing(pace_scale: float) -> void:
	_realtime_animation_speed_scale = 1.0
	_lane_move_duration_seconds = DEFAULT_LANE_MOVE_DURATION_SECONDS
	if _player_token != null:
		_player_token.set_animation_speed(_realtime_animation_speed_scale)
	if _enemy_token != null:
		_enemy_token.set_animation_speed(_realtime_animation_speed_scale)

func play_presentation_event(event: Dictionary) -> void:
	var side := str(event.get("side", ""))
	var token := _token_for_side(side)
	var data: Dictionary = _snapshot.get(side, {})
	if token == null or data.is_empty():
		return

	match str(event.get("type", "")):
		"final_blow":
			token.set_animation_speed(float(event.get("animation_speed", 0.42)))
			if token.play_animation("Die", true):
				await _wait_for_token_animation_cue(
					token,
					"Die",
					FINAL_BLOW_SETTLE_FRACTION
				)
		"death":
			if event.get("skip_lane_presentation", false):
				return
			if token.play_animation("Die"):
				await _wait_for_token_animation_cue(
					token,
					"Die",
					FINAL_BLOW_SETTLE_FRACTION
				)
		"damage":
			if event.get("skip_lane_presentation", false):
				return
			if not data.get("is_dead", false):
				if token.play_one_shot("TakeDamage", _token_pose(data)):
					await _wait_for_token_animation_finished(token, "TakeDamage")
		"action":
			var animation := _animation_for_action(
				side,
				int(event.get("action", -1))
			)
			if not animation.is_empty():
				var duration := float(event.get(
					"presentation_duration",
					token.get_animation_duration(animation)
				))
				var cue_fraction := float(event.get("cue_fraction", 1.0))
				if token.play_timed_one_shot(
					animation,
					_token_pose(data),
					duration
				):
					await _wait_for_token_animation_cue(
						token,
						animation,
						cue_fraction
					)

func layout_for_viewport(viewport_size: Vector2) -> void:
	var safe_viewport := Vector2(
		maxf(1.0, viewport_size.x),
		maxf(1.0, viewport_size.y)
	)
	var stage_width := maxf(STAGE_MIN_SIZE.x, safe_viewport.x)
	var stage_height_for_aspect := stage_width * safe_viewport.y / safe_viewport.x
	_stage_size = Vector2(
		stage_width,
		maxf(STAGE_MIN_SIZE.y, stage_height_for_aspect)
	)
	# The gameplay lane still occupies the viewport-sized stage. Horizontal visual
	# bleed lets the duel camera center a lock occurring near either territory edge
	# instead of pinning the fighters against a screen corner.
	_camera_bleed = Vector2(_stage_size.x * CAMERA_BLEED_X_RATIO, 0.0)
	_resize_stage_backdrop(_stage_size)
	var lane_y := _stage_size.y * 0.49
	var usable_width := maxf(720.0, _stage_size.x - 180.0)
	var cell_step := usable_width / 12.0
	var start_x := _stage_size.x * 0.5 - usable_width * 0.5 + cell_step * 0.5
	var slot_size := Vector2(cell_step - 10.0, clampf(viewport_size.y * 0.13, 82.0, 116.0))
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

func get_stage_bounds_global() -> Rect2:
	return Rect2(global_position, _stage_size)


func get_camera_bounds_global() -> Rect2:
	return Rect2(
		global_position - _camera_bleed,
		_stage_size + _camera_bleed * 2.0
	)


func get_stage_center_global() -> Vector2:
	return global_position + _stage_size * 0.5

func get_camera_min_zoom(viewport_size: Vector2) -> float:
	if _stage_size.x <= 0.0 or _stage_size.y <= 0.0:
		return 1.0
	return minf(
		viewport_size.x / _stage_size.x,
		viewport_size.y / _stage_size.y
	)

func get_projectile_anchor_global(side: String, lane_index: int = -1) -> Vector2:
	var anchor := get_actor_anchor_global(side)
	if lane_index >= 0 and lane_index < _slot_nodes.size():
		var shared_lane := (
			int(_snapshot.get("player", {}).get("lane", -1))
			== int(_snapshot.get("enemy", {}).get("lane", -2))
		)
		anchor = _slot_nodes[lane_index].get_actor_anchor(side, shared_lane)
	return anchor + Vector2(0.0, -18.0)

func get_projectile_miss_anchor_global(
	attacker_side: String,
	target_lane: int,
	overshoot_lanes: float = 1.35
) -> Vector2:
	var origin_lane := int(_snapshot.get(attacker_side, {}).get("lane", target_lane))
	var direction := signi(target_lane - origin_lane)
	if direction == 0:
		direction = 1 if attacker_side == "player" else -1
	if _slot_nodes.size() < 2:
		return get_slot_center_global(target_lane) + Vector2(160.0 * direction, -18.0)
	var cell_step: float = (
		_slot_nodes[1].global_position.x
		- _slot_nodes[0].global_position.x
	)
	return (
		get_slot_center_global(target_lane)
		+ Vector2(cell_step * overshoot_lanes * float(direction), -18.0)
	)

func get_combat_focus_global() -> Vector2:
	if (
		_player_token.visible
		and _enemy_token.visible
		and (_token_is_moving(true) or _token_is_moving(false))
	):
		return (_player_token.global_position + _enemy_token.global_position) * 0.5
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

func has_active_motion() -> bool:
	return _token_is_moving(true) or _token_is_moving(false)

func wait_for_motion_complete(frame_limit: int = MOTION_WAIT_FRAME_LIMIT) -> bool:
	for _frame in range(frame_limit):
		if not has_active_motion():
			return true
		await get_tree().process_frame
	return not has_active_motion()

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
	_resize_stage_grass(viewport_size)

func _resize_stage_grass(viewport_size: Vector2) -> void:
	if _stage_grass == null or _stage_grass.texture == null:
		return
	var texture_size := _stage_grass.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var camera_safe_size := viewport_size + _camera_bleed * 2.0
	var scale_factor := maxf(
		camera_safe_size.x / texture_size.x,
		camera_safe_size.y / texture_size.y
	)
	_stage_grass.position = viewport_size * 0.5
	_stage_grass.scale = Vector2.ONE * scale_factor

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

	token.set_appearance(_presentation_appearance(data, is_player))
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
		_player_token.set_display_scale(1.36)
		_enemy_token.set_display_scale(1.36)
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

	_player_token.set_display_scale(1.08)
	_enemy_token.set_display_scale(1.08)
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

func _presentation_appearance(
	data: Dictionary,
	is_player: bool
) -> Dictionary:
	var fallback := HumanoidVisualCatalog.appearance_from_slot_item_ids({})
	var appearance: Dictionary = data.get("appearance", fallback)
	var has_outfit := _appearance_has_outfit_layers(appearance)
	var cached: Dictionary = (
		_last_player_appearance
		if is_player
		else _last_enemy_appearance
	)
	if data.get("is_dead", false) and not has_outfit and not cached.is_empty():
		return cached
	if has_outfit:
		if is_player:
			_last_player_appearance = appearance.duplicate(true)
		else:
			_last_enemy_appearance = appearance.duplicate(true)
	return appearance

func _appearance_has_outfit_layers(appearance: Dictionary) -> bool:
	for raw_layer in appearance.get("layers", []):
		if not raw_layer is Dictionary:
			continue
		var layer: Dictionary = raw_layer
		if not str(layer.get("directory", "")).is_empty():
			return true
	return false

func _move_or_place_token(
	token: HumanoidTokenView,
	target: Vector2,
	lane: int,
	is_player: bool
) -> void:
	var previous_lane := _last_player_lane if is_player else _last_enemy_lane
	var predicted_lane := (
		_player_realtime_target_lane
		if is_player
		else _enemy_realtime_target_lane
	)
	if predicted_lane == lane and _token_is_moving(is_player):
		return
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
		_lane_move_duration_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_finish_token_move.bind(is_player))
	if is_player:
		_player_move_tween = tween
	else:
		_enemy_move_tween = tween

func _finish_token_move(is_player: bool) -> void:
	if is_player:
		_player_realtime_target_lane = -1
	else:
		_enemy_realtime_target_lane = -1
	var token := _player_token if is_player else _enemy_token
	token.set_animation_speed(1.0)
	var side := "player" if is_player else "enemy"
	var data: Dictionary = _snapshot.get(side, {})
	var pose := _token_pose(data)
	if (
		not data.get("is_dead", false)
		and not _token_is_impaired(data)
		and data.get("has_firearm", false)
	):
		# Keep the established ready-weapon beat, but fit it into a short,
		# explicit recovery window instead of occupying the channel for the
		# full 15-frame Taunt clip.
		token.play_timed_one_shot("Taunt", pose, 0.58)
	else:
		token.play_animation(pose)

func _start_realtime_move(
	side: String,
	to_lane: int,
	duration: float,
	animation: String
) -> void:
	if to_lane < 0 or to_lane >= _slot_nodes.size():
		return
	var is_player := side == "player"
	var token := _token_for_side(side)
	if token == null:
		return
	var tween := _player_move_tween if is_player else _enemy_move_tween
	if tween != null and tween.is_valid():
		tween.kill()
	var opponent_side := "enemy" if is_player else "player"
	var opponent_lane := int(_snapshot.get(opponent_side, {}).get("lane", -1))
	var shared_lane := opponent_lane == to_lane
	var target := to_local(_slot_nodes[to_lane].get_actor_anchor(side, shared_lane))
	token.set_animation_speed(0.72)
	token.play_animation(animation if not animation.is_empty() else "Run")
	if is_player:
		_player_realtime_target_lane = to_lane
	else:
		_enemy_realtime_target_lane = to_lane
	tween = create_tween()
	tween.tween_property(token, "position", target, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_finish_token_move.bind(is_player))
	if is_player:
		_player_move_tween = tween
	else:
		_enemy_move_tween = tween

func _token_is_moving(is_player: bool) -> bool:
	var tween := _player_move_tween if is_player else _enemy_move_tween
	return tween != null and tween.is_valid() and tween.is_running()

func _wait_for_token_animation_finished(
	token: HumanoidTokenView,
	animation: String,
	frame_limit: int = TOKEN_PRESENTATION_FRAME_LIMIT
) -> bool:
	for _frame in range(frame_limit):
		if token.get_animation() != animation:
			return true
		if token.has_animation_finished(animation):
			return true
		await get_tree().process_frame
	return token.get_animation() != animation or token.has_animation_finished(animation)

func _wait_for_token_animation_cue(
	token: HumanoidTokenView,
	animation: String,
	fraction: float,
	frame_limit: int = TOKEN_PRESENTATION_FRAME_LIMIT
) -> bool:
	var max_frames: int = maxi(1, HumanoidVisualCatalog.animation_frames(animation))
	var target_frame := clampi(
		int(round(float(max_frames - 1) * clampf(fraction, 0.0, 1.0))),
		0,
		max_frames - 1
	)
	for _frame in range(frame_limit):
		if token.get_animation() != animation:
			return true
		if token.get_frame_index() >= target_frame:
			return true
		if token.has_animation_finished(animation):
			return true
		await get_tree().process_frame
	return (
		token.get_animation() != animation
		or token.get_frame_index() >= target_frame
		or token.has_animation_finished(animation)
	)

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
		GameEnums.ActionType.GRAPPLE:
			return "Attack2"
		GameEnums.ActionType.BREAK:
			return "Attack2"
		GameEnums.ActionType.PUSH_STAY, GameEnums.ActionType.PUSH_FOLLOW:
			return "Attack2"
		GameEnums.ActionType.PULL_FOLLOW, GameEnums.ActionType.TRIP:
			return "Attack2"
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
