extends RefCounted
class_name SiteCatalog

## Place-centric site data for the exploration stage.
## Fixtures own verbs (search / sleep / trap). Rooms group fixtures for UI.
## `rooms` with extra entries is the extension point for later story sub-nodes
## (deeper multi-room sites) without a second empty hex board.
##
## Scale: fixtures describe one neighborhood parcel (~450 m pitch), not a
## continent. Quiet hexes stay 1–3 fixtures; stamped POIs keep landmark density.

const VERB_SEARCH := "search"
const VERB_SLEEP := "sleep"
const VERB_TRAP := "trap"
const VERB_INSTALL_RELICS := "install_relics"

const HOMESTEAD_LANDMARKS := ["homestead_b", "homestead_d", "plains_homestead", "plains_homestead_d"]


static func site_for_hex(
	hex_data: MacroHexData,
	search_options: Array,
	camp_access: Dictionary,
	world_seed: String,
	coords: Vector2i
) -> Dictionary:
	var site: Dictionary = {}
	if hex_data.world_generation_version >= 2 and hex_data.composition_role == "settlement_anchor":
		site = _starter_settlement_site(hex_data, camp_access)
		return _with_route_objective_fixture(site, hex_data)
	var landmark_id := (
		hex_data.landmark_id
		if not hex_data.landmark_id.is_empty()
		else hex_data.poi_id
	)
	if _is_homestead(landmark_id, hex_data.poi_id):
		site = _homestead_site(hex_data, search_options, camp_access, world_seed, coords)
		return _with_route_objective_fixture(site, hex_data)
	if hex_data.has_landmark() or hex_data.is_poi:
		site = _generic_landmark_site(hex_data, search_options, camp_access, landmark_id)
		return _with_route_objective_fixture(site, hex_data)
	return _parcel_site(hex_data, search_options, camp_access, world_seed, coords)


static func _with_route_objective_fixture(site: Dictionary, hex_data: MacroHexData) -> Dictionary:
	var catalog := RouteObjectiveCatalog.data()
	var objective := catalog.for_poi(hex_data.poi_id) if catalog != null else null
	if objective == null:
		return site
	var fixtures: Array = site.get("fixtures", []).duplicate(true)
	var fixture := _fixture(
		objective.turn_in_fixture_id,
		str(site.get("rooms", [{"id": "main"}])[0].get("id", "main")),
		"Relay Control Cabinet",
		"Install all three recovered relay relics to clear the northern road.",
		[VERB_INSTALL_RELICS],
		"",
		Vector2(0.66, 0.40),
		[],
		0.0,
		{"allowed": true, "reason": ""}
	)
	fixture["objective_id"] = objective.objective_id
	fixture["required_item_ids"] = Array(objective.required_item_ids)
	fixtures.append(fixture)
	site["fixtures"] = fixtures
	return site


static func _starter_settlement_site(hex_data: MacroHexData, camp_access: Dictionary) -> Dictionary:
	return {
		"site_id": "starter_settlement_v2",
		"display_name": hex_data.poi_name,
		"rooms": [_room("commons", "Settlement Commons", false)],
		"fixtures": [
			_fixture(
				"settlement_sleep_spot", "commons", "Guest Cot",
				"A guarded cot beside the wayfinder's post.", [VERB_SLEEP], "",
				Vector2(0.50, 0.68), [GameEnums.InteractionItemRole.CAMP_GEAR], 1.0, camp_access
			),
			_fixture(
				"settlement_perimeter", "commons", "Roadside Perimeter",
				"The old paved approach is the settlement's only clear sightline.", [VERB_TRAP], "",
				Vector2(0.76, 0.58), [GameEnums.InteractionItemRole.TRAP_GEAR], 0.0, camp_access
			),
		],
		"supports_story_rooms": false,
		"story_rooms_deferred": true,
	}


static func fixture_by_id(site: Dictionary, fixture_id: String) -> Dictionary:
	for fixture in site.get("fixtures", []):
		if fixture is Dictionary and str(fixture.get("id", "")) == fixture_id:
			return fixture
	return {}


static func rooms_for_site(site: Dictionary) -> Array:
	return site.get("rooms", [])


