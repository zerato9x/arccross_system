extends Node2D
class_name CombatActionButton

signal pressed(payload: Dictionary)
signal target_limb_focused(limb: int)
signal target_limb_unfocused

const HUDAssetLibrary := preload("res://UI/HUD/HUDAssetLibrary.gd")
const COLOR_NORMAL := Color("#1c2c33")
const COLOR_HOVER := Color("#2d4650")
const COLOR_DISABLED := Color("#10191d")
const COLOR_BORDER := Color("#66848d")
const COLOR_BORDER_HOVER := Color("#efe1bd")
const COLOR_TEXT := HUDAssetLibrary.COLOR_TEXT
const COLOR_MUTED := HUDAssetLibrary.COLOR_MUTED

var _payload: Dictionary = {}
var _base_text := ""
var _button_size := Vector2(168.0, 42.0)
var _enabled := true
var _hovered := false
var _target_limbs: Array = []
var _target_limb_index := 0

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
	_box.visible = true
	_border.visible = true
	var shape := RectangleShape2D.new()
	shape.size = _button_size
	_collision.shape = shape
	_collision.position = _button_size * 0.5

func _refresh() -> void:
	_refresh_icon()
	_box.color = COLOR_DISABLED if not _enabled else (COLOR_HOVER if _hovered else COLOR_NORMAL)
	_border.default_color = COLOR_BORDER_HOVER if _hovered and _enabled else COLOR_BORDER
	_border.width = 2.0 if _hovered and _enabled else 1.2
	_label.modulate = COLOR_TEXT if _enabled else COLOR_MUTED
	_label.text = _display_text()

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
