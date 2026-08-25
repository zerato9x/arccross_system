extends RefCounted
class_name MacroInteractionResolver

## Clothes slots stay with the fleeing NPC. Everything else may drop to ground.
const THREAT_CLOTHES_LOADOUT_KEYS := [
	"inner_torso",
	"outer_torso",
	"legs",
	"feet",
	"head",
	"eyes",
	"face",
	"neck",
	"arms",
]

const THREAT_DROP_LOADOUT_KEYS := [
	"weapon",
	"offhand",
	"vest",
	"backpack_gear",
	"belt",
	"sling",
]

const SEARCH_KEYS := ["loot", "safety", "sneak"]
const CAMP_KEYS := ["sleep", "shelter", "healing", "concealment", "alertness"]

static func build_search_options(
	world_seed: String,
	coords: Vector2i,
	hex_data: MacroHexData
) -> Array:
	var options: Array = []
	if hex_data.world_generation_version >= 2:
		if hex_data.composition_role != "rubble_search":
			return options
		var catalog := SearchSiteCatalog.data()
		var site := (
			catalog.descriptor(hex_data.search_site_id)
			if catalog != null and not hex_data.search_site_id.is_empty()
			else {}
		)
		if site.is_empty():
			options.append(_search_option(
				"wreckage",
				"Picked-over Rubble",
				"A poor, finite pocket of salvage. Once cleared, it stays cleared.",
				{},
				{"loot": -3.0, "safety": -0.5, "sneak": 0.0}
			))
		else:
			options.append(_search_option(
				str(site.get("id", hex_data.search_site_id)),
				str(site.get("label", "Roadside Rubble")),
				str(site.get("description", "Search the roadside debris.")),
				site.get("requirements", {}),
				site.get("metric_modifiers", {})
			))
		return options
	var _seed_signature := (
		world_seed
		+ ":search_options:"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
	)

	options.append(_search_option(
		"surface_sweep",
		"Open Ground Sweep",
		"Loose supplies, tracks, and anything not nailed to civilization's corpse.",
		{},
		{"loot": -1.0, "safety": 1.0, "sneak": 1.0}
	))

	if hex_data.flora_layer == GameEnums.MacroFloraLayer.SHRUBS:
		options.append(_search_option(
			"shrub_cache",
			"Shrub Cache",
			"Check low brush and half-buried containers.",
			{"any_tags": ["tools"], "any_roles": [GameEnums.InteractionItemRole.SEARCH_TOOL]},
			{"loot": 1.0, "safety": -0.5, "sneak": 0.5}
		))
	elif hex_data.flora_layer == GameEnums.MacroFloraLayer.TREES:
		options.append(_search_option(
			"tree_line",
			"Tree Line",
			"Search roots, hanging scraps, and concealed travel traces.",
			{},
			{"loot": 0.5, "safety": 0.5, "sneak": 1.5}
		))

	if hex_data.structure_layer == GameEnums.MacroStructureLayer.STRUCTURES:
		options.append(_search_option(
			"building_shell",
			"Building Shell",
			"Rooms, counters, shelves, and all the places loot designers hide mercy.",
			{},
			{"loot": 1.5, "safety": -1.0, "sneak": -0.5}
		))
		options.append(_search_option(
			"locked_chest",
			"Locked Chest",
			"A sealed container that wants tools, patience, or both.",
			{"any_item_ids": ["crowbar", "multitool", "keys"]},
			{"loot": 3.0, "safety": -1.0, "sneak": -1.0}
		))
		options.append(_search_option(
			"drawers",
			"Drawers",
			"Small storage, office trash, and maybe something sharp enough to matter.",
			{},
			{"loot": 0.75, "safety": 0.0, "sneak": 0.5}
		))
	elif hex_data.structure_layer == GameEnums.MacroStructureLayer.REMNANTS:
		options.append(_search_option(
			"wreckage",
			"Wreckage",
			"Collapsed storage and metal cavities. Extremely normal. Definitely safe.",
			{"any_item_ids": ["crowbar", "multitool"], "any_tags": ["tools"]},
			{"loot": 2.0, "safety": -2.0, "sneak": -1.0}
		))

	if hex_data.rock_layer == GameEnums.MacroRockLayer.HILLS:
		options.append(_search_option(
			"ridge_overlook",
			"Ridge Overlook",
			"Scout the terrain before rummaging through trouble.",
			{"any_item_ids": ["binoculars", "map"]},
			{"loot": -0.5, "safety": 2.0, "sneak": 1.0}
		))

	if hex_data.is_poi:
		options.append(_search_option(
			"poi_core",
			hex_data.poi_name if not hex_data.poi_name.is_empty() else "POI Core",
			"Search the location's main point of interest.",
			{},
			{"loot": 2.0, "safety": -0.5, "sneak": -0.5}
		))

	if hex_data.poi_id in ["alpha_central_hub", "central_core"]:
		options.append(_search_option(
			"activate_core",
			"Activate Alpha Core",
			"Bring the central hub back online and rewrite the wasteland.",
			{},
			{"loot": 0.0, "safety": -3.0, "sneak": -2.0}
		))

	return options

