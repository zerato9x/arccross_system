extends SceneTree

const MenuParallaxCatalog := preload("res://PresentationCore/MenuParallaxCatalog.gd")
const EventBgCatalog := preload("res://PresentationCore/EventBgCatalog.gd")
const MacroEventResolver := preload("res://WorldCore/MacroEventResolver.gd")
const MacroEntityCollisionResolver := preload("res://WorldCore/MacroEntityCollisionResolver.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packs: PackedStringArray = MenuParallaxCatalog.available_packs()
	if packs.is_empty():
		_fail("MenuParallaxCatalog found no Event_bg parallax packs.")
		return
	if packs.size() < 10:
		_fail("Expected a broad Event_bg pack set, got %d." % packs.size())
		return

	var plains_present := false
	var numbered_present := false
	var war_present := false
	for pack_dir in packs:
		var layers: Array = MenuParallaxCatalog.layers_for_pack(pack_dir)
		if layers.is_empty():
			_fail("Pack reported available but has no layers: %s" % pack_dir)
			return
		var paths: Array[String] = []
		for layer in layers:
			paths.append(str(layer.get("path", "")).get_file().to_lower())
		if str(pack_dir).contains("Postapocalypce3"):
			plains_present = true
			if not paths.has("sky.png"):
				_fail("Postapocalypce3 pack missing sky.png layer.")
				return
			if paths.has("postapocalypse3.png"):
				_fail("Composite postapocalypse3.png should be skipped.")
				return
		if str(pack_dir).contains("apocalyptic_bg_2") or str(pack_dir).contains("background 3"):
			numbered_present = true
		if str(pack_dir).contains("trees_forest"):
			_fail("trees_forest packs must stay out of the menu pool: %s" % pack_dir)
			return
		if str(pack_dir).contains("war/War"):
			war_present = true
			if paths.has("war.png") or paths.has("war2.png") or paths.has("war3.png") or paths.has("war4.png"):
				_fail("War composite ref should be skipped in %s." % pack_dir)
				return
			if not paths.has("sky.png"):
				_fail("War pack missing sky.png: %s" % pack_dir)
				return
			var near_house := ""
			if paths.has("houses1.png"):
				near_house = "houses1.png"
			elif paths.has("houses2.png"):
				near_house = "houses2.png"
			if not near_house.is_empty() and not _assert_before(paths, "sky.png", near_house, pack_dir):
				return
			if paths.has("houses4.png") and paths.has("houses1.png") \
					and not _assert_before(paths, "houses4.png", "houses1.png", pack_dir):
				return
			if paths.has("houses4.png") and paths.has("houses2.png") \
					and not _assert_before(paths, "houses4.png", "houses2.png", pack_dir):
				return
			if paths.has("houses4.png") and paths.has("houses3.png") \
					and not _assert_before(paths, "houses4.png", "houses3.png", pack_dir):
				return
			if paths.has("fence.png") and not near_house.is_empty() \
					and not _assert_before(paths, near_house, "fence.png", pack_dir):
				return
			if paths.has("wall.png") and not near_house.is_empty() \
					and not _assert_before(paths, near_house, "wall.png", pack_dir):
				return
			if paths.has("wall.png") and paths.has("road.png") \
					and not _assert_before(paths, "wall.png", "road.png", pack_dir):
				return
			if paths.has("trees.png") and paths.has("fence.png") \
					and not _assert_before(paths, "fence.png", "trees.png", pack_dir):
				return
		var first_scale := float(layers[0].get("motion_scale", 1.0))
		var last_scale := float(layers[layers.size() - 1].get("motion_scale", 0.0))
		if first_scale > last_scale:
			_fail("Layer motion scales should increase toward foreground in %s." % pack_dir)
			return
		for layer in layers:
			var path := str(layer.get("path", ""))
			if path.contains("Event_bg") == false:
				_fail("Parallax layer escaped Event_bg: %s" % path)
				return
			if not ResourceLoader.exists(path):
				_fail("Missing parallax texture: %s" % path)
				return

	if not plains_present or not numbered_present or not war_present:
		_fail("Catalog must include named apocalyptic, numbered, and war packs.")
		return
	if DirAccess.open("res://Asset/UI/Event_bg/trees_forest") == null:
		_fail("trees_forest assets should remain on disk for the duel-scene overhaul.")
		return

	var picked: String = MenuParallaxCatalog.pick_random_pack()
	if picked.is_empty() or not packs.has(picked):
		_fail("pick_random_pack returned an invalid pack.")
		return

	if MacroEventResolver.DEFAULT_EVENT_IMAGE.contains("Event_bg"):
		_fail("MacroEventResolver still defaults to Event_bg art.")
		return
	if MacroEntityCollisionResolver.DEFAULT_IMAGE.contains("Event_bg"):
		_fail("MacroEntityCollisionResolver still defaults to Event_bg art.")
		return
	if MacroEventResolver.DEFAULT_EVENT_IMAGE != EventBgCatalog.PLAINS_BG:
		_fail("Event default image should be EventBgCatalog.PLAINS_BG.")
		return
	if MacroEntityCollisionResolver.DEFAULT_IMAGE != EventBgCatalog.PLAINS_BG:
		_fail("Collision default image should be EventBgCatalog.PLAINS_BG.")
		return

	print(
		"[TEST PASS] MenuParallaxCatalog packs=%d random=%s; event/collision unwired from Event_bg."
		% [packs.size(), picked]
	)
	quit(0)


func _assert_before(
	paths: Array[String],
	earlier: String,
	later: String,
	pack_dir: String
) -> bool:
	var earlier_index := paths.find(earlier)
	var later_index := paths.find(later)
	if earlier_index < 0 or later_index < 0:
		_fail("Missing expected war layers %s/%s in %s." % [earlier, later, pack_dir])
		return false
	if earlier_index >= later_index:
		_fail(
			"War layer order wrong in %s: %s should be behind %s (got %s)."
			% [pack_dir, earlier, later, ", ".join(paths)]
		)
		return false
	return true


func _fail(message: String) -> void:
	push_error("[TEST FAIL] %s" % message)
	quit(1)
