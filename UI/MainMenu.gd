extends Control
class_name MainMenu

@export_file("*.tscn") var game_scene_path: String
@export_file("*.tscn") var wave_scene_path: String

@onready var btn_new_game = %BtnNewGame
@onready var btn_continue = %BtnContinue
@onready var btn_wave = %BtnWave
@onready var btn_settings = %BtnSettings
@onready var btn_quit = %BtnQuit
@onready var save_load_menu = %SaveLoadMenu
@onready var settings_panel: Control = %SettingsPanel
@onready var combat_mode_option: OptionButton = %CombatModeOption
@onready var hud_scheme_option: OptionButton = %HudSchemeOption
@onready var settings_close_button: Button = %SettingsCloseButton

func _ready() -> void:
	HUDAssetLibrary.apply_button(btn_new_game)
	HUDAssetLibrary.apply_button(btn_continue)
	HUDAssetLibrary.apply_button(btn_wave)
	HUDAssetLibrary.apply_button(btn_settings)
	HUDAssetLibrary.apply_button(btn_quit)
	
	btn_new_game.pressed.connect(_on_new_game)
	btn_continue.pressed.connect(_on_continue)
	btn_wave.pressed.connect(_on_wave)
	btn_settings.pressed.connect(func(): settings_panel.visible = true)
	btn_quit.pressed.connect(_on_quit)
	settings_close_button.pressed.connect(func(): settings_panel.visible = false)
	combat_mode_option.clear()
	combat_mode_option.add_item("Real-Time Duel", 0)
	combat_mode_option.add_item("Turn-Based Duel", 1)
	_populate_hud_scheme_option()
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		combat_mode_option.select(
			1 if settings.combat_mode == settings.COMBAT_TURN_BASED else 0
		)
		_select_hud_scheme(settings.hud_scheme)
	combat_mode_option.item_selected.connect(_on_combat_mode_selected)
	hud_scheme_option.item_selected.connect(_on_hud_scheme_selected)
	settings_panel.visible = false
	
	save_load_menu.visible = false
	save_load_menu.setup_mode("load")
	save_load_menu.slot_selected.connect(_on_slot_selected)
	save_load_menu.menu_closed.connect(_on_save_load_closed)

	var bus = get_node_or_null("/root/GameEventBus")
	if bus and bus.has_method("emit_scene_audio"):
		bus.emit_scene_audio("silent")


func _process(delta: float) -> void:
	if %ParallaxBackground:
		%ParallaxBackground.scroll_offset.x -= 20.0 * delta

func _on_new_game() -> void:
	var save_service = get_node_or_null("/root/SaveLoadService")
	if save_service:
		save_service.begin_new_world("DEMO_WASTELAND_01")
	_change_to_game_scene()

func _on_continue() -> void:
	save_load_menu.visible = true
	save_load_menu.refresh_slots()

func _on_wave() -> void:
	if wave_scene_path.is_empty():
		push_error("[MainMenu] Missing wave_scene_path.")
		return
	get_tree().change_scene_to_file(wave_scene_path)

func _on_slot_selected(slot_index: int) -> void:
	var save_service = get_node_or_null("/root/SaveLoadService")
	if save_service and save_service.load_from_slot(slot_index):
		_change_to_game_scene()


func _change_to_game_scene() -> void:
	if game_scene_path.is_empty():
		push_error("[MainMenu] Missing game_scene_path.")
		return
	get_tree().change_scene_to_file(game_scene_path)

func _on_save_load_closed() -> void:
	save_load_menu.visible = false

func _on_quit() -> void:
	get_tree().quit()


func _on_combat_mode_selected(index: int) -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	settings.set_combat_mode(
		settings.COMBAT_TURN_BASED if index == 1 else settings.COMBAT_REALTIME
	)


func _populate_hud_scheme_option() -> void:
	hud_scheme_option.clear()
	for scheme_id in HUDAssetLibrary.scheme_ids():
		hud_scheme_option.add_item(HUDAssetLibrary.scheme_label(scheme_id))
		hud_scheme_option.set_item_metadata(
			hud_scheme_option.item_count - 1,
			scheme_id
		)


func _select_hud_scheme(scheme_id: String) -> void:
	var sanitized := HUDAssetLibrary.sanitize_scheme_id(scheme_id)
	for index in range(hud_scheme_option.item_count):
		if str(hud_scheme_option.get_item_metadata(index)) == sanitized:
			hud_scheme_option.select(index)
			return
	hud_scheme_option.select(0)


func _on_hud_scheme_selected(index: int) -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	settings.set_hud_scheme(str(hud_scheme_option.get_item_metadata(index)))
	HUDAssetLibrary.apply_button(btn_new_game)
	HUDAssetLibrary.apply_button(btn_continue)
	HUDAssetLibrary.apply_button(btn_wave)
	HUDAssetLibrary.apply_button(btn_settings)
	HUDAssetLibrary.apply_button(btn_quit)
	HUDAssetLibrary.apply_button(settings_close_button)
	HUDAssetLibrary.apply_option_button(combat_mode_option)
	HUDAssetLibrary.apply_option_button(hud_scheme_option)
