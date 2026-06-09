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

	var shelter_bias := 5.0 if biome == GameEnums.GridBiome.FOREST else 0.0
	var concealment_bias := 4.0 if biome == GameEnums.GridBiome.FOREST else 0.0
	return {
		"search": {
			"loot": rng.randf_range(0.35, 0.72),
			"safety": rng.randf_range(0.32, 0.78),
			"sneak": rng.randf_range(0.28, 0.75),
		},
		"camp": {
			"sleep": rng.randf_range(4.0, 10.0),
			"shelter": clampf(rng.randf_range(3.0, 12.0) + shelter_bias, 0.0, 27.0),
			"healing": rng.randf_range(2.0, 7.0),
			"concealment": clampf(
				rng.randf_range(4.0, 13.0) + concealment_bias,
				0.0,
				27.0
			),
			"alertness": rng.randf_range(2.0, 8.0),
		},
	}

static func calculate_search_metrics(
	base_metrics: Dictionary,
	tool_descriptors: Array,
	search_count: int
) -> Dictionary:
	var metrics := base_metrics.duplicate(true)
	metrics["loot"] = maxf(
		0.05,
		float(metrics.get("loot", 0.0)) - (float(search_count) * 0.12)
	)
	for descriptor in tool_descriptors:
		var bonuses: Dictionary = descriptor.get("search", {})
		for key in SEARCH_KEYS:
			metrics[key] = clampf(
				float(metrics.get(key, 0.0)) + float(bonuses.get(key, 0.0)),
				0.0,
				1.0
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
				27.0
			)
	return metrics

static func resolve_search(
	world_seed: String,
	coords: Vector2i,
	search_count: int,
	metrics: Dictionary,
	loot_pool: Array[String]
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

	var loot_strength := float(metrics.get("loot", 0.0)) * 3.0
	var loot_count := floori(loot_strength)
	if rng.randf() < loot_strength - float(loot_count):
		loot_count += 1

	var loot_ids: Array[String] = []
	for index in range(loot_count):
		if loot_pool.is_empty():
			break
		loot_ids.append(loot_pool[rng.randi_range(0, loot_pool.size() - 1)])

	var injured := rng.randf() > float(metrics.get("safety", 0.0))
	var attracted_enemy := rng.randf() > float(metrics.get("sneak", 0.0))
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
		"injury_damage": rng.randf_range(2.0, 6.0) if injured else 0.0,
		"attracted_enemy": attracted_enemy,
	}

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

	var sleep := float(metrics.get("sleep", 0.0)) / 27.0
	var shelter := float(metrics.get("shelter", 0.0)) / 27.0
	var healing := float(metrics.get("healing", 0.0)) / 27.0
	var concealment := float(metrics.get("concealment", 0.0)) / 27.0
	var alertness := float(metrics.get("alertness", 0.0)) / 27.0
	var intrusion_risk := clampf(
		0.45 - (concealment * 0.25) - (alertness * 0.15),
		0.03,
		0.45
	)

	return {
		"metrics": metrics.duplicate(true),
		"fatigue_recovery": clampf(0.2 + (sleep * 0.55) + (shelter * 0.15), 0.0, 0.9),
		"healing_amount": healing * 8.0,
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
