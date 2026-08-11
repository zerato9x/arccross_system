extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if not main_scene:
		_fail("Could not load the configured game director scene.")
		return

	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if not macro_map:
		_fail("MainWorld did not initialize.")
		return

	macro_map.refresh_proximity(macro_map.player_token.current_hex_coords)
	await process_frame
	await process_frame

	# This smoke verifies persistent player/enemy presentation and collision,
	# not fog-gated encounter RNG. Central's safe start can legitimately produce
	# no nearby record, so materialize an explicit fixture when needed.
	if macro_map.active_enemies.is_empty():
		if not macro_map.debug_spawn_enemy_near_player():
			_fail("Could not spawn a fixture enemy near the persistent player.")
			return
		await process_frame

	if macro_map.active_enemies.is_empty():
		_fail("The persistent-player fixture produced no nearby enemy token.")
		return

	var player_core := macro_map.player_token.get_humanoid_core()
	if not player_core:
		_fail("Macro player has no authoritative HumanoidCore.")
		return
	var player_token := macro_map.player_token.humanoid_token
	if player_token == null:
		_fail("Macro player did not create the layered Humanoid Token.")
		return
	var legacy_sprite := macro_map.player_token.get_node_or_null("Sprite2D") as Sprite2D
	if legacy_sprite != null and legacy_sprite.visible:
		_fail("The legacy macro placeholder remained visible behind the token.")
		return
	if not HumanoidVisualCatalog.supports_animation("StrafeLeft"):
		_fail("The token runtime omitted the Take Cover strafe animation.")
		return
	if HumanoidVisualCatalog.supports_animation("StrafeLeftAttack"):
		_fail("The token runtime still includes an unused moving attack.")
		return
	if (
		HumanoidVisualCatalog.visual_directory_for_item_id("jeans_1")
		!= HumanoidVisualCatalog.visual_directory_for_item_id("jeans_2")
	):
		_fail("Items sharing an Innawoods look resolved to different token art.")
		return

	var player_signature := player_token.get_appearance_signature()
	for expected_layer in [
		"bag_small_survivalist",
		"jacket_leather",
		"boots_brown",
		"weapons/guns/revolver",
	]:
		if expected_layer not in player_signature:
			_fail("Player token omitted visual layer: " + expected_layer)
			return
	if player_token._layer_sprites.size() < 5:
		_fail("Player token did not build its expected layered sprites.")
		return
	for layer_sprite in player_token._layer_sprites:
		if layer_sprite.texture == null:
			_fail("Player token created a layer without a loaded texture.")
			return
	player_token.face_direction(Vector2.RIGHT)
	if (
		player_token.get_direction_row()
		!= HumanoidVisualCatalog.DIRECTION_RIGHT
	):
		_fail("The Humanoid Token right-facing sheet row is reversed.")
		return
	player_token.face_direction(Vector2.LEFT)
	if (
		player_token.get_direction_row()
		!= HumanoidVisualCatalog.DIRECTION_LEFT
	):
		_fail("The Humanoid Token left-facing sheet row is reversed.")
		return
	var backpack_index := player_token._layer_directories.find(
		HumanoidVisualCatalog.visual_directory_for_item_id(
			"backpack_survivalist"
		)
	)
	var coat_index := player_token._layer_directories.find(
		HumanoidVisualCatalog.visual_directory_for_item_id("coat_leather")
	)
	if backpack_index < 0 or coat_index < 0:
		_fail("The depth test could not find the backpack and coat layers.")
		return
	player_token.set_direction_row(
		HumanoidVisualCatalog.DIRECTION_DOWN_RIGHT
	)
	if (
		player_token._layer_sprites[backpack_index].z_index
		>= player_token._layer_sprites[coat_index].z_index
	):
		_fail("A front-facing backpack rendered over torso clothing.")
		return
	player_token.set_direction_row(
		HumanoidVisualCatalog.DIRECTION_UP_RIGHT
	)
	if (
		player_token._layer_sprites[backpack_index].z_index
		<= player_token._layer_sprites[coat_index].z_index
	):
		_fail("A back-facing diagonal hid the backpack under torso clothing.")
		return

	var first_enemy := macro_map.active_enemies.values()[0] as MacroEnemy
	var enemy_legacy := first_enemy.get_node_or_null("Sprite2D") as Sprite2D
	if (
		first_enemy.humanoid_token == null
		or (enemy_legacy != null and enemy_legacy.visible)
	):
		_fail("A macro enemy did not replace its legacy sprite with a token.")
		return

	if player_core.inventory.get_active_weapon(false) == null:
		_fail("Persistent player loadout was not applied.")
		return

	if (
		not is_equal_approx(player_core.body.blood_level, GameEnums.SCALE_MAX)
		or not is_equal_approx(player_core.body.hunger, GameEnums.SCALE_MAX)
		or not is_equal_approx(player_core.body.thirst, GameEnums.SCALE_MAX)
		or not is_zero_approx(player_core.body.fatigue)
	):
		_fail("A new body did not initialize its systemic vitals on the 0-12 scale.")
		return

	var left_arm_max := player_core.body.get_limb_max(
		GameEnums.LimbRegion.LEFT_ARM
	)
	if not is_equal_approx(
		player_core.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM],
		left_arm_max
	):
		_fail("Fortitude-derived limb structure did not initialize at full health.")
		return

	player_core.body.apply_targeted_hit(GameEnums.LimbRegion.LEFT_ARM, 0.5, 0.0)
	var hunger_before_move: float = player_core.body.hunger

	var enemy_coords: Vector2i = _nearest_enemy_coords(
		macro_map.player_token.current_hex_coords,
		macro_map.active_enemies.keys()
	)
	var enemy_token := macro_map.active_enemies[enemy_coords] as MacroEnemy
	var enemy_id := enemy_token.entity_id
	var origin := macro_map.player_token.current_hex_coords

	var movement_target := _adjacent_passable_hex(
		macro_map,
		origin,
		enemy_coords
	)
	if movement_target == origin:
		_fail("Could not find a passable hex for the movement smoke step.")
		return

	# Exercise the shipping animated step. debug_step_player_to is deliberately
	# instantaneous and therefore cannot validate Walk timing or arrival commits.
	macro_map.call("_execute_player_step", movement_target, true)
	await create_timer(0.22).timeout
	if player_token.get_animation() != "Walk":
		_fail("Macro movement did not drive the token Walk animation.")
		return
	if player_token.get_frame_index() < 1:
		_fail("Macro movement ended before the Walk sheet advanced.")
		return
	await create_timer(MacroPlayer.WALK_DURATION_SECONDS - 0.22 + 0.05).timeout
	if player_core.body.hunger >= hunger_before_move:
		_fail("Macro movement did not tick the persistent player's biology.")
		return

	var enemy_record := macro_map.get_runtime_state_store().get_entity(enemy_id)
	if enemy_record == null:
		_fail("Proximity enemy record disappeared before collision.")
		return
	enemy_coords = enemy_record.coords
	macro_map.debug_project_npc_token(enemy_record)

	var approach_from := macro_map.player_token.current_hex_coords
	macro_map.player_token.snap_to_hex(
		enemy_coords,
		macro_map.map_visualizer.map_to_local(enemy_coords)
	)
	macro_map.get_runtime_state_store().update_player_runtime(
		player_core.capture_runtime_state().to_dict(),
		enemy_coords
	)
	macro_map.close_macro_interaction()
	if not macro_map.queue_entity_collision(enemy_id, enemy_coords, approach_from):
		_fail("Could not queue entity collision for combat handoff.")
		return
	await process_frame

	if (
		macro_map.get_pending_interaction_type()
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		_fail("Entity collision did not open the interaction decision.")
		return

	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.STANDARD)
	await process_frame
	await process_frame

	var arena = game_director.get_active_arena()
	if not arena:
		_fail("Entering an occupied hex did not create a duel.")
		return

	if arena.player_core == player_core:
		_fail("Combat incorrectly reused the live macro player node.")
		return

	if (
		arena.player_core.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM]
		!= player_core.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM]
	):
		_fail("Player injuries were reset during the combat transition.")
		return

	var combat_ai := arena.get_node_or_null("TacticalCombatAI_01") as TacticalCombatAI
	if combat_ai == null or combat_ai.actor != arena.enemy_core:
		_fail("The encounter enemy did not receive the tactical AI controller.")
		return
	if combat_ai.actor == arena.player_core:
		_fail("The direct player incorrectly received tactical AI control.")
		return

	print("[TEST PASS] Persistent player state survives the macro-to-combat transition.")
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)

