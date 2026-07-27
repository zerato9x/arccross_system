extends SceneTree

## Campaign path: MacroZoneGenerator → inject into HexWorldGenerator.
## Does not assert legacy hub_core / wedge_* layout.

const MASTER_SEED := "DETERMINISM_SMOKE"
const SAMPLE_COORDS := [
	Vector2i(0, 0),
	Vector2i(5, -2),
	Vector2i(-4, 6),
	Vector2i(8, 3),
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
	generator.configure_services(world_state)
	generator.configure_seed(MASTER_SEED)
	root.add_child(generator)
	await process_frame

	if not _verify_injected_plains_zone(generator, world_state):
		return
	if not _verify_injected_north_zone(generator, world_state):
		return

	print(
		"[TEST PASS] Hex visual variant generation, TileSet geometry, and injected zone layout are deterministic."
	)
	quit(0)


func _verify_injected_plains_zone(
	generator: HexWorldGenerator,
	world_state: RuntimeStateStore
) -> bool:
	var node := MacroNodeData.new()
	node.id = "east_random_1"
	node.zone_kind = GameEnums.MacroZoneKind.BIOME_RNG
	node.biome = GameEnums.GridBiome.PLAINS
	node.persistence = GameEnums.MacroNodePersistence.SEEDED_RANDOM
	node.role = GameEnums.MacroNodeRole.RANDOM_ZONE
	node.arm_direction = GameEnums.MacroArmDirection.EAST
	node.arm_tier = 1

	if not _inject_node_zone(generator, world_state, node):
		return false

	var zone_seed := MASTER_SEED + ":zone:" + node.id
	for coords in SAMPLE_COORDS:
		if not HexCoordUtils.is_in_radius(coords, GameEnums.MACRO_ZONE_RADIUS):
			return _fail("Sample coord %s is outside zone radius." % str(coords))
		var first := generator.get_hex_at(coords)
		var second := generator.get_hex_at(coords)
		if first.visual_variant_hash != second.visual_variant_hash:
			return _fail(
				"visual_variant_hash changed for %s on repeated get_hex_at." % str(coords)
			)
		if first.biome != second.biome:
			return _fail("Biome changed for %s on repeated calls." % str(coords))
		if first.terrain_tile != second.terrain_tile:
			return _fail("Terrain tile changed for %s on repeated calls." % str(coords))
		if first.flora_layer != second.flora_layer:
			return _fail("Flora layer changed for %s on repeated calls." % str(coords))
		if first.rock_layer != second.rock_layer:
			return _fail("Rock layer changed for %s on repeated calls." % str(coords))
		if first.structure_layer != second.structure_layer:
			return _fail("Structure layer changed for %s on repeated calls." % str(coords))
		if first.visual_variant_hash == 0:
			return _fail("visual_variant_hash was not assigned for %s." % str(coords))
		if first.zone_id.begins_with("wedge_") or first.zone_id == "hub_core":
			return _fail(
				"Injected plains cell %s leaked legacy hub/wedge zone_id %s."
				% [str(coords), first.zone_id]
			)

	generator.world_hex_cache.clear()
	for coords in SAMPLE_COORDS:
		var expected_hash := HexWorldGenerator.compute_visual_variant_hash(coords, zone_seed)
		var regenerated := generator.get_hex_at(coords)
		if regenerated.visual_variant_hash != expected_hash:
			return _fail(
				"visual_variant_hash drifted after cache clear for %s." % str(coords)
			)

	var found_forest := false
	var found_mud := false
	for coords in HexCoordUtils.cells_in_radius(GameEnums.MACRO_ZONE_RADIUS):
		var hex := generator.get_hex_at(coords)
		found_forest = found_forest or (
			hex.terrain_tile == GameEnums.MacroTerrainTile.FOREST_SPARSE
			and hex.flora_layer == GameEnums.MacroFloraLayer.TREES
		)
		found_mud = found_mud or (
			hex.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW
		)
	if not found_forest:
		return _fail("No forest tile with tree flora in injected east_random_1 zone.")
	if not found_mud:
		return _fail("No mud tile in injected east_random_1 zone.")
	return true


func _verify_injected_north_zone(
	generator: HexWorldGenerator,
	world_state: RuntimeStateStore
) -> bool:
	var node := MacroNodeData.new()
	node.id = "north_random_2"
	node.zone_kind = GameEnums.MacroZoneKind.BIOME_RNG
	node.biome = GameEnums.GridBiome.PLAINS
	node.persistence = GameEnums.MacroNodePersistence.SEEDED_RANDOM
	node.role = GameEnums.MacroNodeRole.RANDOM_ZONE
	node.arm_direction = GameEnums.MacroArmDirection.NORTH
	node.arm_tier = 2

	if not _inject_node_zone(generator, world_state, node):
		return false

	var found_snow := false
	for coords in HexCoordUtils.cells_in_radius(GameEnums.MACRO_ZONE_RADIUS):
		var hex := generator.get_hex_at(coords)
		if hex.terrain_tile == GameEnums.MacroTerrainTile.SNOW_TRANSITION:
			found_snow = true
			break
		if hex.biome_pack == GameEnums.BIOME_PACK_NORTH:
			found_snow = true
			break
	if not found_snow:
		return _fail("No snow terrain/biome_pack in injected north_random_2 zone.")

	var sample := Vector2i(3, -1)
	var first := generator.get_hex_at(sample)
	var second := generator.get_hex_at(sample)
	if first.visual_variant_hash != second.visual_variant_hash or first.visual_variant_hash == 0:
		return _fail("North injected visual_variant_hash unstable for %s." % str(sample))
	return true


func _inject_node_zone(
	generator: HexWorldGenerator,
	world_state: RuntimeStateStore,
	node: MacroNodeData
) -> bool:
	world_state.hex_records.clear()

	var zone := MacroZoneGenerator.new()
	zone.configure_services(world_state)
	zone.configure_seed(MASTER_SEED)
	zone.generate_node_zone(
		node,
		GameEnums.MacroTravelDirection.SOUTH,
		[GameEnums.MacroTravelDirection.SOUTH]
	)
	if zone.hex_count() <= 0:
		return _fail("MacroZoneGenerator produced an empty zone for %s." % node.id)

	generator.configure_seed(MASTER_SEED + ":node:" + node.id)
	generator.enable_zone_bounds(MacroZoneGenerator.ZONE_RADIUS)
	generator.inject_zone_hexes(zone.world_hex_cache)
	generator.inject_zone_decorations(zone.zone_decorations)
	for coords in zone.world_hex_cache.keys():
		var hex: MacroHexData = zone.world_hex_cache[coords]
		world_state.set_hex_record(coords, hex.to_state())
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
	# Node-zone overhaul: PLAINS_GRASS is green_hex_* only (currently 3 variants).
	if not _expect_min_count(catalog.get_terrain_ids(GameEnums.MacroTerrainTile.PLAINS_GRASS), 3, "plains terrain"):
		return false
	if not _expect_min_count(catalog.get_terrain_ids(GameEnums.MacroTerrainTile.FOREST_SPARSE), 1, "forest terrain"):
		return false
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
