extends MacroCornerPanel
class_name MacroHexCornerPanel

signal expand_requested_hex(coords: Vector2i)
signal travel_requested_hex(coords: Vector2i)
signal location_action_requested(command: Dictionary)
signal location_inventory_action_requested(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary
)

enum LocationState { COMPACT, BROWSING, FIXTURE_SELECTED, CONFIGURING, RESOLVING, OUTCOME }

var _location: Dictionary = {}
var _session: Dictionary = {}
var _preview_panel: MacroHexPreviewPanel
var _location_state := LocationState.COMPACT
var _selected_fixture_id := ""
var _selected_verb := ""
var _selected_item_ids: Array[String] = []

var _board: Control
var _board_bg: TextureRect
var _board_composition: MacroHexCompositionView
var _prop_layer: Control
var _fixture_layer: Control
var _location_title: Label
var _location_meta: Label
var _fixture_title: Label
var _fixture_description: Label
var _verb_row: HBoxContainer
var _preview_label: Label
var _gear_list: VBoxContainer
var _ground_list: VBoxContainer
var _confirm_button: Button
var _outcome_box: PanelContainer
var _outcome_label: Label


func _ready() -> void:
	panel_id = "hex"
	panel_corner = PanelCorner.TOP_RIGHT
	preview_size = Vector2(460.0, 360.0)
	expand_width_ratio = 0.72
	expand_height_ratio = 0.78
	expanded_min_size = Vector2(820.0, 620.0)
	expanded_max_size = Vector2(1360.0, 900.0)
	super._ready()
	_install_preview_ui()
	_install_expanded_ui()
	state_changed.connect(_on_corner_state_changed)


func _install_preview_ui() -> void:
	var root := get_node_or_null("%PreviewRoot") as Control
	if root == null:
		push_error("MacroHexCornerPanel requires PreviewRoot.")
		return
	_preview_panel = root.get_node_or_null("MacroHexPreviewPanel") as MacroHexPreviewPanel
	if _preview_panel == null:
		push_error("MacroHexCornerPanel requires MacroHexPreviewPanel under PreviewRoot.")
		return
	_preview_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview_panel.expand_requested.connect(expand_requested_hex.emit)


