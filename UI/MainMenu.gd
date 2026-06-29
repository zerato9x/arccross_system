extends Control
class_name MainMenu

@onready var btn_new_game = %BtnNewGame
@onready var btn_continue = %BtnContinue
@onready var btn_quit = %BtnQuit
@onready var save_load_menu = %SaveLoadMenu

func _ready() -> void:
	HUDAssetLibrary.apply_button(btn_new_game)
	HUDAssetLibrary.apply_button(btn_continue)
	HUDAssetLibrary.apply_button(btn_quit)
	
	btn_new_game.pressed.connect(_on_new_game)
	btn_continue.pressed.connect(_on_continue)
	btn_quit.pressed.connect(_on_quit)
	
	save_load_menu.visible = false
	save_load_menu.setup_mode("load")
	save_load_menu.slot_selected.connect(_on_slot_selected)
	save_load_menu.menu_closed.connect(_on_save_load_closed)

	# AudioConductor: stop combat/macro music and play main menu string music
	var conductor = get_node_or_null("/root/AudioConductor")
	if conductor and conductor.has_method("stop_all"):
		conductor.stop_all()

func _process(delta: float) -> void:
	if %ParallaxBackground:
		%ParallaxBackground.scroll_offset.x -= 20.0 * delta

func _on_new_game() -> void:
	var world_state = get_node("/root/WorldState") as RuntimeStateStore
	world_state.begin_new_world("DEMO_WASTELAND_01")
	get_tree().change_scene_to_file("res://SystemCore/game_director.tscn")

func _on_continue() -> void:
	save_load_menu.visible = true
	save_load_menu.refresh_slots()

func _on_slot_selected(slot_index: int) -> void:
	var world_state = get_node("/root/WorldState") as RuntimeStateStore
	if world_state.load_from_slot(slot_index):
		get_tree().change_scene_to_file("res://SystemCore/game_director.tscn")

func _on_save_load_closed() -> void:
	save_load_menu.visible = false

func _on_quit() -> void:
	get_tree().quit()