static func fixtures_in_room(site: Dictionary, room_id: String) -> Array:
	var out: Array = []
	for fixture in site.get("fixtures", []):
		if not fixture is Dictionary:
			continue
		if str(fixture.get("room_id", "")) == room_id:
			out.append(fixture)
	return out


static func searchable_fixtures(site: Dictionary) -> Array:
	var out: Array = []
	for fixture in site.get("fixtures", []):
		if not fixture is Dictionary:
			continue
		if VERB_SEARCH in fixture.get("verbs", []):
			out.append(fixture)
	return out


static func _is_homestead(landmark_id: String, poi_id: String) -> bool:
	if landmark_id in HOMESTEAD_LANDMARKS:
		return true
	if poi_id in HOMESTEAD_LANDMARKS:
		return true
	return landmark_id.begins_with("homestead") or poi_id.begins_with("plains_homestead")


static func _homestead_site(
	hex_data: MacroHexData,
	search_options: Array,
	camp_access: Dictionary,
	_world_seed: String,
	_coords: Vector2i
) -> Dictionary:
	## Hero site: proves fixture+verb presence. Extra rooms reserved for later story beats.
	## Search option IDs must match landmark session options (structure_N / event_*),
	## not MacroInteractionResolver wilderness ids.
	var search_ids := _assign_distinct_search_ids(
		search_options,
		[
			["structure_0", "drawers", "poi_core", "building_shell", "primary_search", "surface_sweep"],
			["structure_1", "locked_chest", "building_shell", "drawers", "primary_search"],
			["structure_2", "building_shell", "poi_core", "surface_sweep", "primary_search"],
		]
	)
	var rooms: Array = [
		_room("bedroom", "Bedroom", false),
		_room("kitchen", "Kitchen", false),
		_room("yard", "Yard", false),
		## Deferred story capacity — not shown until authored content fills them.
		_room("cellar", "Cellar", true),
		_room("attic", "Attic", true),
	]
	var fixtures: Array = [
		_fixture(
			"bedroom_bed",
			"bedroom",
			"Bed",
			"A warped mattress. Search the frame, or sleep if you dare.",
			[VERB_SEARCH, VERB_SLEEP],
			search_ids[0] if search_ids.size() > 0 else "",
			Vector2(0.28, 0.55),
			[GameEnums.InteractionItemRole.CAMP_GEAR, GameEnums.InteractionItemRole.SEARCH_TOOL],
			1.2,
			camp_access
		),
		_fixture(
			"bedroom_wardrobe",
			"bedroom",
			"Wardrobe",
			"Doors hang open. Something still rattles inside.",
			[VERB_SEARCH],
			search_ids[1] if search_ids.size() > 1 else (search_ids[0] if search_ids.size() > 0 else ""),
			Vector2(0.42, 0.48),
			[GameEnums.InteractionItemRole.SEARCH_TOOL],
			0.0,
			camp_access
		),
		_fixture(
			"kitchen_cupboard",
			"kitchen",
			"Cupboards",
			"Grease, rust, and maybe a tin that hasn't spoiled.",
			[VERB_SEARCH],
			search_ids[2] if search_ids.size() > 2 else (search_ids[0] if search_ids.size() > 0 else ""),
			Vector2(0.58, 0.52),
			[GameEnums.InteractionItemRole.SEARCH_TOOL],
			0.0,
			camp_access
		),
		_fixture(
			"kitchen_floor",
			"kitchen",
			"Floor",
			"Cold boards. Sleep here if the bed is worse — or drop a bedroll.",
			[VERB_SLEEP],
			"",
			Vector2(0.62, 0.68),
			[GameEnums.InteractionItemRole.CAMP_GEAR],
			0.45,
			camp_access
		),
		_fixture(
			"yard_door",
			"yard",
			"Door Frame",
			"Arm a trap on the frame before you rest.",
			[VERB_TRAP],
			"",
			Vector2(0.78, 0.58),
			[GameEnums.InteractionItemRole.TRAP_GEAR],
			0.0,
			camp_access
		),
		_fixture(
			"yard_brush",
			"yard",
			"Brush Line",
			"Low scrub along the approach. Good for a second trap.",
			[VERB_TRAP],
			"",
			Vector2(0.88, 0.62),
			[GameEnums.InteractionItemRole.TRAP_GEAR],
			0.0,
			camp_access
		),
	]
	return {
		"site_id": "homestead_hero",
		"display_name": (
			hex_data.poi_name if not hex_data.poi_name.is_empty() else "Abandoned Homestead"
		),
		"rooms": rooms,
		"fixtures": fixtures,
		"supports_story_rooms": true,
		"story_rooms_deferred": true,
	}


