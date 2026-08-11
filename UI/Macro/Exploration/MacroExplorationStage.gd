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

const HUMAN_TOKEN_SCENE := preload("res://UI/Humanoid/HumanoidToken.tscn")
const PAPER_DOLL_SCENE := preload("res://UI/Inventory/PaperDollModel.tscn")

var _session: Dictionary = {}
var _result: Dictionary = {}
var _choice_buttons: Array[Button] = []
var _choice_ids: Array[String] = []
var _mode := ""
var _blocking := false
var _open_tween: Tween
var _exploration_window: MacroExplorationWindow
var _face_doll: PaperDollModel
var _face_stage: Control
var _face_bg: TextureRect
var _field_tokens: Array[HumanoidTokenView] = []

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


func restyle() -> void:
	HUDAssetLibrary.apply_panel(_event_panel, "warning")
	HUDAssetLibrary.apply_panel(_result_box, "neutral")
	HUDAssetLibrary.apply_label(_title_label, "title")
	HUDAssetLibrary.apply_label(_body_label, "body")
	HUDAssetLibrary.apply_label(_result_title, "warning")
	HUDAssetLibrary.apply_label(_result_meta, "muted")
	HUDAssetLibrary.apply_label(_result_body, "body")
	HUDAssetLibrary.apply_button(_continue_button, "pass")
	HUDAssetLibrary.apply_button(_close_button, "pass")
	HUDAssetLibrary.apply_soft_edge(_event_panel, 0.18)
	if _exploration_window != null and _exploration_window.has_method("restyle"):
		_exploration_window.restyle()
	if _travel != null and _travel.has_method("restyle"):
		_travel.restyle()


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
	if bool(_session.get("walk_in", false)) or _mode == "collision":
		_play_collision_walk_in()


func open_event(session: Dictionary) -> void:
	var packed := session.duplicate(true)
	if not packed.has("mode"):
		packed["mode"] = "event"
	present_session(packed)


func present_poi(
	session: Dictionary,
	inventory_snapshot: Dictionary = {},
	player_record: Dictionary = {}
) -> void:
	_dismiss_travel_quiet()
	_session = session.duplicate(true)
	_mode = "poi"
	_blocking = true
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_center.visible = false
	_event_panel.visible = false
	_dim.visible = true
	_dim.modulate.a = 0.0
	_poi_host.visible = false
	if _exploration_window == null:
		push_error("[MacroExplorationStage] POI opened without exploration window.")
		return
	var edge := 48.0
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x < 1280.0:
		edge = 18.0
	_exploration_window.present_as_stage_overlay(edge)
	var resolved_record: Dictionary = player_record
	if resolved_record.is_empty():
		resolved_record = _session.get("player_record", {})
	_exploration_window.open_landmark(_session, inventory_snapshot, resolved_record)
	_kill_open_tween()
	_open_tween = create_tween()
	_open_tween.tween_property(_dim, "modulate:a", 1.0, HudMotion.FEEDBACK_SEC)
	if _exploration_window != null:
		var poi_panel := _exploration_window.get_exploration_panel()
		if poi_panel != null:
			poi_panel.pivot_offset = poi_panel.size * 0.5
			HudMotion.panel_enter(self, poi_panel, HudMotion.PANEL_ENTER_SEC)
	_play_mode_fx()


func cache_poi_snapshot(session: Dictionary) -> void:
	_session = session.duplicate(true)
	_mode = "poi"
	if _exploration_window != null:
		_exploration_window.cache_session_snapshot(_session)


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
	if _face_stage:
		_face_stage.visible = false
	if _face_bg:
		_face_bg.texture = null
	if _image_rect:
		_image_rect.visible = true
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
	else:
		# This is deliberately unconditional. Combat can be requested while a
		# collision modal is between states, and CanvasLayer visibility alone
		# does not make a full-screen Control stop intercepting GUI input.
		close_event(notify)


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
	_event_panel.pivot_offset = _event_panel.size * 0.5
	_open_tween = create_tween()
	_open_tween.set_parallel(true)
	_open_tween.tween_property(_dim, "modulate:a", 1.0, HudMotion.FEEDBACK_SEC)
	_open_tween.tween_property(_event_panel, "modulate:a", 1.0, HudMotion.PANEL_ENTER_SEC)
	_open_tween.tween_property(_event_panel, "scale", Vector2.ONE, HudMotion.PANEL_ENTER_SEC).set_trans(
		Tween.TRANS_BACK
	).set_ease(Tween.EASE_OUT)
	_play_mode_fx()


