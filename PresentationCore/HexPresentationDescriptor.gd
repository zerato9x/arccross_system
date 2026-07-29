extends RefCounted
class_name HexPresentationDescriptor

## Shared visual contract for the macro map, compact HERE preview, and
## expanded location board. It resolves generated source IDs back to the
## authored assets without asking HUD code to understand generator rules.


static func build(
	hex_data: MacroHexData,
	tile_catalog: MacroTileCatalog,
	decorations: Array,
	world_seed: String,
	coords: Vector2i,
	entity_descriptor: Dictionary = {},
	ground_items: Array = []
) -> Dictionary:
	var layers: Array = []
	_append_full_hex_layer(layers, "terrain", _terrain_path(hex_data, tile_catalog), 0)
	_append_full_hex_layer(layers, "road", _road_path(hex_data, tile_catalog), 10)
	_append_full_hex_layer(layers, "water", _water_path(hex_data, tile_catalog), 20)
	_append_full_hex_layer(layers, "flora", _flora_path(hex_data, tile_catalog), 30)
	_append_full_hex_layer(layers, "rock", _rock_path(hex_data, tile_catalog), 40)
	_append_full_hex_layer(layers, "structure", _structure_path(hex_data, tile_catalog), 50)
	for overlay_asset_id in hex_data.overlay_asset_ids:
		_append_full_hex_layer(
			layers,
			"overlay",
			_path_for_source(tile_catalog, tile_catalog.resolve_asset_id(str(overlay_asset_id))),
			45
		)

	var decor_layers: Array = []
	for entry in decorations:
		if not entry is Dictionary:
			continue
		var path := str(entry.get("sprite_path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			continue
		decor_layers.append({
			"kind": str(entry.get("kind", "decor")),
			"path": path,
			"offset": entry.get("offset", Vector2.ZERO),
			"scale_multiplier": float(entry.get("scale_multiplier", 1.0)),
			"rotation": float(entry.get("rotation", 0.0)),
			"flip_h": bool(entry.get("flip_h", false)),
			"layer": int(entry.get("layer", 60)),
			"target_box": entry.get("target_box", Vector2(112.0, 112.0)),
		})
	decor_layers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("layer", 0)) < int(b.get("layer", 0))
	)

	var scene := EventBgCatalog.build_scene_descriptor(hex_data, world_seed, coords)
	var scene_props: Array = scene.get("props", []).duplicate(true)
	for decor in decor_layers:
		var offset: Vector2 = decor.get("offset", Vector2.ZERO)
		var anchor := Vector2(
			clampf(0.5 + offset.x / 512.0, 0.08, 0.92),
			clampf(0.55 + offset.y / 512.0, 0.12, 0.88)
		)
		scene_props.append({
			"id": "decor_%d" % scene_props.size(),
			"label": str(decor.get("kind", "Terrain detail")).capitalize(),
			"sprite_path": str(decor.get("path", "")),
			"anchor": anchor,
			"decorative": true,
			"scale_multiplier": float(decor.get("scale_multiplier", 1.0)),
			"flip_h": bool(decor.get("flip_h", false)),
		})
	scene["props"] = scene_props

	return {
		"coords": coords,
		"layers": layers,
		"decorations": decor_layers,
		"scene": scene,
		"entity": entity_descriptor.duplicate(true),
		"ground_items": ground_items.duplicate(true),
		"composition_role": hex_data.composition_role,
		"stamp_instance_id": hex_data.stamp_instance_id,
		"generation_version": hex_data.world_generation_version,
	}


