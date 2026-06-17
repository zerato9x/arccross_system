extends SceneTree

## Headless or editor-run builder for the macro hex TileSet and biome catalog.
## Run: godot --headless --script res://Tools/Build-HexTileSet.gd

const HEX_TILES_ROOT := "res://Asset/HexTiles/_BIOMES"
const TILESET_OUTPUT := "res://Asset/MacroTileSet.tres"
const CATALOG_OUTPUT := "res://Asset/MacroTileCatalog.tres"
const DEFAULT_TILE_SIZE := Vector2i(512, 512)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var result := build_macro_tile_assets()
	if result.get("ok", false):
		print("[Build-HexTileSet] Success. Wrote ", result.get("source_count", 0), " tiles.")
		quit(0)
	else:
		push_error("[Build-HexTileSet] " + str(result.get("error", "Unknown failure.")))
		quit(1)

static func build_macro_tile_assets() -> Dictionary:
	var image_paths := _collect_all_tile_paths()
	if image_paths.is_empty():
		return {"ok": false, "error": "No tiles found in " + HEX_TILES_ROOT}

	var tile_size := DEFAULT_TILE_SIZE

	var tile_set := TileSet.new()
	tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	tile_set.tile_layout = TileSet.TILE_LAYOUT_STACKED
	tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	tile_set.tile_size = tile_size

	var catalog := MacroTileCatalog.new()
	catalog.tile_size = tile_size
	
	for biome_key in GameEnums.GridBiome.values():
		catalog.biome_source_ids[biome_key] = PackedInt32Array()
		catalog.overlay_source_ids[biome_key] = PackedInt32Array()
	catalog.poi_source_ids["structures"] = PackedInt32Array()
	catalog.poi_source_ids["remnants"] = PackedInt32Array()

	var source_id := 0
	for image_path in image_paths:
		var texture := load(image_path) as Texture2D
		if texture == null:
			continue

		var atlas := TileSetAtlasSource.new()
		atlas.texture = texture
		atlas.texture_region_size = texture.get_size()
		atlas.create_tile(Vector2i.ZERO)
		tile_set.add_source(atlas, source_id)

		_categorize_tile(image_path, source_id, catalog)
		source_id += 1

	ResourceSaver.save(tile_set, TILESET_OUTPUT)
	ResourceSaver.save(catalog, CATALOG_OUTPUT)
	return {"ok": true, "source_count": source_id}

static func _categorize_tile(path: String, source_id: int, catalog: MacroTileCatalog) -> void:
	var lowered := path.to_lower()
	
	# Backgrounds
	if "grass_tiles" in lowered or "water_default" in lowered:
		# SWAMP
		if "v2 red" in lowered or "redmist" in lowered:
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.SWAMP, source_id)
		# MUD (Yellow grass)
		elif "yellow" in lowered or "t crossroad" in lowered:
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.MUD, source_id)
		# HILLS / MOUNTAIN (Snowy/high altitude)
		elif "snowy" in lowered:
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.HILLS, source_id)
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.MOUNTAIN, source_id)
		# FOREST (Sparse green grass)
		elif "sparse green" in lowered or "old riverbed" in lowered:
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.FOREST, source_id)
		# PLAINS (Dense green grass)
		else:
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.PLAINS, source_id)
			
	# Overlays
	elif "trees" in lowered:
		_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.FOREST, source_id)
	elif "rocks" in lowered:
		if "sz3" in lowered or "boulder" in lowered or "rocky hill" in lowered:
			_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.MOUNTAIN, source_id)
		else:
			_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.HILLS, source_id)
	elif "remnants" in lowered:
		# Remnants generated in PLAINS
		_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.PLAINS, source_id)
		_add_to_catalog_array(catalog.poi_source_ids, "remnants", source_id)
	elif "structures" in lowered or "infrastructure" in lowered:
		_add_to_catalog_array(catalog.poi_source_ids, "structures", source_id)

static func _add_to_catalog_array(dict: Dictionary, key, source_id: int) -> void:
	var packed: PackedInt32Array = dict.get(key, PackedInt32Array())
	packed.append(source_id)
	dict[key] = packed

static func _collect_all_tile_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	var pending: Array[String] = [HEX_TILES_ROOT]
	while not pending.is_empty():
		var current_dir: String = pending.pop_back()
		var dir := DirAccess.open(current_dir)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry_name: String = dir.get_next()
		while entry_name != "":
			if entry_name.begins_with("."):
				entry_name = dir.get_next()
				continue
			var full_path: String = current_dir.path_join(entry_name)
			if dir.current_is_dir():
				pending.append(full_path)
			elif full_path.ends_with(".png"):
				paths.append(full_path)
			entry_name = dir.get_next()
		dir.list_dir_end()
	paths.sort()
	return paths