func _play_mode_fx() -> void:
	if _fx_layer == null:
		return
	match _mode:
		"poi":
			_fx_layer.play_fx({
				"kind": "discover",
				"intensity": 0.55,
				"palette": [HUDAssetLibrary.COLOR_TRAVEL, HUDAssetLibrary.COLOR_DISCOVERY],
			})
		"result":
			var severity := str(_result.get("severity", _result.get("kind", "warning")))
			var color := HUDAssetLibrary.semantic_color(severity)
			_fx_layer.play_fx({
				"kind": "loot" if severity in ["info", "discovery", "travel"] else "danger",
				"intensity": 0.45,
				"palette": [color, color.darkened(0.25)],
			})
		"collision", "event":
			_fx_layer.play_fx({
				"kind": "danger" if _mode == "collision" else "landmark",
				"intensity": 0.4,
				"palette": [HUDAssetLibrary.COLOR_CAUTION, HUDAssetLibrary.COLOR_CRITICAL],
			})
		_:
			pass


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
	var body := str(_session.get("body", ""))
	if bool(_session.get("place_presence", false)):
		var meet := str(_session.get("meet_label", ""))
		if not meet.is_empty():
			body = "%s\n\n%s" % [meet, body]
	_body_label.text = body
	_apply_event_image(str(_session.get("image_path", "")))
	_apply_opponent_face(_session.get("opponent", {}))
	_render_grid_preview(_session.get("grid_preview", {}))
	_render_tags(_session.get("tags", []))
	_render_choices(_session.get("choices", []))
	_focus_first_enabled_choice()


func _apply_opponent_face(opponent: Dictionary) -> void:
	_ensure_face_stack()
	if _face_stage == null or _face_doll == null:
		return
	if opponent.is_empty():
		_face_stage.visible = false
		if _image_rect:
			_image_rect.visible = true
		return
	_face_stage.visible = true
	# Keep the exploration / hex plate under the paperdoll inside the same window.
	if _image_rect:
		_image_rect.visible = true
		_sync_face_background_from_event_image()
	var equipment: Array = opponent.get("equipment", [])
	if equipment.is_empty():
		equipment = PaperDollPresenter.equipment_from_entity_record(
			opponent.get("record", {})
		)
	PaperDollPresenter.apply_to_doll(_face_doll, equipment)


func _sync_face_background_from_event_image() -> void:
	if _face_bg == null or _image_rect == null:
		return
	_face_bg.texture = _image_rect.texture
	_face_bg.visible = _face_bg.texture != null
	# Hide the raw EventImage once the stacked face window owns the plate.
	_image_rect.visible = false


func _ensure_face_stack() -> void:
	if _face_stage != null:
		return
	var image_column := _image_rect.get_parent() as Control
	if image_column == null:
		return
	_face_stage = Control.new()
	_face_stage.name = "OpponentFaceStage"
	_face_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_face_stage.custom_minimum_size = Vector2(0, 280)
	_face_stage.clip_contents = true
	_face_stage.visible = false
	image_column.add_child(_face_stage)
	image_column.move_child(_face_stage, _image_rect.get_index())

	_face_bg = TextureRect.new()
	_face_bg.name = "OpponentFaceBg"
	_face_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_face_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_face_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_stage.add_child(_face_bg)

	_face_doll = PAPER_DOLL_SCENE.instantiate() as PaperDollModel
	_face_doll.name = "OpponentFaceDoll"
	_face_stage.add_child(_face_doll)
	_face_doll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_face_doll.set_backdrop_visible(false)
	_face_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _play_collision_walk_in() -> void:
	var target := _face_stage if _face_stage != null and _face_stage.visible else _image_frame
	if target == null:
		return
	target.modulate.a = 0.35
	target.scale = Vector2(1.04, 1.04)
	target.pivot_offset = target.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(target, "modulate:a", 1.0, 0.45)
	tween.tween_property(target, "scale", Vector2.ONE, 0.45).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_OUT)
	_fx_layer.play_fx({
		"kind": "landmark",
		"intensity": 0.55,
		"palette": [HUDAssetLibrary.COLOR_CAUTION, HUDAssetLibrary.COLOR_TRAVEL],
	})


