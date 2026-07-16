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
	catalog.pack_layer_ids = {
		GameEnums.BIOME_PACK_PLAINS: {},
		GameEnums.BIOME_PACK_CENTRALCORE: {},
	}
	catalog.path_to_source_id = {}

	var source_id := 0
	for image_path in image_paths:
		var texture := load(image_path) as Texture2D
		if texture == null:
			continue
		if not _is_valid_tile_texture(texture, image_path):
			push_warning(
				"[Build-HexTileSet] Skipping non-tile image: " + image_path
			)
			continue

		var atlas := TileSetAtlasSource.new()
		atlas.texture = texture
		atlas.texture_region_size = texture.get_size()
		atlas.create_tile(Vector2i.ZERO)
		tile_set.add_source(atlas, source_id)

		_categorize_tile(image_path, source_id, catalog)
		catalog.path_to_source_id[image_path] = source_id
		source_id += 1

	ResourceSaver.save(tile_set, TILESET_OUTPUT)
	ResourceSaver.save(catalog, CATALOG_OUTPUT)
	return {"ok": true, "source_count": source_id}

static func _biome_pack_from_path(path: String) -> String:
	var lowered := path.to_lower()
	if "biome_centralcore" in lowered:
		return GameEnums.BIOME_PACK_CENTRALCORE
	return GameEnums.BIOME_PACK_PLAINS

static func _categorize_tile(path: String, source_id: int, catalog: MacroTileCatalog) -> void:
	var lowered := path.to_lower()
	var biome_pack := _biome_pack_from_path(path)
	
	if "water_default" in lowered:
		return
	if lowered.ends_with("/bg_plains.png"):
		return
	if lowered.ends_with("/mud.png"):
		_add_to_catalog_array(
			catalog.terrain_source_ids,
			GameEnums.MacroTerrainTile.MUD_YELLOW,
			source_id
		)
		_add_to_pack(
			catalog,
			biome_pack,
			"terrain",
			GameEnums.MacroTerrainTile.MUD_YELLOW,
			source_id
		)
		return

	if "concrete_tiles" in lowered:
		_add_to_catalog_array(
			catalog.terrain_source_ids,
			GameEnums.MacroTerrainTile.HUB_CONCRETE,
			source_id
		)
		_add_to_pack(
			catalog,
			biome_pack,
			"terrain",
			GameEnums.MacroTerrainTile.HUB_CONCRETE,
			source_id
		)
		return

	if "grass_tiles" in lowered:
		if "v2 red" in lowered or "redmist" in lowered:
			_add_to_catalog_array(catalog.biome_source_ids, GameEnums.GridBiome.SWAMP, source_id)
		elif "yellow" in lowered or "t crossroad" in lowered:
			pass
		elif "snowy" in lowered:
			_add_to_catalog_array(catalog.terrain_source_ids, GameEnums.MacroTerrainTile.SNOW_TRANSITION, source_id)
			_add_to_pack(catalog, biome_pack, "terrain", GameEnums.MacroTerrainTile.SNOW_TRANSITION, source_id)
		elif "sparse green" in lowered:
			# Forest sparse floor only — never mixed into PLAINS_GRASS.
			_add_to_catalog_array(catalog.terrain_source_ids, GameEnums.MacroTerrainTile.FOREST_SPARSE, source_id)
			_add_to_pack(catalog, biome_pack, "terrain", GameEnums.MacroTerrainTile.FOREST_SPARSE, source_id)
		elif "green_hex" in lowered or "painted - green" in lowered:
			# Single coherent plains family for node zones.
			_add_to_catalog_array(catalog.terrain_source_ids, GameEnums.MacroTerrainTile.PLAINS_GRASS, source_id)
			_add_to_pack(catalog, biome_pack, "terrain", GameEnums.MacroTerrainTile.PLAINS_GRASS, source_id)
		else:
			# Old Riverbed and other grass families stay out of procedural plains.
			pass
	elif "trees" in lowered or "temperate trees" in lowered:
		if "temperate trees v2" in lowered or "trees 2x2" in lowered:
			_add_to_catalog_array(catalog.flora_source_ids, GameEnums.MacroFloraLayer.TREES, source_id)
			_add_to_pack(catalog, biome_pack, "flora", GameEnums.MacroFloraLayer.TREES, source_id)
	elif "shrub" in lowered:
		if "shrub a" in lowered:
			return
		_add_to_catalog_array(catalog.flora_source_ids, GameEnums.MacroFloraLayer.SHRUBS, source_id)
		_add_to_pack(catalog, biome_pack, "flora", GameEnums.MacroFloraLayer.SHRUBS, source_id)
	elif "rocks" in lowered or "/rock" in lowered:
		if "rocky hill" in lowered:
			_add_to_catalog_array(catalog.rock_source_ids, GameEnums.MacroRockLayer.HILLS, source_id)
			_add_to_pack(catalog, biome_pack, "rock", GameEnums.MacroRockLayer.HILLS, source_id)
		else:
			_add_to_catalog_array(catalog.rock_source_ids, GameEnums.MacroRockLayer.ROCKS, source_id)
			_add_to_pack(catalog, biome_pack, "rock", GameEnums.MacroRockLayer.ROCKS, source_id)
	elif "remnants" in lowered or "crater" in lowered:
		_add_to_catalog_array(catalog.structure_source_ids, GameEnums.MacroStructureLayer.REMNANTS, source_id)
		_add_to_catalog_array(catalog.poi_source_ids, "remnants", source_id)
		_add_to_pack(catalog, biome_pack, "structure", GameEnums.MacroStructureLayer.REMNANTS, source_id)
		_add_to_pack(catalog, biome_pack, "poi", "remnants", source_id)
	elif "structures" in lowered or "warehouse" in lowered or "prefab building" in lowered or "homestead" in lowered or "silo" in lowered or "lumber building" in lowered:
		_add_to_catalog_array(catalog.structure_source_ids, GameEnums.MacroStructureLayer.STRUCTURES, source_id)
		_add_to_catalog_array(catalog.poi_source_ids, "structures", source_id)
		_add_to_pack(catalog, biome_pack, "structure", GameEnums.MacroStructureLayer.STRUCTURES, source_id)
		_add_to_pack(catalog, biome_pack, "poi", "structures", source_id)
	elif "infrastructure" in lowered or "colony infrastructure" in lowered:
		# Decorative props only: available in TileSet for hand-painting,
		# but not rolled into procedural enum pools.
		return
	elif "bg_plains" in lowered:
		return