static func build_camp_interactions(
	hex_data: MacroHexData,
	camp_access: Dictionary
) -> Array:
	var allowed := bool(camp_access.get("allowed", false))
	var lock_reason := str(camp_access.get("reason", ""))
	var locked_requirements := {"reason": lock_reason} if not allowed else {}
	var interactions: Array = []
	interactions.append(_camp_interaction(
		"rest",
		"Rest",
		"Recover fatigue using the selected shelter and sleep gear.",
		allowed,
		locked_requirements
	))
	interactions.append(_camp_interaction(
		"install_gear",
		"Install Camp Gear",
		"Place up to three persistent camp items on this hex.",
		allowed,
		locked_requirements
	))
	interactions.append(_camp_interaction(
		"field_treatment",
		"Field Treatment",
		"Convert healing score into limb recovery after rest.",
		allowed,
		locked_requirements
	))
	interactions.append(_camp_interaction(
		"watch",
		"Watch Rotation",
		"Use concealment and alertness to reduce interruption risk.",
		allowed,
		locked_requirements
	))
	if hex_data.region == GameEnums.MacroRegion.CENTRAL_HUB:
		interactions.append(_camp_interaction(
			"hub_safety",
			"Hub Safety",
			"The central hub suppresses hazard and hostile camp interruption.",
			true,
			{}
		))
	return interactions

static func apply_search_option_metrics(
	base_metrics: Dictionary,
	option: Dictionary
) -> Dictionary:
	var metrics := base_metrics.duplicate(true)
	var modifiers: Dictionary = option.get("metric_modifiers", {})
	for key in SEARCH_KEYS:
		metrics[key] = clampf(
			float(metrics.get(key, 0.0)) + float(modifiers.get(key, 0.0)),
			0.0,
			GameEnums.SCALE_MAX
		)
	return metrics

static func find_option(options: Array, option_id: String) -> Dictionary:
	for option in options:
		if str(option.get("id", "")) == option_id:
			return option
	return {}

static func _search_option(
	option_id: String,
	label: String,
	description: String,
	requirements: Dictionary,
	metric_modifiers: Dictionary
) -> Dictionary:
	return {
		"id": option_id,
		"label": label,
		"description": description,
		"requirements": requirements.duplicate(true),
		"metric_modifiers": metric_modifiers.duplicate(true),
		"priority": 0 if requirements.is_empty() else 1,
	}

static func _camp_interaction(
	interaction_id: String,
	label: String,
	description: String,
	available: bool,
	requirements: Dictionary
) -> Dictionary:
	return {
		"id": interaction_id,
		"label": label,
		"description": description,
		"available": available,
		"requirements": requirements.duplicate(true),
	}