func _render_result() -> void:
	_clear_choices()
	_render_tags(_session.get("tags", []))
	_result_box.visible = true
	_continue_button.visible = true
	_close_button.visible = false
	_title_label.text = str(_session.get("title", "EVENT"))
	_body_label.text = str(_session.get("body", ""))
	_result_title.text = str(_result.get("title", "RESULT"))
	var result_role := _result_severity_role()
	HUDAssetLibrary.apply_label(_result_title, result_role)
	HUDAssetLibrary.apply_panel(_result_box, _panel_kind_for_role(result_role))
	var effects: Dictionary = _result.get("effects", {})
	_result_meta.text = _format_effects(effects)
	_result_meta.visible = not _result_meta.text.is_empty()
	_result_body.text = str(_result.get("body", ""))
	if _result.has("image_path"):
		_apply_event_image(str(_result.get("image_path", "")))
	_clear_grid_preview()


func _result_severity_role() -> String:
	var blob := " ".join(PackedStringArray([
		str(_result.get("title", "")),
		str(_result.get("body", "")),
		str(_result.get("kind", "")),
		str(_result.get("severity", "")),
	])).to_lower()
	for tag in _result.get("tags", _session.get("tags", [])):
		blob += " " + str(tag).to_lower()
	var effects: Dictionary = _result.get("effects", {})
	for key in effects.keys():
		blob += " " + str(key).to_lower()
	if "anomaly" in blob or "mist" in blob or "impossible" in blob:
		return "anomaly"
	if (
		"combat" in blob
		or "wound" in blob
		or "damage" in blob
		or "bleed" in blob
		or "death" in blob
		or "hostile" in blob
	):
		return "critical"
	if "loot" in blob or "discover" in blob or "find" in blob or "scavenge" in blob:
		return "discovery"
	if "heal" in blob or "secure" in blob or "safe" in blob or "clear" in blob or "success" in blob:
		return "success"
	return "caution"


func _panel_kind_for_role(role: String) -> String:
	match role:
		"critical", "danger":
			return "critical"
		"warning", "caution":
			return "warning"
		"anomaly":
			return "anomaly"
	return "neutral"


func _tag_role(tag: String) -> String:
	var text := tag.to_lower()
	if "anomaly" in text or "mist" in text:
		return "anomaly"
	if "combat" in text or "threat" in text or "ambush" in text or "hostile" in text:
		return "critical" if "combat" in text or "ambush" in text else "warning"
	if "travel" in text or "route" in text:
		return "travel"
	if "loot" in text or "discover" in text or "find" in text or "scavenge" in text:
		return "discovery"
	if "success" in text or "secure" in text or "safe" in text:
		return "success"
	return "muted"


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
		var role := _tag_role(str(tag))
		HUDAssetLibrary.apply_panel(chip, _panel_kind_for_role(role))
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 7)
		margin.add_theme_constant_override("margin_top", 3)
		margin.add_theme_constant_override("margin_right", 7)
		margin.add_theme_constant_override("margin_bottom", 3)
		chip.add_child(margin)
		var label := Label.new()
		label.text = str(tag)
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		HUDAssetLibrary.apply_label(label, role)
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
	HUDAssetLibrary.apply_panel(row, "neutral")
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
	var choice_icon := _icon_for_choice(choice)
	HUDAssetLibrary.apply_button(button, choice_icon)
	var choice_label_role := _choice_label_role(choice)
	if choice_label_role != "body":
		button.add_theme_color_override(
			"font_color",
			HUDAssetLibrary.color_for_role(choice_label_role)
		)
		button.add_theme_color_override(
			"font_hover_color",
			HUDAssetLibrary.color_for_role(choice_label_role).lightened(0.12)
		)
		button.add_theme_color_override(
			"font_pressed_color",
			HUDAssetLibrary.color_for_role(choice_label_role)
		)
		button.add_theme_color_override(
			"font_disabled_color",
			HUDAssetLibrary.COLOR_MUTED
		)
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


