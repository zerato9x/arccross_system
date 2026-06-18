extends Node2D
class_name CombatActionButton

signal pressed(payload: Dictionary)

const COLOR_NORMAL := Color(0.12, 0.13, 0.12, 0.96)
const COLOR_HOVER := Color(0.22, 0.24, 0.21, 0.98)
const COLOR_DISABLED := Color(0.08, 0.085, 0.08, 0.82)
const COLOR_BORDER := Color(0.62, 0.60, 0.50, 0.92)
const COLOR_BORDER_HOVER := Color(0.86, 0.75, 0.50, 1.0)
const COLOR_TEXT := Color(0.83, 0.85, 0.80, 1.0)
const COLOR_MUTED := Color(0.48, 0.50, 0.47, 1.0)

var _payload: Dictionary = {}
var _base_text := ""
var _button_size := Vector2(168.0, 42.0)
var _enabled := true
var _hovered := false
var _target_limbs: Array = []
var _target_limb_index := 0

@onready var _box: Polygon2D = %ButtonBox
@onready var _border: Line2D = %Border
@onready var _label: Label = %Label
@onready var _area: Area2D = %HitArea
@onready var _collision: CollisionShape2D = %CollisionShape2D

func _ready() -> void:
	_area.input_pickable = true
	_area.mouse_entered.connect(_set_hovered.bind(true))
	_area.mouse_exited.connect(_set_hovered.bind(false))
	_area.input_event.connect(_on_input_event)
	_apply_geometry()
	_refresh()

func set_button_size(value: Vector2) -> void:
	_button_size = value
	if is_inside_tree():
		_apply_geometry()
		_refresh()

func configure(
	payload: Dictionary,
	base_text: String,
	enabled: bool = true
) -> void:
	_payload = payload.duplicate(true)
	_base_text = base_text
	_enabled = enabled
	_target_limbs = _payload.get("target_limbs", [])
	_target_limb_index = 0
	_apply_target_to_payload()
	if is_inside_tree():
		_refresh()

func activate() -> void:
	if not _enabled:
		return
	pressed.emit(_payload.duplicate(true))

func get_payload() -> Dictionary:
	return _payload.duplicate(true)

func _apply_geometry() -> void:
	_box.polygon = PackedVector2Array([
		Vector2.ZERO,
		Vector2(_button_size.x, 0.0),
		_button_size,
		Vector2(0.0, _button_size.y),
	])
	_border.points = PackedVector2Array([
		Vector2.ZERO,
		Vector2(_button_size.x, 0.0),
		_button_size,
		Vector2(0.0, _button_size.y),
		Vector2.ZERO,
	])
	_label.position = Vector2(9.0, 5.0)
	_label.size = _button_size - Vector2(18.0, 10.0)
	var shape := RectangleShape2D.new()
	shape.size = _button_size
	_collision.shape = shape
	_collision.position = _button_size * 0.5

func _refresh() -> void:
	_box.color = COLOR_DISABLED if not _enabled else (COLOR_HOVER if _hovered else COLOR_NORMAL)
	_border.default_color = COLOR_BORDER_HOVER if _hovered and _enabled else COLOR_BORDER
	_border.width = 2.0 if _hovered and _enabled else 1.2
	_label.modulate = COLOR_TEXT if _enabled else COLOR_MUTED
	_label.text = _display_text()

func _display_text() -> String:
	if _target_limbs.is_empty():
		return _base_text
	var limb := int(_target_limbs[_target_limb_index])
	return "%s\nTARGET %s" % [_base_text, _limb_code(limb)]

func _cycle_target_limb() -> void:
	if _target_limbs.is_empty():
		return
	_target_limb_index = (_target_limb_index + 1) % _target_limbs.size()
	_apply_target_to_payload()
	_refresh()

func _apply_target_to_payload() -> void:
	if _target_limbs.is_empty():
		_payload["target_limb"] = GameEnums.LimbRegion.UPPER_TORSO
		return
	_payload["target_limb"] = int(_target_limbs[_target_limb_index])

func _set_hovered(value: bool) -> void:
	_hovered = value
	_refresh()

func _on_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if not _enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_cycle_target_limb()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			activate()
			get_viewport().set_input_as_handled()

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
