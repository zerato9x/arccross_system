extends Node
class_name CombatResolutionEngine

## Weapon and wound resolver used only after CombatActionController has produced
## a legal quote. Spatial authority remains in CombatBoard.

signal action_started(actor: HumanoidCore, action_id: String)
signal damage_applied(actor: HumanoidCore)
signal damage_resolved(event: Dictionary)
signal shot_resolved(event: Dictionary)
signal presentation_resolved(event: Dictionary)

@export var board: CombatBoard
@export var turn_manager: TacticalTurnManager

## Resolution never uses the process-global RNG. The controller seeds this
## stream from the encounter arena so repeated encounters are replayable.
var rng := RandomNumberGenerator.new()
## Per-action draw ledger. Preview/quote never touches this stream; the
## controller clears it at commit and attaches the draws to the outcome.
var random_trace: Array[Dictionary] = []
var encounter_id := ""
var _action_context: Dictionary = {}

const MELEE_REGIONS := [
	GameEnums.LimbRegion.UPPER_TORSO,
	GameEnums.LimbRegion.LOWER_TORSO,
	GameEnums.LimbRegion.LEFT_ARM,
	GameEnums.LimbRegion.RIGHT_ARM,
	GameEnums.LimbRegion.LEFT_LEG,
	GameEnums.LimbRegion.RIGHT_LEG,
]
const BALLISTIC_REGIONS := [
	GameEnums.LimbRegion.HEAD,
	GameEnums.LimbRegion.UPPER_TORSO,
	GameEnums.LimbRegion.UPPER_TORSO,
	GameEnums.LimbRegion.LOWER_TORSO,
	GameEnums.LimbRegion.LEFT_ARM,
	GameEnums.LimbRegion.RIGHT_ARM,
	GameEnums.LimbRegion.LEFT_LEG,
	GameEnums.LimbRegion.RIGHT_LEG,
]


func begin_random_trace() -> void:
	random_trace.clear()


func begin_action_context(context: Dictionary) -> void:
	_action_context = context.duplicate(true)
	_action_context["encounter_id"] = encounter_id


func end_action_context() -> void:
	_action_context.clear()


func injury_context(region: int, source_item_instance_id: String = "") -> Dictionary:
	var context := _action_context.duplicate(true)
	context["body_region"] = region
	if not source_item_instance_id.is_empty():
		context["source_item_instance_id"] = source_item_instance_id
	return context


func consume_random_trace() -> Array[Dictionary]:
	var result := random_trace.duplicate(true)
	random_trace.clear()
	return result


func draw_int(min_value: int, max_value: int, purpose: String) -> int:
	return _draw_int(min_value, max_value, purpose)


func _draw_float(purpose: String) -> float:
	var value := rng.randf()
	random_trace.append({"purpose": purpose, "distribution": "uniform_0_1", "value": value})
	return value


func _draw_int(min_value: int, max_value: int, purpose: String) -> int:
	var value := rng.randi_range(min_value, max_value)
	random_trace.append({"purpose": purpose, "distribution": "integer", "min": min_value, "max": max_value, "value": value})
	return value


