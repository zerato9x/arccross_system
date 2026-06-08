extends Node
class_name CombatResolutionEngine

@export var lane_manager: CombatLaneManager

# ---------------------------------------------------------
# THE RANGED TRAJECTORY MATH
# ---------------------------------------------------------

func execute_ranged_strike(attacker: HumanoidCore, target_idx: int) -> void:
	var target_slot: CombatLaneSlot = lane_manager.lane_slots[target_idx]
	var weapon: ItemData = attacker.inventory.paper_doll[GameEnums.EquipmentSlot.HANDS]
	
	if weapon == null or (weapon.weapon_type != GameEnums.WeaponClass.PISTOL and weapon.weapon_type != GameEnums.WeaponClass.RIFLE):
		print("ERROR: ", attacker.name, " tried to shoot someone without a gun.")
		return
		
	if target_slot.occupants.size() == 0:
		print("Miss! ", attacker.name, " fired a bullet into empty mud.")
		return

	# 1. Determine Distance
	var attacker_idx = _find_entity_index(attacker)
	var distance = abs(attacker_idx - target_idx)
	
	# 2. Base Accuracy vs Environment Math
	# Example prototype math: 90% base hit chance, minus 5% per grid distance
	var base_accuracy: float = 0.90 - (distance * 0.05) 
	var visibility_penalty: float = target_slot.get_visibility_penalty()
	var final_hit_chance: float = base_accuracy - visibility_penalty
	
	var shot_roll: float = randf()
	
	print("\n--- SHOT FIRED ---")
	print("Distance: ", distance, " | Biome Penalty: -", visibility_penalty * 100, "%")
	
	if shot_roll > final_hit_chance:
		print("CLEAN MISS! The shot was lost in the ", GameEnums.GridBiome.keys()[target_slot.background], ".")
		# Note: This is where you would open the Enemy Reaction Strike window
		return

	# 3. The Collateral Damage Check (Melee Lock)
	var final_victim: HumanoidCore = target_slot.occupants[0]
	
	if target_slot.is_melee_locked:
		print("WARNING: Firing into a Melee Lock! Calculating trajectory risk...")
		if randf() > 0.5:
			# The bullet hits the second occupant instead!
			final_victim = target_slot.occupants[1]
			print("COLLATERAL DAMAGE! The shot veered into ", final_victim.name, "!")
		else:
			print("Threaded the needle! The shot bypassed the grapple.")

	# 4. The Cover Check
	var cover_chance: float = target_slot.get_cover_interception()
	if randf() < cover_chance:
		print("IMPACT! The shot was absorbed by the [", target_slot.object_name, "].")
		target_slot.damage_cover(weapon.flesh_damage)
		return

	# 5. The Meat Impact
	print("DIRECT HIT! Striking ", final_victim.name, "...")
	_apply_ballistic_trauma(final_victim, weapon)

# ---------------------------------------------------------
# TRAUMA ROUTER
# ---------------------------------------------------------

func _apply_ballistic_trauma(victim: HumanoidCore, weapon: ItemData) -> void:
	# Prototype: Randomize which limb gets hit. 
	# A real system would let the player spend extra AP to "Aim" for the head.
	var hit_location = [
		GameEnums.LimbRegion.UPPER_TORSO, GameEnums.LimbRegion.LOWER_TORSO, GameEnums.LimbRegion.LEFT_ARM, 
		GameEnums.LimbRegion.RIGHT_ARM, GameEnums.LimbRegion.LEFT_LEG, GameEnums.LimbRegion.RIGHT_LEG
	].pick_random()
	
	# Run the damage through the armor resolution pipeline
	_resolve_damage(victim, weapon, hit_location)

# ---------------------------------------------------------
# ARMOR RESOLUTION PIPELINE
# ---------------------------------------------------------

func _resolve_damage(victim: HumanoidCore, weapon: ItemData, hit_location: GameEnums.LimbRegion) -> void:
	var raw_flesh: float = weapon.flesh_damage
	var raw_stance: float = weapon.stance_damage
	var penetration: float = weapon.armor_penetration
	var damage_type: GameEnums.DamageType = weapon.damage_type
	
	# 1. Get the victim's armor protection for this damage type
	var armor_value: float = victim.inventory.get_protection_for(damage_type)
	
	# 2. BULK provides bonus damage resistance (only positive BULK helps here)
	var bulk_bonus: float = max(0.0, victim.get_bulk_modifier()) * 0.5
	var total_defense: float = armor_value + bulk_bonus
	
	# 3. Penetration reduces armor effectiveness (0.0 = armor is god, 1.0 = armor is paper)
	var effective_defense: float = total_defense * (1.0 - clamp(penetration, 0.0, 1.0))
	
	# 4. Calculate final damage values
	var final_flesh: float = max(0.0, raw_flesh - effective_defense)
	
	# BLUNT damage always applies stance damage regardless of armor
	# SHARP/BALLISTIC only applies stance damage if it penetrates
	var final_stance: float = raw_stance
	if damage_type != GameEnums.DamageType.BLUNT:
		final_stance = max(0.0, raw_stance - (effective_defense * 0.5))
	
	# 5. Log the math
	print("--- ARMOR RESOLUTION ---")
	print("Damage Type: ", GameEnums.DamageType.keys()[damage_type], " | Raw: ", raw_flesh, " | Armor: ", armor_value, " | Bulk Bonus: ", bulk_bonus)
	print("Penetration: ", penetration, " | Effective Defense: ", effective_defense, " | Final Flesh: ", final_flesh)
	
	if final_flesh <= 0.0 and final_stance <= 0.0:
		print("DEFLECTED! The armor absorbed the entire impact.")
		return
	
	# 6. Apply the surviving damage to the meat
	if final_flesh > 0.0:
		victim.body.apply_targeted_hit(hit_location, final_flesh, penetration)
	
	# 7. Apply stance damage (equilibrium erosion)
	if final_stance > 0.0:
		var resulting_state = victim.apply_stance_damage(final_stance)
		print("STANCE IMPACT: -", final_stance, " equilibrium → ", GameEnums.StanceState.keys()[resulting_state], " (", victim.stance_points, "/12)")

func _find_entity_index(entity: HumanoidCore) -> int:
	for i in range(lane_manager.lane_slots.size()):
		if lane_manager.lane_slots[i].occupants.has(entity):
			return i
	return -1
