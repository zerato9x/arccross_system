extends PanelContainer
class_name MacroHexTargetPanel

signal travel_requested(coords: Vector2i)
signal expand_requested(coords: Vector2i)
signal cancel_requested

var _target: Dictionary = {}
var _snapshot: Dictionary = {}
var _title: Label
var _details: Label
var _composition_view: MacroHexCompositionView
var _composition_placeholder: Label
var _intel_row: HBoxContainer
var _summary: Label
var _route_label: Label
var _explore_button: Button
var _travel_button: Button
var _cancel_button: Button
var _action_coords := Vector2i.ZERO
var _current_mode := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0.0, 0.0)
	HUDAssetLibrary.apply_panel(self, "travel")
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(_title, "travel")
	column.add_child(_title)
	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(0.0, 34.0)
	HUDAssetLibrary.apply_label(_details, "muted")
	column.add_child(_details)
	# The outer target panel is the only frame. The old nested inset made the
	# composition look like a second window and consumed room needed by intel.
	var composition_root := Control.new()
	composition_root.name = "BorderlessCompositionRoot"
	composition_root.custom_minimum_size = Vector2(0.0, 132.0)
	composition_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(composition_root)
	_composition_view = MacroHexCompositionView.new()
	_composition_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	composition_root.add_child(_composition_view)
	_composition_placeholder = Label.new()
	_composition_placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_composition_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_composition_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_composition_placeholder.text = "UNKNOWN COMPOSITION"
	HUDAssetLibrary.apply_label(_composition_placeholder, "muted")
	composition_root.add_child(_composition_placeholder)
	_intel_row = HBoxContainer.new()
	_intel_row.add_theme_constant_override("separation", 4)
	_intel_row.custom_minimum_size = Vector2(0.0, 28.0)
	column.add_child(_intel_row)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(0.0, 38.0)
	HUDAssetLibrary.apply_label(_summary, "muted")
	column.add_child(_summary)
	_route_label = Label.new()
	_route_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_route_label.custom_minimum_size = Vector2(0.0, 30.0)
	HUDAssetLibrary.apply_label(_route_label, "info")
	column.add_child(_route_label)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	column.add_child(action_row)
	_explore_button = Button.new()
	_explore_button.custom_minimum_size = Vector2(0.0, 28.0)
	_explore_button.pressed.connect(_on_explore_pressed)
	HUDAssetLibrary.apply_button(_explore_button, "discovery")
	action_row.add_child(_explore_button)
	_travel_button = Button.new()
	_travel_button.custom_minimum_size = Vector2(0.0, 28.0)
	_travel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_travel_button.pressed.connect(_on_travel_pressed)
	HUDAssetLibrary.apply_button(_travel_button, "travel")
	action_row.add_child(_travel_button)
	_cancel_button = Button.new()
	_cancel_button.custom_minimum_size = Vector2(0.0, 28.0)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	HUDAssetLibrary.apply_button(_cancel_button, "pass")
	column.add_child(_cancel_button)
	gui_input.connect(_on_gui_input)
	visible = false


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var current: Dictionary = snapshot.get("current_location", {})
	var remote_target: Dictionary = snapshot.get("target_location", {}).duplicate(true)
	_current_mode = remote_target.is_empty() or remote_target.get("coords") == current.get("coords")
	var display_record: Dictionary = current if _current_mode else remote_target
	if display_record.is_empty():
		visible = false
		return
	visible = true
	_target = display_record.duplicate(true)
	var hex: Dictionary = display_record.get("hex", display_record)
	_action_coords = display_record.get("coords", hex.get("coords", Vector2i.ZERO))
	var coords: Vector2i = _action_coords
	var mode_label := "HERE" if _current_mode else "TARGET"
	_title.text = "%s // HEX %d,%d // %s" % [
		mode_label,
		coords.x,
		coords.y,
		str(hex.get("feature_title", "Unknown Hex")).to_upper(),
	]
	var known := _current_mode or bool(hex.get("explored", false))
	_details.text = "%s\n%s" % [
		str(hex.get("environment_summary", "No survey data is available.")),
		"VIS %s  ·  COVER %s  ·  HAZARD %s" % [
			str(hex.get("visibility", "UNKNOWN")),
			str(hex.get("cover", "UNKNOWN")),
			("%.1f" % float(hex.get("hazard", 0.0))) if known else "UNKNOWN",
		],
	]
	var presentation: Dictionary = display_record.get("presentation", {})
	_composition_view.visible = known and not presentation.is_empty()
	_composition_placeholder.visible = not _composition_view.visible
	if _composition_view.visible:
		_composition_view.show_composition(presentation)
	_render_intel(hex.get("intel_signals", []))
	_summary.text = "%s\nRESOURCE // %s" % [
		str(hex.get("movement_note", "UNKNOWN")),
		str(hex.get("resource_hint", "UNKNOWN")),
	]
	var movement: Dictionary = snapshot.get("movement", {})
	var active := bool(movement.get("active", false))
	if active:
		var phase := str(movement.get("phase", "walking")).to_upper()
		var total := int(movement.get("total_steps", 0))
		var completed := int(movement.get("completed_steps", 0))
		var remaining := int(movement.get("remaining_steps", 0))
		_route_label.text = "%s // STEP %d / %d // %d REMAINING" % [
			phase,
			min(completed + 1, max(total, 1)),
			total,
			remaining,
		]
		if not str(movement.get("message", "")).is_empty():
			_route_label.text += "\n" + str(movement.get("message", ""))
	else:
		var blocked_reason := str(display_record.get("blocked_reason", ""))
		if _current_mode:
			var exploration: Dictionary = hex.get("exploration", {})
			_route_label.text = (
				"HERE // CURRENT LOCATION  ·  EXPLORE AVAILABLE"
				if bool(exploration.get("available", display_record.get("can_open", false)))
				else "EXPLORE LOCKED // " + str(exploration.get("lock_reason", "Movement in progress")).to_upper()
			)
		elif blocked_reason.is_empty():
			_route_label.text = "ROUTE // %d STEP(S)  ·  %d MIN  ·  ~%.1f KM  ·  EXERTION %.1f" % [
				int(display_record.get("route_steps", 0)),
				int(display_record.get("travel_minutes", 0)),
				float(display_record.get("travel_km", 0.0)),
				float(display_record.get("travel_exertion", 0.0)),
			]
		else:
			_route_label.text = "ROUTE BLOCKED // %s" % blocked_reason.to_upper()
	var can_travel := not _current_mode and bool(display_record.get("can_travel", false)) and not active
	_travel_button.visible = not _current_mode
	_travel_button.text = "TRAVEL [T]" if can_travel else (
		"TRAVEL UNAVAILABLE // " + str(display_record.get("blocked_reason", "Movement in progress"))
	)
	_travel_button.disabled = not can_travel
	var exploration: Dictionary = hex.get("exploration", {})
	var can_explore := _current_mode and bool(exploration.get("available", display_record.get("can_open", false))) and not active
	_explore_button.text = "EXPLORE HERE [E]" if _current_mode else "TRAVEL HERE FIRST"
	_explore_button.disabled = not can_explore
	_explore_button.tooltip_text = (
		"Open the current location board."
		if _current_mode and can_explore
		else "Explore is available only on the player’s current hex."
	)
	_cancel_button.visible = active and str(movement.get("kind", "travel")) == "travel"
	_cancel_button.disabled = not bool(movement.get("can_cancel", false))
	_cancel_button.text = "CANCEL ROUTE"


