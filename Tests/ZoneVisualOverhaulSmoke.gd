extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _verify_time_rules():
		return
	if not _verify_plains_catalog():
		return
	if not _verify_authored_plains_template():
		return
	if not _verify_zone_density_offline():
		return
	if not await _verify_zone_and_fog():
		return
	print("[TEST PASS] Zone visuals: authored radius-12 template, layers, sockets, and fog.")
	quit(0)


func _verify_time_rules() -> bool:
	if GameTimeRules.MOVE_MINUTES != GameTimeRules.ACTION_MINUTES:
		_fail(
			"MOVE_MINUTES must equal ACTION_MINUTES (%d), got %d."
			% [GameTimeRules.ACTION_MINUTES, GameTimeRules.MOVE_MINUTES]
		)
		return false
	if GameTimeRules.ACTION_MINUTES != 15:
		_fail("ACTION_MINUTES must be 15 for four beats per hour.")
		return false
	if GameTimeRules.HEX_CENTER_DISTANCE_KM < 0.4 or GameTimeRules.HEX_CENTER_DISTANCE_KM > 0.5:
		_fail("HEX_CENTER_DISTANCE_KM must sit near 0.45 km district pitch.")
		return false
	if GameTimeRules.HEX_AREA_KM2 <= 0.0 or GameTimeRules.ZONE_AREA_KM2 < 70.0:
		_fail("Zone/hex area constants missing or invalid for retuned scale.")
		return false
	var plains := MacroHexData.new()
	plains.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	var hills := MacroHexData.new()
	hills.rock_layer = GameEnums.MacroRockLayer.HILLS
	var mud := MacroHexData.new()
	mud.terrain_tile = GameEnums.MacroTerrainTile.MUD_YELLOW
	var river := MacroHexData.new()
	river.water_layer = GameEnums.MacroWaterLayer.SHALLOW_RIVER
	if not is_equal_approx(plains.travel_exertion(), 1.0):
		_fail("Plains exertion should be 1.0.")
		return false
	if hills.travel_exertion() <= plains.travel_exertion():
		_fail("Hills exertion must exceed plains.")
		return false
	if mud.travel_time_multiplier() <= plains.travel_time_multiplier():
		_fail("Mud travel time must exceed plains.")
		return false
	if (
		not river.is_passable()
		or river.travel_time_multiplier() <= plains.travel_time_multiplier()
	):
		_fail("Shallow river must be fordable but slower than plains.")
		return false
	if GameTimeRules.move_minutes_for_hex(plains) != 15:
		_fail("Plains move minutes should be 15.")
		return false
	if GameTimeRules.move_minutes_for_hex(hills) != 30:
		_fail("Hills move minutes should be 30.")
		return false
	if not _verify_lighting_phases():
		return false
	return true


