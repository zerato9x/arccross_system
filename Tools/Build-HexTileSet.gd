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
	tile_set.tile_layout = TileSet.TILE_LAYOUT_STAIRS_RIGHT
	tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	tile_set.tile_size = tile_size

	var catalog := MacroTileCatalog.new()
	catalog.tile_size = tile_size
	
	for terrain_key in GameEnums.MacroTerrainTile.values():
		catalog.terrain_source_ids[terrain_key] = PackedInt32Array()
	for flora_key in GameEnums.MacroFloraLayer.values():
		catalog.flora_source_ids[flora_key] = PackedInt32Array()
	for rock_key in GameEnums.MacroRockLayer.values():
		catalog.rock_source_ids[rock_key] = PackedInt32Array()
	for structure_key in GameEnums.MacroStructureLayer.values():
		catalog.structure_source_ids[structure_key] = PackedInt32Array()
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
	if "water_default" in lowered:
		# Water becomes its own impassable terrain later. Do not let it masquerade
		# as Phase 1 plains just because it happens to live under the biome folder.
		return

	if "grass_tiles" in lowered:
		# SWAMP
		if "v2 red" in lowered or "redmist" in lowered:
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.SWAMP, source_id)
		# MUD (Yellow grass)
		elif "yellow" in lowered or "t crossroad" in lowered:
			_add_to_catalog_array(catalog.terrain_source_ids, GameEnums.MacroTerrainTile.MUD_YELLOW, source_id)
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.MUD, source_id)
		# HILLS / MOUNTAIN (Snowy/high altitude)
		elif "snowy" in lowered:
			_add_to_catalog_array(catalog.terrain_source_ids, GameEnums.MacroTerrainTile.SNOW_TRANSITION, source_id)
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.HILLS, source_id)
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.MOUNTAIN, source_id)
		# FOREST (Sparse green grass)
		elif "sparse green" in lowered:
			_add_to_catalog_array(catalog.terrain_source_ids, GameEnums.MacroTerrainTile.FOREST_SPARSE, source_id)
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.FOREST, source_id)
		# PLAINS (Dense green grass)
		else:
			_add_to_catalog_array(catalog.terrain_source_ids, GameEnums.MacroTerrainTile.PLAINS_GRASS, source_id)
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.PLAINS, source_id)
			
	# Overlays
	elif "trees" in lowered:
		if not "temperate trees v2" in lowered:
			return
		_add_to_catalog_array(catalog.flora_source_ids, GameEnums.MacroFloraLayer.TREES, source_id)
		_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.FOREST, source_id)
	elif "shrub" in lowered:
		if "shrub a" in lowered:
			return
		_add_to_catalog_array(catalog.flora_source_ids, GameEnums.MacroFloraLayer.SHRUBS, source_id)
		_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.PLAINS, source_id)
	elif "rocks" in lowered:
		if "rocky hill" in lowered:
			_add_to_catalog_array(catalog.rock_source_ids, GameEnums.MacroRockLayer.HILLS, source_id)
			_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.HILLS, source_id)
		elif "sz3" in lowered or "boulder" in lowered:
			_add_to_catalog_array(catalog.rock_source_ids, GameEnums.MacroRockLayer.ROCKS, source_id)
			_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.MOUNTAIN, source_id)
		else:
			_add_to_catalog_array(catalog.rock_source_ids, GameEnums.MacroRockLayer.ROCKS, source_id)
			_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.MOUNTAIN, source_id)
	elif "remnants" in lowered:
		# Remnants generated in PLAINS
		_add_to_catalog_array(catalog.structure_source_ids, GameEnums.MacroStructureLayer.REMNANTS, source_id)
		_add_to_catalog_array(catalog.overlay_source_ids, GameEnums.GridBiome.PLAINS, source_id)
		_add_to_catalog_array(catalog.poi_source_ids, "remnants", source_id)
	elif "structures" in lowered:
		_add_to_catalog_array(catalog.structure_source_ids, GameEnums.MacroStructureLayer.STRUCTURES, source_id)
		_add_to_catalog_array(catalog.poi_source_ids, "structures", source_id)
	elif "infrastructure" in lowered:
		# Reserved for future sector/infrastructure routing, not random Phase 1 POIs.
		return

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
