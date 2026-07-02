extends PanelContainer
class_name InteractionDropTarget

signal item_dropped(instance_id: String, target_id: String)

@export var target_id: String = ""
@export var accepted_roles: Array[int] = []

const _EMPTY_STYLE_COLOR := Color("#141a22")
const _EMPTY_STYLE_BORDER := Color("#4a6a86")
const _FILLED_STYLE_COLOR := Color("#1c2416")
const _FILLED_STYLE_BORDER := Color("#8fae57")

var _label: Label
var _icon_rect: TextureRect
var _highlight: ColorRect
var _column: VBoxContainer
var _assigned_instance_id := ""
var _target_label := ""

func _ready() -> void:
	custom_minimum_size = Vector2(120, 84)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()
	_apply_box_style()

func configure(new_target_id: String, new_target_label: String, roles: Array) -> void:
	target_id = new_target_id
	_target_label = new_target_label
	accepted_roles.clear()
	for role in roles:
		accepted_roles.append(int(role))
	if _label:
		_label.text = _target_label

func set_assigned_instance(
	instance_id: String,
	item_name: String = "",
	sprite_path: String = ""
) -> void:
	_assigned_instance_id = instance_id
	if _label:
		_label.text = item_name if not item_name.is_empty() else _target_label
	_set_icon(sprite_path)
	_apply_box_style()

func get_assigned_instance() -> String:
	return _assigned_instance_id

func clear_assignment() -> void:
	_assigned_instance_id = ""
	if _label:
		_label.text = _target_label
	_set_icon("")
	_apply_box_style()

func _build_shell() -> void:
	_highlight = ColorRect.new()
	_highlight.color = Color(0.2, 0.35, 0.2, 0.0)
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 4)
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_column)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(36, 36)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.visible = false
	_column.add_child(_icon_rect)

	_label = Label.new()
	_label.text = target_id
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HUDAssetLibrary.apply_label(_label, "muted")
	_column.add_child(_label)

func _set_icon(sprite_path: String) -> void:
	if _icon_rect == null:
		return
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		_icon_rect.texture = load(sprite_path)
		_icon_rect.visible = true
	else:
		_icon_rect.texture = null
		_icon_rect.visible = false

func _apply_box_style() -> void:
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(3)
	style.set_border_width_all(2)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	if _assigned_instance_id.is_empty():
		style.bg_color = _EMPTY_STYLE_COLOR
		style.border_color = _EMPTY_STYLE_BORDER
	else:
		style.bg_color = _FILLED_STYLE_COLOR
		style.border_color = _FILLED_STYLE_BORDER
	add_theme_stylebox_override("panel", style)

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var payload := _extract_drag_payload(data)
	if payload.is_empty():
		_set_highlight(false)
		return false
	var roles: Array = payload.get("interaction_roles", [])
	for role in accepted_roles:
		if roles.has(role):
			_set_highlight(true)
			return true
	_set_highlight(false)
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload := _extract_drag_payload(data)
	if payload.is_empty():
		return
	var instance_id: String = str(payload.get("instance_id", ""))
	if instance_id.is_empty():
		return
	set_assigned_instance(
		instance_id,
		str(payload.get("name", target_id)),
		str(payload.get("sprite_path", ""))
	)
	item_dropped.emit(instance_id, target_id)
	_set_highlight(false)

func _extract_drag_payload(data: Variant) -> Dictionary:
	if data is Dictionary:
		return data
	if data is InventorySlot and data.has_item():
		var descriptor: Dictionary = data.item_descriptor
		return {
			"instance_id": str(descriptor.get("instance_id", "")),
			"name": str(descriptor.get("name", "")),
			"sprite_path": str(descriptor.get("sprite_path", "")),
			"interaction_roles": descriptor.get(
				"interaction_roles",
				descriptor.get("roles", [])
			),
		}
	return {}

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_set_highlight(false)

func _set_highlight(active: bool) -> void:
	if _highlight:
		_highlight.color = (
			Color(0.25, 0.55, 0.25, 0.35)
			if active
			else Color(0.2, 0.35, 0.2, 0.0)
		)
