extends CanvasLayer
class_name MacroInteractionPanel

signal poi_action_submitted(action: GameEnums.PoiAction, selected_item_ids: Array)
signal poi_preview_requested(action: GameEnums.PoiAction, selected_item_ids: Array)
signal talk_action_submitted(action: GameEnums.TalkAction)
signal ambush_submitted(position: GameEnums.AmbushPosition)
signal inventory_requested
signal interaction_closed

const MAX_TOOL_SLOTS := 3
const HUDAssetLibrary := preload("res://UI/HUD/HUDAssetLibrary.gd")

var _panel: PanelContainer
var _content: VBoxContainer
var _session: Dictionary = {}
var _slot_selectors: Array[OptionButton] = []
var _metric_rows: Dictionary = {}
var _active_poi_action := GameEnums.PoiAction.SEARCH

func _ready() -> void:
	layer = 20
	_bind_authored_shell()
	_apply_hud_assets()
	close_panel(false)

func open_poi(session: Dictionary) -> void:
	_session = session.duplicate(true)
	_panel.visible = true
	_show_poi_root()

func open_entity_collision(session: Dictionary) -> void:
	_session = session.duplicate(true)
	_panel.visible = true
	_clear_content()
	_add_title("ENTITY COLLISION")
	_add_body(
		"You collided with %s. Choose how the encounter begins."
		% _session.get("entity_name", "Unknown")
	)
	_add_button("TALK", _show_talk_options)
	_add_button("AMBUSH", _show_ambush_options)

func show_result(title: String, message: String) -> void:
	_panel.visible = true
	_clear_content()
	_add_title(title)
	_add_body(message)
	_add_button("CLOSE", close_panel)

func close_panel(notify: bool = true) -> void:
	if _panel:
		_panel.visible = false
	_session.clear()
	if notify:
		interaction_closed.emit()

func is_open() -> bool:
	return _panel != null and _panel.visible

func _bind_authored_shell() -> void:
	_panel = get_node_or_null("Panel") as PanelContainer
	_content = get_node_or_null("Panel/Margin/Content") as VBoxContainer
	if _panel == null or _content == null:
		push_error("MacroInteractionPanel requires authored Panel/Margin/Content nodes.")

func _apply_hud_assets() -> void:
	if _panel:
		HUDAssetLibrary.apply_panel(_panel, "warning")

func _show_poi_root() -> void:
	_clear_content()
	_add_title(_session.get("poi_name", "POINT OF INTEREST"))
	var clock: Dictionary = _session.get("world_time", {})
	_add_body(
		(
			"SEARCH the location for supplies or establish a persistent "
			+ "three-slot CAMP.\nDay %d, %02d:%02d"
		) % [
			clock.get("day", 1),
			clock.get("hour", 0),
			clock.get("minute", 0),
		]
	)
	_add_button("SEARCH", _show_search)
	var camp_button := _add_button("CAMP", _show_camp)
	camp_button.disabled = not _session.get("camp_allowed", false)
	camp_button.tooltip_text = _session.get("camp_block_reason", "")
	_add_button("INVENTORY / GROUND", inventory_requested.emit)
	_add_button("LEAVE", close_panel)

func _show_search() -> void:
	_active_poi_action = GameEnums.PoiAction.SEARCH
	_show_tool_screen(
		"SEARCH",
		"Insert up to three tools. Better loot can trade away safety or stealth.",
		GameEnums.InteractionItemRole.SEARCH_TOOL
	)

func _show_camp() -> void:
	if not _session.get("camp_allowed", false):
		show_result(
			"CAMP UNAVAILABLE",
			_session.get("camp_block_reason", "This location is unsafe.")
		)
		return
	_active_poi_action = GameEnums.PoiAction.CAMP
	_show_tool_screen(
		"CAMP",
		"Install up to three campsite items. Installed gear remains stored at this hex.",
		GameEnums.InteractionItemRole.CAMP_GEAR
	)

func _show_tool_screen(
	title: String,
	description: String,
	role: GameEnums.InteractionItemRole
) -> void:
	_clear_content()
	_add_title(title)
	_add_body(description)

	var compatible := _compatible_items(role)
	var installed_ids: Array = (
		_session.get("camp_item_ids", [])
		if role == GameEnums.InteractionItemRole.CAMP_GEAR
		else []
	)
	_slot_selectors.clear()
	for slot_index in range(MAX_TOOL_SLOTS):
		var selector := OptionButton.new()
		selector.add_item("Slot %d: Empty" % (slot_index + 1))
		selector.set_item_metadata(0, "")
		for descriptor in compatible:
			selector.add_item(descriptor.get("name", "Unknown Tool"))
			var item_index := selector.item_count - 1
			var instance_id: String = descriptor.get("instance_id", "")
			selector.set_item_metadata(item_index, instance_id)
			if slot_index < installed_ids.size() and installed_ids[slot_index] == instance_id:
				selector.select(item_index)
		selector.item_selected.connect(_on_slot_selection_changed)
		HUDAssetLibrary.apply_option_button(selector)
		_content.add_child(selector)
		_slot_selectors.append(selector)

	_metric_rows.clear()
	var keys: Array = (
		_session.get("search_metric_keys", [])
		if _active_poi_action == GameEnums.PoiAction.SEARCH
		else _session.get("camp_metric_keys", [])
	)
	for key in keys:
		_add_metric_row(key)
	_request_preview()

	var submit_text := (
		"SCAVENGE"
		if _active_poi_action == GameEnums.PoiAction.SEARCH
		else "MAKE CAMP AND REST"
	)
	_add_button(submit_text, _submit_poi_action)
	_add_button("INVENTORY / GROUND", inventory_requested.emit)
	_add_button("BACK", _show_poi_root)

