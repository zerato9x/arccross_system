extends Node2D
class_name CombatActionButton

signal pressed(payload: Dictionary)
signal target_limb_focused(limb: int)
signal target_limb_unfocused

const HUDAssetLibrary := preload("res://UI/HUD/HUDAssetLibrary.gd")
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

@onready var _frame_sprite: Sprite2D = %FrameSprite
@onready var _icon_sprite: Sprite2D = %IconSprite
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

func get_target_limb() -> int:
	return int(
		_payload.get("target_limb", GameEnums.LimbRegion.UPPER_TORSO)
	)

func _apply_geometry() -> void:
	_frame_sprite.centered = false
	_frame_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon_sprite.centered = false
	_icon_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	_box.visible = false
	_border.visible = false
	_scale_frame_sprite()
	var shape := RectangleShape2D.new()
	shape.size = _button_size
	_collision.shape = shape
	_collision.position = _button_size * 0.5

func _refresh() -> void:
	var state := "disabled" if not _enabled else ("hover" if _hovered else "normal")
	_frame_sprite.texture = HUDAssetLibrary.button_texture(state)
	_scale_frame_sprite()
	_refresh_icon()
	_box.color = COLOR_DISABLED if not _enabled else (COLOR_HOVER if _hovered else COLOR_NORMAL)
	_border.default_color = COLOR_BORDER_HOVER if _hovered and _enabled else COLOR_BORDER
	_border.width = 2.0 if _hovered and _enabled else 1.2
	_label.modulate = COLOR_TEXT if _enabled else COLOR_MUTED
	_label.text = _display_text()

func _scale_frame_sprite() -> void:
	var texture := _frame_sprite.texture
	if texture == null:
		return
	_frame_sprite.scale = Vector2(
		_button_size.x / maxf(1.0, float(texture.get_width())),
		_button_size.y / maxf(1.0, float(texture.get_height()))
	)

func _refresh_icon() -> void:
	var texture := _icon_texture_for_payload()
	_icon_sprite.texture = texture
	_icon_sprite.visible = texture != null
	var label_left := 9.0
	if texture != null:
		_icon_sprite.position = Vector2(10.0, 9.0)
		_icon_sprite.scale = Vector2(
			22.0 / maxf(1.0, float(texture.get_width())),
			22.0 / maxf(1.0, float(texture.get_height()))
		)
		label_left = 38.0
	_label.position = Vector2(label_left, 5.0)
	_label.size = _button_size - Vector2(label_left + 9.0, 10.0)

func _icon_texture_for_payload() -> Texture2D:
	var mode := str(_payload.get("mode", ""))
	if mode == "pass":
		return HUDAssetLibrary.combat_icon("pass")
	if mode == "reaction":
		return HUDAssetLibrary.combat_icon("reaction")
	var descriptor: Dictionary = _payload.get("descriptor", {})
	var label := str(descriptor.get("label", _base_text)).to_lower()
	if label.contains("reload"):
		return HUDAssetLibrary.combat_icon("reload")
	if label.contains("cycle"):
		return HUDAssetLibrary.combat_icon("cycle")
	if label.contains("shoot") or label.contains("fire") or label.contains("snipe"):
		return HUDAssetLibrary.combat_icon("shoot")
	if label.contains("block") or label.contains("guard"):
		return HUDAssetLibrary.combat_icon("block")
	if label.contains("dodge") or label.contains("evade"):
		return HUDAssetLibrary.combat_icon("dodge")
	if label.contains("grapple"):
		return HUDAssetLibrary.combat_icon("grapple")
	if label.contains("break"):
		return HUDAssetLibrary.combat_icon("break_guard")
	if label.contains("cover"):
		return HUDAssetLibrary.combat_icon("cover")
	if label.contains("execute"):
		return HUDAssetLibrary.combat_icon("execute")
	if label.contains("pass"):
		return HUDAssetLibrary.combat_icon("pass")
	return HUDAssetLibrary.combat_icon("melee")

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
	_emit_target_focus()

func _apply_target_to_payload() -> void:
	if _target_limbs.is_empty():
		_payload["target_limb"] = GameEnums.LimbRegion.UPPER_TORSO
		return
	_payload["target_limb"] = int(_target_limbs[_target_limb_index])

func _emit_target_focus() -> void:
	if _target_limbs.is_empty():
		return
	target_limb_focused.emit(get_target_limb())

func _set_hovered(value: bool) -> void:
	_hovered = value
	_refresh()
	if _target_limbs.is_empty():
		return
	if _hovered:
		_emit_target_focus()
	else:
		target_limb_unfocused.emit()

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