static func merge_scene(
	composed_scene: Dictionary,
	interaction_scene: Dictionary
) -> Dictionary:
	## Keep the interaction scene authoritative for its background and fixture
	## anchors, then append generator-only decoration props. This makes fixture
	## clicks stable without dropping visual details which only exist in v2.
	var merged := interaction_scene.duplicate(true)
	if merged.is_empty():
		return composed_scene.duplicate(true)
	if str(merged.get("background_path", "")).is_empty():
		merged["background_path"] = composed_scene.get("background_path", "")
	var merged_props: Array = merged.get("props", []).duplicate(true)
	var known_ids := {}
	var known_paths := {}
	for prop in merged_props:
		if not prop is Dictionary:
			continue
		known_ids[str(prop.get("id", ""))] = true
		known_paths[str(prop.get("sprite_path", ""))] = true
	for prop in composed_scene.get("props", []):
		if not prop is Dictionary:
			continue
		var prop_id := str(prop.get("id", ""))
		var sprite_path := str(prop.get("sprite_path", ""))
		if known_ids.has(prop_id):
			continue
		if not sprite_path.is_empty() and known_paths.has(sprite_path):
			continue
		merged_props.append(prop.duplicate(true))
		known_ids[prop_id] = true
		known_paths[sprite_path] = true
	merged["props"] = merged_props
	return merged


static func _append_full_hex_layer(
	layers: Array,
	kind: String,
	path: String,
	z_index: int
) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	for existing in layers:
		if existing is Dictionary and str(existing.get("path", "")) == path:
			return
	layers.append({"kind": kind, "path": path, "z_index": z_index})


static func _terrain_path(hex_data: MacroHexData, catalog: MacroTileCatalog) -> String:
	if not hex_data.terrain_sprite_path.is_empty():
		return hex_data.terrain_sprite_path
	if catalog == null:
		return ""
	var source_id := -1
	if not hex_data.terrain_asset_id.is_empty():
		source_id = catalog.resolve_asset_id(hex_data.terrain_asset_id)
	if source_id < 0:
		source_id = catalog.resolve_terrain_id(
			hex_data.terrain_tile,
			hex_data.visual_variant_hash,
			hex_data.biome_pack
		)
	return _path_for_source(catalog, source_id)


static func _road_path(hex_data: MacroHexData, catalog: MacroTileCatalog) -> String:
	if catalog == null or hex_data.road_mask <= 0:
		return ""
	var surface_id := "dirt" if hex_data.composition_role == "dirt_service_spur" else "paved"
	return _path_for_source(catalog, catalog.resolve_road_mask_id(hex_data.road_mask, surface_id))


static func _water_path(hex_data: MacroHexData, catalog: MacroTileCatalog) -> String:
	if not hex_data.water_sprite_path.is_empty():
		return hex_data.water_sprite_path
	if catalog == null or hex_data.water_layer == GameEnums.MacroWaterLayer.NONE:
		return ""
	return ""


static func _flora_path(hex_data: MacroHexData, catalog: MacroTileCatalog) -> String:
	if not hex_data.flora_sprite_path.is_empty():
		return hex_data.flora_sprite_path
	if catalog == null:
		return ""
	return _path_for_source(
		catalog,
		catalog.resolve_flora_id(
			hex_data.flora_layer,
			hex_data.visual_variant_hash,
			hex_data.biome_pack
		)
	)


static func _rock_path(hex_data: MacroHexData, catalog: MacroTileCatalog) -> String:
	if not hex_data.rock_sprite_path.is_empty():
		return hex_data.rock_sprite_path
	if catalog == null:
		return ""
	return _path_for_source(
		catalog,
		catalog.resolve_rock_id(
			hex_data.rock_layer,
			hex_data.visual_variant_hash,
			hex_data.biome_pack
		)
	)


static func _structure_path(hex_data: MacroHexData, catalog: MacroTileCatalog) -> String:
	if not hex_data.structure_sprite_path.is_empty():
		return hex_data.structure_sprite_path
	if catalog == null:
		return ""
	return _path_for_source(
		catalog,
		catalog.get_structure_tile_id(
			hex_data.structure_layer,
			hex_data.visual_variant_hash,
			hex_data.structure_pack
		)
	)


static func _path_for_source(catalog: MacroTileCatalog, source_id: int) -> String:
	if catalog == null or source_id < 0:
		return ""
	return catalog.path_for_source_id(source_id)
