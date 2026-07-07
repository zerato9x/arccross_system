extends CanvasLayer
class_name MacroEventHud

signal choice_submitted(choice_id: String)
signal event_closed

var _session: Dictionary = {}
var _result: Dictionary = {}
var _choice_buttons: Array[Button] = []
var _choice_ids: Array[String] = []

@onready var _root: Control = %Root
@onready var _center: CenterContainer = %Center
@onready var _event_panel: PanelContainer = %EventPanel
@onready var _main_row: HBoxContainer = %MainRow
@onready var _image_frame: PanelContainer = %ImageFrame
@onready var _image_rect: TextureRect = %EventImage
@onready var _text_column: VBoxContainer = %TextColumn
@onready var _title_label: Label = %TitleLabel
@onready var _body_label: Label = %BodyLabel
@onready var _tag_row: HFlowContainer = %TagRow
@onready var _choice_scroll: ScrollContainer = %ChoiceScroll
@onready var _choice_list: VBoxContainer = %ChoiceList
@onready var _result_box: PanelContainer = %ResultBox
@onready var _result_title: Label = %ResultTitle
@onready var _result_meta: Label = %ResultMeta
@onready var _result_body: Label = %ResultBody
@onready var _continue_button: Button = %ContinueButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	HUDAssetLibrary.apply_panel(_event_panel, "warning")
	HUDAssetLibrary.apply_panel(_result_box, "neutral")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_label(_body_label, "body")
	HUDAssetLibrary.apply_label(_result_title, "warning")
	HUDAssetLibrary.apply_label(_result_meta, "muted")
	HUDAssetLibrary.apply_label(_result_body, "body")
	HUDAssetLibrary.apply_button(_continue_button, "pass")
	HUDAssetLibrary.apply_button(_close_button, "pass")
	_continue_button.pressed.connect(close_event)
	_close_button.pressed.connect(close_event)
	get_viewport().size_changed.connect(_update_layout_for_viewport)
	_update_layout_for_viewport()


func open_event(session: Dictionary) -> void:
	_session = session.duplicate(true)
	_result.clear()
	visible = true
	_update_layout_for_viewport()
	_render_event()


func show_result(result: Dictionary) -> void:
	_result = result.duplicate(true)
	visible = true
	_update_layout_for_viewport()
	_render_result()


func close_event(notify: bool = true) -> void:
	visible = false
	_session.clear()
	_result.clear()
	_clear_choices()
	_clear_tags()
	if notify:
		event_closed.emit()


func is_open() -> bool:
	return visible


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		get_viewport().set_input_as_handled()
		return
	if _result_box.visible:
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER or key.keycode == KEY_SPACE:
			close_event()
		get_viewport().set_input_as_handled()
		return
	var choice_index := _choice_index_for_key(key)
	if choice_index >= 0:
		_submit_choice_index(choice_index)
	elif key.keycode == KEY_ESCAPE and _close_button.visible:
		close_event()
	get_viewport().set_input_as_handled()


func _render_event() -> void:
	_result_box.visible = false
	_continue_button.visible = false
	_close_button.visible = bool(_session.get("can_close", false))
	_title_label.text = str(_session.get("title", "EVENT"))
	_body_label.text = str(_session.get("body", ""))
	_apply_event_image(str(_session.get("image_path", "")))
	_render_tags(_session.get("tags", []))
	_render_choices(_session.get("choices", []))
	_focus_first_enabled_choice()


func _render_result() -> void:
	_clear_choices()
	_render_tags(_session.get("tags", []))
	_result_box.visible = true
	_continue_button.visible = true
	_close_button.visible = false
	_title_label.text = str(_session.get("title", "EVENT"))
	_body_label.text = str(_session.get("body", ""))
	_result_title.text = str(_result.get("title", "RESULT"))
	var effects: Dictionary = _result.get("effects", {})
	_result_meta.text = _format_effects(effects)
	_result_meta.visible = not _result_meta.text.is_empty()
	_result_body.text = str(_result.get("body", ""))
	if _result.has("image_path"):
		_apply_event_image(str(_result.get("image_path", "")))


func _apply_event_image(path: String) -> void:
	_image_rect.texture = null
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	_image_rect.texture = load(path) as Texture2D


func _render_tags(tags: Array) -> void:
	_clear_tags()
	for tag in tags:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		HUDAssetLibrary.apply_panel(chip, "neutral")

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 7)
		margin.add_theme_constant_override("margin_top", 3)
		margin.add_theme_constant_override("margin_right", 7)
		margin.add_theme_constant_override("margin_bottom", 3)
		chip.add_child(margin)

		var label := Label.new()
		label.text = str(tag)
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		HUDAssetLibrary.apply_label(label, "muted")
		margin.add_child(label)
		_tag_row.add_child(chip)


func _render_choices(choices: Array) -> void:
	_clear_choices()
	for index in range(choices.size()):
		var choice = choices[index]
		if not (choice is Dictionary):
			continue
		_choice_list.add_child(_build_choice_row(choice, index + 1))


