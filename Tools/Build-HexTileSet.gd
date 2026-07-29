extends SceneTree

## Headless or editor-run builder for the macro hex TileSet and biome catalog.
## Run: godot --headless --script res://Tools/Build-HexTileSet.gd

const HEX_TILES_ROOT := "res://Asset/HexTiles/_BIOMES"
const TILESET_OUTPUT := "res://Asset/MacroTileSet.tres"
const CATALOG_OUTPUT := "res://Asset/MacroTileCatalog.tres"
const DEFAULT_TILE_SIZE := Vector2i(512, 512)
const _Manifest := preload("res://WorldCore/GenerationV2/WorldAssetManifest.gd")

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
		GameEnums.BIOME_PACK_NORTH: {},
		GameEnums.BIOME_PACK_DEFAULT_ERA8: {},
	}
	catalog.path_to_source_id = {}
	catalog.road_mask_source_ids = {}
	catalog.dirt_road_mask_source_ids = {}
	catalog.source_id_to_path = {}
	catalog.edge_signatures = {}
	catalog.asset_id_to_source_id = {}

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
		_register_stable_asset_id(image_path, source_id, catalog)
		catalog.path_to_source_id[image_path] = source_id
		catalog.source_id_to_path[source_id] = image_path
		catalog.edge_signatures[source_id] = _sample_edge_signatures(texture)
		source_id += 1

	ResourceSaver.save(tile_set, TILESET_OUTPUT)
	ResourceSaver.save(catalog, CATALOG_OUTPUT)
	return {"ok": true, "source_count": source_id}


static func _register_stable_asset_id(path: String, source_id: int, catalog: MacroTileCatalog) -> void:
	var lowered := path.to_lower()
	if "/_overlays/roads/dirt/dirt_road_mask_" in lowered:
		var mask_text := path.get_file().get_basename().trim_prefix("dirt_road_mask_")
		catalog.asset_id_to_source_id["overlay.road.dirt.%02d" % int(mask_text)] = source_id
	elif "/_overlays/roads/road_mask_" in lowered:
		var mask_text := path.get_file().get_basename().trim_prefix("road_mask_")
		catalog.asset_id_to_source_id["overlay.road.paved.%02d" % int(mask_text)] = source_id
		catalog.asset_id_to_source_id["overlay.road.%02d" % int(mask_text)] = source_id
	elif "green_hex" in lowered:
		var basename := path.get_file().get_basename()
		var variant := basename.get_slice("_", basename.get_slice_count("_") - 1)
		catalog.asset_id_to_source_id["terrain.plains.green.%s" % variant] = source_id
		if not catalog.asset_id_to_source_id.has("terrain.plains.green.base"):
			catalog.asset_id_to_source_id["terrain.plains.green.base"] = source_id

static func _biome_pack_from_path(path: String) -> String:
	var lowered := path.to_lower()
	if "biome_centralcore" in lowered:
		return GameEnums.BIOME_PACK_CENTRALCORE
	if "biome_north" in lowered or "/snow_tiles/" in lowered:
		return GameEnums.BIOME_PACK_NORTH
	if "default_era8" in lowered:
		return GameEnums.BIOME_PACK_DEFAULT_ERA8
	return GameEnums.BIOME_PACK_PLAINS

static func _categorize_tile(path: String, source_id: int, catalog: MacroTileCatalog) -> void:
	var lowered := path.to_lower()
	var biome_pack := _biome_pack_from_path(path)

	if "/_overlays/roads/dirt/dirt_road_mask_" in lowered:
		var mask_text := path.get_file().get_basename().trim_prefix("dirt_road_mask_")
		if mask_text.is_valid_int():
			catalog.dirt_road_mask_source_ids[int(mask_text)] = source_id
		return
	if "/_overlays/roads/road_mask_" in lowered:
		var mask_text := path.get_file().get_basename().trim_prefix("road_mask_")
		if mask_text.is_valid_int():
			catalog.road_mask_source_ids[int(mask_text)] = source_id
		return
	
	if "water_default" in lowered:
		return
	if lowered.ends_with("/bg_plains.png") or lowered.ends_with("/bg_north.png"):
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

	if "snow_tiles" in lowered or "hex_snowy" in lowered or "ice field_hex" in lowered:
		_add_to_catalog_array(
			catalog.terrain_source_ids,
			GameEnums.MacroTerrainTile.SNOW_TRANSITION,
			source_id
		)
		_add_to_pack(
			catalog,
			biome_pack,
			"terrain",
			GameEnums.MacroTerrainTile.SNOW_TRANSITION,
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
		elif "old riverbed" in lowered:
			_add_to_catalog_array(catalog.terrain_source_ids, GameEnums.MacroTerrainTile.MUD_YELLOW, source_id)
			_add_to_pack(catalog, biome_pack, "terrain", GameEnums.MacroTerrainTile.MUD_YELLOW, source_id)
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
	var pending: Array[String] = []
	for root in _Manifest.approved_hex_roots():
		if DirAccess.dir_exists_absolute(root):
			pending.append(root)
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
	if not _Manifest.is_runtime_hex_path(path) or _Manifest.is_explicitly_excluded(path):
		return false
	if "/_overlays/roads/" in lowered and "road_mask_" in lowered:
		return true
	if "concrete_tiles" in lowered or "snow_tiles" in lowered:
		return true
	if "grass_tiles" in lowered:
		return (
			"green_hex" in lowered
			or "painted - green" in lowered
			or "sparse green" in lowered
			or "old riverbed" in lowered
		)
	return false

static func _is_valid_tile_texture(texture: Texture2D, image_path: String) -> bool:
	var size := texture.get_size()
	return (
		_Manifest.is_runtime_hex_path(image_path)
		and not _Manifest.is_explicitly_excluded(image_path)
		and int(size.x) == DEFAULT_TILE_SIZE.x
		and int(size.y) == DEFAULT_TILE_SIZE.y
	)


static func _sample_edge_signatures(texture: Texture2D) -> PackedInt32Array:
	var image := texture.get_image()
	var signatures := PackedInt32Array()
	if image == null or image.is_empty():
		return signatures
	var vertices := [
		Vector2(256, 0), Vector2(511, 128), Vector2(511, 383),
		Vector2(256, 511), Vector2(0, 383), Vector2(0, 128),
	]
	var center := Vector2(256, 256)
	for edge_index in range(6):
		var a: Vector2 = vertices[edge_index]
		var b: Vector2 = vertices[(edge_index + 1) % 6]
		var red := 0.0
		var green := 0.0
		var blue := 0.0
		var samples := 0
		for sample_index in range(4, 17):
			var t := float(sample_index) / 20.0
			var edge_point := a.lerp(b, t)
			var point := edge_point.lerp(center, 0.055)
			var color := image.get_pixel(
				clampi(roundi(point.x), 0, image.get_width() - 1),
				clampi(roundi(point.y), 0, image.get_height() - 1)
			)
			if color.a < 0.25:
				continue
			red += color.r
			green += color.g
			blue += color.b
			samples += 1
		if samples == 0:
			signatures.append(0)
		else:
			var r := clampi(roundi(red / float(samples) * 255.0), 0, 255)
			var g := clampi(roundi(green / float(samples) * 255.0), 0, 255)
			var bl := clampi(roundi(blue / float(samples) * 255.0), 0, 255)
			signatures.append((r << 16) | (g << 8) | bl)
	return signatures
