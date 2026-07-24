extends RefCounted
class_name SiteCatalog

## Place-centric site data for the exploration stage.
## Fixtures own verbs (search / sleep / trap). Rooms group fixtures for UI.
## `rooms` with extra entries is the extension point for later story sub-nodes
## (deeper multi-room sites) without a second empty hex board.

const VERB_SEARCH := "search"
const VERB_SLEEP := "sleep"
const VERB_TRAP := "trap"

const HOMESTEAD_LANDMARKS := ["homestead_b", "homestead_d", "plains_homestead", "plains_homestead_d"]


static func site_for_hex(
	hex_data: MacroHexData,
	search_options: Array,
	camp_access: Dictionary,
	world_seed: String,
	coords: Vector2i
) -> Dictionary:
	var landmark_id := (
		hex_data.landmark_id
		if not hex_data.landmark_id.is_empty()
		else hex_data.poi_id
	)
	if _is_homestead(landmark_id, hex_data.poi_id):
		return _homestead_site(hex_data, search_options, camp_access, world_seed, coords)
	if hex_data.has_landmark() or hex_data.is_poi:
		return _generic_landmark_site(hex_data, search_options, camp_access, landmark_id)
	return _camp_only_site(hex_data, camp_access)


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
			_pick_search_id(search_options, ["drawers", "poi_core", "building_shell", "surface_sweep"]),
			Vector2(0.28, 0.55),
			[GameEnums.InteractionItemRole.CAMP_GEAR],
			1.2,
			camp_access
		),
		_fixture(
			"bedroom_wardrobe",
			"bedroom",
			"Wardrobe",
			"Doors hang open. Something still rattles inside.",
			[VERB_SEARCH],
			_pick_search_id(search_options, ["drawers", "locked_chest", "building_shell"]),
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
			_pick_search_id(search_options, ["building_shell", "poi_core", "surface_sweep"]),
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
		var anchor := Vector2(0.28 + 0.18 * float(index % 3), 0.50 + 0.08 * float(index / 3))
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


static func _camp_only_site(hex_data: MacroHexData, camp_access: Dictionary) -> Dictionary:
	return {
		"site_id": "wilderness_camp",
		"display_name": "Open Ground",
		"rooms": [_room("camp", "Camp", false)],
		"fixtures": [
			_fixture(
				"sleep_spot",
				"camp",
				"Sleep Spot",
				"Lay out gear and rest under open sky.",
				[VERB_SLEEP],
				"",
				Vector2(0.5, 0.65),
				[GameEnums.InteractionItemRole.CAMP_GEAR],
				0.7,
				camp_access
			),
			_fixture(
				"trap_line",
				"camp",
				"Perimeter",
				"Trap the brush line before you sleep.",
				[VERB_TRAP],
				"",
				Vector2(0.72, 0.58),
				[GameEnums.InteractionItemRole.TRAP_GEAR],
				0.0,
				camp_access
			),
		],
		"supports_story_rooms": false,
		"story_rooms_deferred": true,
	}


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
		if verb == VERB_SLEEP and not bool(camp_access.get("allowed", false)):
			continue
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
	}


static func _pick_search_id(search_options: Array, preferred: Array) -> String:
	var available: Dictionary = {}
	for option in search_options:
		if option is Dictionary:
			available[str(option.get("id", ""))] = true
	for option_id in preferred:
		if available.has(str(option_id)):
			return str(option_id)
	for option in search_options:
		if not option is Dictionary:
			continue
		var option_id := str(option.get("id", ""))
		if option_id.is_empty() or option_id == "activate_core":
			continue
		return option_id
	return "surface_sweep"
