extends SceneTree

const SiteCatalog := preload("res://WorldCore/SiteCatalog.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _verify_scale():
		return
	if not _verify_homestead_site():
		return
	if not _verify_story_rooms_deferred():
		return
	if not _verify_collision_presence():
		return
	print("[TEST PASS] SiteCatalog homestead fixtures, deferred story rooms, scale, collision presence.")
	quit(0)


func _verify_scale() -> bool:
	if GameTimeRules.ACTION_MINUTES != 15 or GameTimeRules.MOVE_MINUTES != 15:
		return _fail("15-minute action atom not locked.")
	if GameTimeRules.SEARCH_MINUTES != 30:
		return _fail("SEARCH_MINUTES should be two action atoms (30).")
	if absf(GameTimeRules.HEX_CENTER_DISTANCE_KM - 0.45) > 0.001:
		return _fail("HEX_CENTER_DISTANCE_KM should be 0.45.")
	return true


func _verify_homestead_site() -> bool:
	var hex := MacroHexData.new()
	hex.landmark_id = "homestead_b"
	hex.poi_id = "plains_homestead"
	hex.poi_name = "Abandoned Homestead"
	hex.is_poi = true
	hex.structure_layer = GameEnums.MacroStructureLayer.STRUCTURES
	var options := MacroInteractionResolver.build_search_options("SITE_SMOKE", Vector2i(3, 1), hex)
	var site := SiteCatalog.site_for_hex(
		hex,
		options,
		{"allowed": true, "reason": ""},
		"SITE_SMOKE",
		Vector2i(3, 1)
	)
	if str(site.get("site_id", "")) != "homestead_hero":
		return _fail("Homestead landmark did not resolve to homestead_hero site.")
	var fixtures: Array = site.get("fixtures", [])
	if fixtures.size() < 5:
		return _fail("Homestead site needs multiple fixtures, got %d." % fixtures.size())
	var bed := SiteCatalog.fixture_by_id(site, "bedroom_bed")
	if bed.is_empty():
		return _fail("bedroom_bed fixture missing.")
	var verbs: Array = bed.get("verbs", [])
	if not verbs.has(SiteCatalog.VERB_SEARCH) or not verbs.has(SiteCatalog.VERB_SLEEP):
		return _fail("Bed must support Search and Sleep.")
	var kitchen_floor := SiteCatalog.fixture_by_id(site, "kitchen_floor")
	if kitchen_floor.is_empty() or not kitchen_floor.get("verbs", []).has(SiteCatalog.VERB_SLEEP):
		return _fail("Kitchen floor must be a sleep verb fixture.")
	return true


func _verify_story_rooms_deferred() -> bool:
	var hex := MacroHexData.new()
	hex.landmark_id = "homestead_b"
	hex.poi_id = "plains_homestead"
	hex.is_poi = true
	var site := SiteCatalog.site_for_hex(
		hex,
		[],
		{"allowed": true, "reason": ""},
		"SITE_SMOKE",
		Vector2i.ZERO
	)
	if not bool(site.get("supports_story_rooms", false)):
		return _fail("Homestead must advertise story room capacity.")
	if not bool(site.get("story_rooms_deferred", false)):
		return _fail("Story rooms must remain deferred until authored.")
	var deferred := 0
	var active := 0
	for room in site.get("rooms", []):
		if not room is Dictionary:
			continue
		if bool(room.get("deferred", false)):
			deferred += 1
		else:
			active += 1
	if active < 3:
		return _fail("Expected active Bedroom/Kitchen/Yard rooms.")
	if deferred < 2:
		return _fail("Expected deferred Cellar/Attic story rooms.")
	return true


func _verify_collision_presence() -> bool:
	var record := EntityRecord.new()
	record.entity_id = "smoke_enemy"
	record.definition = {"archetype_name": "Dust Runner"}
	var session := MacroEntityCollisionResolver.build_root_session(record)
	if not bool(session.get("place_presence", false)):
		return _fail("Collision session missing place_presence.")
	if not bool(session.get("walk_in", false)):
		return _fail("Root collision session missing walk_in.")
	if str(session.get("meet_label", "")).is_empty():
		return _fail("Collision session missing meet_label.")
	return true


func _fail(message: String) -> bool:
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
