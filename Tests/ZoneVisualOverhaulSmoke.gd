extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _verify_time_rules():
		return
	if not _verify_plains_catalog():
		return
	if not _verify_zone_density_offline():
		return
	if not await _verify_zone_and_fog():
		return
	print("[TEST PASS] Zone visual overhaul: axial 12x12, full-hex black fog, density, 45min moves.")
	quit(0)


func _verify_time_rules() -> bool:
	if GameTimeRules.MOVE_MINUTES != 45:
		_fail("MOVE_MINUTES must be 45 for ~100 km² zones, got %d." % GameTimeRules.MOVE_MINUTES)
		return false
	if GameTimeRules.ZONE_AREA_KM2 < 99.0 or GameTimeRules.HEX_AREA_KM2 <= 0.0:
		_fail("Zone/hex area constants missing or invalid.")
		return false
	var plains := MacroHexData.new()
	plains.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	var hills := MacroHexData.new()
	hills.rock_layer = GameEnums.MacroRockLayer.HILLS
	var mud := MacroHexData.new()
	mud.terrain_tile = GameEnums.MacroTerrainTile.MUD_YELLOW
	if not is_equal_approx(plains.travel_exertion(), 1.0):
		_fail("Plains exertion should be 1.0.")
		return false
	if hills.travel_exertion() <= plains.travel_exertion():
		_fail("Hills exertion must exceed plains.")
		return false
	if mud.travel_time_multiplier() <= plains.travel_time_multiplier():
		_fail("Mud travel time must exceed plains.")
		return false
	if GameTimeRules.move_minutes_for_hex(plains) != 45:
		_fail("Plains move minutes should be 45.")
		return false
	if GameTimeRules.move_minutes_for_hex(hills) != 90:
		_fail("Hills move minutes should be 90.")
		return false
	return true


func _verify_plains_catalog() -> bool:
	var catalog := load("res://Asset/MacroTileCatalog.tres") as MacroTileCatalog
	if catalog == null:
		_fail("MacroTileCatalog.tres missing.")
		return false
	var plains: PackedInt32Array = catalog.terrain_source_ids.get(
		GameEnums.MacroTerrainTile.PLAINS_GRASS,
		PackedInt32Array()
	)
	var mud: PackedInt32Array = catalog.terrain_source_ids.get(
		GameEnums.MacroTerrainTile.MUD_YELLOW,
		PackedInt32Array()
	)
	if plains.is_empty():
		_fail("PLAINS_GRASS has no green_hex sources.")
		return false
	if mud.is_empty():
		_fail("MUD_YELLOW has no mud.png source.")
		return false
	for sid in plains:
		var path := _path_for_source(catalog, sid)
		var lowered := path.to_lower()
		if "green_hex" not in lowered and "painted - green" not in lowered:
			_fail("PLAINS_GRASS source is not green_hex: %s" % path)
			return false
		if "sparse green" in lowered or "riverbed" in lowered or "old riverbed" in lowered:
			_fail("PLAINS_GRASS still includes mismatched family: %s" % path)
			return false
	return true


func _path_for_source(catalog: MacroTileCatalog, source_id: int) -> String:
	for path in catalog.path_to_source_id.keys():
		if int(catalog.path_to_source_id[path]) == source_id:
			return str(path)
	return ""


