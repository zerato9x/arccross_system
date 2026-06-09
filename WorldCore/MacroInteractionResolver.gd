extends RefCounted
class_name MacroInteractionResolver

const SEARCH_KEYS := ["loot", "safety", "sneak"]
const CAMP_KEYS := ["sleep", "shelter", "healing", "concealment", "alertness"]

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
	loot_profile: Dictionary
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
		GameEnums.TalkAction.ROB:
			player_score = (
				float(player_summary.get("threat", 0.0))
				+ float(player_summary.get("brawn", 0.0)) * 0.45
				- 2.0
			)
		GameEnums.TalkAction.CEASEFIRE:
			player_score = (
				float(player_summary.get("finesse", 0.0)) * 0.55
				+ float(player_summary.get("will", 0.0)) * 0.55
			)

	var succeeded := player_score + rng.randf_range(-2.0, 2.0) >= enemy_score
	if not succeeded:
		return GameEnums.NegotiationOutcome.COMBAT

	match action:
		GameEnums.TalkAction.THREAT:
			return GameEnums.NegotiationOutcome.INTIMIDATED
		GameEnums.TalkAction.ROB:
			return GameEnums.NegotiationOutcome.ROB_SUCCESS
		_:
			return GameEnums.NegotiationOutcome.CEASEFIRE