func _choice_label_role(choice: Dictionary) -> String:
	var kind := str(choice.get("kind", "")).to_lower()
	match kind:
		"threat", "ambush", "force":
			return "critical" if kind in ["ambush", "force"] else "warning"
		"observe":
			return "travel"
		"talk", "trade", "ceasefire", "pass":
			return "info"
	return "body"


func _add_chip(row: HFlowContainer, text: String, enabled: bool = true) -> void:
	if text.is_empty():
		return
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	HUDAssetLibrary.apply_panel(chip, "neutral")
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
	var sector_grid := GridContainer.new()
	var width := maxi(1, int(preview.get("width", 7)))
	var height := maxi(1, int(preview.get("height", 5)))
	sector_grid.columns = width
	sector_grid.add_theme_constant_override("h_separation", 4)
	sector_grid.add_theme_constant_override("v_separation", 4)
	sector_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_preview_root.add_child(sector_grid)
	var player_sector: Vector2i = preview.get("player_sector", Vector2i(-1, -1))
	var enemy_sector: Vector2i = preview.get("enemy_sector", Vector2i(-1, -1))
	var player_appearance: Dictionary = _session.get("player", {}).get(
		"appearance",
		{}
	)
	var enemy_appearance: Dictionary = _session.get("opponent", {}).get(
		"appearance",
		{}
	)
	for sector_index in range(width * height):
		var coords := Vector2i(sector_index % width, sector_index / width)
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(36, 72)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_player := coords == player_sector
		var is_enemy := coords == enemy_sector
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
		index_label.text = "%d,%d" % [coords.x, coords.y]
		index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		HUDAssetLibrary.apply_label(index_label, "muted")
		column.add_child(index_label)
		if is_player or is_enemy:
			var host := Control.new()
			host.custom_minimum_size = Vector2(0, 48)
			host.size_flags_vertical = Control.SIZE_EXPAND_FILL
			host.clip_contents = true
			column.add_child(host)
			var token := HUMAN_TOKEN_SCENE.instantiate() as HumanoidTokenView
			host.add_child(token)
			token.position = Vector2(18.0, 36.0)
			token.set_display_scale(0.42)
			var appearance := player_appearance if is_player else enemy_appearance
			if appearance.is_empty():
				appearance = HumanoidVisualCatalog.appearance_from_slot_item_ids({})
			var anim := "Idle2" if is_enemy else "Idle"
			var face_dir := Vector2.RIGHT if is_player else Vector2.LEFT
			_bind_field_token(token, appearance, anim, face_dir)
			_field_tokens.append(token)
		else:
			var marker := Label.new()
			marker.text = "·"
			marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			HUDAssetLibrary.apply_label(marker, "muted")
			column.add_child(marker)
		sector_grid.add_child(cell)
	var legend := Label.new()
	legend.text = "Field presence // player and contact tokens"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	HUDAssetLibrary.apply_label(legend, "muted")
	_grid_preview_root.add_child(legend)


func _bind_field_token(
	token: HumanoidTokenView,
	appearance: Dictionary,
	animation: String,
	face_dir: Vector2
) -> void:
	if token == null:
		return
	var apply := func():
		token.set_appearance(appearance)
		token.play_animation(animation, false)
		token.face_direction(face_dir)
	if token.is_node_ready():
		apply.call()
	else:
		token.ready.connect(apply, CONNECT_ONE_SHOT)


func _clear_grid_preview() -> void:
	_field_tokens.clear()
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