static func build_poi_profile(
	world_seed: String,
	coords: Vector2i,
	biome: GameEnums.GridBiome,
	poi_id: String
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":poi_profile:"
		+ poi_id
		+ ":"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
	).hash()

	var shelter_bias := 2.0 if biome == GameEnums.GridBiome.FOREST else 0.0
	var concealment_bias := 2.0 if biome == GameEnums.GridBiome.FOREST else 0.0
	return {
		"search": {
			"loot": rng.randf_range(4.0, 9.0),
			"safety": rng.randf_range(4.0, 9.0),
			"sneak": rng.randf_range(3.0, 9.0),
		},
		"camp": {
			"sleep": rng.randf_range(2.0, 5.0),
			"shelter": clampf(
				rng.randf_range(1.0, 5.0) + shelter_bias,
				0.0,
				GameEnums.SCALE_MAX
			),
			"healing": rng.randf_range(1.0, 3.0),
			"concealment": clampf(
				rng.randf_range(2.0, 6.0) + concealment_bias,
				0.0,
				GameEnums.SCALE_MAX
			),
			"alertness": rng.randf_range(1.0, 4.0),
		},
	}

static func calculate_search_metrics(
	base_metrics: Dictionary,
	tool_descriptors: Array,
	search_count: int,
	max_searches: int = 4
) -> Dictionary:
	var metrics := base_metrics.duplicate(true)
	if search_count >= maxi(1, max_searches):
		metrics["loot"] = 0.0
	else:
		metrics["loot"] = maxf(
			0.0,
			float(metrics.get("loot", 0.0)) - (float(search_count) * 1.5)
		)
	for descriptor in tool_descriptors:
		var bonuses: Dictionary = descriptor.get("search", {})
		for key in SEARCH_KEYS:
			metrics[key] = clampf(
				float(metrics.get(key, 0.0)) + float(bonuses.get(key, 0.0)),
				0.0,
				GameEnums.SCALE_MAX
			)
	return metrics

static func calculate_camp_metrics(
	base_metrics: Dictionary,
	gear_descriptors: Array
) -> Dictionary:
	var metrics := base_metrics.duplicate(true)
	for descriptor in gear_descriptors:
		var bonuses: Dictionary = descriptor.get("camp", {})
		for key in CAMP_KEYS:
			metrics[key] = clampf(
				float(metrics.get(key, 0.0)) + float(bonuses.get(key, 0.0)),
				0.0,
				GameEnums.SCALE_MAX
			)
	return metrics

static func resolve_search(
	world_seed: String,
	coords: Vector2i,
	search_count: int,
	metrics: Dictionary,
	loot_profile: Dictionary,
	target_id: String = ""
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":search:"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
		+ ":"
		+ str(search_count)
		+ ":"
		+ target_id
	).hash()

	var max_searches := int(loot_profile.get("max_searches", 4))
	var max_items := int(loot_profile.get("max_items_per_search", 3))
	var loot_ratio := 0.0
	if search_count < max_searches:
		loot_ratio = clampf(
			float(metrics.get("loot", 0.0)) / GameEnums.SCALE_MAX,
			0.0,
			1.0
		)
	var loot_strength := loot_ratio * float(max_items)
	var loot_count := floori(loot_strength)
	if rng.randf() < loot_strength - float(loot_count):
		loot_count += 1

	var loot_ids: Array[String] = []
	if search_count == 0:
		for guaranteed in loot_profile.get("guaranteed_entries", []):
			var quantity := rng.randi_range(
				maxi(1, int(guaranteed.get("quantity_min", 1))),
				maxi(1, int(guaranteed.get("quantity_max", 1)))
			)
			for _quantity_index in range(quantity):
				loot_ids.append(str(guaranteed.get("item_id", "")))
	for index in range(loot_count):
		var item_id := _roll_weighted_item_id(
			rng,
			loot_profile.get("entries", [])
		)
		if item_id.is_empty():
			break
		loot_ids.append(item_id)

	var safety_ratio := clampf(
		float(metrics.get("safety", 0.0)) / GameEnums.SCALE_MAX,
		0.0,
		1.0
	)
	var sneak_ratio := clampf(
		float(metrics.get("sneak", 0.0)) / GameEnums.SCALE_MAX,
		0.0,
		1.0
	)
	var injured := rng.randf() > safety_ratio
	var attracted_enemy := rng.randf() > sneak_ratio
	var injury_limb := GameEnums.LimbRegion.LEFT_ARM
	if injured:
		var limbs := [
			GameEnums.LimbRegion.LEFT_ARM,
			GameEnums.LimbRegion.RIGHT_ARM,
			GameEnums.LimbRegion.LEFT_LEG,
			GameEnums.LimbRegion.RIGHT_LEG,
			GameEnums.LimbRegion.LOWER_TORSO,
		]
		injury_limb = limbs[rng.randi_range(0, limbs.size() - 1)]

	return {
		"metrics": metrics.duplicate(true),
		"loot_ids": loot_ids,
		"injured": injured,
		"injury_limb": injury_limb,
		"injury_damage": rng.randf_range(0.5, 1.5) if injured else 0.0,
		"attracted_enemy": attracted_enemy,
	}

