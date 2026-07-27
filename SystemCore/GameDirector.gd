extends Node
class_name GameDirector

@export_group("System Links")
@export var macro_map: MacroGameManager
@export var duel_scene: PackedScene
@export var defeat_panel: DefeatPanel

var _active_arena: Node = null
var _combat_coords: Vector2i = Vector2i.ZERO
var _combat_approach_from: Vector2i = Vector2i.ZERO
var _combat_enemy_id: String = ""
var _combat_request: Dictionary = {}
var _macro_canvas_visibility: Dictionary = {}
var _world_state: RuntimeStateStore
var _event_bus: Node

func _ready() -> void:
	_world_state = get_node("/root/WorldState") as RuntimeStateStore
	_event_bus = get_node_or_null("/root/GameEventBus")
	if macro_map:
		macro_map.configure_services(
			_world_state,
			get_node_or_null("/root/LootCatalog")
		)
	if not macro_map or not duel_scene:
		push_error("Director is blind. Assign the Macro Map and Duel Scene in the inspector.")
		return
		
	macro_map.combat_requested.connect(_on_combat_requested)
	macro_map.save_requested.connect(save_game)
	macro_map.load_requested.connect(load_saved_run)
	macro_map.core_activated.connect(_on_core_activated)
	if defeat_panel:
		defeat_panel.restart_requested.connect(restart_new_run)
		defeat_panel.load_requested.connect(load_saved_run)
	if macro_map.player_token.get_humanoid_core().is_dead:
		macro_map.hide()
		macro_map.set_process_unhandled_input(false)
		if defeat_panel:
			defeat_panel.open_panel(_world_state.has_save_file())
	
	_world_state.world_time_advanced.connect(_on_world_time_advanced)
	_start_macro_audio()

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
	if macro_map.macro_hud:
		# Defensive handoff guard for combat requests that do not originate from
		# MacroGameManager's normal collision-choice path.
		macro_map.macro_hud.clear_exploration_presentation(false)
	_suspend_macro_canvas_layers()
	macro_map.hide()
	_set_macro_camera_active(false)
	_combat_coords = coords
	_combat_approach_from = request.get(
		"approach_from",
		macro_map.player_token.current_hex_coords
	)
	_combat_enemy_id = enemy_id
	_combat_request = request.duplicate(true)
	
	var selected_scene := duel_scene
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		var selected_path := (
			PresentationSceneRegistry.TURN_BASED_DUEL_SCENE
			if settings.combat_mode == settings.COMBAT_TURN_BASED
			else PresentationSceneRegistry.REALTIME_DUEL_SCENE
		)
		var loaded_scene := load(selected_path) as PackedScene
		if loaded_scene != null:
			selected_scene = loaded_scene
		else:
			push_error("[DIRECTOR] Selected combat scene failed to load: " + selected_path)
	_active_arena = selected_scene.instantiate()
	add_child(_active_arena)
	
	_active_arena.duel_finished.connect(_on_duel_finished)
	
	var enemy_record := _world_state.get_entity(enemy_id)
	if enemy_record == null:
		push_error("[DIRECTOR] No entity record for enemy_id: " + enemy_id)
		return
	_active_arena.setup_duel_from_records(
		macro_map.player_token.capture_runtime_record(),
		enemy_record.to_dict(),
		_combat_request
	)
	
	_emit_scene_audio("combat_standard")

func _on_duel_finished(
	outcome: GameEnums.CombatOutcome,
	enemy_id: String,
	enemy_runtime: Dictionary,
	player_runtime: Dictionary,
	dropped_items: Array
) -> void:
	print("\n[DIRECTOR] Duel finished with outcome: ", GameEnums.CombatOutcome.keys()[outcome])
	_world_state.advance_world_time(GameTimeRules.COMBAT_MINUTES)
	macro_map.player_token.restore_runtime_record({
		"entity_id": "player",
		"coords": macro_map.player_token.current_hex_coords,
		"definition": macro_map.player_token.capture_runtime_record().get("definition", {}),
		"runtime": player_runtime,
	})
	macro_map.player_token.get_humanoid_core().process_survival_time(
		GameTimeRules.COMBAT_MINUTES,
		15.0,
		1.5
	)
	_world_state.update_entity_runtime(enemy_id, enemy_runtime)
	_world_state.update_player_runtime(
		player_runtime,
		macro_map.player_token.current_hex_coords
	)

	if dropped_items.size() > 0:
		macro_map.add_ground_item_states(_combat_coords, dropped_items)

	var should_retreat_player := false
	var combat_approach_from := _combat_approach_from
	var combat_initiator := str(_combat_request.get("initiator_id", "player"))
	match outcome:
		GameEnums.CombatOutcome.PLAYER_VICTORY:
			_world_state.set_entity_life_state(
				enemy_id,
				GameEnums.EntityLifeState.DEAD
			)
			macro_map.unload_enemy_token(_combat_coords)
		GameEnums.CombatOutcome.PLAYER_DEFEAT:
			_on_player_defeat_preserve_mutations()
			_teardown_arena()
			macro_map.set_process_unhandled_input(false)
			_emit_scene_audio("game_over")
			if defeat_panel:
				defeat_panel.open_panel(_world_state.has_save_file())
			print("[DIRECTOR] Player defeat preserved. Run-ended presentation opened.")
			return
		GameEnums.CombatOutcome.PLAYER_ESCAPED:
			should_retreat_player = true
		GameEnums.CombatOutcome.ENEMY_ESCAPED:
			pass
		GameEnums.CombatOutcome.DRAW:
			pass

	_teardown_arena()
	macro_map.show()
	_set_macro_camera_active(true)
	_restore_macro_canvas_layers()
	if should_retreat_player:
		macro_map.retreat_player_from_combat(
			_combat_coords,
			combat_approach_from,
			combat_initiator
		)
	macro_map.set_process_unhandled_input(true)
	set_process_unhandled_input(true)
	_start_macro_audio()
	print("[DIRECTOR] Macro map re-enabled.")

