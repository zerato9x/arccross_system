extends Node
class_name CombatCameraController

## Combat camera rig extracted from CombatLaneHUD.
## Owns mode / focus overrides and drives Camera2D + VirtualCamera2D profiles.

const MODE_NEUTRAL := "neutral"
const MODE_BULLET := "bullet"
const MODE_FINAL := "final"
const MODE_RESULTS := "results"

const MIN_ZOOM := 1.0
const MAX_ZOOM := 2.15
const TRANSITION_SPEED := 5.8
const RESOLVE_ZOOM := 1.9

## Fields projectile VFX and resolve flow poke directly.
var camera_mode := MODE_NEUTRAL
var camera_focus_override := Vector2.ZERO
var has_camera_focus_override := false
var camera_transition_speed_override := -1.0
var resolve_focus_side := ""

var _camera: Camera2D
var _focus_anchor: Node2D
var _lane_view: CombatLaneView
var _profiles: Dictionary = {}
var _camera_initialized := false


func configure(
	camera: Camera2D,
	focus_anchor: Node2D,
	lane_view: CombatLaneView,
	neutral_profile: VirtualCamera2D,
	bullet_profile: VirtualCamera2D,
	final_profile: VirtualCamera2D,
	results_profile: VirtualCamera2D
) -> void:
	_camera = camera
	_focus_anchor = focus_anchor
	_lane_view = lane_view
	_profiles.clear()
	_profiles[MODE_NEUTRAL] = _configure_camera_profile(neutral_profile, 1.0)
	_profiles[MODE_BULLET] = _configure_camera_profile(bullet_profile, 1.55)
	_profiles[MODE_FINAL] = _configure_camera_profile(final_profile, RESOLVE_ZOOM)
	_profiles[MODE_RESULTS] = _configure_camera_profile(results_profile, 1.18)
	_setup_camera_rig()


func setup() -> void:
	_setup_camera_rig()


func reset() -> void:
	camera_mode = MODE_NEUTRAL
	has_camera_focus_override = false
	camera_transition_speed_override = -1.0
	update(0.0, _viewport_size())


func update(delta: float, viewport_size: Vector2 = Vector2.ZERO) -> void:
	if viewport_size == Vector2.ZERO:
		viewport_size = _viewport_size()
	if _camera == null or _lane_view == null:
		return
	if _camera is CinematicCamera2D:
		var cinematic := _camera as CinematicCamera2D
		cinematic.transition_speed = _target_camera_transition_speed()
	var target_zoom := _target_camera_zoom(viewport_size)
	var target_position := _target_camera_position()
	_apply_camera_profile(camera_mode, target_zoom, viewport_size)
	if has_camera_focus_override:
		target_position = camera_focus_override
	target_position = _clamp_camera_position(
		target_position,
		target_zoom,
		viewport_size
	)
	if _focus_anchor:
		_focus_anchor.global_position = target_position
	if not _camera_initialized or delta <= 0.0:
		_camera.global_position = target_position
		_camera.zoom = Vector2.ONE * target_zoom
		_camera_initialized = true
	elif not (_camera is CinematicCamera2D):
		var follow_t := clampf(delta * TRANSITION_SPEED, 0.0, 1.0)
		var zoom_t := clampf(delta * TRANSITION_SPEED, 0.0, 1.0)
		_camera.global_position = _camera.global_position.lerp(
			target_position,
			follow_t
		)
		_camera.zoom = _camera.zoom.lerp(
			Vector2.ONE * target_zoom,
			zoom_t
		)


func enter_bullet_mode(pos: Vector2, transition_speed: float = -1.0) -> void:
	camera_mode = MODE_BULLET
	set_focus_override(pos)
	camera_transition_speed_override = transition_speed


func set_focus_override(pos: Vector2) -> void:
	has_camera_focus_override = true
	camera_focus_override = pos


func clear_focus_override() -> void:
	has_camera_focus_override = false
	camera_transition_speed_override = -1.0


func enter_final_mode(focus_side: String = "") -> void:
	if not focus_side.is_empty():
		resolve_focus_side = focus_side
	camera_mode = MODE_FINAL
	has_camera_focus_override = false


