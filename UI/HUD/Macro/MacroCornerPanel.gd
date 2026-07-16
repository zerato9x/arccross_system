extends Control
class_name MacroCornerPanel

signal state_changed(panel_id: String, state: int)
signal expand_requested
signal collapse_requested

enum PanelCorner { TOP_LEFT, BOTTOM_LEFT, TOP_RIGHT, BOTTOM_RIGHT }
enum PanelState { PREVIEW, EXPANDED }

const PREVIEW_MARGIN := 14.0
const EXPAND_WIDTH_RATIO := 0.32
const EXPAND_HEIGHT_RATIO := 0.50
const DEFAULT_EXPANDED_MIN_SIZE := Vector2(560.0, 420.0)
const DEFAULT_EXPANDED_MAX_SIZE := Vector2(1040.0, 760.0)

@export var panel_id: String = "corner"
@export var panel_corner: PanelCorner = PanelCorner.TOP_LEFT
@export var can_expand: bool = true
@export var preview_size: Vector2 = Vector2(260.0, 200.0)
@export var expand_width_ratio: float = EXPAND_WIDTH_RATIO
@export var expand_height_ratio: float = EXPAND_HEIGHT_RATIO
@export var expanded_min_size: Vector2 = DEFAULT_EXPANDED_MIN_SIZE
@export var expanded_max_size: Vector2 = DEFAULT_EXPANDED_MAX_SIZE
@export var use_authored_preview_rect: bool = false

var _state: PanelState = PanelState.PREVIEW
var _snapshot: Dictionary = {}
var _authored_anchor_left := 0.0
var _authored_anchor_top := 0.0
var _authored_anchor_right := 0.0
var _authored_anchor_bottom := 0.0
var _authored_offset_left := 0.0
var _authored_offset_top := 0.0
var _authored_offset_right := 0.0
var _authored_offset_bottom := 0.0
var _expanded_available_override := Vector2.ZERO

@onready var _preview_root: Control = %PreviewRoot
@onready var _expanded_root: Control = %ExpandedRoot
@onready var _close_button: Button = %CloseButton
@onready var _emergency_overlay: ColorRect = %EmergencyOverlay


func _ready() -> void:
	_capture_authored_rect()
	if _close_button:
		_close_button.pressed.connect(collapse)
		_close_button.visible = false
		HUDAssetLibrary.apply_button(_close_button)
	if _expanded_root:
		_expanded_root.visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_layout()
	get_viewport().size_changed.connect(_apply_layout)


func get_panel_state() -> PanelState:
	return _state


func is_expanded() -> bool:
	return _state == PanelState.EXPANDED


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_render_preview()
	if _state == PanelState.EXPANDED:
		_render_expanded()


func expand() -> void:
	if not can_expand or _state == PanelState.EXPANDED:
		return
	_set_state(PanelState.EXPANDED)
	expand_requested.emit()


func collapse() -> void:
	if _state == PanelState.PREVIEW:
		return
	_set_state(PanelState.PREVIEW)
	collapse_requested.emit()


func toggle_expanded() -> void:
	if _state == PanelState.EXPANDED:
		collapse()
	else:
		expand()


func get_occupied_rect() -> Rect2:
	if _state != PanelState.EXPANDED:
		return Rect2()
	return get_global_rect()


func set_emergency_active(active: bool, tint: Color = Color(0.0, 0.0, 0.0, 0.45)) -> void:
	if _emergency_overlay == null:
		return
	_emergency_overlay.visible = active
	_emergency_overlay.color = tint


func set_expanded_available_override(available_size: Vector2) -> void:
	_expanded_available_override = available_size
	if _state == PanelState.EXPANDED:
		_apply_layout()


func expanded_size_for_viewport(viewport_size: Vector2) -> Vector2:
	return _expanded_size_for_viewport(viewport_size)


func _set_state(state: PanelState) -> void:
	_state = state
	if _preview_root:
		_preview_root.visible = state == PanelState.PREVIEW
	if _expanded_root:
		_expanded_root.visible = state == PanelState.EXPANDED
	if _close_button:
		_close_button.visible = state == PanelState.EXPANDED and can_expand
	_apply_layout()
	state_changed.emit(panel_id, state)


