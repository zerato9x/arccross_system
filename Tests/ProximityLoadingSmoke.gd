extends SceneTree

const MAX_VISIBLE_TOKENS := 3
const MAX_RENDERED_RADIUS_CELLS := 91

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame

	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	var world_state := root.get_node("WorldState") as RuntimeStateStore
	if not macro_map or not world_state:
		_fail("World systems did not initialize.")
		return

	if macro_map.active_enemies.size() < 2:
		_seed_probe_enemies(macro_map, world_state)

	if macro_map.active_enemies.size() < 2:
		_fail("Proximity smoke could not create two controlled enemies.")
		return

	if macro_map.active_enemies.size() > MAX_VISIBLE_TOKENS:
		_fail("Initial proximity refresh projected more than 3 enemies.")
		return

	var tracked_coords: Vector2i = macro_map.active_enemies.keys()[0]
	var tracked_token := macro_map.active_enemies[tracked_coords] as MacroEnemy
	var tracked_id := tracked_token.entity_id
	var tracked_record := world_state.get_entity(tracked_id)
	var tracked_definition: Dictionary = tracked_record.definition
	world_state.update_entity_runtime(tracked_id, {"persistence_marker": 12})

	var dead_coords := Vector2i.ZERO
	var dead_id := ""
	for coords in macro_map.active_enemies.keys():
		if coords == tracked_coords:
			continue
		dead_coords = coords
		dead_id = (macro_map.active_enemies[coords] as MacroEnemy).entity_id
		break
	if dead_id.is_empty():
		_fail("The initial region did not contain a second enemy for death persistence.")
		return
	world_state.set_entity_life_state(dead_id, GameEnums.EntityLifeState.DEAD)
	macro_map.unload_enemy_token(dead_coords)

	var deterministic_copy := macro_map.mob_spawner.generate_mob_record(
		tracked_coords,
		tracked_definition.get("faction", GameEnums.Faction.UNALIGNED),
		floori(float(macro_map.hex_distance(Vector2i.ZERO, tracked_coords)) / 8.0),
		macro_map._encounter_key(tracked_coords)
	)
	if deterministic_copy.definition != tracked_definition:
		_fail("Coordinate-stable mob generation produced a different definition.")
		return

	# Zone-inject worlds paint the full MACRO_ZONE_RADIUS disk at boot via
	# render_zone(). That is intentional retention, not a proximity leak —
	# do not count it against the chunked render_radius budget below.
	var initial_cells := macro_map.map_visualizer.rendered_cells.size()
	if initial_cells > GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail(
			"Initial zone paint exceeded MACRO_ZONE_CELL_COUNT (%d > %d)."
			% [initial_cells, GameEnums.MACRO_ZONE_CELL_COUNT]
		)
		return

	var peak_tokens := macro_map.active_enemies.size()
	# Start at 0 so the boot-time zone paint does not inflate the retained-
	# radius peak measured during the render_radius walk.
	var peak_cells := 0
	var peak_markers := 0

	for step in range(1, 101):
		var center := Vector2i(step, 0)
		macro_map.map_visualizer.render_radius(center, 3)
		macro_map.refresh_proximity(center)
		peak_tokens = maxi(peak_tokens, macro_map.active_enemies.size())
		peak_cells = maxi(
			peak_cells,
			macro_map.map_visualizer.rendered_cells.size()
		)
		peak_markers = maxi(
			peak_markers,
			macro_map.map_visualizer.poi_markers.size()
		)
		if not _tokens_within_unload_radius(macro_map, center):
			_fail("A projected enemy remained outside the unload radius.")
			return

	if macro_map.active_enemies.has(tracked_coords):
		_fail("A distant enemy token was not unloaded.")
		return

	if peak_tokens > MAX_VISIBLE_TOKENS:
		_fail("Enemy token count exceeded the visible token cap.")
		return

	if peak_cells > MAX_RENDERED_RADIUS_CELLS:
		_fail("Rendered tile count grew beyond the retained visual radius.")
		return

	if peak_markers > peak_cells:
		_fail("POI marker count exceeded retained rendered cells.")
		return

	var persisted_record := world_state.get_entity(tracked_id)
	if persisted_record.runtime.get("persistence_marker", 0) != 12:
		_fail("Unloading the enemy token erased runtime state.")
		return

	var record_count_before_return := world_state.entity_records.size()
	macro_map.map_visualizer.render_radius(Vector2i.ZERO, 3)
	macro_map.refresh_proximity(Vector2i.ZERO)
	await process_frame

	if not macro_map.active_enemies.has(tracked_coords):
		_fail("Returning to the region did not reload the persistent enemy.")
		return

	var reloaded := macro_map.active_enemies[tracked_coords] as MacroEnemy
	if reloaded.entity_id != tracked_id:
		_fail("Returning to the region projected a different enemy identity.")
		return

	if world_state.entity_records.size() != record_count_before_return:
		_fail("Revisiting an evaluated region generated duplicate entity records.")
		return

	if macro_map.active_enemies.has(dead_coords):
		_fail("A dead persistent enemy projected a token after revisiting.")
		return

	var dead_record := world_state.get_entity(dead_id)
	if dead_record == null or world_state.is_entity_alive(dead_id):
		_fail("Dead enemy record was lost or revived after revisiting.")
		return
	if world_state.get_entity_at(dead_coords) != null:
		_fail("Dead enemy still occupied its hex after death.")
		return

	if not _entity_coordinates_are_unique(world_state.get_all_entity_records()):
		_fail("Multiple persistent enemies occupy the same coordinate.")
		return

	print(
		"[TEST PASS] Proximity loading stayed bounded across 100 steps. Peak tokens: ",
		peak_tokens,
		", peak cells: ",
		peak_cells,
		", peak POIs: ",
		peak_markers
	)
	quit(0)

func _entity_coordinates_are_unique(records: Array) -> bool:
	var occupied: Dictionary = {}
	for record in records:
		var coords: Vector2i = record.coords
		if occupied.has(coords):
			return false
		occupied[coords] = true
	return true

func _seed_probe_enemies(
	macro_map: MacroGameManager,
	world_state: RuntimeStateStore
) -> void:
	for coords in [
		Vector2i(3, 0),
		Vector2i(3, -1),
		Vector2i(3, 1),
		Vector2i(2, -3),
	]:
		if macro_map.active_enemies.size() >= 2:
			return
		if world_state.has_entity_at(coords):
			var record := world_state.get_entity_at(coords)
			if record != null and world_state.is_entity_alive(record.entity_id):
				macro_map.load_enemy_token(record.entity_id)
			continue
		var hex := macro_map.world_generator.get_hex_at(coords)
		if not hex.is_passable():
			continue
		macro_map.spawn_procedural_enemy(
			coords,
			GameEnums.Faction.SCAVENGER_CELL,
			0
		)

func _tokens_within_unload_radius(
	macro_map: MacroGameManager,
	center: Vector2i
) -> bool:
	for coords in macro_map.active_enemies.keys():
		if macro_map.hex_distance(center, coords) > macro_map.unload_radius:
			return false
	return true

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
