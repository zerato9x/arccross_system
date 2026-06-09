extends Node
class_name GameDirector

@export_group("System Links")
@export var macro_map: MacroGameManager
@export var duel_scene: PackedScene

var _active_arena: Node = null
var _combat_coords: Vector2i = Vector2i.ZERO
var _combat_enemy_id: String = ""
var _combat_request: Dictionary = {}
var _world_state: RuntimeStateStore

func _ready() -> void:
	_world_state = get_node("/root/WorldState") as RuntimeStateStore
	if not macro_map or not duel_scene:
		push_error("Director is blind. Assign the Macro Map and Duel Scene in the inspector.")
		return
		
	macro_map.combat_requested.connect(_on_combat_requested)

func _on_combat_requested(request: Dictionary) -> void:
	var enemy_id: String = request.get("enemy_id", "")
	var coords: Vector2i = request.get("coords", Vector2i.ZERO)
	print("\n[DIRECTOR] Combat request accepted. Stopping macro world...")
	set_process_unhandled_input(false)
	macro_map.hide()
	_combat_coords = coords
	_combat_enemy_id = enemy_id
	_combat_request = request.duplicate(true)
	
	_active_arena = duel_scene.instantiate()
	add_child(_active_arena)
	
	_active_arena.duel_finished.connect(_on_duel_finished)
	
	var enemy_record := _world_state.get_entity(enemy_id)
	_active_arena.setup_duel(
		macro_map.player_token.get_humanoid_core(),
		enemy_record,
		_combat_request
	)

func _on_duel_finished(
	outcome: GameEnums.CombatOutcome,
	enemy_id: String,
	enemy_runtime: Dictionary,
	dropped_items: Array
) -> void:
	print("\n[DIRECTOR] Duel finished with outcome: ", GameEnums.CombatOutcome.keys()[outcome])
	_world_state.update_entity_runtime(enemy_id, enemy_runtime)
	_world_state.update_player_runtime(
		macro_map.player_token.get_humanoid_core().capture_runtime_state(),
		macro_map.player_token.current_hex_coords
	)

	if dropped_items.size() > 0:
		macro_map.add_ground_item_states(_combat_coords, dropped_items)

	match outcome:
		GameEnums.CombatOutcome.PLAYER_VICTORY:
			_world_state.set_entity_life_state(
				enemy_id,
				GameEnums.EntityLifeState.DEAD
			)
			macro_map.unload_enemy_token(_combat_coords)
		GameEnums.CombatOutcome.PLAYER_DEFEAT:
			_teardown_arena()
			macro_map.show()
			macro_map.set_process_unhandled_input(false)
			print("[DIRECTOR] Player defeat preserved. Macro input remains disabled.")
			return
		GameEnums.CombatOutcome.PLAYER_ESCAPED, GameEnums.CombatOutcome.ENEMY_ESCAPED:
			pass
		GameEnums.CombatOutcome.DRAW:
			pass

	_teardown_arena()
	macro_map.show()
	macro_map.set_process_unhandled_input(true)
	print("[DIRECTOR] Macro map re-enabled.")

func _teardown_arena() -> void:
	if _active_arena:
		_active_arena.queue_free()
		_active_arena = null
	_combat_request.clear()
	
