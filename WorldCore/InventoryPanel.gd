extends CanvasLayer
class_name InventoryPanel

signal inventory_action_requested(
	action_id: String,
	instance_id: String,
	equipment_slot: int
)
signal inventory_closed

const ACTION_TAKE := "take"
const ACTION_DROP := "drop"
const ACTION_EQUIP := "equip"
const ACTION_UNEQUIP := "unequip"
const ACTION_CONSUME := "consume"

var _panel: PanelContainer
var _content: VBoxContainer
var _snapshot: Dictionary = {}
var _feedback: String = ""

func _ready() -> void:
	layer = 30
	_build_shell()
	close_panel(false)

func open_inventory(snapshot: Dictionary, feedback: String = "") -> void:
	_snapshot = snapshot.duplicate(true)
	_feedback = feedback
	_panel.visible = true
	_render()

func close_panel(notify: bool = true) -> void:
	if _panel:
		_panel.visible = false
	_snapshot.clear()
	_feedback = ""
	if notify:
		inventory_closed.emit()

func is_open() -> bool:
	return _panel != null and _panel.visible

func _build_shell() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.offset_left = -390.0
	_panel.offset_top = -350.0
	_panel.offset_right = 390.0
	_panel.offset_bottom = 350.0
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	_panel.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 10)
	margin.add_child(_content)

func _render() -> void:
	_clear_content()
	_add_title("INVENTORY")

	var clock: Dictionary = _snapshot.get("world_time", {})
	_add_body(
		"Hex %s | Day %d, %02d:%02d | Capacity %d / %d"
		% [
			str(_snapshot.get("coords", Vector2i.ZERO)),
			clock.get("day", 1),
			clock.get("hour", 0),
			clock.get("minute", 0),
			_snapshot.get("current_capacity", 0),
			_snapshot.get("maximum_capacity", 0),
		]
	)
	if not _feedback.is_empty():
		var feedback_label := _add_body(_feedback)
		feedback_label.modulate = Color(0.95, 0.82, 0.35)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(scroll)

	var lists := VBoxContainer.new()
	lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lists.add_theme_constant_override("separation", 14)
	scroll.add_child(lists)

	_add_item_section(
		lists,
		"EQUIPPED",
		_snapshot.get("equipment", []),
		"equipment"
	)
	_add_item_section(
		lists,
		"BACKPACK",
		_snapshot.get("backpack", []),
		"backpack"
	)
	_add_item_section(
		lists,
		"GROUND",
		_snapshot.get("ground", []),
		"ground"
	)
	_add_button(_content, "CLOSE", close_panel)

func _add_item_section(
	parent: VBoxContainer,
	title: String,
	items: Array,
	source: String
) -> void:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 6)
	parent.add_child(section)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 18)
	section.add_child(heading)

	if items.is_empty():
		var empty := Label.new()
		empty.text = "None"
		empty.modulate = Color(0.65, 0.65, 0.65)
		section.add_child(empty)
		return

	for descriptor in items:
		_add_item_row(section, descriptor, source)

func _add_item_row(
	parent: VBoxContainer,
	descriptor: Dictionary,
	source: String
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = _format_item_label(descriptor, source)
	label.tooltip_text = descriptor.get("description", "")
	row.add_child(label)

	var instance_id: String = descriptor.get("instance_id", "")
	var slot: int = descriptor.get(
		"equipment_slot",
		GameEnums.EquipmentSlot.NONE
	)
	match source:
		"ground":
			_add_action_button(row, "TAKE", ACTION_TAKE, instance_id, slot)
		"equipment":
			_add_action_button(
				row,
				"UNEQUIP",
				ACTION_UNEQUIP,
				instance_id,
				slot
			)
		"backpack":
			if descriptor.get("can_equip", false):
				_add_action_button(
					row,
					"EQUIP",
					ACTION_EQUIP,
					instance_id,
					descriptor.get(
						"target_slot",
						GameEnums.EquipmentSlot.NONE
					)
				)
			if descriptor.get("can_consume", false):
				_add_action_button(
					row,
					"USE",
					ACTION_CONSUME,
					instance_id,
					GameEnums.EquipmentSlot.NONE
				)
			_add_action_button(
				row,
				"DROP",
				ACTION_DROP,
				instance_id,
				GameEnums.EquipmentSlot.NONE
			)

func _format_item_label(descriptor: Dictionary, source: String) -> String:
	var prefix := ""
	if source == "equipment":
		var slot: int = descriptor.get(
			"equipment_slot",
			GameEnums.EquipmentSlot.NONE
		)
		prefix = "%s: " % GameEnums.EquipmentSlot.keys()[slot]
	return "%s%s [size %d]" % [
		prefix,
		descriptor.get("name", "Unknown Item"),
		descriptor.get("size_cost", 0),
	]

func _add_action_button(
	parent: Control,
	text: String,
	action_id: String,
	instance_id: String,
	equipment_slot: int
) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(
		_emit_action.bind(action_id, instance_id, equipment_slot)
	)
	parent.add_child(button)

func _emit_action(
	action_id: String,
	instance_id: String,
	equipment_slot: int
) -> void:
	inventory_action_requested.emit(action_id, instance_id, equipment_slot)

func _add_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	_content.add_child(title)

func _add_body(text: String) -> Label:
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(body)
	return body

func _add_button(
	parent: Control,
	text: String,
	callback: Callable
) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _clear_content() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
