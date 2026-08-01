class_name MacroCamera
extends Camera2D
## Stable top-down macro camera: damped follow, soft look-ahead, smooth wheel zoom.
## Never pulses zoom on travel — that causes motion sickness.

@export var target: Node2D
@export var follow_lerp: float = 6.0
@export var look_ahead_distance: float = 48.0
@export var look_ahead_blend: float = 5.0
@export var settle_lerp: float = 4.0
@export var zoom_min: float = 0.55
@export var zoom_max: float = 2.4
@export var zoom_step: float = 0.08
@export var zoom_smooth_speed: float = 10.0

var _desired_zoom: float = 1.0
var _look_ahead: Vector2 = Vector2.ZERO
var _look_ahead_goal: Vector2 = Vector2.ZERO
var _hud_offset: Vector2 = Vector2.ZERO
var _travel_active: bool = false


func _ready() -> void:
	make_current()
	_desired_zoom = zoom.x
	# Drag deadzone absorbs tiny hex-step jitter; we still own follow for look-ahead.
	anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	position_smoothing_enabled = false
	drag_horizontal_enabled = true
	drag_vertical_enabled = true
	drag_left_margin = 0.12
	drag_right_margin = 0.12
	drag_top_margin = 0.12
	drag_bottom_margin = 0.12
	if target != null:
		global_position = target.global_position + _hud_offset


func _process(delta: float) -> void:
	_update_zoom(delta)
	_update_follow(delta)


func _unhandled_input(event: InputEvent) -> void:
	var host := get_parent()
	if host != null and host.has_method("blocks_world_commands"):
		if bool(host.call("blocks_world_commands")):
			return
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed:
		return
	if mouse.button_index == MOUSE_BUTTON_WHEEL_UP:
		_desired_zoom = clampf(_desired_zoom + zoom_step, zoom_min, zoom_max)
		get_viewport().set_input_as_handled()
	elif mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_desired_zoom = clampf(_desired_zoom - zoom_step, zoom_min, zoom_max)
		get_viewport().set_input_as_handled()


func set_viewport_insets(_insets: Rect2i) -> void:
	## Work surfaces are transient overlays. Opening medical, inventory, or map
	## UI must never reframe the world underneath the player's cursor.
	## Insets remain useful to the HUD layout manager, but the camera deliberately
	## ignores them and keeps one stable spatial reference.
	_hud_offset = Vector2.ZERO


func begin_travel_look_ahead(from_world: Vector2, to_world: Vector2) -> void:
	## Soft lead toward the destination hex. Position only — never zoom.
	_travel_active = true
	var delta := to_world - from_world
	if delta.length_squared() < 1.0:
		_look_ahead_goal = Vector2.ZERO
		return
	_look_ahead_goal = delta.normalized() * look_ahead_distance


func end_travel_look_ahead() -> void:
	_travel_active = false
	_look_ahead_goal = Vector2.ZERO


func snap_to_target() -> void:
	if target == null:
		return
	_look_ahead = Vector2.ZERO
	_look_ahead_goal = Vector2.ZERO
	_travel_active = false
	global_position = target.global_position + _hud_offset


func _update_zoom(delta: float) -> void:
	var current := zoom.x
	if is_equal_approx(current, _desired_zoom):
		return
	var next := lerpf(current, _desired_zoom, clampf(zoom_smooth_speed * delta, 0.0, 1.0))
	zoom = Vector2(next, next)


func _update_follow(delta: float) -> void:
	if target == null:
		return
	var blend := clampf(
		(look_ahead_blend if _travel_active else settle_lerp) * delta,
		0.0,
		1.0
	)
	_look_ahead = _look_ahead.lerp(_look_ahead_goal, blend)
	var goal := target.global_position + _look_ahead + _hud_offset
	var rate := clampf(follow_lerp * delta, 0.0, 1.0)
	global_position = global_position.lerp(goal, rate)
