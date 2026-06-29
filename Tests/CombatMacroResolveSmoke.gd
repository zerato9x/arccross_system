extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var escape_ok := await _verify_player_escape_retreat()
	if not escape_ok:
		return
	var resolve_ok := await _verify_enemy_death_resolve_zoom()
	if not resolve_ok:
		return
	print("[TEST PASS] Combat escape retreats on the macro map and enemy death shows a resolve zoom.")
	quit(0)

func _verify_player_escape_retreat() -> bool:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	if macro_map == null or world_state == null:
		return _fail("World systems did not initialize for escape retreat.")

	var origin := macro_map.player_token.current_hex_coords
	var collision_coords := _find_clear_adjacent_hex(macro_map, world_state, origin)
	if collision_coords == origin:
		return _fail("Could not find a clear adjacent combat collision hex.")

	macro_map.spawn_procedural_enemy(
		collision_coords,
		GameEnums.Faction.SCAVENGER_CELL,
		0
	)
	var enemy_record := world_state.get_entity_at(collision_coords)
	if enemy_record == null:
		return _fail("Could not spawn the controlled retreat enemy.")

	macro_map.player_token.snap_to_hex(
		collision_coords,
		macro_map.map_visualizer.map_to_local(collision_coords)
	)
	world_state.update_player_runtime(
		macro_map.player_token.get_humanoid_core().capture_runtime_state(),
		collision_coords
	)
	macro_map._begin_entity_collision(
		enemy_record.entity_id,
		collision_coords,
		origin
	)
	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.STANDARD)
	await process_frame
	await process_frame

	var arena = game_director.get("_active_arena")
	if arena == null:
		return _fail("Combat handoff did not create an arena for escape.")
	arena.turn_manager.escape_combat(arena.player_core)
	if not await _wait_for_director_teardown(game_director):
		return _fail("Player escape did not return to the macro scene.")

	if macro_map.player_token.current_hex_coords != origin:
		return _fail(
			"Player token did not retreat to the approach hex after escape."
		)
	if world_state.player_coords != origin:
		return _fail("Player runtime coords did not follow the escape retreat.")
	if not world_state.is_entity_alive(enemy_record.entity_id):
		return _fail("Player escape incorrectly killed the macro enemy.")

	game_director.queue_free()
	await process_frame
	return true

func _verify_enemy_death_resolve_zoom() -> bool:
	var holder := Node.new()
	root.add_child(holder)

	var duel_scene := load("res://CombatCore/MainDuelScene.tscn") as PackedScene
	var arena = duel_scene.instantiate()
	holder.add_child(arena)
	await process_frame

	var player_definition := load(
		"res://BiologicalCore/player_def.tres"
	) as EntityDefinition
	var enemy_definition := load(
		"res://BiologicalCore/scavenger_def.tres"
	) as EntityDefinition
	var player: HumanoidCore = arena._fabricate_humanoid(
		"Resolve_Player",
		player_definition,
		false
	)
	arena.setup_duel(
		player,
		{
			"entity_id": "resolve_zoom_enemy",
			"definition": enemy_definition.to_state(),
			"runtime": {},
		}
	)
	await process_frame

	var outcomes: Array = []
	arena.duel_finished.connect(
		func(
			outcome: GameEnums.CombatOutcome,
			_enemy_id: String,
			_enemy_runtime: Dictionary,
			_dropped_items: Array
		) -> void:
			outcomes.append(outcome)
	)
	arena.enemy_core.body.apply_targeted_hit(
		GameEnums.LimbRegion.HEAD,
		999.0,
		0.0
	)
	await create_timer(0.35).timeout
	if not arena.lane_hud.is_resolve_screen_visible():
		return _fail("Enemy death did not show the resolve screen.")
	if arena.lane_hud.get_resolve_focus_side() != "enemy":
		return _fail("Resolve screen did not focus the enemy token.")
	if arena.lane_hud.get_camera_zoom_value() < 1.25:
		return _fail("Resolve screen did not zoom the combat camera.")
	var enemy_token: HumanoidTokenView = arena.lane_hud._lane_view._enemy_token
	if enemy_token.get_animation() != "Die":
		return _fail("Final blow did not drive the enemy death animation.")
	if enemy_token.get("_animation_speed_scale") >= 0.75:
		return _fail("Final blow did not slow the enemy death animation.")
	if not arena.lane_hud._fatal_thud_player.playing:
		return _fail("Final blow did not play the fatal body-fall thud.")

	await create_timer(
		CombatLaneHUD.FINAL_BLOW_HOLD_SECONDS
		+ CombatLaneHUD.RESOLVE_PRESENTATION_SECONDS
		+ 0.35
	).timeout
	if not arena.lane_hud.is_result_overlay_waiting():
		return _fail("Enemy death did not settle into the result overlay.")
	if not outcomes.is_empty():
		return _fail("Combat finished before the result overlay was acknowledged.")
	arena.lane_hud.request_resolve_continue()
	for _frame in range(12):
		if not outcomes.is_empty():
			break
		await process_frame
	if outcomes.size() != 1 or outcomes[0] != GameEnums.CombatOutcome.PLAYER_VICTORY:
		return _fail("Enemy death did not finish as a player victory.")

	holder.queue_free()
	await process_frame
	return true

func _find_clear_adjacent_hex(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore,
	origin: Vector2i
) -> Vector2i:
	for raw_offset in MacroGameManager.HEX_NEIGHBORS:
		var offset: Vector2i = raw_offset
		var coords := origin + offset
		if world_state.has_entity_at(coords):
			continue
		var hex := macro_map.world_generator.get_hex_at(coords)
		if hex.is_passable():
			return coords
	return origin

func _wait_for_director_teardown(game_director: Node) -> bool:
	for _index in range(90):
		await process_frame
		if game_director.get("_active_arena") == null:
			return true
	return false

func _fail(message: String) -> bool:
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
