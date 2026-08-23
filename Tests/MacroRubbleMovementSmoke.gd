extends SceneTree

const _PerceptionQuery := preload("res://WorldCore/WorldPerceptionQuery.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load("res://SystemCore/game_director.tscn") as PackedScene
	var director := packed.instantiate()
	root.add_child(director)
	await process_frame
	await process_frame

	var macro_map := director.get_node("MainWorld") as MacroGameManager
	if macro_map == null:
		_fail("Macro world did not initialize.")
		return
	var origin := macro_map.player_token.current_hex_coords
	var rubble_coords := _find_adjacent_passable(macro_map, origin)
	if rubble_coords == origin:
		_fail("Could not find an adjacent passable rubble test hex.")
		return

	var rubble_hex := macro_map.world_generator.get_hex_at(rubble_coords)
	rubble_hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS
	rubble_hex.composition_role = "rubble_search"
	rubble_hex.impassable = false
	rubble_hex.is_explored = false
	macro_map.world_generator.world_hex_cache[rubble_coords] = rubble_hex
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	world_state.set_hex_record(rubble_coords, rubble_hex.to_state())

	if not _PerceptionQuery.can_see(origin, rubble_coords, 1, 1.0, 0.82):
		_fail("Adjacent rubble was incorrectly hidden by its own obstruction factor.")
		return

	# Rebuild line-of-sight, then deliberately leave the authoritative explored
	# bit behind. The route and HUD must still use the live visible projection.
	macro_map._refresh_map_visuals(origin, true)
	if not macro_map._is_hex_visible(rubble_coords):
		_fail("Visible adjacent rubble was not present in the visibility projection.")
		return
	rubble_hex.is_explored = false
	macro_map.world_generator.world_hex_cache[rubble_coords] = rubble_hex
	world_state.set_hex_record(rubble_coords, rubble_hex.to_state())

	var route := macro_map._build_travel_route(origin, rubble_coords)
	if route.is_empty() or route[0] != rubble_coords:
		_fail("Visible adjacent rubble was still rejected by route planning.")
		return
	macro_map._select_hex_for_hud(rubble_coords)
	await process_frame
	var snapshot: Dictionary = macro_map.macro_hud.get("_snapshot")
	var selected_hex: Dictionary = snapshot.get("selected_hex", {})
	var target_location: Dictionary = snapshot.get("target_location", {})
	if not bool(selected_hex.get("travel_known", false)):
		_fail("Selected visible rubble did not expose travel-known state.")
		return
	if not bool(target_location.get("can_travel", false)):
		_fail("Selected visible rubble remained blocked in the target preview.")
		return
	if bool(selected_hex.get("explored", false)):
		_fail("Rubble regression test lost the unknown-preview redaction boundary.")
		return

	print("[TEST PASS] Visible adjacent rubble remains routeable without exposing unknown intel.")
	quit(0)


func _find_adjacent_passable(macro_map: MacroGameManager, origin: Vector2i) -> Vector2i:
	for delta in [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
	]:
		var coords: Vector2i = origin + delta
		if macro_map.world_generator.is_in_zone_bounds(coords):
			var hex_data := macro_map.world_generator.get_hex_at(coords)
			if hex_data != null and hex_data.is_passable():
				return coords
	return origin


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