func _install_expanded_ui() -> void:
	var root := get_node_or_null("%ExpandedRoot") as Control
	if root == null:
		return
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 14)
	root.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var scene_frame := PanelContainer.new()
	scene_frame.custom_minimum_size = Vector2(500.0, 0.0)
	scene_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scene_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	HUDAssetLibrary.apply_panel(scene_frame, "neutral")
	row.add_child(scene_frame)

	_board = Control.new()
	_board.name = "LocationBoard"
	_board.clip_contents = true
	_board.resized.connect(_layout_board_elements)
	scene_frame.add_child(_board)
	_board_bg = TextureRect.new()
	_board_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_board_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_board_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_board_bg)
	_board_composition = MacroHexCompositionView.new()
	_board_composition.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.add_child(_board_composition)
	_prop_layer = Control.new()
	_prop_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_prop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(_prop_layer)
	_fixture_layer = Control.new()
	_fixture_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fixture_layer.mouse_filter = Control.MOUSE_FILTER_PASS
	_board.add_child(_fixture_layer)

	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size = Vector2(310.0, 0.0)
	side_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	side_scroll.add_child(side)

	_location_title = Label.new()
	_location_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(_location_title, "title")
	side.add_child(_location_title)
	_location_meta = Label.new()
	_location_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(_location_meta, "muted")
	side.add_child(_location_meta)
	_fixture_title = Label.new()
	HUDAssetLibrary.apply_label(_fixture_title, "caution")
	side.add_child(_fixture_title)
	_fixture_description = Label.new()
	_fixture_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(_fixture_description, "body")
	side.add_child(_fixture_description)
	_verb_row = HBoxContainer.new()
	_verb_row.add_theme_constant_override("separation", 6)
	side.add_child(_verb_row)
	_preview_label = Label.new()
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(_preview_label, "info")
	side.add_child(_preview_label)

	var gear_header := Label.new()
	gear_header.text = "ELIGIBLE GEAR"
	HUDAssetLibrary.apply_label(gear_header, "muted")
	side.add_child(gear_header)
	_gear_list = VBoxContainer.new()
	side.add_child(_gear_list)
	_confirm_button = Button.new()
	_confirm_button.text = "Choose a place and action"
	_confirm_button.disabled = true
	HUDAssetLibrary.apply_button(_confirm_button, "discovery")
	_confirm_button.pressed.connect(_confirm_action)
	side.add_child(_confirm_button)

	var ground_header := Label.new()
	ground_header.text = "ON THE GROUND"
	HUDAssetLibrary.apply_label(ground_header, "muted")
	side.add_child(ground_header)
	_ground_list = VBoxContainer.new()
	side.add_child(_ground_list)

	_outcome_box = PanelContainer.new()
	HUDAssetLibrary.apply_panel(_outcome_box, "discovery")
	_outcome_box.visible = false
	side.add_child(_outcome_box)
	var outcome_margin := MarginContainer.new()
	outcome_margin.add_theme_constant_override("margin_left", 10)
	outcome_margin.add_theme_constant_override("margin_top", 8)
	outcome_margin.add_theme_constant_override("margin_right", 10)
	outcome_margin.add_theme_constant_override("margin_bottom", 8)
	_outcome_box.add_child(outcome_margin)
	_outcome_label = Label.new()
	_outcome_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(_outcome_label, "discovery")
	outcome_margin.add_child(_outcome_label)


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_location = snapshot.get("current_location", {}).duplicate(true)
	_session = _location.get("session", {}).duplicate(true)
	visible = not _location.is_empty()
	_render_preview()
	if is_expanded():
		_render_expanded()


func _render_preview() -> void:
	if _preview_panel:
		_preview_panel.show_location(_location)


func _render_expanded() -> void:
	if _location.is_empty() or _board == null:
		return
	var hex: Dictionary = _location.get("hex", {})
	var coords: Vector2i = _location.get("coords", Vector2i.ZERO)
	_location_title.text = "HERE // %s" % str(
		_session.get("site", {}).get(
			"display_name", hex.get("feature_title", "Unknown location")
		)
	).to_upper()
	_location_meta.text = "HEX %d,%d  ·  %s  ·  %s\n%s" % [
		coords.x,
		coords.y,
		str(hex.get("terrain", "UNKNOWN")),
		str(hex.get("visibility", "UNKNOWN")),
		str(hex.get("environment_summary", "")),
	]
	_render_board_scene()
	_render_fixture_hotspots()
	_render_ground_items()
	if _selected_fixture_id.is_empty():
		var fixtures: Array = _session.get("site", {}).get("fixtures", [])
		if not fixtures.is_empty() and fixtures[0] is Dictionary:
			_selected_fixture_id = str(fixtures[0].get("id", ""))
	_select_fixture(_selected_fixture_id, false)


