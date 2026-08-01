extends Node
class_name GameDirector

@export_group("System Links")
@export var macro_map: MacroGameManager
@export var combat_scene: PackedScene
@export var defeat_panel: DefeatPanel

var _active_arena: Node = null
var _combat_coords: Vector2i = Vector2i.ZERO
var _combat_approach_from: Vector2i = Vector2i.ZERO
var _combat_enemy_id: String = ""
var _combat_enemy_ids: Array[String] = []
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
	if not macro_map or not combat_scene:
		push_error("Director is blind. Assign the Macro Map and Duel Scene in the inspector.")
		return
	var player_token := macro_map.player_token
	if player_token == null:
		push_error("[DIRECTOR] Macro map has no player_token assigned.")
		return
	var player_core := player_token.get_humanoid_core()
	if player_core == null:
		push_error("[DIRECTOR] Player token has no HumanoidCore.")
		return

	macro_map.combat_requested.connect(_on_combat_requested)
	macro_map.save_requested.connect(save_game)
	macro_map.load_requested.connect(load_saved_run)
	macro_map.core_activated.connect(_on_core_activated)
	if defeat_panel:
		defeat_panel.restart_requested.connect(restart_new_run)
		defeat_panel.load_requested.connect(load_saved_run)
	if player_core.is_dead:
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
	var enemy_record := _world_state.get_entity(enemy_id)
	if enemy_record == null or not _world_state.is_entity_alive(enemy_id):
		push_warning(
			"[DIRECTOR] Combat request rejected — enemy missing or not alive: "
			+ enemy_id
		)
		if macro_map:
			macro_map.show()
			_set_macro_camera_active(true)
			_restore_macro_canvas_layers()
			macro_map.set_process_unhandled_input(true)
		set_process_unhandled_input(true)
		return

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
	_combat_enemy_ids.clear()
	_combat_request = request.duplicate(true)
	
	# Production and Combat Lab combat share the authoritative turn-based arena.
	var selected_scene := combat_scene
	var loaded_scene := load(PresentationSceneRegistry.TACTICAL_COMBAT_SCENE) as PackedScene
	if loaded_scene != null:
		selected_scene = loaded_scene
	else:
		push_error(
			"[DIRECTOR] Tactical combat scene failed to load: "
			+ PresentationSceneRegistry.TACTICAL_COMBAT_SCENE
		)
	_active_arena = selected_scene.instantiate()
	add_child(_active_arena)
	
	var encounter := CombatEncounterRecord.from_dict(
		request.get("encounter", {})
	)
	encounter.topology_id = "duel_12x1"
	encounter.actors = [
		{
			"actor_id": "player",
			"team_id": "player",
			"runtime_record": macro_map.player_token.capture_runtime_record(),
		},
	]
	for combat_enemy in _combat_enemy_records(enemy_record):
		_combat_enemy_ids.append(combat_enemy.entity_id)
		encounter.actors.append({
			"actor_id": combat_enemy.entity_id,
			"team_id": "enemy",
			"runtime_record": combat_enemy.to_dict(),
		})
	_active_arena.combat_finished.connect(_on_combat_finished)
	_active_arena.setup_encounter(encounter)
	
	# Waiting_game → first_strike → War (see AudioConductor COMBAT_SPECIAL)
	_emit_scene_audio("combat_special")

