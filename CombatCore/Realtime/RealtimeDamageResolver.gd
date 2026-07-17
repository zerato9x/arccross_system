extends Node
class_name RealtimeDamageResolver

signal damage_resolved(event: Dictionary)

func resolve_melee(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	weapon: ItemData,
	flesh_multiplier: float,
	stance_multiplier: float,
	source: String
) -> Dictionary:
	var target_limb := _roll_melee_target()
	if defender.current_stance == GameEnums.StanceState.FELLED:
		target_limb = GameEnums.LimbRegion.HEAD
		flesh_multiplier *= 1.35
	if weapon == null:
		return _resolve_unarmed(
			attacker,
			defender,
			target_limb,
			flesh_multiplier,
			stance_multiplier,
			source
		)
	return _resolve_weapon_damage(
		attacker,
		defender,
		weapon,
		target_limb,
		flesh_multiplier,
		stance_multiplier,
		source
	)

func resolve_block(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	weapon: ItemData,
	target_limb: int = -1
) -> Dictionary:
	if defender == null or not defender.body.has_functional_arms():
		return {"result": "guard_failed", "blocked": false}
	var shield := _blocking_shield(defender)
	if (
		weapon != null
		and weapon.damage_type == GameEnums.DamageType.BALLISTIC
		and (
			shield == null
			or not shield.can_block_damage(weapon.damage_type, target_limb)
		)
	):
		return {"result": "guard_failed", "blocked": false}
	if (
		shield != null
		and weapon != null
		and not shield.can_block_damage(weapon.damage_type, target_limb)
	):
		return {"result": "guard_failed", "blocked": false}

	var incoming_type := (
		weapon.damage_type if weapon != null else GameEnums.DamageType.BLUNT
	)
	var flesh := 0.5
	var stance := 1.0
	if weapon != null and shield != null:
		flesh = weapon.flesh_damage * shield.block_flesh_multiplier
		stance = weapon.stance_damage * shield.block_stance_multiplier
	elif weapon != null and weapon.damage_type == GameEnums.DamageType.BLUNT:
		flesh = weapon.flesh_damage * 0.25
		stance = weapon.stance_damage * 0.5
	elif weapon != null:
		flesh = weapon.flesh_damage * 0.1
		stance = 0.0
	if incoming_type == GameEnums.DamageType.BALLISTIC:
		stance = 0.0

	var arm := GameEnums.LimbRegion.LEFT_ARM
	if defender.body.limb_hp.get(arm, 0.0) <= 0.0:
		arm = GameEnums.LimbRegion.RIGHT_ARM
	var stance_before := defender.stance_points
	if flesh > 0.0:
		defender.body.apply_targeted_hit(arm, flesh, 0.0, incoming_type)
	if stance > 0.0:
		defender.apply_stance_damage(stance)
	var event := _event(
		attacker,
		defender,
		arm,
		flesh,
		float(stance_before - defender.stance_points),
		"shield_block" if shield != null else "block",
		incoming_type
	)
	event["blocked"] = true
	event["result"] = "blocked"
	damage_resolved.emit(event)
	return event

func resolve_shot(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	weapon: ItemData,
	distance: int,
	target_slot: CombatLaneSlot,
	aim_progress: float,
	guard_active: bool
) -> Dictionary:
	if weapon == null or not weapon.is_ranged():
		return {"result": "no_weapon", "hit": false}
	var profile := DuelWeaponProfileCatalog.profile_for(weapon)
	var shooter_accuracy := clampf(attacker.get_combat_accuracy(true), 0.0, 1.0)
	var weapon_accuracy := clampf(
		weapon.accuracy_rating / GameEnums.SCALE_MAX,
		0.0,
		1.0
	)
	var base_accuracy := 0.25 + shooter_accuracy * 0.35 + weapon_accuracy * 0.4
	var range_penalty := maxf(0.0, float(distance - 1) * 0.04)
	var visibility_penalty := target_slot.get_visibility_penalty()
	var aim_bonus := profile.full_aim_accuracy_bonus * clampf(aim_progress, 0.0, 1.0)
	var hit_chance := clampf(
		base_accuracy + aim_bonus - range_penalty - visibility_penalty,
		0.05,
		0.95
	)
	var limb := _roll_ballistic_target()
	if aim_progress > 0.0:
		var head_weight := profile.full_aim_head_weight * clampf(aim_progress, 0.0, 1.0)
		limb = (
			GameEnums.LimbRegion.HEAD
			if randf() < head_weight
			else GameEnums.LimbRegion.UPPER_TORSO
		)
	if randf() > hit_chance:
		return {
			"result": "miss",
			"hit": false,
			"limb_index": limb,
			"hit_chance": hit_chance,
		}
	if randf() < target_slot.get_cover_interception():
		target_slot.damage_cover(weapon.flesh_damage)
		return {
			"result": "cover_impact",
			"hit": false,
			"limb_index": limb,
			"hit_chance": hit_chance,
		}
	if guard_active:
		var block_event := resolve_block(attacker, defender, weapon, limb)
		if block_event.get("blocked", false):
			block_event["hit"] = false
			block_event["limb_index"] = limb
			block_event["hit_chance"] = hit_chance
			return block_event
	var event := _resolve_weapon_damage(
		attacker,
		defender,
		weapon,
		limb,
		weapon.damage_multiplier_at_distance(distance),
		1.0,
		"aimed_shot" if aim_progress > 0.0 else "shot"
	)
	event["result"] = "hit"
	event["hit"] = true
	event["hit_chance"] = hit_chance
	return event

