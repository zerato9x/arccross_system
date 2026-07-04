extends CanvasLayer
class_name MacroHudController

signal inventory_requested
signal save_requested
signal load_requested
signal hex_preview_expand_requested(coords: Vector2i)
signal hex_preview_travel_requested(coords: Vector2i)
signal medical_action_requested(instance_id: String, limb_region: int)
signal viewport_insets_changed(insets: Rect2i)

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
@onready var _settings_close_button: Button = %SettingsCloseButton
@onready var _settings_save_button: Button = %SettingsSaveButton
@onready var _settings_load_button: Button = %SettingsLoadButton
@onready var _settings_menu_button: Button = %SettingsMenuButton


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
	_hex_panel.expand_requested_hex.connect(hex_preview_expand_requested.emit)
	_hex_panel.travel_requested_hex.connect(hex_preview_travel_requested.emit)
	_world_status.settings_requested.connect(_open_settings)
	_settings_close_button.pressed.connect(_close_settings)
	_settings_save_button.pressed.connect(func(): _open_save_load("save"))
	_settings_load_button.pressed.connect(func(): _open_save_load("load"))
	_settings_menu_button.pressed.connect(
		func(): get_tree().change_scene_to_file(
			PresentationSceneRegistry.MAIN_MENU_SCENE
		)
	)
	if _save_load_menu:
		_save_load_menu.menu_closed.connect(func(): _save_load_menu.visible = false)
		_save_load_menu.slot_selected.connect(_on_save_load_slot_selected)
	_screen_noise_toggle.toggled.connect(func(enabled): _screen_overlay.visible = enabled)
	_hud_scale_slider.value_changed.connect(_set_hud_scale)
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
	_inventory_panel.toggle_expanded()


func expand_hex_panel() -> void:
	_hex_panel.expand()


func collapse_hex_panel() -> void:
	_hex_panel.collapse()


func dock_hex_session(session: Dictionary) -> void:
	_hex_panel.dock_session(session)


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
		KEY_ESCAPE:
			if _layout_manager.is_any_expanded():
				_layout_manager.collapse_all()
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
	_update_scale_label()


func _update_scale_label() -> void:
	if _hud_scale_label == null or _hud_scale_slider == null:
		return
	_hud_scale_label.text = "HUD SCALE %.0f%%" % (_hud_scale_slider.value * 100.0)
