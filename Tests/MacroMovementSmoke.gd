extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	var director := packed.instantiate()
	root.add_child(director)
	await process_frame
	await process_frame
	await process_frame

	var macro := director.get_node_or_null("MainWorld") as MacroGameManager
	if macro == null or macro.player_token == null:
		_fail("Macro movement scene did not initialize.")
		return
	var state := root.get_node_or_null("WorldState") as RuntimeStateStore
	if state == null:
		_fail("Runtime state store is missing.")
		return
	var canonical_core := EntityFactory.record_to_humanoid_core(
		state.player_record.to_dict(), null, "MacroMovementCanonicalFixture"
	)
	if canonical_core == null:
		_fail("Could not reconstruct the canonical movement fixture.")
		return
	canonical_core.body.fatigue = 7.25
	var canonical_runtime := canonical_core.capture_runtime_state().to_dict()
	canonical_core.free()
	if not state.update_player_runtime(
		canonical_runtime,
		state.player_record.coords
	):
		_fail("Could not seed canonical-only movement biology.")
		return

	var origin: Vector2i = macro.player_token.current_hex_coords
	var far_target := _find_far_known_target(macro, origin)
	if far_target == Vector2i(999999, 999999):
		_fail("No known multi-step target was available.")
		return
	macro.call("_select_hex_for_hud", far_target)
	var world_snapshot: Dictionary = macro.call("_build_world_hud_snapshot")
	var target_snapshot: Dictionary = macro.call(
		"_build_target_location_snapshot",
		world_snapshot
	)
	if not bool(target_snapshot.get("can_travel", false)):
		_fail("Known multi-step target is still marked unavailable: %s" % str(target_snapshot))
		return

	var target := _find_explored_passable_neighbor(macro, origin)
	if target == Vector2i(999999, 999999):
		_fail("No explored passable movement neighbor was available.")
		return
	macro.call("_select_hex_for_hud", target)
	macro.call("_try_travel_to_selected_hex")
	if (macro.get("_pending_player_step") as Dictionary).is_empty():
		_fail("Animated movement did not create a pending step.")
		return
	await create_timer(MacroPlayer.WALK_DURATION_SECONDS + 0.25).timeout
	await process_frame
	if not (macro.get("_pending_player_step") as Dictionary).is_empty():
		_fail("Pending movement was not cleared on arrival.")
		return
	if macro.player_token.current_hex_coords != target:
		_fail("Player token did not arrive at the requested hex.")
		return
	if state.player_record.coords != target:
		_fail("Authoritative player position did not commit on arrival.")
		return
	if float(state.player_record.runtime.get("body", {}).get("fatigue", 0.0)) < 7.25:
		_fail("Travel overwrote canonical biology with the stale live projection.")
		return
	if (
		macro.player_token.get_humanoid_core().capture_runtime_state().to_dict()
		!= state.player_record.runtime
	):
		_fail("Travel did not reproject committed canonical runtime to the player.")
		return

	macro.call("_select_hex_for_hud", origin)
	if macro.get("_selected_hex_coords") != origin:
		_fail("Hex selection remained blocked after movement arrival.")
		return

	if not macro.retreat_player_from_combat(target, origin):
		_fail("Retreat movement was rejected from a valid adjacent hex.")
		return
	if (macro.get("_pending_player_step") as Dictionary).is_empty():
		_fail("Retreat did not create a pending movement.")
		return
	await create_timer(MacroPlayer.WALK_DURATION_SECONDS + 0.25).timeout
	await process_frame
	if not (macro.get("_pending_player_step") as Dictionary).is_empty():
		_fail("Retreat pending movement was not cleared on arrival.")
		return
	if state.player_record.coords != origin:
		_fail("Retreat authoritative position committed before or after the wrong hex.")
		return

	print("[TEST PASS] Macro animated movement, multi-step travel, selection unlock, and retreat commit.")
	director.queue_free()
	await process_frame
	quit(0)


func _find_explored_passable_neighbor(
	macro: MacroGameManager,
	origin: Vector2i
) -> Vector2i:
	for direction in [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
	]:
		var candidate: Vector2i = origin + direction
		var hex_data := macro.world_generator.get_hex_at(candidate)
		if hex_data.is_explored and hex_data.is_passable():
			return candidate
	return Vector2i(999999, 999999)


func _find_far_known_target(
	macro: MacroGameManager,
	origin: Vector2i
) -> Vector2i:
	for value in macro.world_generator.world_hex_cache.keys():
		if not value is Vector2i:
			continue
		var coords: Vector2i = value
		if coords == origin or HexCoordUtils.distance(origin, coords) <= 1:
			continue
		var hex_data := macro.world_generator.get_hex_at(coords)
		if not hex_data.is_explored or not hex_data.is_passable():
			continue
		var route: Array = macro.call("_build_travel_route", origin, coords)
		if not route.is_empty():
			return coords
	return Vector2i(999999, 999999)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
