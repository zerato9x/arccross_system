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

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if not macro_map:
		_fail("MainWorld did not initialize.")
		return

	if macro_map.active_enemies.is_empty():
		_fail("Deterministic proximity generation created no nearby enemies.")
		return

	var player_core := macro_map.player_token.get_humanoid_core()
	if not player_core:
		_fail("Macro player has no authoritative HumanoidCore.")
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
	var injured_arm_hp: float = player_core.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM]
	var hunger_before_move: float = player_core.body.hunger

	var enemy_coords: Vector2i = _nearest_enemy_coords(
		macro_map.player_token.current_hex_coords,
		macro_map.active_enemies.keys()
	)
	var path := _build_hex_path(
		macro_map.player_token.current_hex_coords,
		enemy_coords
	)

	for step_index in range(path.size()):
		macro_map._execute_player_step(path[step_index])
		await process_frame

		if step_index == 0 and player_core.body.hunger >= hunger_before_move:
			_fail("Macro movement did not tick the persistent player's biology.")
			return

	if (
		macro_map._pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		_fail("Entity collision did not open the interaction decision.")
		return

	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.STANDARD)
	await process_frame
	await process_frame

	var arena = game_director.get("_active_arena")
	if not arena:
		_fail("Entering an occupied hex did not create a duel.")
		return

	if arena.player_core != player_core:
		_fail("Combat replaced the authoritative macro player core.")
		return

	if arena.player_core.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM] != injured_arm_hp:
		_fail("Player injuries were reset during the combat transition.")
		return

	if player_core.get_node_or_null("CombatAIEvaluator") != null:
		_fail("The persistent player incorrectly received combat AI.")
		return

	if arena.enemy_core.get_node_or_null("CombatAIEvaluator") == null:
		_fail("The encounter enemy did not receive combat AI.")
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