func _on_combat_finished(result: CombatResultRecord) -> void:
	if result == null:
		push_error("Combat finished without a result record.")
		return
	var player_runtime := _runtime_from_result(result, "player")
	_world_state.advance_world_time(result.elapsed_minutes)
	macro_map.player_token.restore_runtime_record({
		"entity_id": "player",
		"coords": macro_map.player_token.current_hex_coords,
		"definition": macro_map.player_token.capture_runtime_record().get("definition", {}),
		"runtime": player_runtime,
	})
	macro_map.player_token.get_humanoid_core().process_survival_time(
		result.elapsed_minutes,
		15.0,
		1.5
	)
	player_runtime = macro_map.player_token.get_humanoid_core().capture_runtime_state().to_dict()
	for combat_enemy_id in _combat_enemy_ids:
		var enemy_runtime := _runtime_from_result(result, combat_enemy_id)
		if not enemy_runtime.is_empty():
			_world_state.update_entity_runtime(combat_enemy_id, enemy_runtime)
	_world_state.update_player_runtime(
		player_runtime,
		macro_map.player_token.current_hex_coords
	)
	_apply_combat_site_result(result)
	if not result.ground_items.is_empty():
		macro_map.add_ground_item_states(_combat_coords, result.ground_items)

	var should_retreat_player := false
	match result.outcome:
		GameEnums.CombatOutcome.PLAYER_VICTORY:
			for combat_enemy_id in _combat_enemy_ids:
				var runtime := _runtime_from_result(result, combat_enemy_id)
				if bool(runtime.get("is_dead", false)):
					_world_state.set_entity_life_state(combat_enemy_id, GameEnums.EntityLifeState.DEAD)
				elif bool(runtime.get("is_comatose", false)):
					_world_state.set_entity_world_status(combat_enemy_id, GameEnums.EntityWorldStatus.WITHDRAWN)
				var record := _world_state.get_entity(combat_enemy_id)
				if record != null:
					macro_map.unload_enemy_token(record.coords)
		GameEnums.CombatOutcome.PLAYER_DEFEAT:
			if result.reason == "death":
				_on_player_defeat_preserve_mutations()
				_teardown_arena()
				macro_map.set_process_unhandled_input(false)
				_emit_scene_audio("game_over")
				if defeat_panel:
					defeat_panel.open_panel(_world_state.has_save_file())
				return
			should_retreat_player = true
		GameEnums.CombatOutcome.PLAYER_ESCAPED:
			should_retreat_player = true
		GameEnums.CombatOutcome.PLAYER_SURRENDERED:
			should_retreat_player = true
		GameEnums.CombatOutcome.ENEMY_SURRENDERED:
			for combat_enemy_id in _combat_enemy_ids:
				_world_state.set_entity_world_status(combat_enemy_id, GameEnums.EntityWorldStatus.WITHDRAWN)
				var record := _world_state.get_entity(combat_enemy_id)
				if record != null:
					macro_map.unload_enemy_token(record.coords)
		_:
			pass

	var approach_from := _combat_approach_from
	var initiator := str(_combat_request.get("initiator_id", "player"))
	_teardown_arena()
	macro_map.show()
	_set_macro_camera_active(true)
	_restore_macro_canvas_layers()
	if should_retreat_player:
		macro_map.retreat_player_from_combat(
			_combat_coords,
			approach_from,
			initiator
		)
	macro_map.set_process_unhandled_input(true)
	set_process_unhandled_input(true)
	_start_macro_audio()


func _runtime_from_result(result: CombatResultRecord, actor_id: String) -> Dictionary:
	for update in result.actor_runtime_updates:
		if str(update.get("actor_id", "")) == actor_id:
			return update.get("runtime", {}).duplicate(true)
	return {}


func _combat_enemy_records(primary: EntityRecord) -> Array[EntityRecord]:
	var result: Array[EntityRecord] = [primary]
	var squad_id := str(primary.runtime.get("squad_id", ""))
	if squad_id.is_empty():
		return result
	for candidate in _world_state.get_all_entity_records():
		if result.size() >= 2:
			break
		if candidate == null or candidate.entity_id == primary.entity_id:
			continue
		if not _world_state.is_entity_alive(candidate.entity_id) or not _world_state.is_entity_hostile(candidate.entity_id):
			continue
		if str(candidate.runtime.get("squad_id", "")) != squad_id:
			continue
		if HexCoordUtils.distance(primary.coords, candidate.coords) > 1:
			continue
		result.append(candidate)
	return result


func _apply_combat_site_result(result: CombatResultRecord) -> void:
	var record := _world_state.get_hex_record(result.source_coords)
	if record == null:
		return
	var state := result.environment_patch.duplicate(true)
	state["bodies"] = result.body_locations.duplicate(true)
	state["ground_items"] = result.ground_items.duplicate(true)
	record.combat_site_state = state
	_world_state.set_hex_record(result.source_coords, record)

func _teardown_arena() -> void:
	if _active_arena:
		_active_arena.queue_free()
		_active_arena = null
	_combat_request.clear()
	_combat_enemy_ids.clear()
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
	print("\n[DIRECTOR] Central infrastructure activation recorded.")
	var meta_progress := get_node_or_null("/root/MetaProgression")
	if meta_progress != null and meta_progress.has_method("evaluate_campaign_milestones"):
		meta_progress.evaluate_campaign_milestones()

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