func _teardown_arena() -> void:
	if _active_arena:
		_active_arena.queue_free()
		_active_arena = null
	_combat_request.clear()
	_combat_approach_from = Vector2i.ZERO


func _set_macro_camera_active(active: bool) -> void:
	if macro_map == null:
		return
	var macro_camera := macro_map.get_node_or_null("Camera2D") as Camera2D
	if macro_camera == null:
		return
	macro_camera.enabled = active
	if active:
		macro_camera.make_current()


func _suspend_macro_canvas_layers() -> void:
	_macro_canvas_visibility.clear()
	if macro_map == null:
		return
	for child in macro_map.get_children():
		if child is CanvasLayer:
			var canvas_layer := child as CanvasLayer
			_macro_canvas_visibility[String(canvas_layer.name)] = canvas_layer.visible
			canvas_layer.visible = false


func _restore_macro_canvas_layers() -> void:
	if macro_map == null:
		_macro_canvas_visibility.clear()
		return
	for child in macro_map.get_children():
		if not child is CanvasLayer:
			continue
		var canvas_layer := child as CanvasLayer
		if _macro_canvas_visibility.has(String(canvas_layer.name)):
			canvas_layer.visible = bool(
				_macro_canvas_visibility[String(canvas_layer.name)]
			)
	_macro_canvas_visibility.clear()

func restart_new_run() -> void:
	macro_map.flush_world_mutations()
	_world_state.begin_new_world("DEMO_WASTELAND_01")
	get_tree().reload_current_scene()

func _on_core_activated() -> void:
	print("\n[DIRECTOR] Alpha Core activated. Endgame reached.")
	macro_map.set_process_unhandled_input(false)
	set_process_unhandled_input(false)
	_emit_scene_audio("game_over")
	if defeat_panel:
		defeat_panel.open_victory_panel()

func _on_player_defeat_preserve_mutations() -> void:
	if macro_map:
		macro_map.flush_world_mutations()

func save_game(path: String = RuntimeStateStore.DEFAULT_SAVE_PATH) -> bool:
	macro_map.synchronize_runtime_state()
	var saved := _world_state.save_to_disk(path)
	if saved:
		print("[DIRECTOR] Saved runtime world to ", path)
	return saved

func save_game_to_slot(slot: int) -> bool:
	macro_map.synchronize_runtime_state()
	var saved := _world_state.save_to_slot(slot)
	if saved:
		print("[DIRECTOR] Saved runtime world to slot ", slot)
	return saved

func load_saved_run(path: String = RuntimeStateStore.DEFAULT_SAVE_PATH) -> bool:
	if not _world_state.load_from_disk(path):
		return false
	get_tree().reload_current_scene()
	return true

func load_saved_run_from_slot(slot: int) -> bool:
	if not _world_state.load_from_slot(slot):
		return false
	get_tree().reload_current_scene()
	return true

func begin_new_world(seed: String) -> void:
	_world_state.begin_new_world(seed)

func get_active_arena() -> Node:
	return _active_arena


func exit_to_main_menu() -> void:
	get_tree().change_scene_to_file(PresentationSceneRegistry.MAIN_MENU_SCENE)

func _start_macro_audio() -> void:
	var snapshot: Dictionary = _world_state.get_world_time_snapshot()
	var hour: int = snapshot.get("hour", 8)
	if GameTimeRules.is_night_hour(hour):
		_emit_scene_audio("macro_night")
	else:
		_emit_scene_audio("macro_day")

func _on_world_time_advanced(_previous: int, current: int, _elapsed: int) -> void:
	var snapshot: Dictionary = GameTimeRules.clock_snapshot(current)
	_emit_scene_audio(
		"world_time_changed",
		{"hour": snapshot.get("hour", 8)}
	)

func _emit_scene_audio(scene_id: String, context: Dictionary = {}) -> void:
	if _event_bus and _event_bus.has_method("emit_scene_audio"):
		_event_bus.emit_scene_audio(scene_id, context)