func _build_choice_row(choice: Dictionary, choice_number: int) -> Control:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HUDAssetLibrary.apply_panel(row, "neutral" if bool(choice.get("enabled", true)) else "anomaly")

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	row.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)

	var button := Button.new()
	button.text = "%d. %s" % [choice_number, str(choice.get("label", "Choice"))]
	button.disabled = not bool(choice.get("enabled", true))
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size()
	HUDAssetLibrary.apply_button(button, _icon_for_choice(choice))
	var choice_id := str(choice.get("id", ""))
	_choice_ids.append(choice_id)
	_choice_buttons.append(button)
	button.pressed.connect(func(): _submit_choice(choice_id))
	column.add_child(button)

	var meta_row := HFlowContainer.new()
	meta_row.add_theme_constant_override("h_separation", 6)
	meta_row.add_theme_constant_override("v_separation", 4)
	_add_chip(meta_row, "READY" if not button.disabled else "LOCKED", not button.disabled)
	for chip_text in choice.get("stakes", []):
		_add_chip(meta_row, str(chip_text), not button.disabled)
	column.add_child(meta_row)

	var reason := Label.new()
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reason.text = str(
		choice.get(
			"reason",
			"Available." if bool(choice.get("enabled", true)) else "Unavailable."
		)
	)
	HUDAssetLibrary.apply_label(reason, "warning" if button.disabled else "muted")
	column.add_child(reason)

	var preview_text := str(choice.get("preview", ""))
	if not preview_text.is_empty():
		var preview := Label.new()
		preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.text = preview_text
		HUDAssetLibrary.apply_label(preview, "body")
		column.add_child(preview)

	return row


func _add_chip(row: HFlowContainer, text: String, enabled: bool = true) -> void:
	if text.is_empty():
		return
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	HUDAssetLibrary.apply_panel(chip, "neutral" if enabled else "anomaly")

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 2)
	chip.add_child(margin)

	var label := Label.new()
	label.text = text
	HUDAssetLibrary.apply_label(label, "muted" if enabled else "warning")
	margin.add_child(label)
	row.add_child(chip)


func _format_effects(effects: Dictionary) -> String:
	var parts: PackedStringArray = []
	var elapsed := int(effects.get("elapsed_minutes", 0))
	if elapsed > 0:
		parts.append("+%d min" % elapsed)
	var exertion := float(effects.get("exertion", 0.0))
	if not is_zero_approx(exertion):
		parts.append("exertion %.2f" % exertion)
	return " | ".join(parts)


func _icon_for_choice(choice: Dictionary) -> String:
	var kind := str(choice.get("kind", ""))
	match kind:
		"observe":
			return "map"
		"force":
			return "warning"
		"item":
			return "inventory"
	return ""


func _submit_choice(choice_id: String) -> void:
	if choice_id.is_empty():
		return
	choice_submitted.emit(choice_id)


func _submit_choice_index(index: int) -> void:
	if index < 0 or index >= _choice_buttons.size():
		return
	var button := _choice_buttons[index]
	if button == null or button.disabled:
		return
	_submit_choice(_choice_ids[index])


func _choice_index_for_key(key: InputEventKey) -> int:
	if key.keycode >= KEY_1 and key.keycode <= KEY_9:
		return key.keycode - KEY_1
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_9:
		return key.physical_keycode - KEY_1
	if key.unicode >= 49 and key.unicode <= 57:
		return key.unicode - 49
	return -1


func _focus_first_enabled_choice() -> void:
	for button in _choice_buttons:
		if button != null and not button.disabled:
			button.grab_focus()
			return


func _update_layout_for_viewport() -> void:
	if _center == null or _event_panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var edge := 48.0 if viewport_size.x >= 1280.0 else 18.0
	_center.offset_left = edge
	_center.offset_top = edge
	_center.offset_right = -edge
	_center.offset_bottom = -edge

	var panel_width = maxf(600.0, viewport_size.x - edge * 2.0)
	var panel_height = maxf(460.0, viewport_size.y - edge * 2.0)
	panel_width = minf(panel_width, 1180.0)
	panel_height = minf(panel_height, 760.0)
	_event_panel.custom_minimum_size = Vector2(panel_width, panel_height)

	var image_width = clampf(panel_width * 0.52, 260.0, 590.0)
	if viewport_size.x < 900.0:
		image_width = clampf(panel_width * 0.42, 220.0, 360.0)
	_image_frame.custom_minimum_size = Vector2(image_width, 0.0)
	_text_column.custom_minimum_size = Vector2(maxf(320.0, panel_width - image_width - 78.0), 0.0)
	_choice_scroll.custom_minimum_size = Vector2(0.0, maxf(180.0, panel_height * 0.36))


func _clear_choices() -> void:
	_choice_buttons.clear()
	_choice_ids.clear()
	for child in _choice_list.get_children():
		_choice_list.remove_child(child)
		child.queue_free()


func _clear_tags() -> void:
	for child in _tag_row.get_children():
		_tag_row.remove_child(child)
		child.queue_free()