func _nearest_enemy_coords(origin: Vector2i, candidates: Array) -> Vector2i:
	var nearest: Vector2i = candidates[0]
	var nearest_distance := _hex_distance(origin, nearest)
	for coords in candidates:
		var distance := _hex_distance(origin, coords)
		if distance < nearest_distance:
			nearest = coords
			nearest_distance = distance
	return nearest

func _adjacent_passable_hex(
	macro_map: MacroGameManager,
	origin: Vector2i,
	avoid: Vector2i
) -> Vector2i:
	for direction in MacroGameManager.HEX_NEIGHBORS:
		var candidate: Vector2i = origin + direction
		if candidate == avoid:
			continue
		if macro_map._world_state.has_entity_at(candidate):
			continue
		var hex := macro_map.world_generator.get_hex_at(candidate)
		if hex.is_passable():
			return candidate
	return origin

func _build_hex_path(origin: Vector2i, destination: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var current := origin
	while current != destination:
		var best_step := current
		var best_distance := _hex_distance(current, destination)
		for direction in MacroGameManager.HEX_NEIGHBORS:
			var candidate: Vector2i = current + direction
			var distance := _hex_distance(candidate, destination)
			if distance < best_distance:
				best_step = candidate
				best_distance = distance
		current = best_step
		path.append(current)
	return path

func _hex_distance(from_coords: Vector2i, to_coords: Vector2i) -> int:
	var delta := to_coords - from_coords
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))