static func _generic_landmark_site(
	hex_data: MacroHexData,
	search_options: Array,
	camp_access: Dictionary,
	landmark_id: String
) -> Dictionary:
	var rooms: Array = [_room("main", "Main", false)]
	var fixtures: Array = []
	var index := 0
	for option in search_options:
		if not option is Dictionary:
			continue
		var option_id := str(option.get("id", ""))
		if option_id.is_empty() or option_id == "activate_core":
			continue
		var anchor := Vector2(0.28 + 0.18 * float(index % 3), 0.50 + 0.08 * float(int(index / 3)))
		fixtures.append(_fixture(
			"search_%s" % option_id,
			"main",
			str(option.get("label", option_id)),
			str(option.get("description", "Search this spot.")),
			[VERB_SEARCH],
			option_id,
			anchor,
			[GameEnums.InteractionItemRole.SEARCH_TOOL],
			0.0,
			camp_access
		))
		index += 1
	fixtures.append(_fixture(
		"sleep_spot",
		"main",
		"Sleep Spot",
		"Rest here if the site is safe enough.",
		[VERB_SLEEP],
		"",
		Vector2(0.50, 0.72),
		[GameEnums.InteractionItemRole.CAMP_GEAR],
		1.0,
		camp_access
	))
	fixtures.append(_fixture(
		"trap_line",
		"main",
		"Approach",
		"Set a trap on the approach before you sleep.",
		[VERB_TRAP],
		"",
		Vector2(0.78, 0.60),
		[GameEnums.InteractionItemRole.TRAP_GEAR],
		0.0,
		camp_access
	))
	return {
		"site_id": "landmark_%s" % landmark_id,
		"display_name": (
			hex_data.poi_name if not hex_data.poi_name.is_empty() else landmark_id.capitalize()
		),
		"rooms": rooms,
		"fixtures": fixtures,
		"supports_story_rooms": false,
		"story_rooms_deferred": true,
	}


static func _parcel_site(
	hex_data: MacroHexData,
	search_options: Array,
	camp_access: Dictionary,
	world_seed: String,
	coords: Vector2i
) -> Dictionary:
	## Quiet neighborhood parcel: 1–3 fixtures. Do not densify every cell.
	var rooms: Array = [_room("parcel", "Parcel", false)]
	var fixtures: Array = []
	var search_ids := _parcel_search_ids(search_options, world_seed, coords)
	for index in range(search_ids.size()):
		var option_id: String = search_ids[index]
		var option := _option_by_id(search_options, option_id)
		var anchor := Vector2(0.32 + 0.18 * float(index), 0.52 + 0.04 * float(index % 2))
		fixtures.append(_fixture(
			"parcel_search_%s" % option_id,
			"parcel",
			str(option.get("label", option_id.replace("_", " ").capitalize())),
			str(option.get(
				"description",
				"Check this stretch of the parcel for salvage."
			)),
			[VERB_SEARCH],
			option_id,
			anchor,
			[GameEnums.InteractionItemRole.SEARCH_TOOL],
			0.0,
			camp_access
		))
	fixtures.append(_fixture(
		"sleep_spot",
		"parcel",
		"Sleep Spot",
		"Lay out gear and rest on this parcel.",
		[VERB_SLEEP],
		"",
		Vector2(0.50, 0.70),
		[GameEnums.InteractionItemRole.CAMP_GEAR],
		0.7,
		camp_access
	))
	fixtures.append(_fixture(
		"trap_line",
		"parcel",
		"Perimeter",
		"Trap the brush line before you sleep.",
		[VERB_TRAP],
		"",
		Vector2(0.74, 0.58),
		[GameEnums.InteractionItemRole.TRAP_GEAR],
		0.0,
		camp_access
	))
	## Prefer one search + sleep + trap (3 fixtures) for quiet parcels.
	if fixtures.size() > 3:
		var preferred: Array = []
		for fixture in fixtures:
			if not fixture is Dictionary:
				continue
			var fid := str(fixture.get("id", ""))
			if fid.begins_with("parcel_search_") and preferred.is_empty():
				preferred.append(fixture)
			elif fid == "sleep_spot" or fid == "trap_line":
				preferred.append(fixture)
		if preferred.size() >= 2:
			fixtures = preferred
	return {
		"site_id": "parcel_ground",
		"display_name": "Neighborhood Parcel",
		"rooms": rooms,
		"fixtures": fixtures,
		"supports_story_rooms": false,
		"story_rooms_deferred": true,
	}


