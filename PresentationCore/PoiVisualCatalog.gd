extends RefCounted
class_name PoiVisualCatalog

const STRUCTURE_PATHS := {
	"homestead_b": [
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - B-i.png",
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - B-ii.png",
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 B-i shadow.png",
	],
	"homestead_d": [
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - D.png",
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - B-ii.png",
	],
	"shed_a": [
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size1 B-i shadow.png",
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - B-i.png",
	],
	"warehouse_b": [
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Cylindrical Tank A - Size 1 - Yellow.png",
		"res://Asset/HexTiles/_BIOMES/default_era8/Structures/Homestead Building Size 2 - D.png",
	],
	"centralcore_city": [
		"res://Asset/HexTiles/_BIOMES/biome_centralcore/Structures/Prefab Building - Size 2F.png",
		"res://Asset/HexTiles/_BIOMES/biome_centralcore/Structures/Warehouse Left B.png",
	],
	"alpha_hub": [
		"res://Asset/HexTiles/_BIOMES/biome_centralcore/Structures/Prefab Building - Size 2F.png",
		"res://Asset/HexTiles/_BIOMES/biome_centralcore/Structures/Warehouse Left B.png",
	],
}

const FLORA_PATHS := [
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Temperate Trees v2 size-3 A green.png",
	"res://Asset/HexTiles/_BIOMES/biome_plains/flora/Shrub H.png",
]

const PROP_ANCHORS := [
	Vector2(0.32, 0.58),
	Vector2(0.58, 0.60),
	Vector2(0.78, 0.56),
]

static func pick_structure_paths(
	landmark_id: String,
	seed_value: String,
	coords: Vector2i,
	max_count: int = 3
) -> Array[String]:
	var options: Array = STRUCTURE_PATHS.get(landmark_id, [])
	if options.is_empty():
		options = STRUCTURE_PATHS.get("homestead_b", [])
	var valid: Array[String] = []
	for path in options:
		if ResourceLoader.exists(path):
			valid.append(str(path))
	if valid.is_empty():
		return []

	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value + ":structures:" + landmark_id + ":" + str(coords)).hash()
	var count := mini(3, valid.size())
	var picked: Array[String] = []
	var pool := valid.duplicate()
	while picked.size() < count and not pool.is_empty():
		var index := rng.randi_range(0, pool.size() - 1)
		picked.append(pool[index])
		pool.remove_at(index)
	return picked


static func pick_structure_path(
	landmark_id: String,
	seed_value: String,
	coords: Vector2i
) -> String:
	var paths := pick_structure_paths(landmark_id, seed_value, coords, 1)
	if paths.is_empty():
		return ""
	return paths[0]

static func pick_flora_path(seed_value: String, coords: Vector2i) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value + ":flora:" + str(coords)).hash()
	var valid: Array[String] = []
	for path in FLORA_PATHS:
		if ResourceLoader.exists(path):
			valid.append(path)
	if valid.is_empty():
		return ""
	return valid[rng.randi_range(0, valid.size() - 1)]

static func build_prop_descriptors(
	hex_data: MacroHexData,
	world_seed: String,
	coords: Vector2i
) -> Array:
	var props: Array = []
	var landmark_id := (
		hex_data.landmark_id
		if not hex_data.landmark_id.is_empty()
		else hex_data.poi_id
	)
	var structure_paths := pick_structure_paths(landmark_id, world_seed, coords)
	if structure_paths.is_empty() and not hex_data.structure_sprite_path.is_empty():
		structure_paths = [hex_data.structure_sprite_path]

	for index in range(structure_paths.size()):
		var sprite_path: String = structure_paths[index]
		if sprite_path.is_empty() or not ResourceLoader.exists(sprite_path):
			continue
		var anchor: Vector2 = PROP_ANCHORS[min(index, PROP_ANCHORS.size() - 1)]
		props.append({
			"id": "structure_%d" % index,
			"label": _structure_search_label(index, structure_paths.size()),
			"sprite_path": sprite_path,
			"anchor": anchor,
			"search_option_id": "structure_%d" % index,
		})

	if hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
		var flora_path := pick_flora_path(world_seed, coords)
		if not flora_path.is_empty():
			props.append({
				"id": "flora_trees",
				"label": "Tree Line",
				"sprite_path": flora_path,
				"anchor": Vector2(0.20, 0.52),
				"search_option_id": "flora_trees",
			})
	return props

static func _structure_search_label(index: int, total: int) -> String:
	if total <= 1:
		return "Main Building"
	match index:
		0:
			return "Front Structure"
		1:
			return "Side Building"
		_:
			return "Rear Shed"

static func sleep_anchor_label(anchor: String) -> String:
	match anchor:
		"bed":
			return "Built-in Bed"
		"bench":
			return "Salvaged Bench"
		_:
			return "Open Ground"