func _apply_layout() -> void:
	var vp := get_viewport_rect().size
	if _state == PanelState.EXPANDED:
		var expanded := _expanded_size_for_viewport(vp)
		custom_minimum_size = expanded
		size = expanded
		_set_corner_anchors()
	else:
		custom_minimum_size = preview_size
		if use_authored_preview_rect:
			_restore_authored_rect()
			size = preview_size
		else:
			size = preview_size
			_set_corner_anchors()


func _expanded_size_for_viewport(viewport_size: Vector2) -> Vector2:
	var available := Vector2(
		maxf(1.0, viewport_size.x - PREVIEW_MARGIN * 2.0),
		maxf(1.0, viewport_size.y - PREVIEW_MARGIN * 2.0)
	)
	if _expanded_available_override.x > 0.0:
		available.x = minf(available.x, _expanded_available_override.x)
	if _expanded_available_override.y > 0.0:
		available.y = minf(available.y, _expanded_available_override.y)
	var max_size := Vector2(
		available.x if expanded_max_size.x <= 0.0 else minf(expanded_max_size.x, available.x),
		available.y if expanded_max_size.y <= 0.0 else minf(expanded_max_size.y, available.y)
	)
	var min_size := Vector2(
		minf(expanded_min_size.x, max_size.x),
		minf(expanded_min_size.y, max_size.y)
	)
	return Vector2(
		clampf(viewport_size.x * expand_width_ratio, min_size.x, max_size.x),
		clampf(viewport_size.y * expand_height_ratio, min_size.y, max_size.y)
	)


func _capture_authored_rect() -> void:
	_authored_anchor_left = anchor_left
	_authored_anchor_top = anchor_top
	_authored_anchor_right = anchor_right
	_authored_anchor_bottom = anchor_bottom
	_authored_offset_left = offset_left
	_authored_offset_top = offset_top
	_authored_offset_right = offset_right
	_authored_offset_bottom = offset_bottom


func _restore_authored_rect() -> void:
	anchor_left = _authored_anchor_left
	anchor_top = _authored_anchor_top
	anchor_right = _authored_anchor_right
	anchor_bottom = _authored_anchor_bottom
	offset_left = _authored_offset_left
	offset_top = _authored_offset_top
	offset_right = _authored_offset_right
	offset_bottom = _authored_offset_bottom


func _set_corner_anchors() -> void:
	match panel_corner:
		PanelCorner.TOP_LEFT:
			set_anchors_preset(Control.PRESET_TOP_LEFT)
			offset_left = PREVIEW_MARGIN
			offset_top = PREVIEW_MARGIN
			offset_right = offset_left + size.x
			offset_bottom = offset_top + size.y
		PanelCorner.BOTTOM_LEFT:
			set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			offset_left = PREVIEW_MARGIN
			offset_top = -PREVIEW_MARGIN - size.y
			offset_right = offset_left + size.x
			offset_bottom = -PREVIEW_MARGIN
		PanelCorner.TOP_RIGHT:
			set_anchors_preset(Control.PRESET_TOP_RIGHT)
			offset_left = -PREVIEW_MARGIN - size.x
			offset_top = PREVIEW_MARGIN
			offset_right = -PREVIEW_MARGIN
			offset_bottom = offset_top + size.y
		PanelCorner.BOTTOM_RIGHT:
			set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			offset_left = -PREVIEW_MARGIN - size.x
			offset_top = -PREVIEW_MARGIN - size.y
			offset_right = -PREVIEW_MARGIN
			offset_bottom = -PREVIEW_MARGIN


func _render_preview() -> void:
	pass


func _render_expanded() -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	if not can_expand or _state == PanelState.EXPANDED:
		return
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			if _is_primary_action_click(mouse.global_position):
				return
			expand()
			accept_event()


func _is_primary_action_click(_global_pos: Vector2) -> bool:
	return false
