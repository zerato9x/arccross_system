extends CanvasLayer
class_name MacroHudController

signal inventory_requested
signal save_requested
signal load_requested
signal hex_preview_expand_requested(coords: Vector2i)
signal hex_preview_travel_requested(coords: Vector2i)
signal medical_action_requested(instance_id: String, limb_region: int)
signal viewport_insets_changed(insets: Rect2i)
signal event_choice_submitted(choice_id: String)
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
signal exploration_inventory_action_requested(
	action_id: String,
	instance_id: String,
	equipment_slot: int,
	action_payload: Dictionary
)
signal exploration_interaction_closed
signal node_map_requested

const MAX_SCALE := 12.0

var _snapshot: Dictionary = {}
var _layout_manager := MacroHudLayoutManager.new()

@onready var _root: Control = %Root
@onready var _health_panel: MacroHealthCornerPanel = %MacroHealthPanel
@onready var _inventory_panel: MacroInventoryCornerPanel = %MacroInventoryPanel
@onready var _hex_panel: MacroHexCornerPanel = %MacroHexPanel
@onready var _world_status: MacroWorldStatusPanel = %MacroWorldStatusPanel
@onready var _settings_panel: PanelContainer = %SettingsPanel
@onready var _save_load_menu: SaveLoadMenu = %SaveLoadMenu
@onready var _screen_overlay: TextureRect = %ScreenOverlay
@onready var _screen_noise_toggle: CheckButton = %ScreenNoiseToggle
@onready var _hud_scale_slider: HSlider = %HudScaleSlider
@onready var _hud_scale_label: Label = %HudScaleLabel
@onready var _combat_mode_option: OptionButton = %CombatModeOption
@onready var _settings_close_button: Button = %SettingsCloseButton
@onready var _settings_save_button: Button = %SettingsSaveButton
@onready var _settings_load_button: Button = %SettingsLoadButton
@onready var _settings_menu_button: Button = %SettingsMenuButton
@onready var _exploration_stage: MacroExplorationStage = %MacroExplorationStage


func _ready() -> void:
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_panel.visible = false
	_screen_overlay.visible = false
	_screen_overlay.texture = HUDAssetLibrary.texture(
		"res://Asset/UI/HUD/overlays/scanline_tile_16.png"
	)
	_screen_overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	HUDAssetLibrary.apply_panel(_settings_panel, "anomaly")
	HUDAssetLibrary.apply_button(_settings_close_button)
	HUDAssetLibrary.apply_button(_settings_save_button)
	HUDAssetLibrary.apply_button(_settings_load_button)
	HUDAssetLibrary.apply_button(_settings_menu_button)
	HUDAssetLibrary.apply_label(_hud_scale_label, "muted")
	_layout_manager.register_panel("health", _health_panel)
	_layout_manager.register_panel("inventory", _inventory_panel)
	_layout_manager.register_panel("hex", _hex_panel)
	_layout_manager.register_world_status(_world_status)
	_layout_manager.viewport_insets_changed.connect(
		func(insets: Rect2i): viewport_insets_changed.emit(insets)
	)
	_health_panel.medical_action_requested.connect(medical_action_requested.emit)
	_health_panel.inventory_requested.connect(inventory_requested.emit)
	_inventory_panel.fullscreen_requested.connect(inventory_requested.emit)
	_health_panel.settings_requested.connect(_open_settings)
	_hex_panel.expand_requested_hex.connect(hex_preview_expand_requested.emit)
	_hex_panel.travel_requested_hex.connect(hex_preview_travel_requested.emit)
	_world_status.settings_requested.connect(_open_settings)
	_world_status.node_map_requested.connect(node_map_requested.emit)
	_exploration_stage.choice_submitted.connect(event_choice_submitted.emit)
	_exploration_stage.event_closed.connect(event_closed.emit)
	_exploration_stage.travel_beat_finished.connect(travel_beat_finished.emit)
	_exploration_stage.poi_action_submitted.connect(poi_action_submitted.emit)
	_exploration_stage.poi_preview_requested.connect(poi_preview_requested.emit)
	_exploration_stage.inventory_action_requested.connect(
		exploration_inventory_action_requested.emit
	)
	_exploration_stage.interaction_closed.connect(exploration_interaction_closed.emit)
	_exploration_stage.node_map_requested.connect(node_map_requested.emit)
	_settings_close_button.pressed.connect(_close_settings)
	_settings_save_button.pressed.connect(func(): _open_save_load("save"))
	_settings_load_button.pressed.connect(func(): _open_save_load("load"))
	_settings_menu_button.pressed.connect(
		func(): get_tree().change_scene_to_file(
			PresentationSceneRegistry.MAIN_MENU_SCENE
		)
	)
	_combat_mode_option.clear()
	_combat_mode_option.add_item("Real-Time Duel", 0)
	_combat_mode_option.add_item("Turn-Based Duel", 1)
	_combat_mode_option.item_selected.connect(_on_combat_mode_selected)
	if _save_load_menu:
		_save_load_menu.menu_closed.connect(func(): _save_load_menu.visible = false)
		_save_load_menu.slot_selected.connect(_on_save_load_slot_selected)
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		_screen_noise_toggle.button_pressed = settings.screen_noise_enabled
		_hud_scale_slider.value = settings.hud_scale
		_combat_mode_option.select(
			1 if settings.combat_mode == settings.COMBAT_TURN_BASED else 0
		)
	_screen_overlay.visible = _screen_noise_toggle.button_pressed
	_screen_noise_toggle.toggled.connect(_on_screen_noise_toggled)
	_hud_scale_slider.value_changed.connect(_set_hud_scale)
	_set_hud_scale(_hud_scale_slider.value)
	_update_scale_label()


