extends PanelContainer
class_name InteractionDropTarget

signal item_dropped(instance_id: String, target_id: String)

@export var target_id: String = ""
@export var accepted_roles: Array[int] = []

var _label: Label
var _highlight: ColorRect
var _assigned_instance_id := ""

func _ready() -> void:
	custom_minimum_size = Vector2(120, 48)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_shell()

func configure(target_label: String, roles: Array) -> void:
	target_id = target_label
	accepted_roles.clear()
	for role in roles:
		accepted_roles.append(int(role))
	if _label:
		_label.text = target_label

func set_assigned_instance(instance_id: String, item_name: String = "") -> void:
	_assigned_instance_id = instance_id
	if _label:
		_label.text = item_name if not item_name.is_empty() else target_id

func get_assigned_instance() -> String:
	return _assigned_instance_id

func clear_assignment() -> void:
	_assigned_instance_id = ""
	if _label:
		_label.text = target_id

func _build_shell() -> void:
	_highlight = ColorRect.new()
	_highlight.color = Color(0.2, 0.35, 0.2, 0.0)
	_highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_highlight)

	_label = Label.new()
	_label.text = target_id
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_label)

	HUDAssetLibrary.apply_panel(self, "neutral")

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
	_assigned_instance_id = instance_id
	_label.text = str(payload.get("name", target_id))
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
