extends RefCounted
class_name MenuParallaxCatalog

## Discovers Event_bg parallax packs and builds ordered layer lists for the main menu.
## Packs stay under Asset/UI/Event_bg; gameplay event/collision art uses HexTiles instead.

const ROOT := "res://Asset/UI/Event_bg/"

const _SKIP_NAMES := {
	"orig.png": true,
	"orig_big.png": true,
	"2304x1296.png": true,
	"moon_asset.png": true,
}

## Full-scene composites that should not be stacked as parallax layers.
const _SKIP_PREFIXES := [
	"postapocalypse",
	"war.png",
	"war2.png",
	"war3.png",
	"war4.png",
]


static func pack_dirs() -> PackedStringArray:
	var dirs := PackedStringArray()
	for scene_id in range(1, 5):
		for tone in ["Bright", "Pale"]:
			dirs.append(
				"%sapocalyptic_bg/PNG/Postapocalypce%d/%s" % [ROOT, scene_id, tone]
			)
	for bg_id in range(1, 5):
		dirs.append("%sapocalyptic_bg_2/background %d" % [ROOT, bg_id])
	dirs.append("%sbackground 3" % ROOT)
	for forest_id in range(1, 9):
		dirs.append("%strees_forest/%d" % [ROOT, forest_id])
	for war_id in range(1, 5):
		for tone in ["Bright", "Pale"]:
			dirs.append("%swar/War%d/%s" % [ROOT, war_id, tone])
	return dirs


static func available_packs() -> PackedStringArray:
	var available := PackedStringArray()
	for pack_dir in pack_dirs():
		if not layers_for_pack(pack_dir).is_empty():
			available.append(pack_dir)
	return available


static func pick_random_pack(rng: RandomNumberGenerator = null) -> String:
	var packs := available_packs()
	if packs.is_empty():
		return ""
	if rng == null:
		return packs[randi() % packs.size()]
	return packs[rng.randi_range(0, packs.size() - 1)]


static func layers_for_pack(pack_dir: String) -> Array[Dictionary]:
	var files := _list_png_files(pack_dir)
	if files.is_empty():
		return []
	var entries: Array[Dictionary] = []
	var numbered := true
	for file_name in files:
		if not _is_numbered_layer(file_name):
			numbered = false
			break
	var sortable: Array = []
	for file_name in files:
		sortable.append(file_name)
	if numbered:
		sortable.sort_custom(func(a: String, b: String) -> bool:
			return a.to_int() < b.to_int()
		)
	else:
		sortable.sort_custom(func(a: String, b: String) -> bool:
			var score_a := _named_depth_score(a)
			var score_b := _named_depth_score(b)
			if score_a == score_b:
				return a < b
			return score_a < score_b
		)
	for index in range(sortable.size()):
		entries.append({
			"path": "%s/%s" % [pack_dir, sortable[index]],
			"motion_scale": _motion_scale_for_index(index, sortable.size()),
		})
	return entries


static func _list_png_files(pack_dir: String) -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(pack_dir)
	if dir == null:
		return files
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.to_lower().ends_with(".png"):
			if _should_keep_layer(entry):
				files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	return files


static func _should_keep_layer(file_name: String) -> bool:
	var lower := file_name.to_lower()
	if _SKIP_NAMES.has(lower):
		return false
	for prefix in _SKIP_PREFIXES:
		if lower == prefix or lower.begins_with(prefix):
			return false
	return true


static func _is_numbered_layer(file_name: String) -> bool:
	var stem := file_name.get_basename()
	return stem.is_valid_int()


static func _named_depth_score(file_name: String) -> int:
	var stem := file_name.get_basename().to_lower()
	if stem == "sky" or stem == "bg" or stem.begins_with("sky_"):
		return 0
	if (
		stem.contains("cloud")
		or stem == "moon"
		or stem == "sun"
		or stem.contains("sky_sun")
	):
		return 1
	if (
		stem.ends_with("_bg")
		or stem.contains("sand_back")
		or stem.contains("houses&trees_bg")
		or stem.contains("ground&houses_bg")
		or stem == "ruins"
		or stem.contains("columns")
		or stem.contains("rail")
	):
		return 2
	if (
		stem == "sand"
		or stem == "road"
		or stem.begins_with("ground")
		or stem.begins_with("houses")
		or stem.contains("house")
		or stem.contains("floor")
		or stem.contains("wall")
		or stem.contains("trees")
		or stem.contains("fence")
	):
		return 3
	if (
		stem.contains("sand&objects")
		or stem.contains("object")
		or stem.contains("bird")
		or stem.contains("car")
		or stem.contains("train")
		or stem.contains("wire")
		or stem.contains("wheel")
		or stem.contains("brick")
		or stem.contains("crack")
		or stem.contains("crater")
		or stem.contains("infopost")
	):
		return 4
	return 3


static func _motion_scale_for_index(index: int, count: int) -> float:
	if count <= 1:
		return 1.0
	# Match the live menu curve: near-still sky through full-speed foreground.
	var t := float(index) / float(count - 1)
	return lerpf(0.01, 1.0, t * t)
