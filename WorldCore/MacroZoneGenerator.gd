extends RefCounted
class_name MacroZoneGenerator

## Generates a bounded 12x12 hex local map for one campaign node.
## Reuses plains layer rules from HexWorldGenerator (noise + shrub/structure rolls).

const ZONE_SIZE := GameEnums.MACRO_ZONE_SIZE
const _PoiVisualCatalog := preload("res://PresentationCore/PoiVisualCatalog.gd")
const _SectorCatalog := preload("res://WorldCore/WorldSectorCatalog.gd")
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

var master_seed: String = ""
var node_id: String = ""
var zone_kind: GameEnums.MacroZoneKind = GameEnums.MacroZoneKind.BIOME_RNG
var biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS
var event_id: String = ""

var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var world_hex_cache: Dictionary = {} # Vector2i -> MacroHexData
var start_coords: Vector2i = Vector2i(5, 10)
var objective_coords: Vector2i = Vector2i(5, 1)
var authored_map: Resource = null # unused; kept for MacroGameManager compatibility
var require_authored_map: bool = false

@export_range(0.0, 1.0) var random_structure_chance: float = 0.08
@export_range(0.0, 1.0) var random_remnant_chance: float = 0.10
@export_range(0.0, 1.0) var shrub_spawn_chance: float = 0.40
@export_range(0.0, 1.0) var landmark_spawn_chance: float = 0.16
@export_range(0, 8) var guaranteed_landmark_count: int = 7
@export_range(0.0, 1.0) var clutter_spawn_chance: float = 0.55

var zone_decorations: Dictionary = {} # Vector2i -> Array[Dictionary]
var trail_hexes: Dictionary = {} # Vector2i -> true

var _world_state: RuntimeStateStore


func configure_services(world_state: RuntimeStateStore) -> void:
	_world_state = world_state


func configure_seed(seed_value: String) -> void:
	master_seed = seed_value
	_initialize_noise()


func is_in_bounds(coords: Vector2i) -> bool:
	return coords.x >= 0 and coords.y >= 0 and coords.x < ZONE_SIZE and coords.y < ZONE_SIZE


func generate_zone(
	p_node_id: String,
	p_zone_kind: GameEnums.MacroZoneKind,
	p_biome: GameEnums.GridBiome = GameEnums.GridBiome.PLAINS,
	p_event_id: String = ""
) -> void:
	node_id = p_node_id
	zone_kind = p_zone_kind
	biome = p_biome
	event_id = p_event_id
	world_hex_cache.clear()
	zone_decorations.clear()
	trail_hexes.clear()
	_initialize_noise()

	start_coords = Vector2i(ZONE_SIZE / 2, ZONE_SIZE - 2)
	objective_coords = Vector2i(ZONE_SIZE / 2, 1)

	for y in range(ZONE_SIZE):
		for x in range(ZONE_SIZE):
			var coords := Vector2i(x, y)
			var hex := _build_hex(coords)
			world_hex_cache[coords] = hex
			if _world_state != null:
				_world_state.set_hex_record(coords, hex.to_state())

	_apply_trail_network()
	_place_start_and_objective()
	_place_guaranteed_landmarks()
	_scatter_zone_decorations()


func get_decorations_at(coords: Vector2i) -> Array:
	return zone_decorations.get(coords, [])


func get_hex_at(coords: Vector2i) -> MacroHexData:
	if world_hex_cache.has(coords):
		return world_hex_cache[coords]
	if not is_in_bounds(coords):
		return HexWorldGenerator.build_void_hex(coords)

	if _world_state != null:
		var persistent: HexRecord = _world_state.get_hex_record(coords)
		if persistent != null:
			var restored := MacroHexData.from_state(persistent)
			world_hex_cache[coords] = restored
			return restored

	var hex := _build_hex(coords)
	world_hex_cache[coords] = hex
	if _world_state != null:
		_world_state.set_hex_record(coords, hex.to_state())
	return hex


