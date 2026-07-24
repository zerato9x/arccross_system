extends Control
class_name MainMenu

const MenuParallaxCatalog := preload("res://PresentationCore/MenuParallaxCatalog.gd")

@export_file("*.tscn") var game_scene_path: String
@export_file("*.tscn") var wave_scene_path: String
@export var parallax_scroll_speed: float = 20.0

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
@onready var _parallax_background: ParallaxBackground = %ParallaxBackground

var _active_pack_dir: String = ""


func _ready() -> void:
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_size_changed):
		viewport.size_changed.connect(_on_viewport_size_changed)
	var game_settings := get_node_or_null("/root/GameSettings")
	if game_settings != null and game_settings.has_signal("settings_changed"):
		if not game_settings.settings_changed.is_connected(_on_settings_changed):
			game_settings.settings_changed.connect(_on_settings_changed)
	_rebuild_random_parallax()
	call_deferred("_rescale_parallax_layers")
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
	combat_mode_option.add_item("Turn-Based Duel (Official)", 0)
	combat_mode_option.add_item("Real-Time Duel (Optional)", 1)
	_populate_hud_scheme_option()
	if game_settings != null:
		combat_mode_option.select(
			0 if game_settings.combat_mode == game_settings.COMBAT_TURN_BASED else 1
		)
		_select_hud_scheme(game_settings.hud_scheme)
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
	if _parallax_background != null:
		_parallax_background.scroll_offset.x -= parallax_scroll_speed * delta


func _on_viewport_size_changed() -> void:
	_rescale_parallax_layers()


func _on_settings_changed(_snapshot: Dictionary) -> void:
	_rescale_parallax_layers()


func _menu_viewport_size() -> Vector2:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return Vector2(1920.0, 1080.0)
	return viewport_size


func _presentation_scale() -> float:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return 1.0
	return clampf(float(settings.hud_scale), 0.85, 1.25)


func _rebuild_random_parallax() -> void:
	if _parallax_background == null:
		return
	for child in _parallax_background.get_children():
		_parallax_background.remove_child(child)
		child.free()
	_active_pack_dir = MenuParallaxCatalog.pick_random_pack()
	if _active_pack_dir.is_empty():
		push_warning("[MainMenu] No Event_bg parallax packs found.")
		return
	var layers := MenuParallaxCatalog.layers_for_pack(_active_pack_dir)
	for index in range(layers.size()):
		var layer_info: Dictionary = layers[index]
		var texture := load(str(layer_info.get("path", ""))) as Texture2D
		if texture == null:
			continue
		var layer := ParallaxLayer.new()
		layer.name = "Layer_%d" % index
		layer.motion_scale = Vector2(float(layer_info.get("motion_scale", 1.0)), 1.0)
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = texture
		layer.add_child(sprite)
		_parallax_background.add_child(layer)
	_rescale_parallax_layers()


func _rescale_parallax_layers() -> void:
	if _parallax_background == null:
		return
	var viewport_size := _menu_viewport_size()
	var presentation_scale := _presentation_scale()
	for child in _parallax_background.get_children():
		var layer := child as ParallaxLayer
		if layer == null:
			continue
		for layer_child in layer.get_children():
			var sprite := layer_child as Sprite2D
			if sprite == null or sprite.texture == null:
				continue
			var texture := sprite.texture
			var cover := maxf(
				viewport_size.x / float(texture.get_width()),
				viewport_size.y / float(texture.get_height())
			) * presentation_scale
			sprite.scale = Vector2(cover, cover)
			layer.motion_mirroring = Vector2(float(texture.get_width()) * cover, 0.0)


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
		settings.COMBAT_TURN_BASED if index == 0 else settings.COMBAT_REALTIME
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
