extends RefCounted
class_name MacroZoneDecorationService

## Owns deterministic visual dressing policy for generated hexes. It emits
## neutral decoration descriptors; presentation scenes decide how to render
## those descriptors.

const DECOR_SHRUB_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub C.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub D.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub E.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub F.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub G.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub H.png",
]
const DECOR_TREE_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Trees Green - 2x2A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Trees Green - 2x2B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Temperate Trees v2 size-2 A green.png",
]
const DECOR_PROP_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Homestead Crates Size1.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Small Crates 1A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Small Crates 1B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Tent A.a - Gray - closed.png",
]
const DECOR_ROCK_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz1 A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz1 B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz1 C shadow.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz2 A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Rocks/Rocks Sz2 B.png",
]
const DECOR_NORTH_ROCK_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_north/Rocks/Snowy Rocks - Sz 1 - A.png",
	"res://Asset/HexTiles/_BIOMES/biome_north/Rocks/Snowy Rocks - Sz 1 - B.png",
	"res://Asset/HexTiles/_BIOMES/biome_north/Rocks/Glacial Ice - Sz 1 - A.png",
	"res://Asset/HexTiles/_BIOMES/biome_north/Rocks/Glacial Ice - Sz 2 - A.png",
]
const RANDOM_REMNANT_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 A.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 B.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 C.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/remnants/Rubble 1x1 D.png",
]
const STARTER_STRUCTURE_PATHS := [
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 B-i shadow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 A shadow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 C shadow.png",
	"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - B-i.png",
]
const STARTER_TENT_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Tent A.a - Gray - closed.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Tent A.b - Green - closed.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/Colony Infrastructure/Tent Quonset - A.a - Gray.png",
]
const STARTER_INFRA_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/MoreInfras/Infrastructural Post A1-i.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/MoreInfras/Infrastructural Crate A1-i.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/MoreInfras/Infrastructural Barrel A1-i.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/Infrastructure/MoreInfras/Infrastructural Solar Panel A1-i.png",
]
const _WorldAssetManifest := preload("res://WorldCore/GenerationV2/WorldAssetManifest.gd")

var _runtime_asset_metadata: Dictionary = {}


func apply_starter_dressing(
	plan: GeneratedZonePlan,
	zone_seed: String,
	world_hex_cache: Dictionary,
	zone_decorations: Dictionary
) -> void:
	if plan == null:
		return
	var structure_index := 0
	var tent_index := 0
	var rubble_index := 0
	for coords in plan.stamp_cells.keys():
		var role := plan.role_at(coords)
		match role:
			"settlement_structure":
				_append_authored_decoration(
					coords,
					STARTER_STRUCTURE_PATHS[structure_index % STARTER_STRUCTURE_PATHS.size()],
					"structure",
					1.0,
					world_hex_cache,
					zone_decorations,
					plan
				)
				structure_index += 1
			"settlement_tent":
				_append_tent_cluster(
					coords,
					tent_index,
					zone_seed,
					world_hex_cache,
					zone_decorations,
					plan
				)
				tent_index += 1
			"settlement_rubble":
				_append_rubble_cluster(
					coords,
					rubble_index,
					1.0,
					3,
					zone_seed,
					world_hex_cache,
					zone_decorations,
					plan
				)
				rubble_index += 1
			"settlement_anchor":
				_append_authored_decoration(
					coords,
					STARTER_INFRA_PATHS[0],
					"prop",
					1.0,
					world_hex_cache,
					zone_decorations,
					plan
				)
	for coords in plan.rubble_search_cells:
		_append_rubble_cluster(
			coords,
			rubble_index,
			0.95,
			3,
			zone_seed,
			world_hex_cache,
			zone_decorations,
			plan
		)
		rubble_index += 1
	for coords in plan.visual_rubble_cells:
		_append_rubble_cluster(
			coords,
			rubble_index,
			0.84,
			2,
			zone_seed,
			world_hex_cache,
			zone_decorations,
			plan
		)
		rubble_index += 1
	var infra_index := 1
	for coords in plan.stamp_cells.keys():
		if infra_index >= STARTER_INFRA_PATHS.size():
			break
		if plan.role_at(coords) == "settlement_structure":
			_append_authored_decoration(
				coords,
				STARTER_INFRA_PATHS[infra_index],
				"prop",
				0.88,
				world_hex_cache,
				zone_decorations,
				plan
			)
			infra_index += 1


