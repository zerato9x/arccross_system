extends RefCounted
class_name CombatForecastService

## Deterministic, snapshot-only attack forecasting. It intentionally consumes
## dictionaries from CombatRulesState so live and projected quotes share the
## same forecast math without borrowing the resolution RNG.

static func build(
	request: CombatActionRequest,
	definition: CombatActionDefinition,
	attacker: Dictionary,
	defender: Dictionary,
	rules_state,
	action_quote: CombatActionQuote
) -> CombatForecastRecord:
	var forecast := CombatForecastRecord.new()
	if request == null or definition == null or not definition.is_weapon_action():
		return forecast
	if defender.is_empty() or rules_state == null:
		return forecast
	var is_melee := definition.is_melee_weapon_action()
	var region := GameEnums.LimbRegion.UPPER_TORSO
	forecast.target_body_region = -1
	if definition.targeting_profile != null:
		forecast.probable_body_regions = definition.targeting_profile.weighted_regions()
	var effect := definition.effect_profile
	var accuracy_modifier := effect.accuracy_modifier if effect != null else 0.0
	var origin := action_quote.projected_origin
	var target_sector: Vector2i = defender.get("sector", Vector2i(-1, -1))
	var distance := maxi(0, _distance(origin, target_sector))
	var weapon: Dictionary = attacker.get("melee_weapon" if is_melee else "ranged_weapon", {})
	if weapon.is_empty():
		weapon = attacker.get("weapon", {})
	if is_melee:
		forecast.hit_probability = _melee_hit_chance(attacker, weapon, accuracy_modifier)
	else:
		forecast.hit_probability = _ranged_hit_chance(attacker, weapon, distance, target_sector, accuracy_modifier, action_quote)
	if weapon.is_empty():
		forecast.bleeding_risk = "low"
		forecast.severe_wound_risk = _risk_band(2.0 * forecast.hit_probability)
		return forecast
	var damage_type := int(weapon.get("damage_type", GameEnums.DamageType.BLUNT))
	var protection := _armor_protection(defender, damage_type, region)
	var penetration := float(weapon.get("armor_penetration", 0.0))
	if effect != null:
		penetration += effect.penetration_modifier
	forecast.armor_penetration = penetration
	forecast.armor_protection = protection
	forecast.armor_result = _armor_result(penetration, protection)
	var multiplier := effect.damage_multiplier if effect != null else 1.0
	var raw_damage := maxf(0.0, float(weapon.get("flesh_damage", 0.0)) * multiplier)
	var post_armor := maxf(0.05, raw_damage - maxf(0.0, protection - float(weapon.get("armor_penetration", 0.0))) * 0.5)
	forecast.expected_post_armor_trauma = post_armor * forecast.hit_probability
	forecast.expected_wound_severity = forecast.expected_post_armor_trauma
	var bleed_multiplier := 1.2 if damage_type in [GameEnums.DamageType.SHARP, GameEnums.DamageType.BALLISTIC] else 0.35
	forecast.bleeding_pressure = forecast.expected_post_armor_trauma * bleed_multiplier
	var incapacity_multiplier := 1.35 if region in [GameEnums.LimbRegion.HEAD, GameEnums.LimbRegion.UPPER_TORSO] else 0.55
	forecast.incapacity_probability = clampf(
		forecast.expected_post_armor_trauma * incapacity_multiplier / 6.0,
		0.0,
		1.0
	)
	forecast.severe_wound_risk = _risk_band(forecast.expected_wound_severity)
	forecast.incapacity_risk = _risk_band(forecast.incapacity_probability * 4.0)
	forecast.bleeding_risk = _risk_band(forecast.bleeding_pressure)
	if action_quote.cover_strength > 0.0:
		forecast.notes.append("Geometric cover may intercept the hit.")
	if action_quote.collateral_risk > 0.0:
		forecast.notes.append("Crowded sector: collateral risk %.0f%%." % (action_quote.collateral_risk * 100.0))
	return forecast


static func _melee_hit_chance(attacker: Dictionary, _weapon: Dictionary, accuracy_modifier: float) -> float:
	var arm_function := clampf(float(attacker.get("right_arm_function", GameEnums.SCALE_MAX)) / GameEnums.SCALE_MAX, 0.0, 1.0)
	var injury := 1.0 - arm_function
	var balance_modifier := -0.12 if bool(attacker.get("off_balance", false)) else 0.0
	return clampf(0.50 + float(attacker.get("combat_accuracy_melee", 0.5)) * 0.34 + accuracy_modifier + balance_modifier - injury * 0.22, 0.05, 0.95)


static func _ranged_hit_chance(
	attacker: Dictionary,
	weapon: Dictionary,
	distance: int,
	_target_sector: Vector2i,
	accuracy_modifier: float,
	action_quote: CombatActionQuote
) -> float:
	var optimal: Variant = weapon.get("optimal_range_cells", Vector2i(1, 1))
	if not optimal is Vector2i:
		optimal = Vector2i(1, 1)
	var optimal_max := int(optimal.y) if int(optimal.y) > 0 else int(optimal.x)
	var cells_outside := 0
	if distance < int(optimal.x):
		cells_outside = int(optimal.x) - distance
	elif distance > optimal_max:
		cells_outside = distance - optimal_max
	var range_pressure := float(cells_outside) * maxf(0.0, float(weapon.get("range_falloff", 0.0)))
	var visibility := float(action_quote.get_meta("visibility_penalty", 0.0)) if action_quote != null else 0.0
	var injury := 1.0 - clampf(float(attacker.get("right_arm_function", GameEnums.SCALE_MAX)) / GameEnums.SCALE_MAX, 0.0, 1.0)
	var engaged_penalty := float(weapon.get("engaged_fire_accuracy_penalty", 0.0)) if distance == 0 and str(weapon.get("engaged_fire_policy", "allowed")) == "penalized" else 0.0
	return clampf(
		0.42
			+ float(attacker.get("combat_accuracy_ranged", 0.5)) * 0.42
			+ accuracy_modifier
			- engaged_penalty
			- range_pressure
			- visibility
			- injury * 0.25,
		0.05,
		0.95
	)


static func _armor_protection(defender: Dictionary, damage_type: int, region: int) -> float:
	var protection: Dictionary = defender.get("armor_protection", {})
	return float(protection.get("%d|%d" % [damage_type, region], protection.get(str(damage_type), 0.0)))


static func _distance(left: Vector2i, right: Vector2i) -> int:
	return absi(left.x - right.x) + absi(left.y - right.y)


static func _risk_band(value: float) -> String:
	if value < 0.75:
		return "low"
	if value < 2.0:
		return "moderate"
	if value < 4.0:
		return "high"
	return "critical"


static func _armor_result(penetration: float, protection: float) -> String:
	if protection <= 0.0:
		return "unarmored"
	if penetration >= protection * 1.25:
		return "overmatched"
	if penetration >= protection:
		return "contested"
	return "protected"