func build_forecast(
	request: CombatActionRequest,
	definition: CombatActionDefinition,
	attacker: HumanoidCore,
	defender: HumanoidCore,
	action_quote: CombatActionQuote
) -> CombatForecastRecord:
	var forecast := CombatForecastRecord.new()
	if attacker == null or defender == null or definition == null:
		return forecast
	if not definition.is_weapon_action():
		return forecast
	var region := GameEnums.LimbRegion.UPPER_TORSO
	forecast.target_body_region = -1
	var targeting := definition.targeting_profile
	if targeting != null:
		forecast.probable_body_regions = targeting.weighted_regions()
	var effect := definition.effect_profile
	var accuracy_modifier := effect.accuracy_modifier if effect != null else 0.0
	var is_melee := definition.is_melee_weapon_action()
	var weapon := attacker.inventory.get_active_weapon(is_melee)
	var projected_origin := board.position_of(attacker)
	if action_quote.projected_origin != Vector2i(-1, -1) and board.arena_state.contains(action_quote.projected_origin):
		projected_origin = board.arena_state.index_for(action_quote.projected_origin)
	var defender_index := board.position_of(defender)
	if is_melee:
		forecast.hit_probability = _melee_hit_chance(attacker, defender, accuracy_modifier, projected_origin)
	elif weapon != null:
		forecast.hit_probability = _ranged_hit_chance(
			attacker, defender, weapon, projected_origin, defender_index, accuracy_modifier
		)
	if weapon == null:
		forecast.bleeding_risk = "low"
		forecast.severe_wound_risk = _risk_band(2.0 * forecast.hit_probability)
		forecast.incapacity_risk = "low"
		return forecast
	forecast.armor_penetration = weapon.armor_penetration + (effect.penetration_modifier if effect != null else 0.0)
	forecast.armor_protection = defender.inventory.preview_protection(weapon.damage_type, region)
	forecast.armor_result = _armor_result(forecast.armor_penetration, forecast.armor_protection)
	var damage := weapon.flesh_damage * (effect.damage_multiplier if effect != null else 1.0)
	damage = maxf(0.05, damage - maxf(0.0, forecast.armor_protection - forecast.armor_penetration) * 0.5)
	forecast.severe_wound_risk = _risk_band(damage * forecast.hit_probability)
	forecast.incapacity_risk = _risk_band(damage * forecast.hit_probability * (1.35 if region in [GameEnums.LimbRegion.HEAD, GameEnums.LimbRegion.UPPER_TORSO] else 0.55))
	forecast.bleeding_risk = _risk_band(damage * forecast.hit_probability * (1.2 if weapon.damage_type in [GameEnums.DamageType.SHARP, GameEnums.DamageType.BALLISTIC] else 0.35))
	if action_quote.cover_strength > 0.0:
		forecast.notes.append("Cover geometry may intercept the hit.")
	return forecast


func execute_ranged_strike(
	attacker: HumanoidCore,
	target_index: int,
	effect_profile: CombatActionEffectProfile = null,
	targeting_profile: CombatTargetingProfile = null,
	target_actor: HumanoidCore = null,
	action_id: String = "fire"
) -> bool:
	return await _execute_shot(attacker, target_index, effect_profile, targeting_profile, target_actor, action_id)


func _execute_shot(
	attacker: HumanoidCore,
	target_index: int,
	effect_profile: CombatActionEffectProfile,
	targeting_profile: CombatTargetingProfile,
	target_actor: HumanoidCore = null,
	action_id: String = "fire"
) -> bool:
	if board == null or attacker == null or target_index < 0 or target_index >= board.sectors.size():
		return false
	var victim := target_actor if target_actor != null else board.actor_at(target_index)
	var weapon := attacker.inventory.get_active_weapon(false)
	if victim == null or weapon == null or not weapon.is_ready_to_fire():
		return false
	var origin_index := board.position_of(attacker)
	var distance := board.grid_distance(origin_index, target_index)
	if distance > weapon.maximum_range_cells or not board.has_line_of_sight(origin_index, target_index):
		return false
	action_started.emit(attacker, action_id)
	var condition := ItemConditionRules.resolve_use(weapon, ItemConditionRules.EVENT_FIREARM)
	weapon.current_magazine = maxi(0, weapon.current_magazine - 1)
	# Chamber, bolt, and pump cycling is part of the ordinary Fire/Reload
	# authority.  Keep the legacy runtime marker clear instead of making CYCLE
	# a second, player-visible firing prerequisite.
	weapon.needs_cycling = false
	if not weapon.fitted_magazine_state.is_empty():
		weapon.fitted_magazine_state["loaded_rounds"] = weapon.current_magazine
	if bool(condition.get("faulted", false)):
		_emit_shot(attacker, victim, origin_index, target_index, action_id, "malfunction", -1, {})
		return true
	var region := _pick_region(targeting_profile, BALLISTIC_REGIONS)
	var accuracy_modifier := effect_profile.accuracy_modifier if effect_profile != null else 0.0
	var hit_chance := _ranged_hit_chance(attacker, victim, weapon, origin_index, target_index, accuracy_modifier)
	if _draw_float("ranged_hit") > hit_chance:
		_emit_shot(attacker, victim, origin_index, target_index, action_id, "miss", region, {})
		return true
	var cover := board.cover_against(target_index, origin_index)
	if cover > 0.0 and _draw_float("cover_intercept") < cover:
		var mutation := board.sectors[target_index].damage_object(weapon.flesh_damage)
		_emit_shot(attacker, victim, origin_index, target_index, action_id, "cover", region, {"terrain_mutation": mutation})
		return true
	var damage := _apply_weapon_damage(
		attacker,
		victim,
		weapon,
		region,
		weapon.damage_multiplier_at_distance(distance) * (effect_profile.damage_multiplier if effect_profile != null else 1.0),
		effect_profile.penetration_modifier if effect_profile != null else 0.0,
		action_id
	)
	_maybe_apply_crowded_collateral(
		attacker,
		victim,
		weapon,
		region,
		weapon.damage_multiplier_at_distance(distance) * (effect_profile.damage_multiplier if effect_profile != null else 1.0),
		effect_profile.penetration_modifier if effect_profile != null else 0.0,
		action_id
	)
	_emit_shot(attacker, victim, origin_index, target_index, action_id, "hit", region, damage)
	return true


