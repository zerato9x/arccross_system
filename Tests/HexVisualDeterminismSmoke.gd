extends SceneTree

const SAMPLE_COORDS := [
	Vector2i(0, 0),
	Vector2i(12, -4),
	Vector2i(-8, 15),
	Vector2i(33, 21),
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _verify_tileset_geometry_and_catalog():
		return

	var world_state := RuntimeStateStore.new()
	world_state.name = "WorldState"
	root.add_child(world_state)

	var generator := HexWorldGenerator.new()
	generator.master_seed = "DETERMINISM_SMOKE"
	generator.configure_seed(generator.master_seed)
	root.add_child(generator)
	await process_frame
	if not _verify_macro_regions(generator):
		return

	for coords in SAMPLE_COORDS:
		var first := generator.get_hex_at(coords)
		var second := generator.get_hex_at(coords)
		if first.visual_variant_hash != second.visual_variant_hash:
			_fail(
				"visual_variant_hash changed for "
				+ str(coords)
				+ " on repeated get_hex_at calls."
			)
			return
		if first.biome != second.biome:
			_fail("Biome changed for " + str(coords) + " on repeated calls.")
			return
		if first.terrain_tile != second.terrain_tile:
			_fail("Terrain tile changed for " + str(coords) + " on repeated calls.")
			return
		if first.flora_layer != second.flora_layer:
			_fail("Flora layer changed for " + str(coords) + " on repeated calls.")
			return
		if first.rock_layer != second.rock_layer:
			_fail("Rock layer changed for " + str(coords) + " on repeated calls.")
			return
		if first.structure_layer != second.structure_layer:
			_fail("Structure layer changed for " + str(coords) + " on repeated calls.")
			return
		if first.visual_variant_hash == 0:
			_fail("visual_variant_hash was not assigned for " + str(coords) + ".")
			return

	generator.world_hex_cache.clear()
	generator.configure_seed("DETERMINISM_SMOKE")
	for coords in SAMPLE_COORDS:
		var expected_hash := HexWorldGenerator.compute_visual_variant_hash(
			coords,
			"DETERMINISM_SMOKE"
		)
		var regenerated := generator.get_hex_at(coords)
		if regenerated.visual_variant_hash != expected_hash:
			_fail(
				"visual_variant_hash drifted after cache clear for "
				+ str(coords)
				+ "."
			)
			return

	var found_forest := false
	var found_mud := false
	var found_impassable_core := false
	var found_wedge_landmark := false
	for q in range(-32, 33):
		for r in range(-32, 33):
			var coords := Vector2i(q, r)
			if maxi(abs(q), maxi(abs(r), abs(q + r))) > 32:
				continue
			var hex := generator.get_hex_at(coords)
			found_forest = found_forest or (
				hex.terrain_tile == GameEnums.MacroTerrainTile.FOREST_SPARSE
				and hex.flora_layer == GameEnums.MacroFloraLayer.TREES
			)
			found_mud = found_mud or (
				hex.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW
			)
			found_impassable_core = found_impassable_core or (
				hex.zone_id == "hub_core"
				and hex.impassable
				and not hex.is_passable()
			)
			found_wedge_landmark = found_wedge_landmark or (
				hex.zone_id.begins_with("wedge_")
				and hex.has_landmark()
			)
	if not found_forest:
		_fail("No forest tile with tree flora was generated in the sample radius.")
		return
	if not found_mud:
		_fail("No mud tile was generated in the sample radius.")
		return
	if not found_impassable_core:
		_fail("No impassable central-core hex was generated in the sample radius.")
		return
	if not found_wedge_landmark:
		_fail("No wedge landmark POI was generated in the sample radius.")
		return

	print(
		"[TEST PASS] Hex visual variant generation, TileSet geometry, and macro wedge layout are deterministic."
	)
	quit(0)

func _verify_macro_regions(generator: HexWorldGenerator) -> bool:
	var hub := generator.get_hex_at(Vector2i.ZERO)
	if (
		hub.region != GameEnums.MacroRegion.CENTRAL_HUB
		or not hub.is_poi
		or hub.poi_id != "alpha_central_hub"
		or hub.hazard_level != 0.0
		or hub.impassable
	):
		return _fail("The alpha central hub was not generated as the enterable service POI.")

	var core_neighbor := generator.get_hex_at(Vector2i(1, 0))
	if not core_neighbor.impassable or core_neighbor.is_poi:
		return _fail("Hub core neighbors were not impassable non-POI city hexes.")

	var border := generator.get_hex_at(Vector2i(3, 0))
	if border.region != GameEnums.MacroRegion.HUB_BORDER or border.is_poi:
		return _fail("The hub border was not a non-POI travel ring.")

	var wedge := generator.get_hex_at(Vector2i(12, 0))
	if not wedge.zone_id.begins_with("wedge_"):
		return _fail("Far east hex did not resolve to a compass wedge zone.")

	var shrub_count := 0
	for q in range(-20, 21):
		for r in range(-20, 21):
			var coords := Vector2i(q, r)
			if maxi(abs(q), maxi(abs(r), abs(q + r))) > 20:
				continue
			var hex := generator.get_hex_at(coords)
			if hex.flora_layer == GameEnums.MacroFloraLayer.SHRUBS:
				shrub_count += 1
	if shrub_count == 0:
		return _fail("Deterministic plains generation produced no sparse shrub decorations.")
	return true

func _verify_tileset_geometry_and_catalog() -> bool:
	var tile_set := load("res://Asset/MacroTileSet.tres") as TileSet
	if tile_set == null:
		return _fail("MacroTileSet could not be loaded.")
	if tile_set.tile_shape != TileSet.TILE_SHAPE_HEXAGON:
		return _fail("MacroTileSet is not configured as a hex TileSet.")
	if tile_set.tile_layout != TileSet.TILE_LAYOUT_STAIRS_RIGHT:
		return _fail("MacroTileSet layout does not match the isometric hex art.")
	if tile_set.tile_offset_axis != TileSet.TILE_OFFSET_AXIS_HORIZONTAL:
		return _fail("MacroTileSet offset axis does not match the isometric hex art.")
	if tile_set.tile_size != Vector2i(512, 512):
		return _fail("MacroTileSet tile size drifted away from the 512px assets.")

	var layer := TileMapLayer.new()
	layer.tile_set = tile_set
	root.add_child(layer)
	var origin := layer.map_to_local(Vector2i.ZERO)
	var east_delta := layer.map_to_local(Vector2i(1, 0)) - origin
	var northeast_delta := layer.map_to_local(Vector2i(1, -1)) - origin
	var southeast_delta := layer.map_to_local(Vector2i(0, 1)) - origin
	layer.queue_free()
	if not east_delta.is_equal_approx(Vector2(512.0, 0.0)):
		return _fail("Hex east neighbor spacing does not match the art footprint.")
	if not northeast_delta.is_equal_approx(Vector2(256.0, -384.0)):
		return _fail("Hex northeast neighbor spacing does not match the art footprint.")
	if not southeast_delta.is_equal_approx(Vector2(256.0, 384.0)):
		return _fail("Hex southeast neighbor spacing does not match the art footprint.")

	var catalog := load("res://Asset/MacroTileCatalog.tres") as MacroTileCatalog
	if catalog == null:
		return _fail("MacroTileCatalog could not be loaded.")
	if catalog.tile_size != Vector2i(512, 512):
		return _fail("MacroTileCatalog tile size drifted away from the TileSet.")
	if not _expect_min_count(catalog.get_terrain_ids(GameEnums.MacroTerrainTile.PLAINS_GRASS), 5, "plains terrain"):
		return false
	if not _expect_min_count(catalog.get_terrain_ids(GameEnums.MacroTerrainTile.FOREST_SPARSE), 1, "forest terrain"):
		return false
	if catalog.get_terrain_ids(GameEnums.MacroTerrainTile.MUD_YELLOW).size() > 0:
		if not _expect_min_count(catalog.get_terrain_ids(GameEnums.MacroTerrainTile.MUD_YELLOW), 1, "mud terrain"):
			return false
	if catalog.get_terrain_ids(GameEnums.MacroTerrainTile.SNOW_TRANSITION).size() > 0:
		if not _expect_min_count(catalog.get_terrain_ids(GameEnums.MacroTerrainTile.SNOW_TRANSITION), 1, "snow transition terrain"):
			return false
	if not _expect_min_count(catalog.get_flora_ids(GameEnums.MacroFloraLayer.SHRUBS), 7, "shrub flora"):
		return false
	if not _expect_min_count(
		catalog.get_terrain_ids(GameEnums.MacroTerrainTile.HUB_CONCRETE),
		1,
		"hub concrete terrain"
	):
		return false
	if not _expect_min_count(catalog.get_flora_ids(GameEnums.MacroFloraLayer.TREES), 6, "tree flora"):
		return false
	return true

func _expect_min_count(ids: PackedInt32Array, minimum: int, label: String) -> bool:
	if ids.size() < minimum:
		return _fail(
			"Expected at least %d %s source IDs, found %d."
			% [minimum, label, ids.size()]
		)
	return true

func _expect_count(ids: PackedInt32Array, expected: int, label: String) -> bool:
	if ids.size() != expected:
		return _fail(
			"Expected %d %s source IDs, found %d."
			% [expected, label, ids.size()]
		)
	return true

func _fail(message: String) -> bool:
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