func _render_board_scene() -> void:
	var presentation: Dictionary = _location.get("presentation", {})
	var scene: Dictionary = presentation.get("scene", {})
	var bg_path := str(scene.get("background_path", ""))
	_board_bg.texture = (
		load(bg_path) as Texture2D
		if not bg_path.is_empty() and ResourceLoader.exists(bg_path)
		else null
	)
	_board_bg.visible = _board_bg.texture != null
	_board_composition.show_composition(presentation)
	_board_composition.modulate = Color(1.0, 1.0, 1.0, 0.36 if _board_bg.visible else 1.0)
	_clear(_prop_layer)
	for entry in scene.get("props", []):
		if not entry is Dictionary:
			continue
		var path := str(entry.get("sprite_path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		var prop := TextureRect.new()
		prop.texture = load(path) as Texture2D
		prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		prop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		prop.set_meta("descriptor", entry)
		_prop_layer.add_child(prop)
	var entity: Dictionary = presentation.get("entity", {})
	if not entity.is_empty():
		var presence := PanelContainer.new()
		presence.mouse_filter = Control.MOUSE_FILTER_IGNORE
		presence.set_meta("entity_presence", true)
		presence.set_meta("anchor", Vector2(0.78, 0.32))
		HUDAssetLibrary.apply_panel(presence, "warning")
		var label := Label.new()
		label.text = "ENTITY // %s" % str(entity.get("name", "Unknown")).to_upper()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		HUDAssetLibrary.apply_label(label, "title")
		presence.add_child(label)
		_prop_layer.add_child(presence)
	_layout_board_elements()


func _render_fixture_hotspots() -> void:
	_clear(_fixture_layer)
	var searched: Array = _session.get("searched_targets", [])
	for entry in _session.get("site", {}).get("fixtures", []):
		if not entry is Dictionary:
			continue
		var fixture: Dictionary = entry
		var fixture_id := str(fixture.get("id", ""))
		var option_id := str(fixture.get("search_option_id", ""))
		var depleted := not option_id.is_empty() and searched.has(option_id)
		var button := Button.new()
		button.text = str(fixture.get("label", fixture_id))
		if depleted:
			button.text += " · searched"
		button.toggle_mode = true
		button.button_pressed = fixture_id == _selected_fixture_id
		button.disabled = depleted and fixture.get("verbs", []).size() == 1
		button.set_meta("fixture", fixture)
		button.set_meta("fixture_id", fixture_id)
		HUDAssetLibrary.apply_button(button, "muted" if depleted else "discovery")
		button.pressed.connect(_select_fixture.bind(fixture_id, true))
		_fixture_layer.add_child(button)
	_layout_board_elements()


func _layout_board_elements() -> void:
	if _board == null:
		return
	for child in _prop_layer.get_children() if _prop_layer else []:
		if child is PanelContainer and bool(child.get_meta("entity_presence", false)):
			var anchor: Vector2 = child.get_meta("anchor", Vector2(0.78, 0.32))
			child.size = Vector2(170.0, 38.0)
			child.position = Vector2(anchor.x * _board.size.x, anchor.y * _board.size.y) - child.size * 0.5
			continue
		if not child is TextureRect:
			continue
		var descriptor: Dictionary = child.get_meta("descriptor", {})
		var anchor: Vector2 = descriptor.get("anchor", Vector2(0.5, 0.55))
		var prop_size := 150.0 * float(descriptor.get("scale_multiplier", 1.0))
		child.size = Vector2(prop_size, prop_size)
		child.position = Vector2(anchor.x * _board.size.x, anchor.y * _board.size.y) - child.size * Vector2(0.5, 0.82)
		child.flip_h = bool(descriptor.get("flip_h", false))
	for child in _fixture_layer.get_children() if _fixture_layer else []:
		if not child is Button:
			continue
		var fixture: Dictionary = child.get_meta("fixture", {})
		var anchor: Vector2 = fixture.get("anchor", Vector2(0.5, 0.6))
		child.size = Vector2(150.0, 34.0)
		child.position = Vector2(anchor.x * _board.size.x, anchor.y * _board.size.y) - Vector2(75.0, 17.0)


func _select_fixture(fixture_id: String, user_initiated: bool = true) -> void:
	var fixture := SiteCatalog.fixture_by_id(_session.get("site", {}), fixture_id)
	if fixture.is_empty():
		_fixture_title.text = "Choose a place"
		_fixture_description.text = "Select a marked part of the scene to inspect it."
		_render_verbs([])
		return
	_selected_fixture_id = fixture_id
	_selected_verb = ""
	_selected_item_ids.clear()
	_location_state = LocationState.FIXTURE_SELECTED
	_fixture_title.text = str(fixture.get("label", fixture_id)).to_upper()
	_fixture_description.text = str(fixture.get("description", ""))
	_render_verbs(fixture.get("verbs", []))
	_render_gear()
	_sync_fixture_buttons()
	if user_initiated:
		_outcome_box.visible = false


func _render_verbs(verbs: Array) -> void:
	_clear(_verb_row)
	var fixture := SiteCatalog.fixture_by_id(_session.get("site", {}), _selected_fixture_id)
	for verb_value in verbs:
		var verb := str(verb_value)
		var button := Button.new()
		button.text = {
			SiteCatalog.VERB_SEARCH: "Search",
			SiteCatalog.VERB_SLEEP: "Sleep here",
			SiteCatalog.VERB_TRAP: "Set trap",
			SiteCatalog.VERB_INSTALL_RELICS: "Install relics",
		}.get(verb, verb.capitalize())
		if verb == SiteCatalog.VERB_SLEEP and not bool(_session.get("camp_allowed", false)):
			button.disabled = true
			button.tooltip_text = str(_session.get("camp_block_reason", "This place is unsafe."))
		if verb == SiteCatalog.VERB_SEARCH:
			var option := _search_option(str(fixture.get("search_option_id", "")))
			if bool(option.get("locked", false)) or bool(option.get("depleted", false)):
				button.disabled = true
				button.tooltip_text = str(option.get("lock_reason", "Already searched."))
		if verb == SiteCatalog.VERB_INSTALL_RELICS:
			var missing: Array = _missing_required_item_ids(fixture.get("required_item_ids", []))
			var completed := bool(_session.get("objective_completed", false))
			button.disabled = completed or not missing.is_empty()
			button.tooltip_text = (
				"Relay already restored."
				if completed
				else ("Missing: " + ", ".join(missing) if not missing.is_empty() else "")
			)
		HUDAssetLibrary.apply_button(button)
		button.pressed.connect(_select_verb.bind(verb))
		_verb_row.add_child(button)


func _select_verb(verb: String) -> void:
	_selected_verb = verb
	_selected_item_ids.clear()
	_location_state = LocationState.CONFIGURING
	_render_gear()
	_update_action_preview()


func _render_gear() -> void:
	_clear(_gear_list)
	var roles: Array = _roles_for_verb(_selected_verb)
	var fixture := SiteCatalog.fixture_by_id(_session.get("site", {}), _selected_fixture_id)
	var accepted_roles: Array = fixture.get("accepted_roles", [])
	if not accepted_roles.is_empty():
		roles = accepted_roles
	for entry in _session.get("available_items", []):
		if not entry is Dictionary:
			continue
		var item_roles: Array = entry.get("interaction_roles", entry.get("roles", []))
		if not _has_any_role(item_roles, roles):
			continue
		var item_id := str(entry.get("instance_id", ""))
		var toggle := CheckButton.new()
		toggle.text = str(entry.get("name", "Gear"))
		toggle.button_pressed = _selected_item_ids.has(item_id)
		toggle.toggled.connect(_toggle_item.bind(item_id))
		HUDAssetLibrary.apply_button(toggle)
		_gear_list.add_child(toggle)
	if _gear_list.get_child_count() == 0:
		var none := Label.new()
		none.text = "No gear required" if roles.is_empty() else "No eligible carried gear"
		HUDAssetLibrary.apply_label(none, "muted")
		_gear_list.add_child(none)


func _toggle_item(enabled: bool, instance_id: String) -> void:
	if enabled and not _selected_item_ids.has(instance_id):
		_selected_item_ids.append(instance_id)
	elif not enabled:
		_selected_item_ids.erase(instance_id)
	_update_action_preview()


func _update_action_preview() -> void:
	var fixture := SiteCatalog.fixture_by_id(_session.get("site", {}), _selected_fixture_id)
	if fixture.is_empty() or _selected_verb.is_empty():
		_preview_label.text = "Select an action to see its cost."
		_confirm_button.disabled = true
		return
	var minutes := int(fixture.get("minutes_search", GameTimeRules.SEARCH_MINUTES))
	var exertion := 1.0
	var risk := "Unknown risk"
	var metric_kind := (
		"search" if _selected_verb == SiteCatalog.VERB_SEARCH else "camp"
	)
	var metrics: Dictionary = _session.get("preview_base_metrics", {}).get(
		metric_kind, {}
	).duplicate(true)
	match _selected_verb:
		SiteCatalog.VERB_INSTALL_RELICS:
			minutes = GameTimeRules.ACTION_MINUTES
			exertion = 0.0
			risk = "Permanent route restoration"
			metrics.clear()
		SiteCatalog.VERB_SLEEP:
			minutes = int(fixture.get("minutes_sleep_preview", GameTimeRules.CAMP_MINUTES))
			exertion = 0.0
			risk = "Rest may be interrupted"
		SiteCatalog.VERB_TRAP:
			minutes = GameTimeRules.ACTION_MINUTES
			exertion = 0.25
			risk = "Consumes selected trap gear"
		_:
			var option := _search_option(str(fixture.get("search_option_id", "")))
			var modifiers: Dictionary = option.get("metric_modifiers", {})
			for key in modifiers:
				metrics[key] = float(metrics.get(key, 0.0)) + float(modifiers[key])
			metrics["loot"] = maxf(
				0.0,
				float(metrics.get("loot", 0.0)) - float(_session.get("search_count", 0)) * 1.5
			)
			risk = "Safety %.1f / Sneak %.1f" % [
				float(metrics.get("safety", 0.0)),
				float(metrics.get("sneak", 0.0)),
			]
	for item_id in _selected_item_ids:
		var bonuses: Dictionary = _available_item(item_id).get(metric_kind, {})
		for key in bonuses:
			metrics[key] = clampf(
				float(metrics.get(key, 0.0)) + float(bonuses[key]),
				0.0,
				GameEnums.SCALE_MAX
			)
	var metric_parts := PackedStringArray()
	for key in metrics:
		metric_parts.append("%s %.1f" % [str(key).capitalize(), float(metrics[key])])
	_preview_label.text = "%d min / exertion %.2f / %s\nExpected: %s\n%d gear selected" % [
		minutes,
		exertion,
		risk,
		", ".join(metric_parts),
		_selected_item_ids.size(),
	]
	_confirm_button.text = "%s %s" % [
		_selected_verb.capitalize(), str(fixture.get("label", "place"))
	]
	var requires_gear := _selected_verb == SiteCatalog.VERB_TRAP
	_confirm_button.disabled = requires_gear and _selected_item_ids.is_empty()
	if _selected_verb == SiteCatalog.VERB_INSTALL_RELICS:
		_confirm_button.text = "Install relay relics"
		_confirm_button.disabled = (
			bool(_session.get("objective_completed", false))
			or not _missing_required_item_ids(fixture.get("required_item_ids", [])).is_empty()
		)


func _confirm_action() -> void:
	if _confirm_button.disabled or _selected_verb.is_empty():
		return
	var fixture := SiteCatalog.fixture_by_id(_session.get("site", {}), _selected_fixture_id)
	_location_state = LocationState.RESOLVING
	_confirm_button.disabled = true
	_confirm_button.text = "Resolving…"
	location_action_requested.emit({
		"coords": _location.get("coords", Vector2i.ZERO),
		"location_revision": int(_location.get("revision", 0)),
		"fixture_id": _selected_fixture_id,
		"verb": _selected_verb,
		"selected_item_ids": _selected_item_ids.duplicate(),
		"search_option_id": str(fixture.get("search_option_id", "")),
	})


func _render_ground_items() -> void:
	_clear(_ground_list)
	for entry in _session.get("ground_items", []):
		if not entry is Dictionary:
			continue
		var item: Dictionary = entry
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(item.get("name", "Item"))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HUDAssetLibrary.apply_label(label, "body")
		row.add_child(label)
		var take := Button.new()
		take.text = "Take" if bool(item.get("can_pick_up", true)) else "Inspect"
		HUDAssetLibrary.apply_button(take, "discovery")
		take.pressed.connect(_on_ground_action.bind(item))
		row.add_child(take)
		_ground_list.add_child(row)
	if _ground_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "Nothing loose here"
		HUDAssetLibrary.apply_label(empty, "muted")
		_ground_list.add_child(empty)


func _missing_required_item_ids(required_ids: Array) -> Array:
	var carried: Dictionary = {}
	for entry in _session.get("available_items", []):
		if entry is Dictionary:
			carried[str(entry.get("id", entry.get("item_id", "")))] = true
	var missing: Array = []
	for item_id_value in required_ids:
		var item_id := str(item_id_value)
		if not carried.has(item_id):
			missing.append(item_id.replace("_", " ").capitalize())
	return missing


func _on_ground_action(item: Dictionary) -> void:
	var instance_id := str(item.get("instance_id", ""))
	location_action_requested.emit({
		"coords": _location.get("coords", Vector2i.ZERO),
		"location_revision": int(_location.get("revision", 0)),
		"fixture_id": "ground:" + instance_id,
		"verb": "take" if bool(item.get("can_pick_up", true)) else "inspect",
		"selected_item_ids": [instance_id],
	})


func show_outcome(title: String, message: String) -> void:
	_location_state = LocationState.OUTCOME
	_outcome_box.visible = true
	_outcome_label.text = "%s\n%s" % [title.to_upper(), message]
	_confirm_button.disabled = true
	_confirm_button.text = "Outcome recorded"


func _search_option(option_id: String) -> Dictionary:
	for option in _session.get("search_options", []):
		if option is Dictionary and str(option.get("id", "")) == option_id:
			return option
	return {}


func _available_item(instance_id: String) -> Dictionary:
	for item in _session.get("available_items", []):
		if item is Dictionary and str(item.get("instance_id", "")) == instance_id:
			return item
	return {}


func dock_session(_session_data: Dictionary) -> void:
	# Compatibility hook. Routine sessions now arrive in current_location.
	pass


func restyle_scheme() -> void:
	super.restyle_scheme()
	if _preview_panel:
		_preview_panel.restyle()


func _is_primary_action_click(global_pos: Vector2) -> bool:
	return _preview_panel != null and _preview_panel.get_global_rect().has_point(global_pos)


func _on_corner_state_changed(_panel_id: String, state: int) -> void:
	_location_state = LocationState.COMPACT if state == PanelState.PREVIEW else LocationState.BROWSING
	if state == PanelState.EXPANDED:
		_render_expanded()


func _sync_fixture_buttons() -> void:
	for child in _fixture_layer.get_children():
		if child is Button:
			child.button_pressed = str(child.get_meta("fixture_id", "")) == _selected_fixture_id


func _roles_for_verb(verb: String) -> Array[int]:
	match verb:
		SiteCatalog.VERB_SEARCH:
			return [GameEnums.InteractionItemRole.SEARCH_TOOL, GameEnums.InteractionItemRole.LIGHT_SOURCE]
		SiteCatalog.VERB_SLEEP:
			return [GameEnums.InteractionItemRole.CAMP_GEAR]
		SiteCatalog.VERB_TRAP:
			return [GameEnums.InteractionItemRole.TRAP_GEAR]
	return []


func _has_any_role(item_roles: Array, accepted_roles: Array) -> bool:
	if accepted_roles.is_empty():
		return true
	for role in accepted_roles:
		if item_roles.has(role):
			return true
	return false


func _clear(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.free()