func _resolve_weapon_damage(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	weapon: ItemData,
	limb: int,
	flesh_multiplier: float,
	stance_multiplier: float,
	source: String
) -> Dictionary:
	var raw_flesh := weapon.flesh_damage * flesh_multiplier
	var raw_stance := weapon.stance_damage * stance_multiplier
	var armor := defender.inventory.get_protection_for(weapon.damage_type)
	var bulk_bonus := maxf(0.0, defender.get_bulk_modifier()) * 0.15
	var penetration_ratio := clampf(
		weapon.armor_penetration / GameEnums.SCALE_MAX,
		0.0,
		1.0
	)
	var defense := (armor + bulk_bonus) * (1.0 - penetration_ratio)
	var flesh := maxf(0.0, raw_flesh - defense)
	var stance := raw_stance
	if weapon.damage_type != GameEnums.DamageType.BLUNT:
		stance = maxf(0.0, raw_stance - defense * 0.5)
	if weapon.damage_type == GameEnums.DamageType.BALLISTIC:
		stance = 0.0
	var stance_before := defender.stance_points
	if flesh > 0.0:
		defender.body.apply_targeted_hit(
			limb,
			flesh,
			weapon.armor_penetration,
			weapon.damage_type
		)
	if stance > 0.0:
		defender.apply_stance_damage(
			stance,
			source in ["heavy", "combo_finisher"]
		)
	var event := _event(
		attacker,
		defender,
		limb,
		flesh,
		float(stance_before - defender.stance_points),
		source,
		weapon.damage_type
	)
	damage_resolved.emit(event)
	return event

func _resolve_unarmed(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	limb: int,
	flesh_multiplier: float,
	stance_multiplier: float,
	source: String
) -> Dictionary:
	var values := CombatRules.get_unarmed_damage(
		attacker.definition.brawn,
		defender.inventory.get_protection_for(GameEnums.DamageType.BLUNT),
		defender.get_bulk_modifier()
	)
	var flesh := float(values.get("flesh", 0.25)) * flesh_multiplier
	var stance := float(values.get("stance", 1.0)) * stance_multiplier
	var stance_before := defender.stance_points
	defender.body.apply_targeted_hit(limb, flesh, 0.0, GameEnums.DamageType.BLUNT)
	defender.apply_stance_damage(
		stance,
		source in ["heavy", "combo_finisher"]
	)
	var event := _event(
		attacker,
		defender,
		limb,
		flesh,
		float(stance_before - defender.stance_points),
		source,
		GameEnums.DamageType.BLUNT
	)
	damage_resolved.emit(event)
	return event

func _event(
	attacker: HumanoidCore,
	defender: HumanoidCore,
	limb: int,
	flesh: float,
	stance: float,
	source: String,
	damage_type: int
) -> Dictionary:
	return {
		"attacker": attacker,
		"defender": defender,
		"limb_index": limb,
		"flesh_damage": flesh,
		"stance_damage": maxf(0.0, stance),
		"source": source,
		"damage_type": damage_type,
	}

func _blocking_shield(defender: HumanoidCore) -> ItemData:
	for slot in [GameEnums.EquipmentSlot.HAND, GameEnums.EquipmentSlot.OFFHAND]:
		var item: ItemData = defender.inventory.paper_doll.get(slot)
		if item != null and item.is_blocking_shield():
			return item
	return null

func _roll_melee_target() -> int:
	return [
		GameEnums.LimbRegion.UPPER_TORSO,
		GameEnums.LimbRegion.LOWER_TORSO,
		GameEnums.LimbRegion.LEFT_ARM,
		GameEnums.LimbRegion.RIGHT_ARM,
		GameEnums.LimbRegion.LEFT_LEG,
		GameEnums.LimbRegion.RIGHT_LEG,
	].pick_random()

func _roll_ballistic_target() -> int:
	return [
		GameEnums.LimbRegion.UPPER_TORSO,
		GameEnums.LimbRegion.LOWER_TORSO,
		GameEnums.LimbRegion.LEFT_ARM,
		GameEnums.LimbRegion.RIGHT_ARM,
		GameEnums.LimbRegion.LEFT_LEG,
		GameEnums.LimbRegion.RIGHT_LEG,
	].pick_random()
