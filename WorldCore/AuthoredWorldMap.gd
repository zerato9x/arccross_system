extends Resource
class_name AuthoredWorldMap

## Hand-painted macro world baseline. Runtime and cross-run mutations layer on top.

@export var map_id: String = "phase2_east"
@export var display_name: String = "Phase 2 East Arm"
@export var playable_arm: GameEnums.MacroArmDirection = GameEnums.MacroArmDirection.EAST
@export var start_coords: Vector2i = Vector2i(3, 0)
@export var core_coords: Vector2i = Vector2i.ZERO
@export var entries: Array[Dictionary] = []
## Scaled sprite props: {coords, sprite_path, scale, offset, layer}
@export var decorations: Array[Dictionary] = []

var _coords_index: Dictionary = {}
var _decor_by_coords: Dictionary = {}


func rebuild_index() -> void:
	_coords_index.clear()
	_decor_by_coords.clear()
	for entry in entries:
		if not entry is Dictionary:
			continue
		var coords: Variant = entry.get("coords", Vector2i.ZERO)
		if coords is Vector2i:
			_coords_index[coords] = entry
	for decor in decorations:
		if not decor is Dictionary:
			continue
		var decor_coords: Variant = decor.get("coords", Vector2i.ZERO)
		if decor_coords is Vector2i:
			if not _decor_by_coords.has(decor_coords):
				_decor_by_coords[decor_coords] = []
			_decor_by_coords[decor_coords].append(decor)


func get_decorations_at(coords: Vector2i) -> Array:
	if _decor_by_coords.is_empty() and not decorations.is_empty():
		rebuild_index()
	return _decor_by_coords.get(coords, [])


func has_hex(coords: Vector2i) -> bool:
	if _coords_index.is_empty() and not entries.is_empty():
		rebuild_index()
	return _coords_index.has(coords)


func get_entry(coords: Vector2i) -> Dictionary:
	if _coords_index.is_empty() and not entries.is_empty():
		rebuild_index()
	return _coords_index.get(coords, {})


func get_all_coords() -> Array:
	if _coords_index.is_empty() and not entries.is_empty():
		rebuild_index()
	return _coords_index.keys()


func set_entry(coords: Vector2i, entry: Dictionary) -> void:
	var stored := entry.duplicate(true)
	stored["coords"] = coords
	if _coords_index.is_empty() and not entries.is_empty():
		rebuild_index()
	var replaced := false
	for index in range(entries.size()):
		var existing: Dictionary = entries[index]
		if existing.get("coords", Vector2i(-9999, -9999)) == coords:
			entries[index] = stored
			replaced = true
			break
	if not replaced:
		entries.append(stored)
	_coords_index[coords] = stored


func build_hex_data(coords: Vector2i, seed_value: String = "") -> MacroHexData:
	var entry := get_entry(coords)
	var hex := MacroHexData.new()
	if entry.is_empty():
		return hex

	hex.biome = int(entry.get("biome", GameEnums.GridBiome.PLAINS))
	hex.terrain_tile = int(
		entry.get("terrain_tile", GameEnums.MacroTerrainTile.PLAINS_GRASS)
	)
	hex.flora_layer = int(entry.get("flora_layer", GameEnums.MacroFloraLayer.NONE))
	hex.rock_layer = int(entry.get("rock_layer", GameEnums.MacroRockLayer.NONE))
	hex.structure_layer = int(
		entry.get("structure_layer", GameEnums.MacroStructureLayer.NONE)
	)
	hex.region = int(entry.get("region", GameEnums.MacroRegion.WASTELAND))
	hex.arm_direction = int(
		entry.get("arm_direction", GameEnums.MacroArmDirection.NONE)
	)
	hex.zone_id = str(entry.get("zone_id", ""))
	hex.biome_pack = str(
		entry.get("biome_pack", GameEnums.BIOME_PACK_PLAINS)
	)
	hex.landmark_id = str(entry.get("landmark_id", ""))
	hex.impassable = bool(entry.get("impassable", false))
	hex.terrain_sprite_path = str(entry.get("terrain_sprite_path", ""))
	hex.flora_sprite_path = str(entry.get("flora_sprite_path", ""))
	hex.rock_sprite_path = str(entry.get("rock_sprite_path", ""))
	hex.structure_sprite_path = str(entry.get("structure_sprite_path", ""))
	hex.is_poi = bool(entry.get("is_poi", false))
	hex.poi_id = str(entry.get("poi_id", ""))
	hex.poi_name = str(entry.get("poi_name", ""))
	hex.sleep_anchor = str(entry.get("sleep_anchor", "ground"))
	hex.hazard_level = clampf(
		float(entry.get("hazard_level", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)

	if not seed_value.is_empty():
		hex.visual_variant_hash = compute_visual_variant_hash(coords, seed_value)
	elif entry.has("visual_variant_hash"):
		hex.visual_variant_hash = int(entry.get("visual_variant_hash", 0))

	if hex.is_poi and hex.structure_layer == GameEnums.MacroStructureLayer.NONE:
		hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES

	return hex


static func compute_visual_variant_hash(coords: Vector2i, seed_value: String) -> int:
	return absi(
		(seed_value + ":variant:" + str(coords.x) + ":" + str(coords.y)).hash()
	)


static func entry_from_hex_data(coords: Vector2i, hex: MacroHexData) -> Dictionary:
	return {
		"coords": coords,
		"biome": hex.biome,
		"terrain_tile": hex.terrain_tile,
		"flora_layer": hex.flora_layer,
		"rock_layer": hex.rock_layer,
		"structure_layer": hex.structure_layer,
		"region": hex.region,
		"arm_direction": hex.arm_direction,
		"zone_id": hex.zone_id,
		"biome_pack": hex.biome_pack,
		"landmark_id": hex.landmark_id,
		"impassable": hex.impassable,
		"terrain_sprite_path": hex.terrain_sprite_path,
		"flora_sprite_path": hex.flora_sprite_path,
		"rock_sprite_path": hex.rock_sprite_path,
		"structure_sprite_path": hex.structure_sprite_path,
		"is_poi": hex.is_poi,
		"poi_id": hex.poi_id,
		"poi_name": hex.poi_name,
		"sleep_anchor": hex.sleep_anchor,
		"hazard_level": hex.hazard_level,
		"visual_variant_hash": hex.visual_variant_hash,
	}