static func _roll_weighted_item_id(
	rng: RandomNumberGenerator,
	entries: Array
) -> String:
	var total_weight := 0.0
	for entry in entries:
		total_weight += maxf(0.0, float(entry.get("weight", 0.0)))
	if total_weight <= 0.0:
		return ""

	var roll := rng.randf_range(0.0, total_weight)
	for entry in entries:
		roll -= maxf(0.0, float(entry.get("weight", 0.0)))
		if roll <= 0.0:
			return str(entry.get("item_id", ""))
	return str(entries.back().get("item_id", ""))

static func resolve_camp(
	world_seed: String,
	coords: Vector2i,
	rest_count: int,
	metrics: Dictionary
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":camp:"
		+ str(coords.x)
		+ ":"
		+ str(coords.y)
		+ ":"
		+ str(rest_count)
	).hash()

	var sleep := float(metrics.get("sleep", 0.0)) / GameEnums.SCALE_MAX
	var shelter := float(metrics.get("shelter", 0.0)) / GameEnums.SCALE_MAX
	var healing := float(metrics.get("healing", 0.0)) / GameEnums.SCALE_MAX
	var concealment := (
		float(metrics.get("concealment", 0.0)) / GameEnums.SCALE_MAX
	)
	var alertness := (
		float(metrics.get("alertness", 0.0)) / GameEnums.SCALE_MAX
	)
	var intrusion_risk := clampf(
		0.45 - (concealment * 0.25) - (alertness * 0.15),
		0.03,
		0.45
	)

	return {
		"metrics": metrics.duplicate(true),
		"fatigue_recovery": clampf(
			2.0 + (sleep * 7.0) + (shelter * 2.0),
			0.0,
			11.0
		),
		"healing_amount": healing * 2.0,
		"interrupted": rng.randf() < intrusion_risk,
	}

static func resolve_negotiation(
	world_seed: String,
	enemy_id: String,
	attempt: int,
	action: GameEnums.TalkAction,
	player_summary: Dictionary,
	enemy_definition: Dictionary
) -> GameEnums.NegotiationOutcome:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":talk:"
		+ enemy_id
		+ ":"
		+ str(attempt)
		+ ":"
		+ str(action)
	).hash()

	var player_score: float
	var enemy_score := float(enemy_definition.get("will", 6))
	match action:
		GameEnums.TalkAction.THREAT:
			player_score = (
				float(player_summary.get("threat", 0.0))
				+ float(player_summary.get("will", 0.0)) * 0.65
			)
		GameEnums.TalkAction.CEASEFIRE:
			player_score = (
				float(player_summary.get("finesse", 0.0)) * 0.55
				+ float(player_summary.get("will", 0.0)) * 0.55
			)
		_:
			player_score = float(player_summary.get("will", 0.0))

	var succeeded := player_score + rng.randf_range(-2.0, 2.0) >= enemy_score
	if not succeeded:
		return GameEnums.NegotiationOutcome.COMBAT

	match action:
		GameEnums.TalkAction.THREAT:
			return GameEnums.NegotiationOutcome.INTIMIDATED
		_:
			return GameEnums.NegotiationOutcome.CEASEFIRE