func scatter_zone_decorations(
	zone_seed: String,
	world_hex_cache: Dictionary,
	zone_decorations: Dictionary,
	start_coords: Vector2i,
	trail_hexes: Dictionary,
	node_role: int,
	clutter_spawn_chance: float,
	starter_route_zone: bool
) -> void:
	zone_decorations.clear()
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		if starter_route_zone and hex.composition_role != "quiet_plains":
			continue
		if (
			(hex.impassable and hex.rock_layer == GameEnums.MacroRockLayer.NONE)
			or hex.is_poi
			or not hex.landmark_id.is_empty()
		):
			continue
		if HexCoordUtils.distance(coords, start_coords) <= 1:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = (zone_seed + ":decor:" + str(coords)).hash()
		var chance := clutter_spawn_chance
		if node_role == GameEnums.MacroNodeRole.CENTRAL_CORE:
			chance *= 0.45
		if (
			hex.rock_layer != GameEnums.MacroRockLayer.NONE
			or hex.flora_layer == GameEnums.MacroFloraLayer.TREES
		):
			chance = 1.0
		if trail_hexes.has(coords):
			chance *= 0.16
		if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
			chance *= 0.85
		if rng.randf() > chance:
			continue
		var props: Array = []
		var count := _cluster_size_for_hex(hex, rng)
		var used_offsets: Array[Vector2] = []
		for i in range(count):
			var path := _pick_cluster_decor_path(hex, rng, i)
			if path.is_empty() or not ResourceLoader.exists(path):
				continue
			var kind := _decor_kind(path)
			var offset := _sample_cluster_offset(rng, used_offsets, kind, path)
			used_offsets.append(offset)
			var asset_meta := _asset_metadata_for_path(path)
			props.append({
				"coords": coords,
				"asset_id": str(asset_meta.get("asset_id", "")),
				"sprite_path": path,
				"kind": kind,
				"footprint_class": str(asset_meta.get("footprint_class", "fitted_prop")),
				"target_box": _decor_target_box(kind, path),
				"scale_multiplier": rng.randf_range(0.88, 1.08),
				"offset": offset,
				"rotation": 0.0,
				"flip_h": kind == "shrub" and rng.randf() < 0.35,
				"layer": _decor_layer(path),
			})
		if not props.is_empty():
			zone_decorations[coords] = props


func _append_tent_cluster(
	coords: Vector2i,
	cluster_index: int,
	zone_seed: String,
	world_hex_cache: Dictionary,
	zone_decorations: Dictionary,
	plan: GeneratedZonePlan
) -> void:
	var phase := posmod(cluster_index + absi((zone_seed + str(coords)).hash()), 3)
	var tent_offset_recipes: Array = [
		[Vector2(-82.0, 28.0), Vector2(76.0, -36.0), Vector2(26.0, 104.0)],
		[Vector2(-72.0, -34.0), Vector2(88.0, 32.0), Vector2(-18.0, 108.0)],
		[Vector2(-92.0, 12.0), Vector2(62.0, 48.0), Vector2(44.0, -104.0)],
	]
	var tent_offsets: Array = tent_offset_recipes[phase]
	_append_authored_decoration(
		coords, STARTER_TENT_PATHS[cluster_index % STARTER_TENT_PATHS.size()], "tent", 0.82,
		world_hex_cache, zone_decorations, plan, tent_offsets[0]
	)
	_append_authored_decoration(
		coords,
		STARTER_TENT_PATHS[(cluster_index + 1) % STARTER_TENT_PATHS.size()],
		"tent",
		0.72,
		world_hex_cache,
		zone_decorations,
		plan,
		tent_offsets[1],
		cluster_index % 2 == 0
	)
	if cluster_index % 2 == 0:
		_append_authored_decoration(
			coords,
			STARTER_TENT_PATHS[(cluster_index + 2) % STARTER_TENT_PATHS.size()],
			"tent",
			0.60,
			world_hex_cache,
			zone_decorations,
			plan,
			tent_offsets[2],
			true
		)
	var detail_offsets := [Vector2(-12.0, 112.0), Vector2(132.0, 74.0)]
	for detail_index in range(2):
		var path: String = STARTER_INFRA_PATHS[
			1 + posmod(cluster_index * 2 + detail_index, STARTER_INFRA_PATHS.size() - 1)
		]
		_append_authored_decoration(
			coords,
			path,
			"prop",
			0.72 if detail_index == 0 else 0.62,
			world_hex_cache,
			zone_decorations,
			plan,
			detail_offsets[detail_index]
		)