func enter_results_mode() -> void:
	camera_mode = MODE_RESULTS


func enter_neutral_mode() -> void:
	camera_mode = MODE_NEUTRAL


func zoom_value() -> float:
	return CombatHudGeometry.camera_zoom_value(_camera)


func get_camera() -> Camera2D:
	return _camera


func _setup_camera_rig() -> void:
	if _camera is CinematicCamera2D:
		var cinematic := _camera as CinematicCamera2D
		cinematic.follow_node = _focus_anchor
		cinematic.virtual_camera = _profiles.get(MODE_NEUTRAL) as VirtualCamera2D
		cinematic.transition_speed = TRANSITION_SPEED


func _configure_camera_profile(
	profile: VirtualCamera2D,
	zoom_value: float
) -> VirtualCamera2D:
	if profile == null:
		return null
	profile.zoom = Vector2.ONE * zoom_value
	profile.offset = Vector2.ZERO
	return profile


func _target_camera_transition_speed() -> float:
	return (
		camera_transition_speed_override
		if camera_transition_speed_override > 0.0
		else TRANSITION_SPEED
	)


func _target_camera_zoom(viewport_size: Vector2) -> float:
	var min_zoom := MIN_ZOOM
	if _lane_view:
		min_zoom = maxf(min_zoom, _lane_view.get_camera_min_zoom(viewport_size))
	var desired := _lane_view.get_focus_zoom() if _lane_view else 1.0
	match camera_mode:
		MODE_BULLET:
			desired = 1.55
		MODE_FINAL:
			desired = RESOLVE_ZOOM
		MODE_RESULTS:
			desired = 1.18
	return clampf(maxf(desired, min_zoom), min_zoom, MAX_ZOOM)


func _target_camera_position() -> Vector2:
	if _lane_view == null:
		return Vector2.ZERO
	match camera_mode:
		MODE_FINAL:
			return _lane_view.get_actor_anchor_global(resolve_focus_side)
		MODE_RESULTS:
			return _lane_view.get_combat_focus_global()
	return _lane_view.get_combat_focus_global()


func _apply_camera_profile(
	mode: String,
	zoom_value: float,
	viewport_size: Vector2
) -> void:
	var profile := _profiles.get(mode) as VirtualCamera2D
	if profile == null:
		profile = _profiles.get(MODE_NEUTRAL) as VirtualCamera2D
	if profile == null:
		return
	profile.zoom = Vector2.ONE * zoom_value
	_update_profile_limits(profile, viewport_size)
	if _camera is CinematicCamera2D:
		var cinematic := _camera as CinematicCamera2D
		cinematic.virtual_camera = profile
		cinematic.follow_node = _focus_anchor


func _update_profile_limits(profile: VirtualCamera2D, _viewport_size: Vector2) -> void:
	if _lane_view == null:
		return
	var bounds := _lane_view.get_stage_bounds_global()
	profile.global_position = Vector2.ZERO
	profile.limit_left = roundi(bounds.position.x)
	profile.limit_top = roundi(bounds.position.y)
	profile.limit_right = roundi(bounds.end.x)
	profile.limit_bottom = roundi(bounds.end.y)


func _clamp_camera_position(
	position: Vector2,
	zoom_value: float,
	viewport_size: Vector2
) -> Vector2:
	if _lane_view == null:
		return position
	var bounds := _lane_view.get_stage_bounds_global()
	var half_view := viewport_size / maxf(0.01, zoom_value) * 0.5
	var min_pos := bounds.position + half_view
	var max_pos := bounds.end - half_view
	if min_pos.x > max_pos.x:
		position.x = bounds.get_center().x
	else:
		position.x = clampf(position.x, min_pos.x, max_pos.x)
	if min_pos.y > max_pos.y:
		position.y = bounds.get_center().y
	else:
		position.y = clampf(position.y, min_pos.y, max_pos.y)
	return position


func _viewport_size() -> Vector2:
	if _camera != null and _camera.get_viewport() != null:
		return _camera.get_viewport().get_visible_rect().size
	return Vector2.ZERO
