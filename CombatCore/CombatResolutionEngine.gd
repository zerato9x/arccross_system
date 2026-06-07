extends Node
class_name CombatResolutionEngine

@export var lane_manager: CombatLaneManager

# ---------------------------------------------------------
# THE RANGED TRAJECTORY MATH
# ---------------------------------------------------------

func execute_ranged_strike(attacker: HumanoidCore, target_idx: int) -> void:
	var target_slot: CombatLaneSlot = lane_manager.lane_slots[target_idx]
	var weapon: ItemData = attacker.inventory.paper_doll[GameEnums.EquipmentSlot.HANDS]
	
	if weapon == null or weapon.weapon_type != GameEnums.WeaponClass.FIREARM:
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
		GameEnums.Limb.TORSO, GameEnums.Limb.LEFT_ARM, 
		GameEnums.Limb.RIGHT_ARM, GameEnums.Limb.LEFT_LEG, GameEnums.Limb.RIGHT_LEG
	].pick_random()
	
	# Firearms have high penetration, guaranteeing bleeding trauma
	victim.body.apply_targeted_hit(hit_location, weapon.flesh_damage, 0.8)

func _find_entity_index(entity: HumanoidCore) -> int:
	for i in range(lane_manager.lane_slots.size()):
		if lane_manager.lane_slots[i].occupants.has(entity):
			return i
	return -1