func _show_talk_options() -> void:
	_clear_content()
	_add_title("TALK")
	_add_body(
		"THREAT pressures them to withdraw. ROB demands property. CEASEFIRE seeks a non-hostile settlement. Failure starts ordinary-position combat."
	)
	_add_button(
		"THREAT",
		func(): talk_action_submitted.emit(GameEnums.TalkAction.THREAT)
	)
	_add_button(
		"ROB",
		func(): talk_action_submitted.emit(GameEnums.TalkAction.ROB)
	)
	_add_button(
		"CEASEFIRE",
		func(): talk_action_submitted.emit(GameEnums.TalkAction.CEASEFIRE)
	)
	_add_button("BACK", open_entity_collision.bind(_session))

func _show_ambush_options() -> void:
	_clear_content()
	_add_title("AMBUSH")
	_add_body(
		"Choose the player's opening lane. As the colliding entity, the player acts first."
	)
	_add_button(
		"FAR APPROACH",
		func(): ambush_submitted.emit(GameEnums.AmbushPosition.FAR)
	)
	_add_button(
		"STANDARD APPROACH",
		func(): ambush_submitted.emit(GameEnums.AmbushPosition.STANDARD)
	)
	_add_button(
		"CLOSE APPROACH",
		func(): ambush_submitted.emit(GameEnums.AmbushPosition.CLOSE)
	)
	_add_button("BACK", open_entity_collision.bind(_session))

func _submit_poi_action() -> void:
	poi_action_submitted.emit(_active_poi_action, _selected_item_ids())

func _on_slot_selection_changed(_index: int) -> void:
	_request_preview()

func _request_preview() -> void:
	poi_preview_requested.emit(_active_poi_action, _selected_item_ids())

func show_poi_preview(
	action: GameEnums.PoiAction,
	metrics: Dictionary
) -> void:
	if action != _active_poi_action:
		return
	for key in _metric_rows.keys():
		var row: Dictionary = _metric_rows[key]
		var value := float(metrics.get(key, 0.0))
		var maximum := GameEnums.SCALE_MAX
		var label: Label = row["label"]
		var bar: ProgressBar = row["bar"]
		label.text = "%s: %.1f / %.1f" % [str(key).to_upper(), value, maximum]
		bar.max_value = maximum
		bar.value = value

func _compatible_items(role: GameEnums.InteractionItemRole) -> Array:
	var compatible: Array = []
	var descriptors: Array = _session.get("available_items", []).duplicate(true)
	descriptors.append_array(_session.get("camp_items", []))
	for descriptor in descriptors:
		if descriptor.get("roles", []).has(role):
			compatible.append(descriptor)
	return compatible

func _selected_item_ids() -> Array:
	var selected: Array = []
	for selector in _slot_selectors:
		var instance_id: String = selector.get_item_metadata(selector.selected)
		if not instance_id.is_empty() and not selected.has(instance_id):
			selected.append(instance_id)
	return selected

func _add_metric_row(key: String) -> void:
	var container := VBoxContainer.new()
	var label := Label.new()
	var bar := ProgressBar.new()
	bar.show_percentage = false
	HUDAssetLibrary.apply_label(label, "muted")
	HUDAssetLibrary.apply_progress_bar(bar, "warning")
	container.add_child(label)
	container.add_child(bar)
	_content.add_child(container)
	_metric_rows[key] = {"label": label, "bar": bar}

func _add_title(text: String) -> void:
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	HUDAssetLibrary.apply_label(title, "title")
	_content.add_child(title)

func _add_body(text: String) -> void:
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(body, "body")
	_content.add_child(body)

func _add_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	HUDAssetLibrary.apply_button(button, _icon_for_button(text))
	_content.add_child(button)
	return button

func _icon_for_button(text: String) -> String:
	var normalized := text.to_lower()
	if normalized.contains("search") or normalized.contains("scavenge"):
		return "search"
	if normalized.contains("camp"):
		return "camp"
	if normalized.contains("inventory"):
		return "inventory"
	if normalized.contains("talk") or normalized.contains("ceasefire"):
		return "talk"
	if normalized.contains("ambush"):
		return "warning"
	if normalized.contains("back") or normalized.contains("leave") or normalized.contains("close"):
		return "pass"
	return ""

func _clear_content() -> void:
	_slot_selectors.clear()
	_metric_rows.clear()
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