func _initialize_noise() -> void:
	var zone_seed := master_seed + ":zone:" + node_id
	elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = (zone_seed + ":elevation").hash()
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Lower frequency → contiguous hills / mud / forest patches.
	elevation_noise.frequency = 0.025

	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = (zone_seed + ":moisture").hash()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	moisture_noise.frequency = 0.03


func _build_hex(coords: Vector2i) -> MacroHexData:
	if node_id == MacroGraphGenerator.HUB_ID:
		return _build_hub_hex(coords)
	if zone_kind == GameEnums.MacroZoneKind.UNIQUE_EVENT:
		return _build_unique_event_hex(coords)
	return _build_plains_rng_hex(coords)


func _build_hub_hex(coords: Vector2i) -> MacroHexData:
	var hex := MacroHexData.new()
	hex.zone_id = "zone_hub"
	hex.biome = GameEnums.GridBiome.PLAINS
	hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
	hex.region = GameEnums.MacroRegion.CENTRAL_HUB
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.NONE
	hex.hazard_level = 0.0
	hex.impassable = false
	hex.visual_variant_hash = HexWorldGenerator.compute_visual_variant_hash(
		coords,
		master_seed + ":zone:" + node_id
	)
	# Hub stays readable: light shrub scatter, no random landmarks.
	var hub_shrub := shrub_spawn_chance * 0.35
	var saved := shrub_spawn_chance
	shrub_spawn_chance = hub_shrub
	_apply_shrub_variation(coords, hex)
	shrub_spawn_chance = saved
	return hex


func _build_plains_rng_hex(coords: Vector2i) -> MacroHexData:
	var hex := MacroHexData.new()
	hex.zone_id = "zone_" + node_id
	hex.biome_pack = GameEnums.BIOME_PACK_PLAINS
	hex.region = GameEnums.MacroRegion.WASTELAND
	hex.biome = biome
	hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	hex.flora_layer = GameEnums.MacroFloraLayer.NONE
	hex.rock_layer = GameEnums.MacroRockLayer.NONE
	hex.structure_layer = GameEnums.MacroStructureLayer.NONE
	hex.is_poi = false
	hex.landmark_id = ""
	hex.hazard_level = 2.0 + float(ZONE_SIZE - 1 - coords.y) * 0.15

	var elevation: float = elevation_noise.get_noise_2dv(coords)
	var moisture: float = moisture_noise.get_noise_2dv(coords)

	# Contiguous rock / hill clusters (flood-style thresholds, not speckles).
	if elevation > 0.52:
		hex.rock_layer = GameEnums.MacroRockLayer.ROCKS
		hex.impassable = true
	elif elevation > 0.22:
		hex.rock_layer = GameEnums.MacroRockLayer.HILLS

	if hex.rock_layer != GameEnums.MacroRockLayer.ROCKS:
		# Mud follows moisture corridors; sparse forest on damp mid-elevation.
		if moisture < -0.18 or elevation < -0.28:
			hex.terrain_tile = GameEnums.MacroTerrainTile.MUD_YELLOW
		elif moisture > 0.20 and elevation > -0.12 and elevation < 0.40:
			hex.terrain_tile = GameEnums.MacroTerrainTile.FOREST_SPARSE
			hex.flora_layer = GameEnums.MacroFloraLayer.TREES

	_apply_shrub_variation(coords, hex)

	var zone_seed := master_seed + ":zone:" + node_id
	var rng := RandomNumberGenerator.new()
	rng.seed = (zone_seed + ":layers:" + str(coords)).hash()
	if hex.structure_layer == GameEnums.MacroStructureLayer.NONE and hex.landmark_id.is_empty():
		var structure_roll := rng.randf()
		if structure_roll < random_structure_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
		elif structure_roll < random_structure_chance + random_remnant_chance:
			hex.structure_layer = GameEnums.MacroStructureLayer.REMNANTS

	var landmark_rng := RandomNumberGenerator.new()
	landmark_rng.seed = (zone_seed + ":landmark:" + str(coords)).hash()
	if (
		not hex.impassable
		and hex.landmark_id.is_empty()
		and landmark_rng.randf() < landmark_spawn_chance
	):
		_apply_landmark_to_hex(hex, coords, zone_seed)

	hex.visual_variant_hash = HexWorldGenerator.compute_visual_variant_hash(
		coords,
		zone_seed
	)
	return hex