func execute_melee_strike(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	target_region: int = -1,
	effect_profile: CombatActionEffectProfile = null,
	targeting_profile: CombatTargetingProfile = null,
	action_id: String = "strike"
) -> bool:
	if board == null or attacker == null or defender == null:
		return false
	var weapon := attacker.inventory.get_active_weapon(true)
	if not board.can_melee_reach(attacker, board.position_of(defender)):
		return false
	action_started.emit(attacker, action_id)
	var aimed := target_region >= 0
	var region := target_region if aimed else _pick_region(targeting_profile, MELEE_REGIONS)
	var accuracy_modifier := effect_profile.accuracy_modifier if effect_profile != null else 0.0
	if aimed and targeting_profile != null:
		accuracy_modifier += targeting_profile.accuracy_modifier(region)
	if _draw_float("melee_hit") > _melee_hit_chance(attacker, defender, accuracy_modifier):
		presentation_resolved.emit(_melee_presentation_event(attacker, defender, action_id, "miss", region))
		return true
	if weapon != null:
		var condition := ItemConditionRules.resolve_use(weapon, ItemConditionRules.EVENT_MELEE)
		var multiplier := float(condition.get("performance_multiplier", 1.0)) * (effect_profile.damage_multiplier if effect_profile != null else 1.0)
		_apply_weapon_damage(
			attacker,
			defender,
			weapon,
			region,
			multiplier,
			effect_profile.penetration_modifier if effect_profile != null else 0.0,
			action_id
		)
		_maybe_apply_crowded_collateral(
			attacker,
			defender,
			weapon,
			region,
			multiplier,
			effect_profile.penetration_modifier if effect_profile != null else 0.0,
			action_id
		)
	else:
		_apply_unarmed_damage(attacker, defender, region, effect_profile.damage_multiplier if effect_profile != null else 1.0, action_id)
	if effect_profile != null and effect_profile.applies_off_balance_on_hit:
		board.set_condition(defender, "off_balance", true)
	presentation_resolved.emit(_melee_presentation_event(attacker, defender, action_id, "hit", region))
	return true


func _melee_presentation_event(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	action_id: String,
	result: String,
	region: int
) -> Dictionary:
	return {
		"type": "melee_resolution",
		"action_id": action_id,
		"attacker_id": _actor_id(attacker),
		"victim_id": _actor_id(defender),
		"result": result,
		"region": region,
	}


func execute_reload(actor: HumanoidCore) -> bool:
	var weapon := actor.inventory.get_active_weapon(false) if actor != null else null
	if weapon == null or not weapon.is_ranged() or weapon.current_magazine >= weapon.max_magazine:
		return false
	var detachable := not weapon.magazine_id.is_empty()
	var feed_id := weapon.magazine_id if detachable else weapon.reload_aid_id
	if not feed_id.is_empty():
		var source := actor.inventory.find_filled_magazine(feed_id)
		if source == null:
			return false
		var receipt := actor.inventory.swap_fitted_magazine(weapon, source) if detachable else actor.inventory.use_reload_aid(weapon, source)
		if receipt.is_empty():
			return false
		weapon.needs_cycling = false
		action_started.emit(actor, "reload")
		return true
	if weapon.cycle_loads_one_round:
		return false
	var loaded := actor.inventory.consume_ammunition(weapon.ammunition_id, weapon.max_magazine - weapon.current_magazine, true)
	if loaded <= 0:
		return false
	weapon.current_magazine += loaded
	weapon.needs_cycling = false
	action_started.emit(actor, "reload")
	return true


