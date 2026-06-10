extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load(
		"res://SystemCore/game_director.tscn"
	) as PackedScene
	if not main_scene:
		_fail("Could not load the game director scene.")
		return

	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var origin := macro_map.player_token.current_hex_coords
	var enemy_coords := _nearest_enemy_coords(
		origin,
		macro_map.active_enemies.keys()
	)
	var enemy_id: String = macro_map.active_enemies[enemy_coords].entity_id

	for step in _build_hex_path(origin, enemy_coords):
		macro_map._execute_player_step(step)
		await process_frame

	if (
		macro_map._pending_interaction.get("type")
		!= GameEnums.MacroInteractionType.ENTITY_COLLISION
	):
		_fail("The test could not enter an entity collision.")
		return

	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.FAR)
	await process_frame
	await process_frame

	var arena = game_director.get("_active_arena")
	if arena == null:
		_fail("The collision did not create a combat arena.")
		return
	if not arena.combat_panel.visible:
		_fail("The combat panel did not open.")
		return

	var adapter: CombatCommandAdapter = arena.command_adapter
	var snapshot := adapter.get_snapshot()
	if not snapshot.get("is_player_turn", false):
		_fail("The initiating player did not receive a command turn.")
		return
	if not _snapshot_has_action(
		snapshot,
		GameEnums.ActionType.MOVE_FORWARD
	):
		_fail("The command snapshot did not expose legal movement.")
		return
	if not _snapshot_has_action(snapshot, GameEnums.ActionType.SHOOT):
		_fail("The command snapshot did not expose the equipped firearm.")
		return

	var lane_before: int = arena.lane_manager._find_entity_lane(
		arena.player_core
	)
	var ap_before: int = arena.turn_manager.current_ap_pool
	adapter.request_player_action(GameEnums.ActionType.MOVE_FORWARD)
	await process_frame
	await process_frame
	var lane_after: int = arena.lane_manager._find_entity_lane(
		arena.player_core
	)
	if lane_after != lane_before + 1:
		_fail("The player command adapter did not advance toward the enemy.")
		return
	if arena.turn_manager.current_ap_pool >= ap_before:
		_fail("The player movement command did not spend AP.")
		return

	arena.turn_manager.reserved_ap[arena.player_core] = 6
	var reactions: Array = arena.turn_manager.open_reaction_window(
		arena.player_core,
		arena.enemy_core,
		GameEnums.ActionType.STRIKE
	)
	if not reactions.has(GameEnums.ActionType.DODGE):
		_fail("A valid player dodge reaction was not offered.")
		return
	await process_frame
	if not arena.turn_manager._reaction_pending:
		_fail("The player reaction prompt did not pause resolution.")
		return
	adapter.resolve_player_reaction(GameEnums.ActionType.DODGE)
	await process_frame
	if arena.turn_manager._reaction_pending:
		_fail("The player reaction command did not resume resolution.")
		return
	if arena.turn_manager.reserved_ap[arena.player_core] >= 6:
		_fail("The player reaction did not spend reserved AP.")
		return

	var player_lane: int = arena.lane_manager._find_entity_lane(
		arena.player_core
	)
	var enemy_lane: int = arena.lane_manager._find_entity_lane(
		arena.enemy_core
	)
	arena.lane_manager.lane_slots[enemy_lane].exit_slot(arena.enemy_core)
	arena.lane_manager.lane_slots[player_lane].enter_slot(arena.enemy_core)
	arena.enemy_core.stance_points = 0
	arena.enemy_core._evaluate_stance_state()
	adapter.refresh_snapshot()

	snapshot = adapter.get_snapshot()
	if _snapshot_has_action(snapshot, GameEnums.ActionType.EXECUTE):
		_fail("The trait-gated EXECUTE action was exposed in the demo.")
		return
	if not _snapshot_has_action(snapshot, GameEnums.ActionType.PULL_FOLLOW):
		_fail("The melee command snapshot did not expose PULL / FOLLOW.")
		return
	var strike_descriptor := _find_action(
		snapshot,
		GameEnums.ActionType.STRIKE
	)
	if not strike_descriptor.get("target_limbs", []).is_empty():
		_fail("STRIKE still requested a player-selected Limb Region.")
		return

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
		GameEnums.SCALE_MAX
	)
	await process_frame
	await process_frame
	await process_frame

	if outcomes.is_empty():
		_fail("Combat death did not resolve the duel.")
		return
	if outcomes[0] != GameEnums.CombatOutcome.PLAYER_VICTORY:
		_fail("The finishing action produced the wrong combat outcome.")
		return
	if world_state.is_entity_alive(enemy_id):
		_fail("Victory did not mark the persistent enemy record dead.")
		return

	game_director.queue_free()
	await process_frame
	await process_frame
	if not await _verify_player_escape():
		return

	print(
		"[TEST PASS] Player combat snapshots, AP commands, reactions, targeting rules, "
		+ "victory, and escape routing are integrated."
	)
	quit(0)

func _verify_player_escape() -> bool:
	var main_scene := load(
		"res://SystemCore/game_director.tscn"
	) as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	var origin := macro_map.player_token.current_hex_coords
	var enemy_coords := _nearest_enemy_coords(
		origin,
		macro_map.active_enemies.keys()
	)
	var enemy_id: String = macro_map.active_enemies[enemy_coords].entity_id
	for step in _build_hex_path(origin, enemy_coords):
		macro_map._execute_player_step(step)
		await process_frame

	macro_map.resolve_entity_ambush(GameEnums.AmbushPosition.FAR)
	await process_frame
	await process_frame
	var arena = game_director.get("_active_arena")
	if arena == null:
		_fail("The escape test could not create combat.")
		return false

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
	var adapter: CombatCommandAdapter = arena.command_adapter
	adapter.request_player_action(GameEnums.ActionType.MOVE_BACKWARD)
	await process_frame
	await process_frame
	if arena.lane_manager._find_entity_lane(arena.player_core) != 0:
		_fail("RETREAT did not move the player into the escape zone.")
		return false

	adapter.request_player_action(GameEnums.ActionType.MOVE_BACKWARD)
	for _frame in range(90):
		if not outcomes.is_empty():
			break
		await process_frame

	if outcomes.is_empty():
		_fail("The player did not escape after surviving the escape-zone wait.")
		return false
	if outcomes[0] != GameEnums.CombatOutcome.PLAYER_ESCAPED:
		_fail("The escape command produced the wrong combat outcome.")
		return false
	if not world_state.is_entity_alive(enemy_id):
		_fail("Player escape incorrectly killed the persistent enemy.")
		return false

	game_director.queue_free()
	await process_frame
	return true

func _snapshot_has_action(snapshot: Dictionary, action: int) -> bool:
	for descriptor in snapshot.get("actions", []):
		if descriptor.get("action", -1) == action:
			return true
	return false

func _find_action(snapshot: Dictionary, action: int) -> Dictionary:
	for descriptor in snapshot.get("actions", []):
		if descriptor.get("action", -1) == action:
			return descriptor
	return {}

func _nearest_enemy_coords(origin: Vector2i, candidates: Array) -> Vector2i:
	var nearest: Vector2i = candidates[0]
	var nearest_distance := _hex_distance(origin, nearest)
	for coords in candidates:
		var distance := _hex_distance(origin, coords)
		if distance < nearest_distance:
			nearest = coords
			nearest_distance = distance
	return nearest

func _build_hex_path(
	origin: Vector2i,
	destination: Vector2i
) -> Array[Vector2i]:
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
	return maxi(
		abs(delta.x),
		maxi(abs(delta.y), abs(delta.x + delta.y))
	)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
