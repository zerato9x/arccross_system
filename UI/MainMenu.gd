extends Control
class_name MainMenu

@export_file("*.tscn") var game_scene_path: String
@export_file("*.tscn") var wave_scene_path: String

@onready var btn_new_game = %BtnNewGame
@onready var btn_continue = %BtnContinue
@onready var btn_wave = %BtnWave
@onready var btn_quit = %BtnQuit
@onready var save_load_menu = %SaveLoadMenu

func _ready() -> void:
	HUDAssetLibrary.apply_button(btn_new_game)
	HUDAssetLibrary.apply_button(btn_continue)
	HUDAssetLibrary.apply_button(btn_wave)
	HUDAssetLibrary.apply_button(btn_quit)
	
	btn_new_game.pressed.connect(_on_new_game)
	btn_continue.pressed.connect(_on_continue)
	btn_wave.pressed.connect(_on_wave)
	btn_quit.pressed.connect(_on_quit)
	
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
