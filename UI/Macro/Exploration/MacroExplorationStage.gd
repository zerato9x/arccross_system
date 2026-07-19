extends CanvasLayer
class_name MacroExplorationStage

## Unified exploration / event presentation surface.
## Modes: travel (non-blocking), event/collision (blocking), poi (blocking), result.

signal choice_submitted(choice_id: String)
signal event_closed
signal travel_beat_finished
signal poi_action_submitted(
	action: GameEnums.PoiAction,
	selected_item_ids: Array,
	selected_search_option_id: String
)
signal poi_preview_requested(
	action: GameEnums.PoiAction,
	selected_item_ids: Array,
	selected_search_option_id: String
)
signal inventory_action_requested(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary
)
signal interaction_closed
signal node_map_requested

var _session: Dictionary = {}
var _result: Dictionary = {}
var _choice_buttons: Array[Button] = []
var _choice_ids: Array[String] = []
var _mode := ""
var _blocking := false
var _open_tween: Tween
var _exploration_window: MacroExplorationWindow

@onready var _root: Control = %Root
@onready var _dim: ColorRect = %DimOverlay
@onready var _fx_layer: ExplorationFxLayer = %FxLayer
@onready var _travel: TravelBeatPresenter = %TravelBeat
@onready var _center: CenterContainer = %Center
@onready var _event_panel: PanelContainer = %EventPanel
@onready var _main_row: HBoxContainer = %MainRow
@onready var _image_frame: PanelContainer = %ImageFrame
@onready var _image_rect: TextureRect = %EventImage
@onready var _grid_preview_root: VBoxContainer = %GridPreview
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
@onready var _poi_host: Control = %PoiHost


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	_dim.visible = false
	_dim.modulate.a = 0.0
	_center.visible = false
	_event_panel.visible = false
	_poi_host.visible = false
	_travel.visible = false
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
	_travel.beat_finished.connect(func(): travel_beat_finished.emit())
	get_viewport().size_changed.connect(_update_layout_for_viewport)
	_update_layout_for_viewport()


func bind_exploration_window(window: MacroExplorationWindow) -> void:
	if _exploration_window == window:
		return
	if _exploration_window != null:
		_disconnect_exploration_window(_exploration_window)
	_exploration_window = window
	if _exploration_window == null:
		return
	_exploration_window.poi_action_submitted.connect(
		func(a, ids, opt): poi_action_submitted.emit(a, ids, opt)
	)
	_exploration_window.poi_preview_requested.connect(
		func(a, ids, opt): poi_preview_requested.emit(a, ids, opt)
	)
	_exploration_window.inventory_action_requested.connect(
		func(aid, iid, slot, payload): inventory_action_requested.emit(aid, iid, slot, payload)
	)
	_exploration_window.interaction_closed.connect(_on_poi_closed)
	_exploration_window.node_map_requested.connect(node_map_requested.emit)


func _disconnect_exploration_window(window: MacroExplorationWindow) -> void:
	if window.interaction_closed.is_connected(_on_poi_closed):
		window.interaction_closed.disconnect(_on_poi_closed)


func present_travel_beat(_session: Dictionary) -> void:
	# Travel feedback is owned by the world log + camera/trail systems.
	pass


func present_session(session: Dictionary) -> void:
	_dismiss_travel_quiet()
	_session = session.duplicate(true)
	_result.clear()
	_mode = str(_session.get("mode", "event"))
	if _mode.begins_with("collision"):
		_mode = "collision"
	elif _mode == "poi":
		present_poi(_session)
		return
	_blocking = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_poi_host.visible = false
	_center.visible = true
	_event_panel.visible = true
	_dim.visible = true
	_update_layout_for_viewport()
	_render_event()
	_animate_modal_open()


func open_event(session: Dictionary) -> void:
	var packed := session.duplicate(true)
	if not packed.has("mode"):
		packed["mode"] = "event"
	present_session(packed)


func present_poi(session: Dictionary, inventory_snapshot: Dictionary = {}) -> void:
	_dismiss_travel_quiet()
	_session = session.duplicate(true)
	_mode = "poi"
	_blocking = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_center.visible = false
	_event_panel.visible = false
	_dim.visible = true
	_dim.modulate.a = 1.0
	_poi_host.visible = false
	if _exploration_window == null:
		push_error("[MacroExplorationStage] POI opened without exploration window.")
		return
	var edge := 48.0
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x < 1280.0:
		edge = 18.0
	_exploration_window.present_as_stage_overlay(edge)
	_exploration_window.open_landmark(_session, inventory_snapshot)


func show_result(result: Dictionary) -> void:
	_result = result.duplicate(true)
	_mode = "result"
	_blocking = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_poi_host.visible = false
	_center.visible = true
	_event_panel.visible = true
	_dim.visible = true
	_update_layout_for_viewport()
	_render_result()
	_animate_modal_open()


func close_event(notify: bool = true) -> void:
	_kill_open_tween()
	_blocking = false
	_mode = ""
	_session.clear()
	_result.clear()
	_clear_choices()
	_clear_tags()
	_clear_grid_preview()
	_center.visible = false
	_event_panel.visible = false
	_dim.visible = false
	_dim.modulate.a = 0.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.clear_fx()
	if notify:
		event_closed.emit()