static func _add_to_pack(
	catalog: MacroTileCatalog,
	biome_pack: String,
	layer_kind: String,
	layer_key,
	source_id: int
) -> void:
	if not catalog.pack_layer_ids.has(biome_pack):
		catalog.pack_layer_ids[biome_pack] = {}
	var pack_dict: Dictionary = catalog.pack_layer_ids[biome_pack]
	if not pack_dict.has(layer_kind):
		pack_dict[layer_kind] = {}
	var layer_dict: Dictionary = pack_dict[layer_kind]
	_add_to_catalog_array(layer_dict, layer_key, source_id)
	pack_dict[layer_kind] = layer_dict
	catalog.pack_layer_ids[biome_pack] = pack_dict

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
				if _should_collect_tile_path(full_path):
					paths.append(full_path)
			entry_name = dir.get_next()
		dir.list_dir_end()
	paths.sort()
	return paths

static func _should_collect_tile_path(path: String) -> bool:
	var lowered := path.to_lower()
	if lowered.ends_with("/bg_plains.png"):
		return false
	# mud.png is a ground terrain source for MUD_YELLOW.
	return true

static func _is_valid_tile_texture(texture: Texture2D, image_path: String) -> bool:
	var lowered := image_path.to_lower()
	if "grass_tiles" in lowered or "concrete_tiles" in lowered:
		var size := texture.get_size()
		return int(size.x) == DEFAULT_TILE_SIZE.x and int(size.y) == DEFAULT_TILE_SIZE.y
	return true