func _build_unique_event_hex(coords: Vector2i) -> MacroHexData:
	var hex := _build_plains_rng_hex(coords)
	hex.zone_id = "zone_event_" + node_id
	hex.region = GameEnums.MacroRegion.ARM_STAGE_3
	hex.hazard_level = maxf(hex.hazard_level, 4.0)
	# Clear a corridor toward the objective so the event site is reachable.
	if coords.x == objective_coords.x and coords.y <= start_coords.y:
		hex.impassable = false
		hex.rock_layer = GameEnums.MacroRockLayer.NONE
		if hex.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
			hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
	return hex


func _apply_shrub_variation(coords: Vector2i, hex: MacroHexData) -> void:
	if (
		hex.terrain_tile != GameEnums.MacroTerrainTile.PLAINS_GRASS
		or hex.flora_layer != GameEnums.MacroFloraLayer.NONE
		or hex.impassable
	):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = (master_seed + ":zone:" + node_id + ":shrub:" + str(coords)).hash()
	if rng.randf() < shrub_spawn_chance:
		hex.flora_layer = GameEnums.MacroFloraLayer.SHRUBS


func _apply_landmark_to_hex(
	hex: MacroHexData,
	coords: Vector2i,
	zone_seed: String
) -> void:
	var landmark := _SectorCatalog.pick_landmark(zone_seed, coords, "wedge_n")
	hex.landmark_id = str(landmark.get("landmark_id", ""))
	hex.is_poi = true
	hex.poi_id = str(landmark.get("poi_id", "plains_landmark"))
	hex.poi_name = str(landmark.get("poi_name", "Landmark"))
	hex.sleep_anchor = str(landmark.get("sleep_anchor", "ground"))
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
		hex.landmark_id,
		zone_seed,
		coords
	)


func _apply_trail_network() -> void:
	trail_hexes.clear()
	var main_path := _axial_line(start_coords, objective_coords)
	for coords in main_path:
		trail_hexes[coords] = true

	var zone_seed := master_seed + ":zone:" + node_id
	var rng := RandomNumberGenerator.new()
	rng.seed = (zone_seed + ":trails").hash()
	# 1–2 spurs off the main path into the zone interior.
	var spur_count := rng.randi_range(1, 2)
	for _i in range(spur_count):
		if main_path.is_empty():
			break
		var junction: Vector2i = main_path[rng.randi_range(0, main_path.size() - 1)]
		var spur_end := Vector2i(
			clampi(junction.x + rng.randi_range(-4, 4), 0, ZONE_SIZE - 1),
			clampi(junction.y + rng.randi_range(-3, 3), 0, ZONE_SIZE - 1)
		)
		for coords in _axial_line(junction, spur_end):
			trail_hexes[coords] = true

	for coords in trail_hexes.keys():
		if not world_hex_cache.has(coords):
			continue
		var hex: MacroHexData = world_hex_cache[coords]
		hex.impassable = false
		hex.rock_layer = GameEnums.MacroRockLayer.NONE
		if hex.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
			hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
		if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
			hex.flora_layer = GameEnums.MacroFloraLayer.NONE
			hex.terrain_tile = GameEnums.MacroTerrainTile.PLAINS_GRASS
		if _world_state != null:
			_world_state.set_hex_record(coords, hex.to_state())


