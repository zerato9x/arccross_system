extends PanelContainer
class_name InteractionDropTarget

signal item_dropped(instance_id: String, target_id: String)
signal item_cleared(instance_id: String, target_id: String)
signal context_menu_requested(global_position: Vector2)

@export var target_id: String = ""
@export var accepted_roles: Array[int] = []

const _EMPTY_STYLE_COLOR := Color("#141a22")
const _EMPTY_STYLE_BORDER := Color("#4a6a86")
const _FILLED_STYLE_BORDER := Color("#8fae57")
const _FILLED_STYLE_COLOR := Color("#1c2416")

var _slot_label: Label
var _item_label: Label
var _icon_rect: TextureRect
var _highlight: ColorRect
var _column: VBoxContainer
var _assigned_instance_id := ""
var _assigned_name := ""
var _assigned_sprite_path := ""
var _slot_title := ""

func _ready() -> void:
	custom_minimum_size = Vector2(108, 88)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_build_shell()
	_apply_box_style()

func configure(new_target_id: String, new_target_label: String, roles: Array) -> void:
	target_id = new_target_id
	_slot_title = new_target_label
	accepted_roles.clear()
	for role in roles:
		accepted_roles.append(int(role))
	tooltip_text = _slot_title + "\nRight-click for actions."
	if _slot_label:
		_slot_label.text = _slot_title
	if _item_label:
		_item_label.text = ""

func set_assigned_instance(
	instance_id: String,
	item_name: String = "",
	sprite_path: String = ""
) -> void:
	_assigned_instance_id = instance_id
	_assigned_name = item_name
	_assigned_sprite_path = sprite_path
	if _item_label:
		_item_label.text = item_name if not item_name.is_empty() else ""
	if _slot_label:
		_slot_label.text = _slot_title
	_set_icon(sprite_path)
	_apply_box_style()

func get_assigned_instance() -> String:
	return _assigned_instance_id


func get_slot_label() -> String:
	return _slot_title

func get_assignment_payload() -> Dictionary:
	if _assigned_instance_id.is_empty():
		return {}
	return {
		"instance_id": _assigned_instance_id,
		"name": _assigned_name,
		"sprite_path": _assigned_sprite_path,
	}

func clear_assignment() -> void:
	_assigned_instance_id = ""
	_assigned_name = ""
	_assigned_sprite_path = ""
	if _item_label:
		_item_label.text = ""
	if _slot_label:
		_slot_label.text = _slot_title
	_set_icon("")
	_apply_box_style()

func _build_shell() -> void:
	_highlight = ColorRect.new()
	_highlight.color = Color(0.2, 0.35, 0.2, 0.0)
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight)

	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 2)
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_column)

	_slot_label = Label.new()
	_slot_label.text = target_id
	_slot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HUDAssetLibrary.apply_label(_slot_label, "muted")
	_column.add_child(_slot_label)

	_icon_rect = TextureRect.new()
	_icon_rect.custom_minimum_size = Vector2(32, 32)
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.visible = false
	_column.add_child(_icon_rect)

	_item_label = Label.new()
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	HUDAssetLibrary.apply_label(_item_label, "body")
	_column.add_child(_item_label)

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
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	if _assigned_instance_id.is_empty():
		style.bg_color = _EMPTY_STYLE_COLOR
		style.border_color = _EMPTY_STYLE_BORDER
	else:
		style.bg_color = _FILLED_STYLE_COLOR
		style.border_color = _FILLED_STYLE_BORDER
	add_theme_stylebox_override("panel", style)

func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if _assigned_instance_id.is_empty():
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		context_menu_requested.emit(event.global_position)
		accept_event()
		return
	var clear_requested: bool = (
		event.button_index == MOUSE_BUTTON_LEFT
		and event.double_click
	)
	if not clear_requested:
		return
	var cleared_id := _assigned_instance_id
	clear_assignment()
	item_cleared.emit(cleared_id, target_id)
	accept_event()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if _assigned_instance_id.is_empty():
		return null
	var preview := TextureRect.new()
	if not _assigned_sprite_path.is_empty() and ResourceLoader.exists(_assigned_sprite_path):
		preview.texture = load(_assigned_sprite_path)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(48, 48)
	preview.modulate = Color(1, 1, 1, 0.88)
	var preview_control := Control.new()
	preview_control.add_child(preview)
	preview.position = -preview.custom_minimum_size * 0.5
	set_drag_preview(preview_control)
	return {
		"instance_id": _assigned_instance_id,
		"name": _assigned_name,
		"sprite_path": _assigned_sprite_path,
		"interaction_roles": accepted_roles.duplicate(),
		"source_drop_target": self,
	}

func accepts_descriptor(descriptor: Dictionary) -> bool:
	var roles: Array = descriptor.get(
		"interaction_roles",
		descriptor.get("roles", [])
	)
	for role in accepted_roles:
		if roles.has(role):
			return true
	return false

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var payload := _extract_drag_payload(data)
	if payload.is_empty():
		_set_highlight(false)
		return false
	if payload.get("source_drop_target", null) == self:
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
	var source_target: InteractionDropTarget = payload.get("source_drop_target", null)
	if source_target != null and source_target != self:
		source_target.clear_assignment()
		source_target.item_cleared.emit(
			str(payload.get("instance_id", "")),
			source_target.target_id
		)
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