func execute_cycle(actor: HumanoidCore) -> bool:
	var weapon := actor.inventory.get_active_weapon(false) if actor != null else null
	if weapon == null or not weapon.is_ranged():
		return false
	if not weapon.is_jammed:
		return false
	if ItemConditionRules.clear_malfunction(weapon):
		action_started.emit(actor, "cycle")
		return true
	return false


func _ranged_hit_chance(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	weapon: ItemData,
	origin_index: int,
	target_index: int,
	accuracy_modifier: float
) -> float:
	var distance := board.grid_distance(origin_index, target_index)
	var optimal_max := weapon.optimal_range_cells.y if weapon.optimal_range_cells.y > 0 else weapon.optimal_range_cells.x
	var cells_outside := 0
	if distance < weapon.optimal_range_cells.x:
		cells_outside = weapon.optimal_range_cells.x - distance
	elif distance > optimal_max:
		cells_outside = distance - optimal_max
	var range_pressure := float(cells_outside) * maxf(0.0, weapon.range_falloff)
	var visibility := board.sectors[target_index].record.visibility_penalty
	var injury := 1.0 - clampf(attacker.body.get_limb_function(GameEnums.LimbRegion.RIGHT_ARM) / GameEnums.SCALE_MAX, 0.0, 1.0)
	var engaged_penalty := weapon.engaged_fire_accuracy_penalty if board.grid_distance(origin_index, target_index) == 0 and weapon.engaged_fire_policy == "penalized" else 0.0
	return clampf(
		0.42
		+ attacker.get_combat_accuracy(true) * 0.42
		+ accuracy_modifier
		- engaged_penalty
		- range_pressure
		- visibility
		- injury * 0.25,
		0.05,
		0.95
	)


func _melee_hit_chance(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	accuracy_modifier: float,
	origin_index: int = -1
) -> float:
	var injury := 1.0 - clampf(attacker.body.get_limb_function(GameEnums.LimbRegion.RIGHT_ARM) / GameEnums.SCALE_MAX, 0.0, 1.0)
	var balance_modifier := -0.12 if board.has_condition(attacker, "off_balance") else 0.0
	return clampf(
		0.50
		+ attacker.get_combat_accuracy(false) * 0.34
		+ accuracy_modifier
		+ balance_modifier
		- injury * 0.22,
		0.05,
		0.95
	)


func _pick_region(profile: CombatTargetingProfile, fallback: Array) -> int:
	var regions: Array = profile.weighted_regions() if profile != null else fallback
	return int(regions[_draw_int(0, regions.size() - 1, "body_region")]) if not regions.is_empty() else GameEnums.LimbRegion.UPPER_TORSO


func _risk_band(value: float) -> String:
	if value < 0.75:
		return "low"
	if value < 2.0:
		return "moderate"
	if value < 4.0:
		return "high"
	return "critical"


func _armor_result(penetration: float, protection: float) -> String:
	if protection <= 0.0:
		return "unarmored"
	if penetration >= protection * 1.25:
		return "overmatched"
	if penetration >= protection:
		return "contested"
	return "protected"


func _apply_weapon_damage(
	attacker: HumanoidCore,
	victim: HumanoidCore,
	weapon: ItemData,
	region: int,
	multiplier: float,
	penetration_modifier: float,
	source: String,
	is_collateral: bool = false,
	intended_victim_id: String = ""
) -> Dictionary:
	var protection := victim.inventory.resolve_protection_event(weapon.damage_type, region)
	var defense := float(protection.get("total_protection", 0.0))
	var penetration := maxf(0.0, weapon.armor_penetration + penetration_modifier - defense)
	var raw := maxf(0.0, weapon.flesh_damage * multiplier)
	var flesh := maxf(0.05, raw - maxf(0.0, defense - weapon.armor_penetration) * 0.5)
	victim.body.apply_targeted_hit(region, flesh, penetration, weapon.damage_type, injury_context(region, weapon.instance_id))
	if weapon.damage_type != GameEnums.DamageType.BALLISTIC:
		_apply_balance_impact(victim, weapon.balance_impact * multiplier)
	var event := {
		"type": "damage",
		"action_id": source,
		"attacker_id": _actor_id(attacker),
		"victim_id": _actor_id(victim),
		"region": region,
		"flesh_damage": flesh,
		"balance_impact": weapon.balance_impact * multiplier,
		"damage_type": weapon.damage_type,
		"source_item_instance_id": weapon.instance_id,
		"collateral": is_collateral,
		"intended_victim_id": intended_victim_id,
	}
	damage_applied.emit(victim)
	damage_resolved.emit(event)
	return event