func _append_rubble_cluster(
	coords: Vector2i,
	cluster_index: int,
	scale_multiplier: float,
	shrub_count: int,
	zone_seed: String,
	world_hex_cache: Dictionary,
	zone_decorations: Dictionary,
	plan: GeneratedZonePlan
) -> void:
	var phase := posmod(cluster_index + absi((zone_seed + ":rubble:" + str(coords)).hash()), 4)
	var rubble_offsets := [
		Vector2(-18.0, 12.0), Vector2(20.0, -8.0),
		Vector2(-8.0, -18.0), Vector2(14.0, 18.0),
	]
	_append_authored_decoration(
		coords,
		RANDOM_REMNANT_PATHS[cluster_index % RANDOM_REMNANT_PATHS.size()],
		"rock",
		scale_multiplier,
		world_hex_cache,
		zone_decorations,
		plan,
		rubble_offsets[phase]
	)
	var shrub_offsets := [
		Vector2(-144.0, 66.0), Vector2(136.0, 54.0),
		Vector2(-112.0, -86.0), Vector2(104.0, -96.0),
	]
	for shrub_index in range(shrub_count):
		var slot := posmod(phase + shrub_index, shrub_offsets.size())
		var shrub_path: String = DECOR_SHRUB_PATHS[
			posmod(cluster_index * 3 + shrub_index, DECOR_SHRUB_PATHS.size())
		]
		_append_authored_decoration(
			coords,
			shrub_path,
			"shrub",
			0.86 + float((cluster_index + shrub_index) % 3) * 0.06,
			world_hex_cache,
			zone_decorations,
			plan,
			shrub_offsets[slot],
			(cluster_index + shrub_index) % 2 == 0
		)


func _append_authored_decoration(
	coords: Vector2i,
	path: String,
	kind: String,
	scale_multiplier: float,
	world_hex_cache: Dictionary,
	zone_decorations: Dictionary,
	plan: GeneratedZonePlan,
	offset: Vector2 = Vector2.ZERO,
	flip_h: bool = false
) -> void:
	if not world_hex_cache.has(coords) or not ResourceLoader.exists(path):
		return
	var asset_meta := _asset_metadata_for_path(path)
	var footprint_class := str(asset_meta.get("footprint_class", "fitted_prop"))
	var props: Array = zone_decorations.get(coords, [])
	props.append({
		"coords": coords,
		"asset_id": str(asset_meta.get("asset_id", "")),
		"sprite_path": path,
		"kind": kind,
		"footprint_class": footprint_class,
		"reserved_cells": _reserved_cells_for_decoration(coords, footprint_class, plan),
		"target_box": _decor_target_box(kind, path),
		"scale_multiplier": scale_multiplier,
		"offset": offset,
		"rotation": 0.0,
		"flip_h": flip_h,
		"layer": _decor_layer(path),
	})
	zone_decorations[coords] = props


func _asset_metadata_for_path(path: String) -> Dictionary:
	if _runtime_asset_metadata.is_empty():
		for entry in _WorldAssetManifest.approved_assets():
			if not entry is Dictionary:
				continue
			_runtime_asset_metadata[str(entry.get("destination", ""))] = entry
	return _runtime_asset_metadata.get(path, {})


func _reserved_cells_for_decoration(
	coords: Vector2i,
	footprint_class: String,
	plan: GeneratedZonePlan
) -> Array[Vector2i]:
	var reserved: Array[Vector2i] = [coords]
	if footprint_class != "reserved_two_hex":
		return reserved
	if plan != null:
		for direction in HexCoordUtils.AXIAL_DIRECTIONS:
			var neighbor: Vector2i = coords + Vector2i(direction)
			if plan.stamp_cells.has(neighbor):
				reserved.append(neighbor)
				return reserved
		plan.overflow_violations.append({
			"coords": coords,
			"footprint_class": footprint_class,
			"reason": "No reserved neighboring stamp cell.",
		})
		plan.validation_errors.append("Large dressing has no reserved neighboring cell.")
	return reserved


func _cluster_size_for_hex(hex: MacroHexData, rng: RandomNumberGenerator) -> int:
	if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return rng.randi_range(3, 5)
	if hex.rock_layer == GameEnums.MacroRockLayer.ROCKS:
		return rng.randi_range(3, 4)
	if hex.rock_layer == GameEnums.MacroRockLayer.HILLS:
		return rng.randi_range(2, 3)
	if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
		return rng.randi_range(2, 4)
	return rng.randi_range(1, 3)


