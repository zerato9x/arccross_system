extends Node
class_name GameDirector

@export_group("System Links")
@export var macro_map: MacroGameManager
@export var duel_scene: PackedScene

var _active_arena: Node = null
var _combat_coords: Vector2i = Vector2i.ZERO

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
	_combat_coords = coords
	
	_active_arena = duel_scene.instantiate()
	add_child(_active_arena)
	
	# Wire up the resolution signal before starting the duel
	_active_arena.duel_resolved.connect(_on_duel_resolved)
	_active_arena.duel_escaped.connect(_on_duel_escaped)
	
	# Pass the genetics data to the combat controller before building the duel
	_active_arena.setup_duel(player_def, enemy_def)

func _on_duel_resolved(winner: HumanoidCore, loser: HumanoidCore, dropped_loot: Array[ItemData]) -> void:
	print("\n[DIRECTOR] Duel resolved. Cleaning up and returning to the Macro Map...")
	
	# 1. Deposit any dropped loot into the macro map remnants
	if dropped_loot.size() > 0 and macro_map:
		if not macro_map.active_map_remnants.has(_combat_coords):
			macro_map.active_map_remnants[_combat_coords] = []
		macro_map.active_map_remnants[_combat_coords].append_array(dropped_loot)
		print("[DIRECTOR] Deposited ", dropped_loot.size(), " items as map remnants at ", _combat_coords)
	
	# 2. Remove the defeated enemy from the macro map tracker
	if macro_map.active_enemies.has(_combat_coords):
		var enemy_token = macro_map.active_enemies[_combat_coords]
		enemy_token.queue_free()
		macro_map.active_enemies.erase(_combat_coords)
		print("[DIRECTOR] Cleared enemy token from hex ", _combat_coords)
	
	# 3. Tear down the combat arena
	if _active_arena:
		_active_arena.queue_free()
		_active_arena = null
	
	# 4. Bring the overworld back online
	macro_map.show()
	macro_map.set_process_unhandled_input(true)
	print("[DIRECTOR] Macro map re-enabled. The wasteland awaits.")
	
func _on_duel_escaped(escaper: HumanoidCore) -> void:
	print("\n[DIRECTOR] Duel ended via escape. The coward lives to fight another day.")
	
	# We intentionally DO NOT queue_free() the enemy token on the macro map
	# so they can be encountered again.
	
	if _active_arena:
		_active_arena.queue_free()
		_active_arena = null
		
	macro_map.show()
	macro_map.set_process_unhandled_input(true)
	print("[DIRECTOR] Macro map re-enabled.")
	