func _verify_lighting_phases() -> bool:
	if GameTimeRules.phase_for_hour(3) != "night":
		_fail("Hour 3 must be night.")
		return false
	if GameTimeRules.phase_for_hour(6) != "dawn":
		_fail("Hour 6 must be dawn.")
		return false
	if GameTimeRules.phase_for_hour(12) != "midday":
		_fail("Hour 12 must be midday.")
		return false
	if GameTimeRules.phase_for_hour(18) != "dusk":
		_fail("Hour 18 must be dusk.")
		return false
	if GameTimeRules.phase_for_hour(22) != "night":
		_fail("Hour 22 must be night.")
		return false
	if not GameTimeRules.is_night_hour(22):
		_fail("is_night_hour(22) should be true.")
		return false
	if GameTimeRules.is_night_hour(12):
		_fail("is_night_hour(12) should be false.")
		return false
	var night: Dictionary = GameTimeRules.lighting_for_phase("night")
	var midday: Dictionary = GameTimeRules.lighting_for_phase("midday")
	if float(night.get("strength", 0.0)) <= float(midday.get("strength", 1.0)):
		_fail("Night lighting strength must exceed midday.")
		return false
	if float(night.get("vision_strength", 0.0)) <= float(midday.get("vision_strength", 1.0)):
		_fail("Night vision_strength must exceed midday.")
		return false
	var night_color: Color = night.get("vignette_color", Color.BLACK)
	var midday_color: Color = midday.get("vignette_color", Color.WHITE)
	if night_color.b <= midday_color.b:
		_fail("Night vignette should be cooler (higher blue) than midday.")
		return false
	var overlay := VisionVignetteOverlay.new()
	overlay.apply_lighting_phase("night")
	if overlay.get_lighting_phase() != "night":
		_fail("VisionVignetteOverlay did not retain night phase.")
		overlay.free()
		return false
	if overlay.strength <= float(midday.get("strength", 1.0)):
		_fail("VisionVignetteOverlay night strength not applied.")
		overlay.free()
		return false
	overlay.apply_lighting_phase("midday")
	if overlay.get_lighting_phase() != "midday":
		_fail("VisionVignetteOverlay did not switch to midday.")
		overlay.free()
		return false
	overlay.free()
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
	if zone.hex_count() != GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail("Expected 469 axial cells, got %d." % zone.hex_count())
		return false
	if zone.start_coords != HexCoordUtils.rim_anchor(
		GameEnums.MacroTravelDirection.SOUTH,
		GameEnums.MACRO_ZONE_RADIUS
	):
		_fail(
			"Start is not on the south rim: %s"
			% str(zone.start_coords)
		)
		return false
	if HexCoordUtils.cells_in_ring(GameEnums.MACRO_ZONE_RADIUS).size() != 72:
		_fail("Radius-12 rim must contain 72 cells.")
		return false

	var landmark_count := 0
	var shrub_count := 0
	var structure_count := 0
	var clustered_hex_count := 0
	var multi_prop_cluster_count := 0
	for coords in zone.world_hex_cache.keys():
		if not zone.is_in_bounds(coords):
			_fail("Generated out-of-bounds cell %s." % str(coords))
			return false
		var hex: MacroHexData = zone.world_hex_cache[coords]
		if hex.is_poi or not hex.landmark_id.is_empty():
			landmark_count += 1
		if hex.flora_layer == GameEnums.MacroFloraLayer.SHRUBS:
			shrub_count += 1
		if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
			structure_count += 1
		var props: Array = zone.get_decorations_at(coords)
		if not props.is_empty():
			clustered_hex_count += 1
			if props.size() >= 3:
				multi_prop_cluster_count += 1

	if landmark_count < zone.guaranteed_landmark_count:
		_fail(
			"Landmark floor unmet: got %d, need >= %d."
			% [landmark_count, zone.guaranteed_landmark_count]
		)
		return false
	if shrub_count < 60:
		_fail("Shrub density too sparse: %d." % shrub_count)
		return false
	if structure_count < 20:
		_fail("Structure/remnant density too sparse: %d." % structure_count)
		return false
	if landmark_count < 12:
		_fail("Expected at least 12 separated POIs, got %d." % landmark_count)
		return false
	if clustered_hex_count < 50 or multi_prop_cluster_count < 35:
		_fail(
			"Cluster density too sparse: occupied=%d multi=%d."
			% [clustered_hex_count, multi_prop_cluster_count]
		)
		return false
	for props in zone.zone_decorations.values():
		for prop in props:
			if not prop is Dictionary:
				continue
			if not is_zero_approx(float(prop.get("rotation", 99.0))):
				_fail("Procedural decoration rotation must remain zero.")
				return false
			if not prop.get("target_box", Vector2.ZERO) is Vector2:
				_fail("Decoration is missing normalized target_box sizing.")
				return false
	return true


