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
	print("[TEST PASS] Combat escape retreats on the macro map and enemy death keeps clothed Die layers through resolve.")
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
		macro_map.player_token.get_humanoid_core().capture_runtime_state().to_dict(),
		collision_coords
	)
	macro_map.queue_entity_collision(
		enemy_record.entity_id,
		collision_coords,
		origin
	)
	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.STANDARD)
	await process_frame
	await process_frame

	var arena = game_director.get_active_arena()
	if arena == null:
		return _fail("Combat handoff did not create an arena for escape.")
	var macro_camera := macro_map.get_node_or_null("Camera2D") as Camera2D
	if macro_camera != null and macro_camera.enabled:
		return _fail("Macro camera stayed enabled during integrated combat.")
	if arena.lane_hud is RealtimeDuelHUD:
		if not arena.lane_hud.combat_camera.enabled:
			return _fail("Real-time duel camera did not claim integrated combat.")
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
	if macro_camera != null and not macro_camera.enabled:
		return _fail("Macro camera was not restored after integrated combat.")

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

	var shirt := (
		load("res://ItemCore/Items/tshirt_black.tres") as ItemData
	).create_runtime_instance()
	var pants := (
		load("res://ItemCore/Items/pants_cargo.tres") as ItemData
	).create_runtime_instance()
	if not arena.enemy_core.inventory.equip_item(
		shirt,
		GameEnums.EquipmentSlot.INNER_TORSO
	):
		return _fail("Could not equip mapped shirt on the resolve enemy.")
	if not arena.enemy_core.inventory.equip_item(
		pants,
		GameEnums.EquipmentSlot.LEGS
	):
		return _fail("Could not equip mapped pants on the resolve enemy.")
	arena.duel_runtime.refresh_snapshot()
	await process_frame

	var shirt_dir := str(
		HumanoidVisualCatalog.ITEM_VISUAL_DIRECTORIES.get("tshirt_black", "")
	)
	var pants_dir := str(
		HumanoidVisualCatalog.ITEM_VISUAL_DIRECTORIES.get("pants_cargo", "")
	)
	if shirt_dir.is_empty() or pants_dir.is_empty():
		return _fail("Mapped clothing directories missing from ITEM_VISUAL_DIRECTORIES.")

	var outcomes: Array = []
	arena.duel_finished.connect(
		func(
			outcome: GameEnums.CombatOutcome,
			_enemy_id: String,
			_enemy_runtime: Dictionary,
			_player_runtime: Dictionary,
			_dropped_items: Array
		) -> void:
			outcomes.append(outcome)
	)
	arena.enemy_core.body.apply_targeted_hit(
		GameEnums.LimbRegion.HEAD,
		999.0,
		0.0
	)

	var enemy_token: HumanoidTokenView = arena.lane_hud.lane_view._enemy_token
	if not await _wait_for_token_animation(enemy_token, "Die", 180):
		return _fail("Final blow did not drive the enemy death animation.")
	if enemy_token.get("_animation_speed_scale") >= 0.75:
		return _fail("Final blow did not slow the enemy death animation.")

	# Reproduce the old strip path mid-Die: drain equipment and rebuild the
	# snapshot. Clothed death appearance must survive.
	arena.enemy_core.inventory.drain_all_items()
	arena.duel_runtime.refresh_snapshot()
	await process_frame
	await process_frame
	if enemy_token.get_animation() != "Die":
		return _fail("Drain/refresh interrupted the Die presentation.")
	var die_signature := enemy_token.get_appearance_signature()
	var die_dirs: Array = enemy_token.get("_layer_directories")
	var has_shirt := false
	var has_pants := false
	for directory in die_dirs:
		var path := str(directory)
		if path.contains(shirt_dir):
			has_shirt = true
		if path.contains(pants_dir):
			has_pants = true
	if (
		not has_shirt
		or not has_pants
		or die_signature.find(shirt_dir) < 0
		or die_signature.find(pants_dir) < 0
	):
		return _fail(
			"Die presentation stripped clothing after drain. signature=%s dirs=%s"
			% [die_signature, str(die_dirs)]
		)
	if die_dirs.size() <= 1:
		return _fail(
			"Die presentation only kept the naked base layer. dirs=%s"
			% str(die_dirs)
		)

	var headless := DisplayServer.get_name() == "headless"
	if headless:
		for _frame in range(240):
			if not outcomes.is_empty():
				break
			await process_frame
		if outcomes.size() != 1 or outcomes[0] != GameEnums.CombatOutcome.PLAYER_VICTORY:
			return _fail("Enemy death did not finish as a player victory.")
		holder.queue_free()
		await process_frame
		return true

	if not await _wait_for_resolve_visible(arena.lane_hud):
		return _fail("Enemy death did not show the resolve screen.")
	if arena.lane_hud.get_resolve_focus_side() != "enemy":
		return _fail("Resolve screen did not focus the enemy token.")
	if arena.lane_hud.get_camera_zoom_value() < 1.25:
		return _fail("Resolve screen did not zoom the combat camera.")
	if not await _wait_for_result_overlay(arena.lane_hud):
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

func _wait_for_token_animation(
	token: HumanoidTokenView,
	animation: String,
	frame_limit: int = 180
) -> bool:
	for _frame in range(frame_limit):
		if token != null and token.get_animation() == animation:
			return true
		await process_frame
	return token != null and token.get_animation() == animation

func _wait_for_resolve_visible(
	hud: RealtimeDuelHUD,
	frame_limit: int = 360
) -> bool:
	for _frame in range(frame_limit):
		if hud.is_resolve_screen_visible():
			return true
		await process_frame
	return hud.is_resolve_screen_visible()

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
		if game_director.get_active_arena() == null:
			return true
	return false

func _wait_for_result_overlay(
	hud: CombatLaneHUD,
	frame_limit: int = 360
) -> bool:
	for _frame in range(frame_limit):
		if hud.is_result_overlay_waiting():
			return true
		await process_frame
	return hud.is_result_overlay_waiting()

func _fail(message: String) -> bool:
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