func get_layout_manager() -> MacroHudLayoutManager:
	return _layout_manager


func get_hex_panel() -> MacroHexCornerPanel:
	return _hex_panel


func get_inventory_corner_panel() -> MacroInventoryCornerPanel:
	return _inventory_panel


func show_snapshot(snapshot: Dictionary) -> void:
	refresh(snapshot)


func refresh(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_health_panel.apply_snapshot(snapshot)
	_inventory_panel.apply_snapshot(snapshot)
	_hex_panel.apply_snapshot(snapshot)
	_world_status.apply_snapshot(snapshot)


func toggle_health_panel() -> void:
	_health_panel.toggle_expanded()


func toggle_inventory_panel() -> void:
	inventory_requested.emit()


func expand_hex_panel() -> void:
	_hex_panel.expand()


func collapse_hex_panel() -> void:
	_hex_panel.collapse()


func dock_hex_session(session: Dictionary) -> void:
	present_poi(session)


func append_exploration_log(message: String) -> void:
	_world_status.append_log(message)


func present_travel_beat(session: Dictionary) -> void:
	# Travel flavor goes to the world log; no modal popup.
	var title := str(session.get("title", "")).strip_edges()
	var body := str(session.get("body", "")).strip_edges()
	var line := title
	if not body.is_empty():
		var first_line := body.split("\n")[0].strip_edges()
		if not first_line.is_empty():
			line = "%s — %s" % [title, first_line] if not title.is_empty() else first_line
	if not line.is_empty():
		append_exploration_log(line)


func present_poi(session: Dictionary, inventory_snapshot: Dictionary = {}) -> void:
	_exploration_stage.present_poi(session, inventory_snapshot)


func bind_exploration_window(window: MacroExplorationWindow) -> void:
	_exploration_stage.bind_exploration_window(window)


func get_exploration_stage() -> MacroExplorationStage:
	return _exploration_stage


func open_event(session: Dictionary) -> void:
	_exploration_stage.open_event(session)


func show_event_result(result: Dictionary) -> void:
	_exploration_stage.show_result(result)


func close_event(notify: bool = true) -> void:
	_exploration_stage.close_event(notify)


func is_event_open() -> bool:
	return _exploration_stage.is_open()


func is_travel_beat_showing() -> bool:
	return false


func clear_exploration_presentation(notify: bool = false) -> void:
	_exploration_stage.clear_presentation(notify)


func get_exploration_window() -> MacroExplorationWindow:
	return _exploration_stage.get_exploration_window()

func toggle_body_scan() -> void:
	toggle_health_panel()


func is_any_panel_expanded() -> bool:
	return _layout_manager.is_any_expanded()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_M:
			toggle_health_panel()
			get_viewport().set_input_as_handled()
		KEY_I, KEY_TAB:
			toggle_inventory_panel()
			get_viewport().set_input_as_handled()


func _open_settings() -> void:
	_settings_panel.visible = true


func _close_settings() -> void:
	_settings_panel.visible = false


func _open_save_load(mode: String) -> void:
	if _save_load_menu:
		_save_load_menu.visible = true
		_save_load_menu.setup_mode(mode)
	_settings_panel.visible = false


func _on_save_load_slot_selected(slot: int) -> void:
	if _save_load_menu._mode == "save":
		var dir = get_node_or_null("/root/GameDirector")
		if dir and dir.has_method("save_game_to_slot"):
			dir.save_game_to_slot(slot)
		_save_load_menu.refresh_slots()
	elif _save_load_menu._mode == "load":
		var dir = get_node_or_null("/root/GameDirector")
		if dir and dir.has_method("load_saved_run_from_slot"):
			dir.load_saved_run_from_slot(slot)


func _set_hud_scale(value: float) -> void:
	_health_panel.scale = Vector2.ONE * value
	_inventory_panel.scale = Vector2.ONE * value
	_hex_panel.scale = Vector2.ONE * value
	_world_status.scale = Vector2.ONE * value
	_settings_panel.scale = Vector2.ONE * value
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		settings.set_hud_scale(value)
	_update_scale_label()


func _on_screen_noise_toggled(enabled: bool) -> void:
	_screen_overlay.visible = enabled
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		settings.set_screen_noise_enabled(enabled)


func _on_combat_mode_selected(index: int) -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	settings.set_combat_mode(
		settings.COMBAT_TURN_BASED if index == 1 else settings.COMBAT_REALTIME
	)


func _update_scale_label() -> void:
	if _hud_scale_label == null or _hud_scale_slider == null:
		return
	_hud_scale_label.text = "HUD Scale %.0f%%" % (_hud_scale_slider.value * 100.0)