func _maybe_apply_crowded_collateral(
	attacker: HumanoidCore,
	victim: HumanoidCore,
	weapon: ItemData,
	region: int,
	multiplier: float,
	penetration_modifier: float,
	source: String
) -> Dictionary:
	if board == null or attacker == null or victim == null or weapon == null:
		return {}
	var target_index := board.position_of(victim)
	if target_index < 0 or board.occupancy_kind(target_index) != "crowded":
		return {}
	var collateral: HumanoidCore
	for candidate in board.actors_at(target_index):
		if candidate != null and candidate != victim and not candidate.is_dead and not candidate.is_comatose:
			collateral = candidate
			break
	if collateral == null:
		return {}
	var risk := clampf(board.balance_profile.crowded_collateral_risk, 0.0, 1.0)
	if _draw_float("crowded_collateral") >= risk:
		return {}
	var event := _apply_weapon_damage(
		attacker,
		collateral,
		weapon,
		region,
		multiplier * board.balance_profile.crowded_collateral_multiplier,
		penetration_modifier,
		source,
		true,
		_actor_id(victim)
	)
	return event


func _apply_unarmed_damage(attacker: HumanoidCore, victim: HumanoidCore, region: int, multiplier: float = 1.0, action_id: String = "strike") -> Dictionary:
	var protection := victim.inventory.resolve_protection_event(GameEnums.DamageType.BLUNT, region)
	var unarmed := CombatRules.get_unarmed_damage(attacker.definition.brawn, float(protection.get("total_protection", 0.0)), 0.0)
	var flesh := float(unarmed.get("flesh", 0.1)) * multiplier
	var impact := float(unarmed.get("balance_impact", 1.0)) * multiplier
	victim.body.apply_targeted_hit(region, flesh, 0.0, GameEnums.DamageType.BLUNT, injury_context(region))
	_apply_balance_impact(victim, impact)
	var event := {
		"type": "damage",
		"action_id": action_id,
		"attacker_id": _actor_id(attacker),
		"victim_id": _actor_id(victim),
		"region": region,
		"flesh_damage": flesh,
		"balance_impact": impact,
		"damage_type": GameEnums.DamageType.BLUNT,
	}
	damage_applied.emit(victim)
	damage_resolved.emit(event)
	return event


func _apply_balance_impact(victim: HumanoidCore, amount: float) -> void:
	if amount <= 0.0 or board == null:
		return
	board.apply_stance_damage(victim, amount, false, "weapon_balance")
	# Brace was retired from the player verb model. A single data-authored
	# critical-margin threshold keeps off-balance behaviour deterministic without
	# smuggling a hidden defensive-action bonus back into resolution.
	var threshold := board.balance_profile.critical_margin
	if amount >= threshold:
		board.set_condition(victim, "off_balance", true)


func _emit_shot(
	attacker: HumanoidCore,
	victim: HumanoidCore,
	origin_index: int,
	target_index: int,
	action_id: String,
	result: String,
	region: int,
	damage: Dictionary
) -> void:
	var event := {
		"type": "shot",
		"action_id": action_id,
		"attacker_id": _actor_id(attacker),
		"victim_id": _actor_id(victim),
		"origin_sector": board.arena_state.coords_for(origin_index),
		"target_sector": board.arena_state.coords_for(target_index),
		"result": result,
		"region": region,
		"damage": damage.duplicate(true),
	}
	shot_resolved.emit(event)


func _actor_id(actor: HumanoidCore) -> String:
	return "" if actor == null else str(actor.get_meta("actor_id", actor.name))
