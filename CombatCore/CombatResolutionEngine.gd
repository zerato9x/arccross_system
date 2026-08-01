extends Node
class_name CombatResolutionEngine

## Weapon and wound resolver used only after CombatActionController has produced
## a legal quote. Spatial authority remains in CombatBoard.

signal action_started(actor: HumanoidCore, action_id: String)
signal damage_applied(actor: HumanoidCore)
signal damage_resolved(event: Dictionary)
signal shot_resolved(event: Dictionary)

@export var board: CombatBoard
@export var turn_manager: TacticalTurnManager

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
	if request.action_id not in ["strike", "power_strike", "aimed_strike", "fire", "aimed_fire"]:
		return forecast
	var aimed := request.action_id in ["aimed_strike", "aimed_fire"]
	var region := request.target_body_region if aimed else GameEnums.LimbRegion.UPPER_TORSO
	forecast.target_body_region = region if aimed else -1
	var targeting := definition.targeting_profile
	if targeting != null:
		forecast.probable_body_regions = targeting.weighted_regions()
	var effect := definition.effect_profile
	var accuracy_modifier := effect.accuracy_modifier if effect != null else 0.0
	if aimed and targeting != null:
		accuracy_modifier += targeting.accuracy_modifier(region)
	var is_melee := request.action_id in ["strike", "power_strike", "aimed_strike"]
	var weapon := attacker.inventory.get_active_weapon(is_melee)
	if is_melee:
		forecast.hit_probability = _melee_hit_chance(attacker, defender, accuracy_modifier)
	elif weapon != null:
		forecast.hit_probability = _ranged_hit_chance(
			attacker, defender, weapon, board.position_of(attacker), board.position_of(defender), accuracy_modifier
		)
	forecast.attack_arc = str(board.attack_arc(attacker, defender).get("arc", "front"))
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
		forecast.notes.append("Directional cover may intercept the hit.")
	return forecast


func execute_ranged_strike(
	attacker: HumanoidCore,
	target_index: int,
	effect_profile: CombatActionEffectProfile = null,
	targeting_profile: CombatTargetingProfile = null
) -> bool:
	return await _execute_shot(attacker, target_index, false, -1, effect_profile, targeting_profile)


func execute_aimed_shot(
	attacker: HumanoidCore,
	target_index: int,
	target_region: int,
	effect_profile: CombatActionEffectProfile = null,
	targeting_profile: CombatTargetingProfile = null
) -> bool:
	return await _execute_shot(attacker, target_index, true, target_region, effect_profile, targeting_profile)