func _axial_line(from_coords: Vector2i, to_coords: Vector2i) -> Array[Vector2i]:
	var results: Array[Vector2i] = []
	var n := _hex_distance(from_coords, to_coords)
	if n == 0:
		results.append(from_coords)
		return results
	for i in range(n + 1):
		var t := float(i) / float(n)
		var q := int(round(lerpf(float(from_coords.x), float(to_coords.x), t)))
		var r := int(round(lerpf(float(from_coords.y), float(to_coords.y), t)))
		var cell := Vector2i(q, r)
		if results.is_empty() or results[results.size() - 1] != cell:
			results.append(cell)
	return results


func _hex_distance(a: Vector2i, b: Vector2i) -> int:
	var delta := b - a
	return maxi(abs(delta.x), maxi(abs(delta.y), abs(delta.x + delta.y)))


func _scatter_zone_decorations() -> void:
	zone_decorations.clear()
	if node_id == MacroGraphGenerator.HUB_ID:
		_scatter_hub_decorations()
		return
	var zone_seed := master_seed + ":zone:" + node_id
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		if hex.impassable or hex.is_poi or not hex.landmark_id.is_empty():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = (zone_seed + ":decor:" + str(coords)).hash()
		var chance := clutter_spawn_chance
		if trail_hexes.has(coords):
			chance *= 0.45
		if hex.structure_layer != GameEnums.MacroStructureLayer.NONE:
			chance *= 0.7
		if rng.randf() > chance:
			continue
		var props: Array = []
		var count := rng.randi_range(1, 2)
		for i in range(count):
			var path := _pick_decor_path(hex, rng)
			if path.is_empty() or not ResourceLoader.exists(path):
				continue
			props.append({
				"coords": coords,
				"sprite_path": path,
				"scale": Vector2.ONE * rng.randf_range(0.12, 0.22),
				"offset": Vector2(
					rng.randf_range(-110.0, 110.0),
					rng.randf_range(-80.0, 80.0)
				),
				"layer": 0 if "flora" in path.to_lower() else 3,
			})
		if not props.is_empty():
			zone_decorations[coords] = props


func _scatter_hub_decorations() -> void:
	var zone_seed := master_seed + ":zone:" + node_id
	for coords in world_hex_cache.keys():
		if coords == start_coords or coords == objective_coords:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = (zone_seed + ":hub_decor:" + str(coords)).hash()
		if rng.randf() > clutter_spawn_chance * 0.2:
			continue
		var path: String = DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]
		if not ResourceLoader.exists(path):
			continue
		zone_decorations[coords] = [{
			"coords": coords,
			"sprite_path": path,
			"scale": Vector2.ONE * rng.randf_range(0.10, 0.16),
			"offset": Vector2(
				rng.randf_range(-64.0, 64.0),
				rng.randf_range(-48.0, 48.0)
			),
			"layer": 0,
		}]


func _pick_decor_path(hex: MacroHexData, rng: RandomNumberGenerator) -> String:
	if hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
		return DECOR_TREE_PATHS[rng.randi_range(0, DECOR_TREE_PATHS.size() - 1)]
	if (
		hex.structure_layer != GameEnums.MacroStructureLayer.NONE
		or rng.randf() < 0.22
	):
		return DECOR_PROP_PATHS[rng.randi_range(0, DECOR_PROP_PATHS.size() - 1)]
	return DECOR_SHRUB_PATHS[rng.randi_range(0, DECOR_SHRUB_PATHS.size() - 1)]


