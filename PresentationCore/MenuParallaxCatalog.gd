extends RefCounted
class_name MenuParallaxCatalog

## Discovers Event_bg parallax packs and builds ordered layer lists for the main menu.
## Packs stay under Asset/UI/Event_bg; gameplay event/collision art uses HexTiles instead.
## Draw order is back-to-front: index 0 is farthest (sky), last index is closest (props).

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

## Explicit back-to-front stems for War packs (matches War.png / WarN.png refs).
## Named-depth heuristics alone put houses1 before houses4 and fence before houses.
const _WAR_LAYER_ORDERS := {
	"war/War1": [
		"sky",
		"sun",
		"ruins",
		"house3",
		"houses2",
		"houses1",
		"fence",
		"road",
		"crater1",
		"crater2",
		"crater3",
	],
	"war/War2": [
		"sky",
		"houses4",
		"houses3",
		"houses2",
		"houses1",
		"wall",
		"road",
		"cracks1",
		"cracks2",
	],
	"war/War3": [
		"sky",
		"sky_sun",
		"houses3",
		"houses2",
		"house&fountain",
		"fence",
		"trees",
		"road",
		"bricks1",
		"bricks2",
		"bricks3",
	],
	"war/War4": [
		"sky",
		"moon",
		"houses4",
		"houses2",
		"houses3",
		"houses1",
		"wall",
		"road",
		"wheels",
		"wheels2",
		"wheels3",
	],
}


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
	# trees_forest stays on disk for a later duel-scene overhaul; not in the menu pool.
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
	var explicit_order := _explicit_order_for_pack(pack_dir)
	if numbered:
		# Numbered packs: 1.png is farthest / bottom, highest number is closest / top.
		sortable.sort_custom(func(a: String, b: String) -> bool:
			return a.to_int() < b.to_int()
		)
	elif not explicit_order.is_empty():
		sortable.sort_custom(func(a: String, b: String) -> bool:
			var index_a := _explicit_index(explicit_order, a)
			var index_b := _explicit_index(explicit_order, b)
			if index_a == index_b:
				return a < b
			return index_a < index_b
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


static func _explicit_order_for_pack(pack_dir: String) -> PackedStringArray:
	var normalized := pack_dir.replace("\\", "/")
	for key in _WAR_LAYER_ORDERS.keys():
		if normalized.contains(str(key)):
			return PackedStringArray(_WAR_LAYER_ORDERS[key])
	return PackedStringArray()


static func _explicit_index(order: PackedStringArray, file_name: String) -> int:
	var stem := file_name.get_basename().to_lower()
	for index in range(order.size()):
		if str(order[index]).to_lower() == stem:
			return index
	# Unknown layers sort after authored ones, still before nothing.
	return order.size() + stem.hash() % 1000


static func _named_depth_score(file_name: String) -> int:
	var stem := file_name.get_basename().to_lower()
	# Celestial / sky glow must not match the bare sky bucket via sky_* prefix.
	if stem == "sky_sun" or stem == "sun" or stem == "moon" or stem.contains("cloud"):
		return 10
	if stem == "sky" or stem == "bg":
		return 0
	if (
		stem.ends_with("_bg")
		or stem.contains("sand_back")
		or stem.contains("houses&trees_bg")
		or stem.contains("ground&houses_bg")
		or stem == "ruins"
		or stem.contains("columns")
		or stem.contains("rail")
	):
		return 20
	# houses4 / house3 are farther than houses1 in the War refs.
	if stem.begins_with("houses") or stem.begins_with("house"):
		var house_num := _trailing_int(stem)
		if house_num > 0:
			return 30 + (10 - clampi(house_num, 1, 9))
		return 34
	if stem.contains("floor"):
		return 40
	if stem == "sand" or stem.begins_with("ground"):
		return 45
	if stem.contains("fence") or stem == "wall" or stem.contains("trees"):
		return 50
	if stem == "road":
		return 55
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
		return 60
	return 40


static func _trailing_int(stem: String) -> int:
	var digits := ""
	for index in range(stem.length() - 1, -1, -1):
		var ch := stem.substr(index, 1)
		if ch.is_valid_int():
			digits = ch + digits
		elif not digits.is_empty():
			break
	if digits.is_empty():
		return 0
	return digits.to_int()


static func _motion_scale_for_index(index: int, count: int) -> float:
	if count <= 1:
		return 1.0
	# Match the live menu curve: near-still sky through full-speed foreground.
	var t := float(index) / float(count - 1)
	return lerpf(0.01, 1.0, t * t)