func _execute_shot(
	attacker: HumanoidCore,
	target_index: int,
	aimed: bool,
	target_region: int,
	effect_profile: CombatActionEffectProfile,
	targeting_profile: CombatTargetingProfile
) -> bool:
	if board == null or attacker == null or target_index < 0 or target_index >= board.sectors.size():
		return false
	var victim := board.actor_at(target_index)
	var weapon := attacker.inventory.get_active_weapon(false)
	if victim == null or weapon == null or not weapon.is_ready_to_fire():
		return false
	var origin_index := board.position_of(attacker)
	var distance := board.grid_distance(origin_index, target_index)
	if distance > weapon.maximum_range_cells or not board.has_line_of_sight(origin_index, target_index):
		return false
	action_started.emit(attacker, "aimed_fire" if aimed else "fire")
	var condition := ItemConditionRules.resolve_use(weapon, ItemConditionRules.EVENT_FIREARM)
	weapon.current_magazine = maxi(0, weapon.current_magazine - 1)
	if not weapon.fitted_magazine_state.is_empty():
		weapon.fitted_magazine_state["loaded_rounds"] = weapon.current_magazine
	if weapon.requires_cycle_after_shot:
		weapon.needs_cycling = true
	if bool(condition.get("faulted", false)):
		_emit_shot(attacker, victim, origin_index, target_index, "malfunction", target_region, {})
		return true
	var reaction := await _request_reaction(victim, attacker, "aimed_fire" if aimed else "fire")
	if reaction == "dodge" and _resolve_dodge(victim, attacker, distance):
		_emit_shot(attacker, victim, origin_index, target_index, "dodge", target_region, {})
		return true
	var region := target_region if aimed else _pick_region(targeting_profile, BALLISTIC_REGIONS)
	if reaction == "block" and _resolve_block(victim, attacker, weapon, region):
		_emit_shot(attacker, victim, origin_index, target_index, "block", region, {})
		return true
	var accuracy_modifier := effect_profile.accuracy_modifier if effect_profile != null else (0.14 if aimed else 0.0)
	if aimed and targeting_profile != null:
		accuracy_modifier += targeting_profile.accuracy_modifier(region)
	var hit_chance := _ranged_hit_chance(attacker, victim, weapon, origin_index, target_index, accuracy_modifier)
	if randf() > hit_chance:
		_emit_shot(attacker, victim, origin_index, target_index, "miss", region, {})
		return true
	var cover := board.cover_against(target_index, origin_index)
	if cover > 0.0 and randf() < cover:
		var mutation := board.sectors[target_index].damage_object(weapon.flesh_damage)
		_emit_shot(attacker, victim, origin_index, target_index, "cover", region, {"terrain_mutation": mutation})
		return true
	var damage := _apply_weapon_damage(
		attacker,
		victim,
		weapon,
		region,
		weapon.damage_multiplier_at_distance(distance) * (effect_profile.damage_multiplier if effect_profile != null else 1.0),
		effect_profile.penetration_modifier if effect_profile != null else 0.0,
		"aimed_fire" if aimed else "fire"
	)
	_emit_shot(attacker, victim, origin_index, target_index, "hit", region, damage)
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
	board.set_facing(attacker, board.facing_toward(board.position_of(attacker), board.position_of(defender)))
	action_started.emit(attacker, action_id)
	var reaction := await _request_reaction(defender, attacker, action_id)
	if reaction == "dodge" and _resolve_dodge(defender, attacker, 1):
		return true
	if reaction == "block" and _resolve_block(defender, attacker, weapon, -1):
		return true
	var aimed := target_region >= 0
	var region := target_region if aimed else _pick_region(targeting_profile, MELEE_REGIONS)
	var accuracy_modifier := effect_profile.accuracy_modifier if effect_profile != null else 0.0
	if aimed and targeting_profile != null:
		accuracy_modifier += targeting_profile.accuracy_modifier(region)
	if randf() > _melee_hit_chance(attacker, defender, accuracy_modifier):
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
	else:
		_apply_unarmed_damage(attacker, defender, region, effect_profile.damage_multiplier if effect_profile != null else 1.0)
	if effect_profile != null and effect_profile.applies_off_balance_on_hit:
		board.set_condition(defender, "off_balance", true)
	return true


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
	if weapon.needs_cycling:
		weapon.needs_cycling = false
		action_started.emit(actor, "cycle")
		return true
	if not weapon.cycle_loads_one_round or weapon.current_magazine >= weapon.max_magazine:
		return false
	var loaded := actor.inventory.consume_ammunition(weapon.ammunition_id, 1, true)
	if loaded != 1:
		return false
	weapon.current_magazine += 1
	action_started.emit(actor, "cycle")
	return true


func execute_clear_malfunction(actor: HumanoidCore) -> bool:
	var weapon := actor.inventory.get_active_weapon(false) if actor != null else null
	if not ItemConditionRules.clear_malfunction(weapon):
		return false
	action_started.emit(actor, "clear_malfunction")
	return true


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
	var arc := board.attack_arc(attacker, defender)
	var posture_modifier := 0.03 if board.posture(attacker) == "crouched" else 0.0
	if board.posture(defender) == "crouched":
		posture_modifier -= 0.08
	return clampf(
		0.42
		+ attacker.get_combat_accuracy(true) * 0.42
		+ accuracy_modifier
		+ float(arc.get("accuracy", 0.0))
		+ posture_modifier
		- range_pressure
		- visibility
		- injury * 0.25,
		0.05,
		0.95
	)


func _melee_hit_chance(attacker: HumanoidCore, defender: HumanoidCore, accuracy_modifier: float) -> float:
	var arc := board.attack_arc(attacker, defender)
	var injury := 1.0 - clampf(attacker.body.get_limb_function(GameEnums.LimbRegion.RIGHT_ARM) / GameEnums.SCALE_MAX, 0.0, 1.0)
	var posture_modifier := -0.05 if board.posture(attacker) == "crouched" else 0.0
	if board.has_condition(attacker, "off_balance"):
		posture_modifier -= 0.12
	return clampf(
		0.50
		+ attacker.get_combat_accuracy(false) * 0.34
		+ float(arc.get("accuracy", 0.0))
		+ accuracy_modifier
		+ posture_modifier
		- injury * 0.22,
		0.05,
		0.95
	)