func _verify_zone_density_offline() -> bool:
	var zone := MacroZoneGenerator.new()
	zone.configure_seed("ZONE_VISUAL_OVERHAUL_SMOKE")
	zone.generate_zone("smoke_plains", GameEnums.MacroZoneKind.BIOME_RNG, GameEnums.GridBiome.PLAINS)
	if zone.hex_count() != GameEnums.MACRO_ZONE_SIZE * GameEnums.MACRO_ZONE_SIZE:
		_fail("Expected 144 axial cells, got %d." % zone.hex_count())
		return false
	if zone.start_coords != Vector2i(6, 10) or zone.objective_coords != Vector2i(6, 1):
		_fail(
			"Start/objective not axial-relative: start=%s objective=%s"
			% [str(zone.start_coords), str(zone.objective_coords)]
		)
		return false

	var landmark_count := 0
	var shrub_count := 0
	var structure_count := 0
	var rejected_by_offset := 0
	for coords in zone.world_hex_cache.keys():
		if not zone.is_in_bounds(coords):
			_fail("Generated out-of-bounds cell %s." % str(coords))
			return false
		# Offset-rect membership must NOT be required for axial zone cells.
		if not HexCoordUtils.is_in_offset_rect(coords, GameEnums.MACRO_ZONE_SIZE):
			rejected_by_offset += 1
		var hex: MacroHexData = zone.world_hex_cache[coords]
		if hex.is_poi or not hex.landmark_id.is_empty():
			landmark_count += 1
		if hex.flora_layer == GameEnums.MacroFloraLayer.SHRUBS:
			shrub_count += 1
		if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
			structure_count += 1

	if landmark_count < zone.guaranteed_landmark_count:
		_fail(
			"Landmark floor unmet: got %d, need >= %d."
			% [landmark_count, zone.guaranteed_landmark_count]
		)
		return false
	if shrub_count < 20:
		_fail("Shrub density too sparse: %d." % shrub_count)
		return false
	if structure_count < 8:
		_fail("Structure/remnant density too sparse: %d." % structure_count)
		return false
	if zone.zone_decorations.is_empty():
		_fail("Expected zone decoration clutter.")
		return false
	if rejected_by_offset <= 0:
		_fail("Expected some axial rhombus cells outside odd-R rect (bounds fight regression).")
		return false
	return true