func _pick_cluster_decor_path(
	hex: MacroHexData,
	rng: RandomNumberGenerator,
	index: int
) -> String:
	if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
		if index == 0:
			return DECOR_TREE_PATHS[rng.randi_range(0, DECOR_TREE_PATHS.size() - 1)]
		return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]
	if hex.rock_layer != GameEnums.MacroRockLayer.NONE:
		var prefer_north_rocks := hex.biome_pack == GameEnums.BIOME_PACK_NORTH
		if prefer_north_rocks and index < 2:
			var north_rock := _pick_curated_layer_path(DECOR_NORTH_ROCK_PATHS, rng)
			if not north_rock.is_empty():
				return north_rock
		if index == 0:
			return DECOR_ROCK_PATHS[rng.randi_range(3, 4)]
		if index == 1 or rng.randf() < 0.72:
			return DECOR_ROCK_PATHS[rng.randi_range(0, 2)]
		return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]
	if rng.randf() < 0.12:
		if hex.biome_pack == GameEnums.BIOME_PACK_NORTH:
			var north_rock := _pick_curated_layer_path(DECOR_NORTH_ROCK_PATHS, rng)
			if not north_rock.is_empty():
				return north_rock
		return DECOR_ROCK_PATHS[rng.randi_range(0, DECOR_ROCK_PATHS.size() - 1)]
	if hex.structure_layer != GameEnums.MacroStructureLayer.NONE and rng.randf() < 0.65:
		return DECOR_PROP_PATHS[rng.randi_range(0, DECOR_PROP_PATHS.size() - 1)]
	return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]


func _pick_curated_layer_path(paths: Array, rng: RandomNumberGenerator) -> String:
	var valid: Array[String] = []
	for path in paths:
		if ResourceLoader.exists(str(path)):
			valid.append(str(path))
	if valid.is_empty():
		return ""
	return valid[rng.randi_range(0, valid.size() - 1)]


func _sample_cluster_offset(
	rng: RandomNumberGenerator,
	used_offsets: Array[Vector2],
	kind: String,
	path: String
) -> Vector2:
	var large_visual := kind == "tree" or (kind == "rock" and "sz2" in path.to_lower())
	var inset := 72.0 if large_visual else 38.0
	var max_y := 154.0 if large_visual else 188.0
	var min_separation := 92.0 if large_visual else (62.0 if kind == "rock" else 48.0)
	for _attempt in range(28):
		var y := rng.randf_range(-max_y, max_y)
		var polygon_limit := 256.0 if absf(y) <= 128.0 else 512.0 - 2.0 * absf(y)
		var x_limit := maxf(36.0, polygon_limit - inset)
		var candidate := Vector2(rng.randf_range(-x_limit, x_limit), y)
		var separated := true
		for used in used_offsets:
			if candidate.distance_to(used) < min_separation:
				separated = false
				break
		if separated:
			return candidate
	var frame_slots := [
		Vector2(-152.0, -58.0), Vector2(152.0, -58.0),
		Vector2(-138.0, 72.0), Vector2(138.0, 72.0),
		Vector2(-68.0, -146.0), Vector2(70.0, 146.0),
	]
	return frame_slots[rng.randi_range(0, frame_slots.size() - 1)]


func _decor_kind(path: String) -> String:
	var lowered := path.to_lower()
	if "tree" in lowered:
		return "tree"
	if "rocks" in lowered:
		return "rock"
	if "shrub" in lowered:
		return "shrub"
	return "prop"


func _decor_target_box(kind: String, path: String = "") -> Vector2:
	var lowered := path.to_lower()
	match kind:
		"structure":
			return Vector2(300.0, 240.0)
		"tent":
			return Vector2(176.0, 126.0)
		"tree":
			return Vector2(310.0, 270.0)
		"rock":
			if "sz2" in lowered:
				return Vector2(270.0, 220.0)
			if "rubble" in lowered:
				return Vector2(270.0, 205.0)
			return Vector2(164.0, 132.0)
		"shrub":
			return Vector2(54.0, 62.0)
		"prop":
			if "post" in lowered:
				return Vector2(78.0, 126.0)
			if "crate" in lowered:
				return Vector2(92.0, 72.0)
			if "barrel" in lowered:
				return Vector2(74.0, 82.0)
			if "solar panel" in lowered:
				return Vector2(150.0, 112.0)
			return Vector2(96.0, 80.0)
		_:
			return Vector2(62.0, 68.0)


func _decor_layer(path: String) -> int:
	var lowered := path.to_lower()
	if "flora" in lowered:
		return 0
	if "rocks" in lowered:
		return 1
	return 3