func _pick_region(profile: CombatTargetingProfile, fallback: Array) -> int:
	var regions: Array = profile.weighted_regions() if profile != null else fallback
	return int(regions.pick_random()) if not regions.is_empty() else GameEnums.LimbRegion.UPPER_TORSO


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
	source: String
) -> Dictionary:
	var protection := victim.inventory.resolve_protection_event(weapon.damage_type, region)
	var defense := float(protection.get("total_protection", 0.0))
	var penetration := maxf(0.0, weapon.armor_penetration + penetration_modifier - defense)
	var raw := maxf(0.0, weapon.flesh_damage * multiplier)
	var flesh := maxf(0.05, raw - maxf(0.0, defense - weapon.armor_penetration) * 0.5)
	victim.body.apply_targeted_hit(region, flesh, penetration, weapon.damage_type)
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
	}
	damage_applied.emit(victim)
	damage_resolved.emit(event)
	return event


func _apply_unarmed_damage(attacker: HumanoidCore, victim: HumanoidCore, region: int, multiplier: float = 1.0) -> Dictionary:
	var protection := victim.inventory.resolve_protection_event(GameEnums.DamageType.BLUNT, region)
	var unarmed := CombatRules.get_unarmed_damage(attacker.definition.brawn, float(protection.get("total_protection", 0.0)), 0.0)
	var flesh := float(unarmed.get("flesh", 0.1)) * multiplier
	var impact := float(unarmed.get("balance_impact", 1.0)) * multiplier
	victim.body.apply_targeted_hit(region, flesh, 0.0, GameEnums.DamageType.BLUNT)
	_apply_balance_impact(victim, impact)
	var event := {
		"type": "damage",
		"action_id": "strike",
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
	var threshold := 3.0 + float(victim.definition.brawn) * 0.25
	if board.has_condition(victim, "braced"):
		threshold += 2.0
	if amount >= threshold:
		board.set_condition(victim, "off_balance", true)


func _request_reaction(defender: HumanoidCore, attacker: HumanoidCore, trigger_id: String) -> String:
	if turn_manager == null:
		return ""
	# Lambdas capture scalar values in GDScript, so keep callback state in a
	# mutable record. Reassigning captured locals would leave this scope stale.
	var reaction_state := {"selected": "", "resolved": false}
	var callback := func(resolved_defender: HumanoidCore, action, success: bool) -> void:
		if resolved_defender == defender:
			reaction_state.resolved = true
			reaction_state.selected = str(action) if success else ""
	turn_manager.reaction_resolved.connect(callback)
	var available := turn_manager.open_reaction_window(defender, attacker, trigger_id)
	# Headless simulations have no prompt surface. Resolve the first authored
	# option deterministically so combat remains presentation-independent.
	if turn_manager._reaction_pending and DisplayServer.get_name().contains("headless"):
		if available.is_empty():
			turn_manager.decline_reaction(defender)
		else:
			turn_manager.resolve_reaction(defender, available[0])
	if turn_manager._reaction_pending and not bool(reaction_state.resolved):
		await turn_manager.reaction_resolved
	turn_manager.reaction_resolved.disconnect(callback)
	return str(reaction_state.selected)


func _resolve_block(
	defender: HumanoidCore,
	_attacker: HumanoidCore,
	weapon: ItemData,
	region: int
) -> bool:
	var shield := _readied_shield(defender, weapon.damage_type if weapon != null else GameEnums.DamageType.BLUNT, region)
	if shield == null:
		return false
	var condition := ItemConditionRules.resolve_use(shield, ItemConditionRules.EVENT_SHIELD)
	return float(condition.get("performance_multiplier", 0.0)) > 0.0


func _resolve_dodge(defender: HumanoidCore, attacker: HumanoidCore, distance: int) -> bool:
	if defender.body.are_both_legs_disabled():
		return false
	var chance := 0.22 + float(defender.definition.finesse - attacker.definition.finesse) / 48.0
	chance += 0.08 if distance > 3 else 0.0
	chance -= 0.12 if board.has_condition(defender, "off_balance") else 0.0
	return randf() < clampf(chance, 0.05, 0.65)


func _readied_shield(defender: HumanoidCore, damage_type: int, region: int) -> ItemData:
	for slot in [GameEnums.EquipmentSlot.HAND, GameEnums.EquipmentSlot.OFFHAND]:
		var item: ItemData = defender.inventory.paper_doll.get(slot)
		if item != null and item.can_block_damage(damage_type, region):
			return item
	return null


func _emit_shot(
	attacker: HumanoidCore,
	victim: HumanoidCore,
	origin_index: int,
	target_index: int,
	result: String,
	region: int,
	damage: Dictionary
) -> void:
	var event := {
		"type": "shot",
		"action_id": "fire",
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