func _verify_zone_and_fog() -> bool:
	var game_director: Node = await _spawn_game()
	if game_director == null:
		return false
	var macro_map := game_director.get_node("MainWorld") as MacroGameManager
	if macro_map == null or macro_map.map_visualizer == null:
		_fail("Macro map / visualizer missing.")
		return false

	await process_frame
	await process_frame

	var viz := macro_map.map_visualizer
	if viz.rendered_cells.size() != GameEnums.MACRO_ZONE_SIZE * GameEnums.MACRO_ZONE_SIZE:
		_fail(
			"Expected full 12x12 render, got %d cells."
			% viz.rendered_cells.size()
		)
		return false

	# Axial membership: every in-bounds playable cell must be accepted.
	var in_bounds_count := 0
	for coords in macro_map.world_generator.world_hex_cache.keys():
		if macro_map.world_generator.is_in_zone_bounds(coords):
			in_bounds_count += 1
			var hex: MacroHexData = macro_map.world_generator.world_hex_cache[coords]
			if hex.zone_id == "void":
				_fail("In-bounds zone cell %s marked void." % str(coords))
				return false
		else:
			# Fog/neighbor probes may cache void hexes just outside the rhombus.
			var outside: MacroHexData = macro_map.world_generator.world_hex_cache[coords]
			if not outside.impassable:
				_fail("Out-of-bounds cell %s should be impassable void." % str(coords))
				return false
	if in_bounds_count != GameEnums.MACRO_ZONE_SIZE * GameEnums.MACRO_ZONE_SIZE:
		_fail("Expected 144 in-bounds zone cells, got %d." % in_bounds_count)
		return false

	var fog_poly := viz._hex_fog_polygon()
	if fog_poly.size() != 6:
		_fail("Fog polygon must be a hex (6 verts).")
		return false
	var fog_aabb := Rect2(fog_poly[0], Vector2.ZERO)
	for point in fog_poly:
		fog_aabb = fog_aabb.expand(point)
	var tile_size := Vector2(512, 512)
	if viz.tile_set != null:
		tile_size = Vector2(viz.tile_set.tile_size)
	if fog_aabb.size.x + 0.01 < tile_size.x or fog_aabb.size.y + 0.01 < tile_size.y:
		_fail(
			"Fog AABB %s smaller than tile footprint %s."
			% [str(fog_aabb.size), str(tile_size)]
		)
		return false

	for fog_color in [
		HexMapVisualizer.FOG_VISIBLE_COLOR,
		HexMapVisualizer.FOG_EXPLORED_COLOR,
		HexMapVisualizer.FOG_UNKNOWN_COLOR,
	]:
		if fog_color.r > 0.01 or fog_color.g > 0.01 or fog_color.b > 0.01:
			_fail("Fog color has non-black chroma: %s" % str(fog_color))
			return false

	var catalog := viz.tile_catalog
	if catalog == null:
		_fail("Visualizer has no tile catalog.")
		return false
	var plains_ids: PackedInt32Array = catalog.terrain_source_ids.get(
		GameEnums.MacroTerrainTile.PLAINS_GRASS,
		PackedInt32Array()
	)

	var poi_count := 0
	for coords in macro_map.world_generator.world_hex_cache.keys():
		var hex: MacroHexData = macro_map.world_generator.world_hex_cache[coords]
		if hex.terrain_tile == GameEnums.MacroTerrainTile.PLAINS_GRASS:
			var source := catalog.resolve_terrain_id(
				hex.terrain_tile,
				hex.visual_variant_hash,
				hex.biome_pack
			)
			if source < 0 or not plains_ids.has(source):
				_fail("Plains hex resolved outside green_hex pool at %s." % str(coords))
				return false
			if source == 0 and not plains_ids.has(0):
				_fail("Plains hex fell back to legacy source 0 at %s." % str(coords))
				return false
		if hex.is_poi or not hex.landmark_id.is_empty():
			poi_count += 1

	if poi_count < 1:
		_fail("Zone has no POIs/landmarks.")
		return false

	var player_coords := macro_map.player_token.current_hex_coords
	if viz.get_fog_state(player_coords) != HexMapVisualizer.FogState.VISIBLE:
		_fail("Player hex is not VISIBLE under fog.")
		return false

	var found_unknown := false
	for coords in viz.rendered_cells.keys():
		if viz.get_fog_state(coords) == HexMapVisualizer.FogState.UNKNOWN:
			found_unknown = true
			break
	if not found_unknown:
		_fail("Expected some UNKNOWN fog hexes outside vision.")
		return false

	if macro_map.has_method("_apply_fog_tint"):
		_fail("Legacy _apply_fog_tint still exists; transparent fog was not removed.")
		return false

	macro_map._refresh_map_visuals(player_coords, false)
	await process_frame
	if viz.get_fog_state(player_coords) != HexMapVisualizer.FogState.VISIBLE:
		_fail("Fog refresh lost VISIBLE on player hex.")
		return false

	if macro_map.player_token.z_index < 5:
		_fail("Player token z_index should sit above fog overlays.")
		return false
	if not is_equal_approx(macro_map.player_token.modulate.a, 1.0):
		_fail("Player token must stay fully opaque.")
		return false

	# HUD chrome: emergency default must be black-alpha, not crimson.
	var panel_style := HUDAssetLibrary.panel_style("critical") as StyleBoxFlat
	if panel_style != null:
		if panel_style.bg_color.r > 0.08 or panel_style.bg_color.g > 0.08 or panel_style.bg_color.b > 0.08:
			_fail("Critical macro panel fill must be near-black.")
			return false

	return true


func _spawn_game() -> Node:
	var main_scene := load("res://SystemCore/game_director.tscn") as PackedScene
	if main_scene == null:
		_fail("Could not load game director scene.")
		return null
	var game_director := main_scene.instantiate()
	root.add_child(game_director)
	await process_frame
	await process_frame
	return game_director


func _fail(message: String) -> void:
	push_error("[TEST FAIL] %s" % message)
	quit(1)
