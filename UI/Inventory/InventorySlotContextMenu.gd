extends PanelContainer
class_name InventorySlotContextMenu

signal menu_action_chosen(entry: Dictionary)
signal menu_closed
signal menu_presented(menu_rect: Rect2)

const MENU_MIN_WIDTH := 210.0
const MENU_PADDING := 8.0

@onready var _header_label: Label = %HeaderLabel
@onready var _header_separator: HSeparator = %HeaderSeparator
@onready var _actions_box: VBoxContainer = %ActionsBox


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = MENU_MIN_WIDTH
	set_process_unhandled_input(true)
	HUDAssetLibrary.apply_panel(self, "neutral")


func open_at(global_pos: Vector2, header: String, entries: Array) -> void:
	_clear_actions()
	if entries.is_empty():
		return

	_header_label.text = header
	var show_header := not header.is_empty()
	_header_label.visible = show_header
	_header_separator.visible = show_header

	for entry in entries:
		if not entry is Dictionary:
			continue
		var button := Button.new()
		button.flat = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.text = "  %s" % str(entry.get("label", "Action"))
		button.disabled = not bool(entry.get("enabled", true))
		button.focus_mode = Control.FOCUS_ALL
		var captured: Dictionary = entry.duplicate(true)
		button.pressed.connect(_on_action_pressed.bind(captured))
		_actions_box.add_child(button)

	reset_size()
	call_deferred("_present_at", global_pos)


func close_menu() -> void:
	if not visible:
		return
	visible = false
	menu_closed.emit()


func _present_at(global_pos: Vector2) -> void:
	reset_size()
	var menu_size := get_combined_minimum_size()
	if menu_size == Vector2.ZERO:
		menu_size = Vector2(MENU_MIN_WIDTH, 48.0)
	size = menu_size
	global_position = _clamped_global_position(global_pos, menu_size)
	visible = true
	if _actions_box.get_child_count() > 0:
		(_actions_box.get_child(0) as Control).grab_focus()
	menu_presented.emit(Rect2(global_position, menu_size))


func _clamped_global_position(anchor: Vector2, menu_size: Vector2) -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	var popup_pos := anchor
	if popup_pos.x + menu_size.x > viewport_size.x - MENU_PADDING:
		popup_pos.x = maxf(MENU_PADDING, viewport_size.x - menu_size.x - MENU_PADDING)
	if popup_pos.y + menu_size.y > viewport_size.y - MENU_PADDING:
		popup_pos.y = maxf(MENU_PADDING, viewport_size.y - menu_size.y - MENU_PADDING)
	return Vector2(
		clampf(popup_pos.x, MENU_PADDING, maxf(MENU_PADDING, viewport_size.x - menu_size.x - MENU_PADDING)),
		clampf(popup_pos.y, MENU_PADDING, maxf(MENU_PADDING, viewport_size.y - menu_size.y - MENU_PADDING))
	)


func _clear_actions() -> void:
	for child in _actions_box.get_children():
		child.queue_free()


func _on_action_pressed(entry: Dictionary) -> void:
	if not entry.get("enabled", true):
		return
	visible = false
	menu_action_chosen.emit(entry)
	menu_closed.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if not get_global_rect().has_point(event.global_position):
			close_menu()
			get_viewport().set_input_as_handled()