func close_poi(notify: bool = true) -> void:
	if _exploration_window and _exploration_window.is_open():
		_exploration_window.close_window(notify)
	else:
		_finish_poi_close(notify)


func clear_presentation(notify: bool = false) -> void:
	_dismiss_travel_quiet()
	if _mode == "poi" or (_exploration_window != null and _exploration_window.is_open()):
		if _exploration_window and _exploration_window.is_open():
			_exploration_window.close_window(false)
		_finish_poi_close(notify)
	elif _blocking:
		close_event(notify)
	else:
		_fx_layer.clear_fx()


func is_open() -> bool:
	if not _blocking:
		return false
	if _center.visible or _poi_host.visible:
		return true
	return _exploration_window != null and _exploration_window.is_open()


func is_travel_showing() -> bool:
	return _travel.is_showing()


func get_exploration_window() -> MacroExplorationWindow:
	return _exploration_window


func _on_poi_closed() -> void:
	_finish_poi_close(true)


func _finish_poi_close(notify: bool) -> void:
	_blocking = false
	_mode = ""
	_poi_host.visible = false
	_dim.visible = false
	_dim.modulate.a = 0.0
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_layer.clear_fx()
	if _exploration_window:
		_exploration_window.undock()
		_exploration_window.layer = 22
	if notify:
		interaction_closed.emit()


func _dismiss_travel_quiet() -> void:
	if _travel.is_showing():
		_travel.dismiss(true)


func _animate_modal_open() -> void:
	_kill_open_tween()
	_dim.modulate.a = 0.0
	_event_panel.modulate.a = 0.0
	_event_panel.scale = Vector2(0.94, 0.94)
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(_dim, "modulate:a", 1.0, 0.2)
	_open_tween.tween_property(_event_panel, "modulate:a", 1.0, 0.22)
	_open_tween.tween_property(_event_panel, "scale", Vector2.ONE, 0.28).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)


func _kill_open_tween() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_open_tween = null


func _input(event: InputEvent) -> void:
	if not _blocking:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
			if _mode == "poi":
				close_poi(true)
			elif _close_button.visible or _mode in ["event", "collision", "result"]:
				close_event(true)
			get_viewport().set_input_as_handled()
			return
	if _mode == "poi":
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
	_render_grid_preview(_session.get("grid_preview", {}))
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
	_clear_grid_preview()


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
		"talk":
			return "talk"
		"threat", "ambush":
			return "warning"
		"trade":
			return "inventory"
		"ceasefire", "pass":
			return "pass"
	return ""


func _render_grid_preview(preview: Dictionary) -> void:
	_clear_grid_preview()
	if _grid_preview_root == null or preview.is_empty():
		return
	_grid_preview_root.visible = true
	var caption := Label.new()
	caption.text = str(preview.get("caption", "Combat grid"))
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(caption, "muted")
	_grid_preview_root.add_child(caption)
	var lane_row := HBoxContainer.new()
	lane_row.add_theme_constant_override("separation", 4)
	lane_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_preview_root.add_child(lane_row)
	var lane_count := maxi(1, int(preview.get("lane_count", 12)))
	var player_lane := int(preview.get("player_lane", -1))
	var enemy_lane := int(preview.get("enemy_lane", -1))
	for lane_index in range(1, lane_count + 1):
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(28, 42)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_player := lane_index == player_lane
		var is_enemy := lane_index == enemy_lane
		HUDAssetLibrary.apply_panel(cell, "warning" if is_player or is_enemy else "neutral")
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 2)
		margin.add_theme_constant_override("margin_top", 2)
		margin.add_theme_constant_override("margin_right", 2)
		margin.add_theme_constant_override("margin_bottom", 2)
		cell.add_child(margin)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 2)
		margin.add_child(column)
		var index_label := Label.new()
		index_label.text = str(lane_index)
		index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		HUDAssetLibrary.apply_label(index_label, "muted")
		column.add_child(index_label)
		var marker := Label.new()
		if is_player and is_enemy:
			marker.text = "P/E"
		elif is_player:
			marker.text = "P"
		elif is_enemy:
			marker.text = "E"
		else:
			marker.text = "·"
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		HUDAssetLibrary.apply_label(marker, "warning" if is_player or is_enemy else "muted")
		column.add_child(marker)
		lane_row.add_child(cell)
	var legend := Label.new()
	legend.text = "P = player spawn   E = opponent spawn"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(legend, "muted")
	_grid_preview_root.add_child(legend)


func _clear_grid_preview() -> void:
	if _grid_preview_root == null:
		return
	for child in _grid_preview_root.get_children():
		_grid_preview_root.remove_child(child)
		child.queue_free()
	_grid_preview_root.visible = false


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
	_poi_host.offset_left = edge
	_poi_host.offset_top = edge
	_poi_host.offset_right = -edge
	_poi_host.offset_bottom = -edge


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