static func _parcel_search_ids(
	search_options: Array,
	world_seed: String,
	coords: Vector2i
) -> Array[String]:
	var available := _available_search_ids(search_options)
	if available.is_empty():
		return []
	var rng := RandomNumberGenerator.new()
	rng.seed = (world_seed + ":parcel_fixtures:" + str(coords)).hash()
	## Quiet parcels: usually one searchable spot; occasionally two.
	var count := 1 if rng.randf() < 0.72 else 2
	count = mini(count, available.size())
	var preferred := [
		"surface_sweep",
		"shrub_cache",
		"tree_line",
		"wreckage",
		"ridge_overlook",
	]
	var picked: Array[String] = []
	for option_id in preferred:
		if available.has(option_id) and not picked.has(option_id):
			picked.append(option_id)
		if picked.size() >= count:
			return picked
	for option_id in available.keys():
		if not picked.has(str(option_id)):
			picked.append(str(option_id))
		if picked.size() >= count:
			break
	return picked


static func _room(room_id: String, label: String, deferred: bool) -> Dictionary:
	return {
		"id": room_id,
		"label": label,
		"deferred": deferred,
	}


static func _fixture(
	fixture_id: String,
	room_id: String,
	label: String,
	description: String,
	verbs: Array,
	search_option_id: String,
	anchor: Vector2,
	accepted_roles: Array,
	sleep_quality: float,
	camp_access: Dictionary
) -> Dictionary:
	var verb_list: Array = []
	for verb in verbs:
		verb_list.append(verb)
	if verb_list.is_empty() and VERB_SEARCH in verbs:
		verb_list.append(VERB_SEARCH)
	return {
		"id": fixture_id,
		"room_id": room_id,
		"label": label,
		"description": description,
		"verbs": verb_list,
		"search_option_id": search_option_id,
		"anchor": anchor,
		"accepted_roles": accepted_roles,
		"sleep_quality": sleep_quality,
		"minutes_search": GameTimeRules.SEARCH_MINUTES,
		"minutes_sleep_preview": GameTimeRules.CAMP_MINUTES,
		"sleep_blocked": (
			VERB_SLEEP in verb_list and not bool(camp_access.get("allowed", false))
		),
		"sleep_block_reason": str(camp_access.get("reason", "")),
	}


static func _pick_search_id(search_options: Array, preferred: Array) -> String:
	var available := _available_search_ids(search_options)
	for option_id in preferred:
		if available.has(str(option_id)):
			return str(option_id)
	for option_id in available.keys():
		return str(option_id)
	return ""


static func _assign_distinct_search_ids(
	search_options: Array,
	preferred_batches: Array
) -> Array[String]:
	var available := _available_search_ids(search_options)
	var used: Dictionary = {}
	var assigned: Array[String] = []
	for batch in preferred_batches:
		if not batch is Array:
			continue
		var chosen := ""
		for option_id in batch:
			var key := str(option_id)
			if available.has(key) and not used.has(key):
				chosen = key
				break
		if chosen.is_empty():
			for option_id in available.keys():
				if not used.has(str(option_id)):
					chosen = str(option_id)
					break
		if chosen.is_empty():
			continue
		used[chosen] = true
		assigned.append(chosen)
	return assigned


static func _available_search_ids(search_options: Array) -> Dictionary:
	var available: Dictionary = {}
	for option in search_options:
		if not option is Dictionary:
			continue
		var option_id := str(option.get("id", ""))
		if option_id.is_empty() or option_id == "activate_core":
			continue
		available[option_id] = true
	return available


static func _option_by_id(search_options: Array, option_id: String) -> Dictionary:
	for option in search_options:
		if option is Dictionary and str(option.get("id", "")) == option_id:
			return option
	return {}
