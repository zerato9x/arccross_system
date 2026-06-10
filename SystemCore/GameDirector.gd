extends Node
class_name GameDirector

@export_group("System Links")
@export var macro_map: MacroGameManager
@export var duel_scene: PackedScene
@export var defeat_panel: DefeatPanel

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
	if defeat_panel:
		defeat_panel.restart_requested.connect(restart_new_run)
		defeat_panel.load_requested.connect(load_saved_run)
	if macro_map.player_token.get_humanoid_core().is_dead:
		macro_map.hide()
		macro_map.set_process_unhandled_input(false)
		if defeat_panel:
			defeat_panel.open_panel(_world_state.has_save_file())

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5:
		save_game()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F9:
		load_saved_run()
		get_viewport().set_input_as_handled()

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
	_world_state.advance_world_time(GameTimeRules.COMBAT_MINUTES)
	macro_map.player_token.get_humanoid_core().process_survival_time(
		GameTimeRules.COMBAT_MINUTES,
		15.0,
		1.5
	)
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
			macro_map.set_process_unhandled_input(false)
			if defeat_panel:
				defeat_panel.open_panel(_world_state.has_save_file())
			print("[DIRECTOR] Player defeat preserved. Run-ended presentation opened.")
			return
		GameEnums.CombatOutcome.PLAYER_ESCAPED, GameEnums.CombatOutcome.ENEMY_ESCAPED:
			pass
		GameEnums.CombatOutcome.DRAW:
			pass

	_teardown_arena()
	macro_map.show()
	macro_map.set_process_unhandled_input(true)
	set_process_unhandled_input(true)
	print("[DIRECTOR] Macro map re-enabled.")

func _teardown_arena() -> void:
	if _active_arena:
		_active_arena.queue_free()
		_active_arena = null
	_combat_request.clear()

func restart_new_run() -> void:
	_world_state.begin_new_world("DEMO_WASTELAND_01")
	get_tree().reload_current_scene()

func save_game(path: String = RuntimeStateStore.DEFAULT_SAVE_PATH) -> bool:
	macro_map.synchronize_runtime_state()
	var saved := _world_state.save_to_disk(path)
	if saved:
		print("[DIRECTOR] Saved runtime world to ", path)
	return saved

func load_saved_run(path: String = RuntimeStateStore.DEFAULT_SAVE_PATH) -> bool:
	if not _world_state.load_from_disk(path):
		return false
	get_tree().reload_current_scene()
	return true
	
