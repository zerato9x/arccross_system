extends SceneTree

const TILESET_PATH := "res://Asset/MacroTileSet.tres"
const CATALOG_PATH := "res://Asset/MacroTileCatalog.tres"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var tile_set := load(TILESET_PATH) as TileSet
	var catalog := load(CATALOG_PATH) as MacroTileCatalog
	if tile_set == null or catalog == null:
		return _fail("Generated TileSet/catalog is missing.")
	if catalog.tile_size != Vector2i(512, 512):
		return _fail("Catalog tile size is not 512x512.")
	if tile_set.get_source_count() != catalog.source_id_to_path.size():
		return _fail("Catalog metadata does not cover every TileSet source.")
	for index in range(tile_set.get_source_count()):
		var source_id := tile_set.get_source_id(index)
		var source := tile_set.get_source(source_id) as TileSetAtlasSource
		var path := catalog.path_for_source_id(source_id)
		if source == null or source.texture_region_size != Vector2i(512, 512):
			return _fail("Source %d is not an exact 512x512 atlas." % source_id)
		if not WorldAssetManifest.is_runtime_hex_path(path):
			return _fail("Unapproved runtime source entered the catalog: %s" % path)
		var lowered := path.to_lower()
		if lowered.ends_with("/mud.png") or "structures" in lowered or "infrastructure" in lowered or "remnants" in lowered:
			return _fail("Dressing/non-HEX source entered MacroTileSet: %s" % path)
		if catalog.edge_signature_for_source(source_id).size() != 6:
			return _fail("Source %d is missing six edge signatures." % source_id)
	for mask in range(64):
		var paved_source := catalog.resolve_road_mask_id(mask, "paved")
		var dirt_source := catalog.resolve_road_mask_id(mask, "dirt")
		if paved_source < 0 or dirt_source < 0:
			return _fail("Paved/dirt road mask %02d is missing." % mask)
		if catalog.resolve_asset_id("overlay.road.paved.%02d" % mask) != paved_source:
			return _fail("Paved road mask %02d has no stable asset ID." % mask)
		if catalog.resolve_asset_id("overlay.road.dirt.%02d" % mask) != dirt_source:
			return _fail("Dirt road mask %02d has no stable asset ID." % mask)
	var base_id := catalog.resolve_asset_id("terrain.plains.green.base")
	if base_id < 0:
		return _fail("Stable green-plains terrain ID is missing.")
	var green_ids := catalog.get_terrain_ids(GameEnums.MacroTerrainTile.PLAINS_GRASS)
	if green_ids.size() != 54:
		return _fail("Catalog must contain exactly the 54 managed grass_default HEX files.")
	for variant in MacroZoneGenerator.STARTER_TERRAIN_VARIANT_NUMBERS:
		if catalog.resolve_asset_id("terrain.plains.green.%d" % variant) < 0:
			return _fail("Missing stable plains variant ID %d." % variant)
	print("[HexAssetContractSmoke] PASSED (%d approved sources, 128 road masks)" % tile_set.get_source_count())
	quit(0)


func _fail(message: String) -> bool:
	push_error("[HexAssetContractSmoke] " + message)
	quit(1)
	return false