func _verify_authored_plains_template() -> bool:
	var packed := load("res://WorldCore/plains_zone_template.tscn") as PackedScene
	if packed == null:
		_fail("Authored plains template scene is missing.")
		return false
	var template := packed.instantiate()
	var terrain := template.get_node_or_null("TerrainLayer") as TileMapLayer
	var water := template.get_node_or_null("WaterLayer") as TileMapLayer
	var baker := template.get_node_or_null("AuthoredWorldMapBaker") as AuthoredWorldMapBaker
	if terrain == null or water == null or baker == null:
		_fail("Template is missing a required paint layer or baker.")
		template.queue_free()
		return false
	var cells := terrain.get_used_cells()
	if cells.size() != GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail("Template terrain must contain 469 cells, got %d." % cells.size())
		template.queue_free()
		return false
	for coords in cells:
		if not HexCoordUtils.is_in_radius(coords, GameEnums.MACRO_ZONE_RADIUS):
			_fail("Template contains terrain outside radius 12: %s." % str(coords))
			template.queue_free()
			return false
	if water.get_used_cells().size() < 3:
		_fail("Template should demonstrate a short authored water segment.")
		template.queue_free()
		return false

	var baked := baker.bake_to_resource(false) as AuthoredWorldMap
	if baked == null or baked.entries.size() != GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail("Template baker did not produce the full radius-12 map.")
		template.queue_free()
		return false
	var arrivals := baked.get_sockets(HexMapSocket.SocketKind.ARRIVAL)
	var exits := baked.get_sockets(HexMapSocket.SocketKind.EXIT)
	if arrivals.size() != 8 or exits.size() != 8:
		_fail("Template must expose eight arrivals and eight exits.")
		template.queue_free()
		return false
	for socket in arrivals + exits:
		var coords: Vector2i = socket.get("coords", Vector2i.ZERO)
		var direction := int(socket.get("direction", GameEnums.MacroTravelDirection.NONE))
		if coords != HexCoordUtils.rim_anchor(direction, GameEnums.MACRO_ZONE_RADIUS):
			_fail("Directional socket is not on its rim anchor: %s." % str(socket))
			template.queue_free()
			return false
	if baked.get_sockets(HexMapSocket.SocketKind.POI).is_empty():
		_fail("Template has no variable POI socket example.")
		template.queue_free()
		return false
	if baked.decorations.size() < 3:
		_fail("Template should demonstrate a small manual decoration cluster.")
		template.queue_free()
		return false
	template.queue_free()
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
	if viz.water_layer == null:
		_fail("Macro world has no dedicated water TileMap layer.")
		return false
	if viz.rendered_cells.size() != GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail(
			"Expected full radius-12 render, got %d cells."
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
	if in_bounds_count != GameEnums.MACRO_ZONE_CELL_COUNT:
		_fail("Expected 469 in-bounds zone cells, got %d." % in_bounds_count)
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
	var fog_exact := viz._hex_exact_polygon()
	if fog_exact.size() != 6:
		_fail("Exact fog polygon must be a hex (6 verts).")
		return false
	var exact_aabb := Rect2(fog_exact[0], Vector2.ZERO)
	for point in fog_exact:
		exact_aabb = exact_aabb.expand(point)
	if absf(exact_aabb.size.x - tile_size.x) > 0.5 or absf(exact_aabb.size.y - tile_size.y) > 0.5:
		_fail(
			"Exact fog AABB %s must match tile footprint %s."
			% [str(exact_aabb.size), str(tile_size)]
		)
		return false
	if fog_aabb.size.x + 0.01 < tile_size.x or fog_aabb.size.y + 0.01 < tile_size.y:
		_fail(
			"Unknown fog AABB %s smaller than tile footprint %s."
			% [str(fog_aabb.size), str(tile_size)]
		)
		return false
	if fog_aabb.size.x <= exact_aabb.size.x or fog_aabb.size.y <= exact_aabb.size.y:
		_fail("Unknown fog oversize must be larger than exact explored fog.")
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