func _place_guaranteed_landmarks() -> void:
	if node_id == MacroGraphGenerator.HUB_ID:
		return
	var zone_seed := master_seed + ":zone:" + node_id
	var existing := 0
	var candidates: Array[Vector2i] = []
	for coords in world_hex_cache.keys():
		var hex: MacroHexData = world_hex_cache[coords]
		if hex.is_poi or not hex.landmark_id.is_empty():
			existing += 1
			continue
		if (
			coords == start_coords
			or coords == objective_coords
			or hex.impassable
		):
			continue
		candidates.append(coords)

	var needed := maxi(0, guaranteed_landmark_count - existing)
	if needed <= 0 or candidates.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = (zone_seed + ":guaranteed_landmarks").hash()
	# Deterministic shuffle.
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp

	var placed := 0
	for coords in candidates:
		if placed >= needed:
			break
		var hex: MacroHexData = world_hex_cache[coords]
		_apply_landmark_to_hex(hex, coords, zone_seed)
		if _world_state != null:
			_world_state.set_hex_record(coords, hex.to_state())
		placed += 1


func _place_start_and_objective() -> void:
	var start_hex: MacroHexData = world_hex_cache[start_coords]
	start_hex.impassable = false
	start_hex.rock_layer = GameEnums.MacroRockLayer.NONE
	start_hex.is_explored = true
	if node_id == MacroGraphGenerator.HUB_ID:
		start_hex.is_poi = true
		start_hex.poi_id = "alpha_central_hub"
		start_hex.poi_name = "Alpha Hub"
		start_hex.landmark_id = "alpha_hub"
		start_hex.sleep_anchor = "bed"
		start_hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
		start_hex.terrain_tile = GameEnums.MacroTerrainTile.HUB_CONCRETE
		start_hex.biome_pack = GameEnums.BIOME_PACK_CENTRALCORE
		start_hex.region = GameEnums.MacroRegion.CENTRAL_HUB
		start_hex.hazard_level = 0.0
		start_hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			"centralcore_city",
			master_seed + ":zone:" + node_id,
			start_coords
		)

	var objective_hex: MacroHexData = world_hex_cache[objective_coords]
	objective_hex.impassable = false
	objective_hex.rock_layer = GameEnums.MacroRockLayer.NONE
	objective_hex.is_poi = true
	if zone_kind == GameEnums.MacroZoneKind.UNIQUE_EVENT:
		objective_hex.poi_id = "macro_event_" + (event_id if not event_id.is_empty() else "event")
		objective_hex.poi_name = "Anomalous Site"
		objective_hex.landmark_id = "event_site"
		objective_hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
		objective_hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			"warehouse_b",
			master_seed + ":zone:" + node_id,
			objective_coords
		)
	else:
		objective_hex.poi_id = "node_exit"
		objective_hex.poi_name = "Northern Exit"
		objective_hex.landmark_id = "exit_marker"
		objective_hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
		objective_hex.structure_sprite_path = _PoiVisualCatalog.pick_structure_path(
			"shed_a",
			master_seed + ":zone:" + node_id,
			objective_coords
		)

	if _world_state != null:
		_world_state.set_hex_record(start_coords, start_hex.to_state())
		_world_state.set_hex_record(objective_coords, objective_hex.to_state())


func hex_count() -> int:
	return world_hex_cache.size()


func debug_ascii() -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		"=== Zone %s kind=%s size=%dx%d ==="
		% [node_id, str(zone_kind), ZONE_SIZE, ZONE_SIZE]
	)
	for y in range(ZONE_SIZE):
		var row := ""
		for x in range(ZONE_SIZE):
			var coords := Vector2i(x, y)
			var ch := "."
			if coords == start_coords:
				ch = "S"
			elif coords == objective_coords:
				ch = "X"
			elif world_hex_cache.has(coords):
				var hex: MacroHexData = world_hex_cache[coords]
				if hex.impassable:
					ch = "#"
				elif hex.is_poi:
					ch = "P"
				elif hex.flora_layer == GameEnums.MacroFloraLayer.TREES:
					ch = "T"
				elif hex.rock_layer == GameEnums.MacroRockLayer.HILLS:
					ch = "^"
				elif hex.terrain_tile == GameEnums.MacroTerrainTile.MUD_YELLOW:
					ch = "~"
			row += ch
		lines.append(row)
	return "\n".join(lines)