static func resolve_threat_surrender(
	world_seed: String,
	enemy_id: String,
	attempt: int,
	enemy_definition: Dictionary,
	loot_catalog: Node
) -> Dictionary:
	if loot_catalog == null or not loot_catalog.has_method(
		"create_runtime_item_from_template_path"
	):
		return {
			"message": "The target flees, abandoning nothing useful.",
			"ground_items": [],
			"kept_loadout": enemy_definition.get("loadout", {}),
		}

	var rng := RandomNumberGenerator.new()
	rng.seed = (
		world_seed
		+ ":threat_drop:"
		+ enemy_id
		+ ":"
		+ str(attempt)
	).hash()

	var loadout: Dictionary = enemy_definition.get("loadout", {}).duplicate(true)
	var ground_items: Array = []
	var dropped_names: PackedStringArray = []
	var kept_loadout: Dictionary = loadout.duplicate(true)

	for key in THREAT_DROP_LOADOUT_KEYS:
		var path := str(loadout.get(key, ""))
		if path.is_empty():
			continue
		# Always dump held weapons / storage carriers when intimidated.
		var drop_chance := 1.0
		if key == "belt" or key == "sling":
			drop_chance = 0.85
		if rng.randf() > drop_chance:
			continue
		var item_state: Dictionary = loot_catalog.create_runtime_item_from_template_path(
			path
		)
		if item_state.is_empty():
			continue
		item_state["instance_id"] = _threat_drop_instance_id(
			world_seed, enemy_id, attempt, "loadout:%s:%s" % [key, path]
		)
		ground_items.append(item_state)
		var item := ItemData.from_runtime_state(item_state)
		dropped_names.append(item.display_name)
		kept_loadout[key] = ""

	var starting_items: Array = loadout.get("starting_items", []).duplicate()
	var kept_starting: Array = []
	for starting_index in range(starting_items.size()):
		var path_value: Variant = starting_items[starting_index]
		var path := str(path_value)
		if path.is_empty():
			continue
		# Loose pack items usually hit the dirt; roll keeps a rare cling.
		if rng.randf() > 0.9:
			kept_starting.append(path)
			continue
		var item_state: Dictionary = loot_catalog.create_runtime_item_from_template_path(
			path
		)
		if item_state.is_empty():
			kept_starting.append(path)
			continue
		item_state["instance_id"] = _threat_drop_instance_id(
			world_seed,
			enemy_id,
			attempt,
			"starting:%d:%s" % [starting_index, path]
		)
		ground_items.append(item_state)
		var item := ItemData.from_runtime_state(item_state)
		dropped_names.append(item.display_name)
	kept_loadout["starting_items"] = kept_starting

	for clothes_key in THREAT_CLOTHES_LOADOUT_KEYS:
		kept_loadout[clothes_key] = loadout.get(clothes_key, "")

	var message: String
	if dropped_names.is_empty():
		message = (
			"The target flees in their clothes, leaving nothing else behind."
		)
	else:
		message = (
			"The target dumps gear and flees. Left on the ground: %s."
			% ", ".join(dropped_names)
		)

	return {
		"message": message,
		"ground_items": ground_items,
		"kept_loadout": kept_loadout,
	}


static func _threat_drop_instance_id(
	world_seed: String,
	enemy_id: String,
	attempt: int,
	slot_identity: String
) -> String:
	var identity := "%s|%s|%d|%s" % [
		world_seed, enemy_id, attempt, slot_identity
	]
	return "item_negotiation_" + identity.sha256_text().substr(0, 24)
