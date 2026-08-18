extends Node
class_name GameDirector

@export_group("System Links")
@export var macro_map: MacroGameManager
@export var combat_scene: PackedScene
@export var defeat_panel: DefeatPanel

var _active_arena: Node = null
var _combat_coords: Vector2i = Vector2i.ZERO
var _combat_approach_from: Vector2i = Vector2i.ZERO
var _combat_request: Dictionary = {}
var _macro_canvas_visibility: Dictionary = {}
var _world_state: RuntimeStateStore
var _event_bus: Node
var _combat_result_application := CombatResultApplicationService.new()

func _ready() -> void:
	_world_state = get_node("/root/WorldState") as RuntimeStateStore
	_combat_result_application.configure(_world_state)
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
		var rejected_encounter: Dictionary = request.get("encounter", {})
		_world_state.cancel_combat_handoff(
			str(rejected_encounter.get("encounter_id", ""))
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
	if selected_scene == null:
		_abort_combat_handoff(
			"Tactical combat scene is unavailable.",
			str(request.get("encounter", {}).get("encounter_id", ""))
		)
		return
	_active_arena = selected_scene.instantiate()
	if _active_arena == null:
		_abort_combat_handoff(
			"Tactical combat scene could not be instantiated.",
			str(request.get("encounter", {}).get("encounter_id", ""))
		)
		return
	add_child(_active_arena)
	
	var encounter := CombatEncounterRecord.from_dict(
		request.get("encounter", {})
	)
	var handoff := _world_state.get_active_combat_handoff()
	var handoff_error := _combat_handoff_error(encounter, handoff)
	if not handoff_error.is_empty():
		_abort_combat_handoff(handoff_error, encounter.encounter_id)
		return
	# WorldCore owns assembly. The director records projection callbacks only;
	# it does not filter, cap, refresh, or fabricate a fallback roster.
	_active_arena.combat_finished.connect(_on_combat_finished)
	_active_arena.setup_encounter(encounter)
	
	# Waiting_game → first_strike → War (see AudioConductor COMBAT_SPECIAL)
	_emit_scene_audio("combat_special")


func _combat_handoff_error(
	encounter: CombatEncounterRecord,
	handoff: CombatHandoffRecord
) -> String:
	if encounter == null or handoff == null:
		return "Combat encounter or registered handoff is missing."
	if encounter.encounter_id != handoff.encounter_id:
		return "Combat encounter identity does not match the registered handoff."
	if encounter.topology_id != "squad_7x5" or handoff.topology_id != "squad_7x5":
		return "Production combat handoff selected a non-squad topology."
	var actor_ids: Array[String] = []
	for actor in encounter.actors:
		var actor_id := str(actor.get("actor_id", ""))
		if actor_id.is_empty() or actor_id in actor_ids:
			return "Combat encounter contains an empty or duplicate actor identity."
		actor_ids.append(actor_id)
	if actor_ids != handoff.actor_ids:
		return "Combat encounter roster differs from the authoritative handoff."
	return ""


func _abort_combat_handoff(message: String, encounter_id: String) -> void:
	push_error("[DIRECTOR] Combat handoff rejected: " + message)
	var active := _world_state.get_active_combat_handoff()
	_world_state.cancel_combat_handoff(
		active.encounter_id if active != null else encounter_id
	)
	_teardown_arena()
	macro_map.show()
	_set_macro_camera_active(true)
	_restore_macro_canvas_layers()
	macro_map.set_process_unhandled_input(true)
	set_process_unhandled_input(true)


func _on_combat_finished(result: CombatResultRecord) -> void:
	if result == null:
		_abort_combat_handoff("Combat finished without a result record.", "")
		return
	var handoff := _world_state.get_active_combat_handoff()
	var application := _combat_result_application.apply(result, handoff)
	if not application.applied:
		_abort_combat_handoff(application.error, result.encounter_id)
		return
	if application.idempotent:
		return
	macro_map.refresh_hex_runtime_projection(application.source_coords)
	macro_map.player_token.restore_runtime_record(
		_world_state.player_record.to_dict()
	)
	for action in application.participant_actions:
		var actor_id := str(action.get("actor_id", ""))
		var old_coords: Vector2i = action.get("old_coords", Vector2i.ZERO)
		macro_map.unload_enemy_token(old_coords)
		if str(action.get("status", "active")) == "dead":
			continue
		var record := _world_state.get_entity(actor_id)
		_restore_participant_to_macro(
			record,
			action.get("participant_context", {})
		)

	var should_retreat_player := application.should_retreat_player
	match result.outcome:
		GameEnums.CombatOutcome.PLAYER_VICTORY:
			if application.hostile_roster_changed:
				macro_map.reconcile_shelter_after_hostile_change()
		GameEnums.CombatOutcome.PLAYER_DEFEAT:
			if result.reason == "death":
				_on_player_defeat_preserve_mutations()
				_teardown_arena()
				macro_map.set_process_unhandled_input(false)
				_emit_scene_audio("game_over")
				if defeat_panel:
					defeat_panel.open_panel(_world_state.has_save_file())
				return
		GameEnums.CombatOutcome.ENEMY_SURRENDERED:
			if application.hostile_roster_changed:
				macro_map.reconcile_shelter_after_hostile_change()
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


func _restore_participant_to_macro(record: EntityRecord, context: Dictionary) -> void:
	if record == null or not _world_state.is_entity_alive(record.entity_id):
		return
	var origin := _context_coords(context.get("macro_origin_coords", context.get("origin_coords", record.coords)), record.coords)
	var target := _nearest_restore_coords(record.entity_id, origin)
	if target != record.coords:
		_world_state.move_entity(record.entity_id, target)


func _nearest_restore_coords(actor_id: String, origin: Vector2i) -> Vector2i:
	var candidates: Array[Vector2i] = [origin]
	for direction in HexCoordUtils.AXIAL_DIRECTIONS:
		candidates.append(origin + direction)
	# The restore neighborhood is intentionally small and deterministic. It
	# preserves the encounter origin whenever possible without teleporting a
	# survivor into an occupied macro cell.
	for coords in candidates:
		if macro_map == null or macro_map.world_generator == null:
			break
		if not macro_map.world_generator.is_in_zone_bounds(coords):
			continue
		var hex := macro_map.world_generator.get_hex_at(coords)
		if hex == null or not hex.is_passable():
			continue
		var occupant := _world_state.get_entity_at(coords)
		if occupant != null and occupant.entity_id != actor_id and _world_state.is_entity_alive(occupant.entity_id):
			continue
		return coords
	return origin


func _context_coords(raw: Variant, fallback: Vector2i) -> Vector2i:
	if raw is Vector2i:
		return raw
	if raw is Vector2:
		return Vector2i(roundi(raw.x), roundi(raw.y))
	if raw is Dictionary:
		return Vector2i(int(raw.get("x", fallback.x)), int(raw.get("y", fallback.y)))
	return fallback


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
	print("\n[DIRECTOR] Central infrastructure activation recorded.")
	var meta_progress := get_node_or_null("/root/MetaProgression")
	if meta_progress != null and meta_progress.has_method("evaluate_campaign_milestones"):
		meta_progress.evaluate_campaign_milestones()

func _on_player_defeat_preserve_mutations() -> void:
	if macro_map:
		if macro_map.has_method("preserve_shelter_after_player_defeat"):
			macro_map.preserve_shelter_after_player_defeat()
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