func _render_intel(signals: Array) -> void:
	for child in _intel_row.get_children():
		child.queue_free()
	var entries := signals
	if entries.is_empty():
		entries = [
			{"kind": "loot", "state": "unknown", "label": "UNKNOWN", "icon_id": "inventory", "role": "muted"},
			{"kind": "structure", "state": "unknown", "label": "UNKNOWN", "icon_id": "location", "role": "muted"},
			{"kind": "risk", "state": "unknown", "label": "UNKNOWN", "icon_id": "warning", "role": "muted"},
		]
	for signal_value in entries:
		if not signal_value is Dictionary:
			continue
		var intel_signal: Dictionary = signal_value
		var badge := PanelContainer.new()
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HUDAssetLibrary.apply_inset_panel(badge, "neutral")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		badge.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(18.0, 18.0)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = HUDAssetLibrary.menu_icon(str(intel_signal.get("icon_id", "warning")))
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\n%s" % [
			str(intel_signal.get("kind", "intel")).to_upper(),
			str(intel_signal.get("label", "UNKNOWN")).to_upper(),
		]
		label.add_theme_font_size_override("font_size", 9)
		HUDAssetLibrary.apply_label(label, str(intel_signal.get("role", "muted")))
		row.add_child(label)
		_intel_row.add_child(badge)


func restyle() -> void:
	HUDAssetLibrary.apply_panel(self, "travel")
	if _title:
		HUDAssetLibrary.apply_label(_title, "travel")
	if _details:
		HUDAssetLibrary.apply_label(_details, "muted")
	if _summary:
		HUDAssetLibrary.apply_label(_summary, "muted")
	if _route_label:
		HUDAssetLibrary.apply_label(_route_label, "info")
	if _explore_button:
		HUDAssetLibrary.apply_button(_explore_button, "discovery")
	if _travel_button:
		HUDAssetLibrary.apply_button(_travel_button, "travel")
	if _cancel_button:
		HUDAssetLibrary.apply_button(_cancel_button, "pass")


func _on_explore_pressed() -> void:
	if _target.is_empty() or _explore_button.disabled:
		return
	expand_requested.emit(_action_coords)


func _on_travel_pressed() -> void:
	if _target.is_empty() or _travel_button.disabled:
		return
	travel_requested.emit(_action_coords)


func _on_cancel_pressed() -> void:
	if _cancel_button.disabled:
		return
	cancel_requested.emit()


func _on_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _cancel_button.visible and not _cancel_button.disabled:
		cancel_requested.emit()
		accept_event()
