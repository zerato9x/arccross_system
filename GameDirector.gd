extends Node
class_name GameDirector

@export_group("System Links")
@export var macro_map: MacroGameManager
@export var duel_scene: PackedScene

func _ready() -> void:
	if not macro_map or not duel_scene:
		push_error("Director is blind. Assign the Macro Map and Duel Scene in the inspector.")
		return
		
	# Wire up the Director to listen to the Map
	macro_map.combat_interception.connect(_on_combat_interception)

func _on_combat_interception(player_def: EntityDefinition, enemy_def: EntityDefinition, coords: Vector2i) -> void:
	print("\n[DIRECTOR] Interception caught! Stopping macro world...")
	set_process_unhandled_input(false)
	macro_map.hide()
	
	var arena = duel_scene.instantiate()
	add_child(arena)
	
	# Pass the genetics data to the combat controller before building the duel
	arena.setup_duel(player_def, enemy_def)
	
