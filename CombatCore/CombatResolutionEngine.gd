extends Node
class_name CombatResolutionEngine

@export var lane_manager: CombatLaneManager
@export var turn_manager: CombatTurnManager

const MELEE_HIT_REGIONS := [
	GameEnums.LimbRegion.UPPER_TORSO,
	GameEnums.LimbRegion.LOWER_TORSO,
	GameEnums.LimbRegion.LEFT_ARM,
	GameEnums.LimbRegion.RIGHT_ARM,
	GameEnums.LimbRegion.LEFT_LEG,
	GameEnums.LimbRegion.RIGHT_LEG,
]

# ---------------------------------------------------------
# THE RANGED TRAJECTORY MATH
# ---------------------------------------------------------

func execute_ranged_strike(attacker: HumanoidCore, target_idx: int) -> void:
	await _execute_shot(
		attacker,
		target_idx,
		false,
		GameEnums.LimbRegion.HEAD
	)

func execute_aimed_shot(attacker: HumanoidCore, target_idx: int, target_limb: GameEnums.LimbRegion) -> void:
	await _execute_shot(attacker, target_idx, true, target_limb)

func _execute_shot(attacker: HumanoidCore, target_idx: int, is_aimed: bool, target_limb: GameEnums.LimbRegion) -> void:
	var target_slot: CombatLaneSlot = lane_manager.lane_slots[target_idx]
	var weapon: ItemData = attacker.inventory.get_active_weapon(false) # Ranged context
	
	if weapon == null or not weapon.is_ranged():
		print("ERROR: ", attacker.name, " tried to shoot someone without a gun.")
		return

	var attacker_idx: int = _find_entity_index(attacker)
	var distance: int = absi(attacker_idx - target_idx)
	if distance > weapon.effective_range:
		print(
			"DENIED: ",
			weapon.display_name,
			" has an effective range of ",
			weapon.effective_range,
			" tiles; target is ",
			distance,
			" tiles away."
		)
		return
	if weapon.current_magazine <= 0:
		print("DENIED: ", attacker.name, "'s ", weapon.display_name, " is empty.")
		return
	if weapon.needs_cycling:
		print("DENIED: ", attacker.name, "'s ", weapon.display_name, " needs CYCLING.")
		return

	weapon.current_magazine -= 1
	weapon.needs_cycling = weapon.requires_cycle_after_shot
	var action_name := (
		"[AIMED %s]" % GameEnums.WeaponClass.keys()[weapon.weapon_type]
		if is_aimed
		else "[%s]" % GameEnums.WeaponClass.keys()[weapon.weapon_type]
	)
	print(
		action_name,
		" ",
		attacker.name,
		" fires! Rounds: ",
		weapon.current_magazine,
		"/",
		weapon.max_magazine
	)

	if target_slot.occupants.size() == 0:
		print("Miss! ", attacker.name, " fired a bullet into empty mud.")
		return

	# 1. Determine Distance
	# 2. Base Accuracy vs Environment Math
	var shooter_accuracy := clampf(
		attacker.get_combat_accuracy(true),
		0.0,
		1.0
	)
	var weapon_accuracy := clampf(
		weapon.accuracy_rating / GameEnums.SCALE_MAX,
		0.0,
		1.0
	)
	var base_accuracy := (
		0.25
		+ shooter_accuracy * 0.35
		+ weapon_accuracy * 0.40
	)
	var range_penalty := maxf(0.0, float(distance - 1) * 0.04)
	var aim_bonus := 0.15 if is_aimed else 0.0
	var visibility_penalty: float = target_slot.get_visibility_penalty()
	var final_hit_chance := clampf(
		base_accuracy + aim_bonus - range_penalty - visibility_penalty,
		0.05,
		0.95
	)
	
	var shot_roll: float = randf()
	
	print("\n--- SHOT FIRED ---")
	print(
		"Distance: ",
		distance,
		" | Accuracy: ",
		roundi(final_hit_chance * 100.0),
		"% | Biome Penalty: -",
		visibility_penalty * 100,
		"%"
	)
	
	# 3. Open DODGE reaction window before resolving the hit
	var victim: HumanoidCore = target_slot.occupants[0]
	var chosen_reaction = -1
	var reaction_success: bool = false
	if turn_manager:
		var reaction_occurred: bool = false
		var on_res = func(def, react, success):
			if def == victim:
				reaction_occurred = true
				chosen_reaction = react
				reaction_success = success
		
		turn_manager.reaction_resolved.connect(on_res)
		var action_type = GameEnums.ActionType.AIMED_SHOT if is_aimed else GameEnums.ActionType.SHOOT
		var reactions = turn_manager.open_reaction_window(victim, attacker, action_type)
		if turn_manager._reaction_pending and not reaction_occurred:
			await turn_manager.reaction_resolved
		turn_manager.reaction_resolved.disconnect(on_res)
		
	if chosen_reaction == GameEnums.ActionType.DODGE and reaction_success:
		if resolve_dodge(victim, attacker):
			print("[SHOOT ABORTED] Dodge succeeded!")
			return
	
	if shot_roll > final_hit_chance:
		print(
			"CLEAN MISS! The shot was lost in the ",
			CombatRules.TileBackground.keys()[target_slot.background],
			"."
		)
		return

	# 4. The Collateral Damage Check (Melee Lock)
	var final_victim: HumanoidCore = target_slot.occupants[0]
	
	if target_slot.is_melee_locked:
		print("WARNING: Firing into a Melee Lock! Calculating trajectory risk...")
		if randf() > 0.5:
			final_victim = target_slot.occupants[1]
			print("COLLATERAL DAMAGE! The shot veered into ", final_victim.name, "!")
		else:
			print("Threaded the needle! The shot bypassed the grapple.")

	# 5. The Cover Check
	var cover_chance: float = target_slot.get_cover_interception()
	if randf() < cover_chance:
		print("IMPACT! The shot was absorbed by the [", target_slot.object_name, "].")
		target_slot.damage_cover(weapon.flesh_damage)
		return

	# 6. The Meat Impact
	print("DIRECT HIT! Striking ", final_victim.name, "...")
	var damage_multiplier := weapon.damage_multiplier_at_distance(distance)
	if is_aimed:
		_resolve_damage(
			final_victim,
			weapon,
			target_limb,
			damage_multiplier
		)
	else:
		_apply_ballistic_trauma(
			final_victim,
			weapon,
			damage_multiplier
		)

# ---------------------------------------------------------
# PISTOL RELOAD
# ---------------------------------------------------------

func execute_reload(entity: HumanoidCore) -> bool:
	var weapon: ItemData = entity.inventory.get_active_weapon(false) # Ranged context
	if weapon == null or not weapon.is_ranged():
		print("ERROR: ", entity.name, " tried to reload something that isn't a firearm.")
		return false
	
	if weapon.current_magazine >= weapon.max_magazine:
		print(entity.name, "'s ", weapon.display_name, " is already full.")
		return false

	if (
		not weapon.magazine_id.is_empty()
		and not _inventory_has_item(entity, weapon.magazine_id)
	):
		print(
			"DENIED: ",
			weapon.display_name,
			" requires ",
			weapon.magazine_id,
			"."
		)
		return false
	if (
		not weapon.reload_aid_id.is_empty()
		and not _inventory_has_item(entity, weapon.reload_aid_id)
	):
		print(
			"DENIED: Fast RELOAD requires ",
			weapon.reload_aid_id,
			"; use CYCLE to load one round."
		)
		return false
	if (
		weapon.magazine_id.is_empty()
		and weapon.reload_aid_id.is_empty()
		and weapon.cycle_loads_one_round
	):
		print("DENIED: ", weapon.display_name, " is loaded one round at a time with CYCLE.")
		return false

	var rounds_needed: int = weapon.max_magazine - weapon.current_magazine
	var rounds_loaded: int = 0
	
	for i in range(rounds_needed):
		if _consume_ammunition_from_backpack(
			entity,
			weapon.ammunition_id
		):
			rounds_loaded += 1
		else:
			break
	
	if rounds_loaded > 0:
		weapon.current_magazine += rounds_loaded
		print(
			"[RELOAD] ",
			entity.name,
			" loaded ",
			rounds_loaded,
			" rounds into ",
			weapon.display_name,
			". Rounds: ",
			weapon.current_magazine,
			"/",
			weapon.max_magazine
		)
		return true
	
	print("DENIED: ", entity.name, " has no compatible ", weapon.ammunition_id, ".")
	return false

# ---------------------------------------------------------
# RIFLE CYCLE
# ---------------------------------------------------------

func execute_cycle(entity: HumanoidCore) -> bool:
	var weapon: ItemData = entity.inventory.get_active_weapon(false) # Ranged context
	if weapon == null or not weapon.is_ranged():
		print("ERROR: ", entity.name, " tried to cycle something that isn't a firearm.")
		return false
	
	if weapon.needs_cycling:
		weapon.needs_cycling = false
		print("[CYCLE] ", entity.name, " cycles ", weapon.display_name, ". Ready to fire.")
		return true

	if not weapon.cycle_loads_one_round:
		print(entity.name, "'s ", weapon.display_name, " does not need cycling.")
		return false
	if weapon.current_magazine >= weapon.max_magazine:
		print(entity.name, "'s ", weapon.display_name, " is already full.")
		return false
	if not _consume_ammunition_from_backpack(
		entity,
		weapon.ammunition_id
	):
		print("DENIED: No compatible ", weapon.ammunition_id, " to load.")
		return false

	weapon.current_magazine += 1
	print(
		"[CYCLE LOAD] ",
		entity.name,
		" loads one round into ",
		weapon.display_name,
		". Rounds: ",
		weapon.current_magazine,
		"/",
		weapon.max_magazine
	)
	return true



# ---------------------------------------------------------
# MELEE STRIKE RESOLUTION
# ---------------------------------------------------------

func execute_melee_strike(attacker: HumanoidCore, defender: HumanoidCore) -> void:
	var weapon: ItemData = attacker.inventory.get_active_weapon(true) # Melee context
	
	# Open BLOCK / DODGE reaction window for defender
	var chosen_reaction = -1
	var reaction_success: bool = false
	if turn_manager:
		var reaction_occurred: bool = false
		var on_res = func(def, react, success):
			if def == defender:
				reaction_occurred = true
				chosen_reaction = react
				reaction_success = success
		
		turn_manager.reaction_resolved.connect(on_res)
		var reactions = turn_manager.open_reaction_window(defender, attacker, GameEnums.ActionType.STRIKE)
		if turn_manager._reaction_pending and not reaction_occurred:
			await turn_manager.reaction_resolved
		turn_manager.reaction_resolved.disconnect(on_res)
		
	if reaction_success:
		if chosen_reaction == GameEnums.ActionType.DODGE:
			if resolve_dodge(defender, attacker):
				print("[STRIKE ABORTED] Dodge succeeded!")
				return
		elif chosen_reaction == GameEnums.ActionType.BLOCK:
			if resolve_block(defender, attacker, weapon):
				print("[STRIKE BLOCKED] Block succeeded, mitigated damage applied.")
				return
	
	var target_limb := roll_melee_target()
	print("\n--- MELEE STRIKE ---")
	print(attacker.name, " swings at ", defender.name, "'s ", GameEnums.LimbRegion.keys()[target_limb])
	
	if weapon:
		_resolve_damage(defender, weapon, target_limb)
	else:
		# Unarmed strike — minimal damage
		defender.body.apply_targeted_hit(target_limb, 0.5, 0.0)
		defender.apply_stance_damage(2.0)
		print("[UNARMED] Fists connect for minor trauma.")

func roll_melee_target() -> GameEnums.LimbRegion:
	return MELEE_HIT_REGIONS.pick_random()

# ---------------------------------------------------------
# GRAPPLE RESOLUTION
# ---------------------------------------------------------
# Opposed Base-12 check. The defender wins ties. Success fells the defender;
# the initiator pays a smaller stance cost for committing to the takedown.

func execute_grapple(
	initiator: HumanoidCore,
	defender: HumanoidCore,
	attack_roll_override: int = -1,
	defense_roll_override: int = -1
) -> bool:
	var initiator_lane := _find_entity_index(initiator)
	var defender_lane := _find_entity_index(defender)
	if initiator_lane < 0 or initiator_lane != defender_lane:
		print("DENIED: GRAPPLE requires both combatants in the same lane slot.")
		return false
	if defender.current_stance == GameEnums.StanceState.FELLED:
		print("DENIED: ", defender.name, " is already FELLED.")
		return false

	var attack_roll := _base12_roll(attack_roll_override)
	var defense_roll := _base12_roll(defense_roll_override)
	var force := (
		initiator.get_grapple_strength()
		+ float(initiator.stance_points) / 3.0
		+ float(attack_roll)
	)
	var resistance := (
		maxf(
			defender.get_grapple_strength(),
			float(defender.definition.finesse)
		)
		+ float(defender.stance_points) / 3.0
		+ float(defense_roll)
	)

	print("\n--- GRAPPLE CHECK ---")
	print(initiator.name, " ", force, " vs ", defender.name, " ", resistance)
	if force <= resistance:
		print("[GRAPPLE FAILED] ", defender.name, " keeps their footing.")
		initiator.apply_stance_damage(2.0)
		return false

	print("[GRAPPLE SUCCESS] ", initiator.name, " takes ", defender.name, " down.")
	if not defender.try_fell():
		print("[GRAPPLE CHECK] Recovery Guard prevented the knockdown.")
		return false
	initiator.apply_stance_damage(3.0)
	return true

# ---------------------------------------------------------
# EXECUTE RESOLUTION
# ---------------------------------------------------------
# Instantly incapacitates/kills a FELLED opponent in the same grid slot.

func execute_execute(executioner: HumanoidCore, victim: HumanoidCore) -> void:
	if not CombatRules.EXECUTE_ENABLED:
		print("DENIED: EXECUTE is disabled until its trait unlock is implemented.")
		return
	if victim.current_stance != GameEnums.StanceState.FELLED:
		print("DENIED: ", victim.name, " is not FELLED. Cannot execute.")
		return
	
	# Verify same grid slot
	var exec_idx = _find_entity_index(executioner)
	var victim_idx = _find_entity_index(victim)
	if exec_idx != victim_idx:
		print("DENIED: ", executioner.name, " is not in the same grid slot as ", victim.name)
		return
	
	print("\n--- EXECUTION ---")
	print(executioner.name, " delivers the killing blow to ", victim.name, "!")
	
	# Instant kill — target the head for narrative flavor
	victim.body.apply_targeted_hit(
		GameEnums.LimbRegion.HEAD,
		999.0,
		GameEnums.SCALE_MAX
	)

# ---------------------------------------------------------
# BREAK (Braced Stance Attack)
# ---------------------------------------------------------
# Focused strike that erodes stance points ONLY, no flesh damage. It can fell
# a target only when they were already Stumbling before the impact.

func execute_break(attacker: HumanoidCore, defender: HumanoidCore) -> void:
	var weapon: ItemData = attacker.inventory.get_active_weapon(true) # Melee context
	
	print("\n--- BREAK STRIKE ---")
	print(attacker.name, " delivers a destabilizing strike against ", defender.name, "'s footing!")
	
	var stance_dmg: float = 4.0 # Base break damage
	if weapon:
		stance_dmg = weapon.stance_damage * 1.5 # Break amplifies stance damage
	
	var can_fell := (
		defender.current_stance == GameEnums.StanceState.STUMBLING
	)
	var resulting_state = defender.apply_stance_damage(
		stance_dmg,
		can_fell
	)
	print("[BREAK] ", defender.name, " takes ", stance_dmg, " stance damage → ", GameEnums.StanceState.keys()[resulting_state], " (", defender.stance_points, "/12)")

# ---------------------------------------------------------
# TAKE COVER RESOLUTION
# ---------------------------------------------------------
# Drops the entity's profile and lets them brace against nearby cover.
# Evasion benefit calculated from environmental assets.

func execute_take_cover(entity: HumanoidCore) -> void:
	print("\n--- TAKE COVER ---")
	print(entity.name, " drops to the ground behind available cover!")
	
	entity.recover_stance(CombatRules.TAKE_COVER_STANCE_RECOVERY)
	print(
		"[COVER] ",
		entity.name,
		" braces and recovers ",
		CombatRules.TAKE_COVER_STANCE_RECOVERY,
		" Stance."
	)
	
	# The Evasion Benefit is evaluated at resolution time when being shot at
	# (CombatResolutionEngine checks for TAKE_COVER status during ranged calculations)

# ---------------------------------------------------------
# GET UP RESOLUTION
# ---------------------------------------------------------

func execute_get_up(entity: HumanoidCore) -> bool:
	if entity.current_stance != GameEnums.StanceState.FELLED:
		print("DENIED: ", entity.name, " is not FELLED.")
		return false

	print("\n--- GET UP ---")
	entity.begin_felled_recovery(CombatRules.FELLED_RECOVERY_POINTS)
	print(
		"[GET UP] ",
		entity.name,
		" rises at ",
		entity.stance_points,
		"/12 Stance."
	)
	return entity.current_stance != GameEnums.StanceState.FELLED

# ---------------------------------------------------------
# TRIP RESOLUTION (Prone Window)
# ---------------------------------------------------------
# Consumes ALL remaining AP. Dexterity check against standing/stumbling opponent.

func execute_trip(tripper: HumanoidCore, target: HumanoidCore) -> bool:
	if target.current_stance == GameEnums.StanceState.FELLED:
		print("DENIED: ", target.name, " is already face-down.")
		return false
	
	# Verify same grid slot
	var tripper_idx = _find_entity_index(tripper)
	var target_idx = _find_entity_index(target)
	if tripper_idx != target_idx:
		print("DENIED: Must be in the same grid slot to TRIP.")
		return false
	
	print("\n--- TRIP ATTEMPT ---")
	print(tripper.name, " sweeps at ", target.name, "'s legs from the ground!")
	
	# Dexterity check: Tripper's Finesse vs Target's Finesse
	var trip_roll: float = randf() * float(tripper.definition.finesse) + float(tripper.definition.finesse)
	var resist_roll: float = randf() * float(target.definition.finesse) + float(target.definition.finesse)
	
	# STUMBLING targets are much easier to trip
	if target.current_stance == GameEnums.StanceState.STUMBLING:
		trip_roll *= 1.5
	
	print("[TRIP] Roll: ", trip_roll, " vs Resist: ", resist_roll)
	
	if trip_roll > resist_roll:
		print("[TRIP SUCCESS] ", target.name, " is yanked into the mud!")
		return target.try_fell()
	else:
		print("[TRIP FAILED] ", target.name, " stayed upright.")
		return false

# ---------------------------------------------------------
# LEVERAGE FORMULA: PUSH / PULL
# ---------------------------------------------------------
# Force = GrappleStrength + StanceSupport + d12
# Resistance = GrappleStrength + StanceSupport + d12
# Defender wins ties. A FELLED defender cannot resist displacement.

func execute_leverage_check(
	initiator: HumanoidCore,
	defender: HumanoidCore,
	is_push: bool,
	attack_roll_override: int = -1,
	defense_roll_override: int = -1
) -> bool:
	print("\n--- LEVERAGE CHECK (", ("PUSH" if is_push else "PULL"), ") ---")
	
	# FELLED = Automatic initiator success
	if defender.current_stance == GameEnums.StanceState.FELLED:
		print("[LEVERAGE] Defender is FELLED → Automatic success!")
		return true
	
	var attack_roll := _base12_roll(attack_roll_override)
	var defense_roll := _base12_roll(defense_roll_override)
	var force := (
		initiator.get_grapple_strength()
		+ float(initiator.stance_points) / 3.0
		+ float(attack_roll)
	)
	var resistance := (
		defender.get_grapple_strength()
		+ float(defender.stance_points) / 3.0
		+ float(defense_roll)
	)
	
	print("Force: ", force, " | Resistance: ", resistance)
	
	if force > resistance:
		print("[LEVERAGE SUCCESS] ", defender.name, " is displaced!")
		return true
	else:
		# Failure Rebound: Initiator slips, takes 2 Stance Points self-damage
		print("[LEVERAGE FAILED] ", initiator.name, " slips! Taking 2 stance self-damage.")
		var rebound_state = initiator.apply_stance_damage(2.0)
		print("[REBOUND] ", initiator.name, " → ", GameEnums.StanceState.keys()[rebound_state], " (", initiator.stance_points, "/12)")
		return false

func _base12_roll(override_value: int) -> int:
	if override_value >= 1:
		return clampi(override_value, 1, int(GameEnums.SCALE_MAX))
	return randi_range(1, int(GameEnums.SCALE_MAX))

# ---------------------------------------------------------
# HAZARD TILE CHECKS (Trip Clause / Momentum Risk)
# ---------------------------------------------------------
# MOVE and CHARGE through MUD or SWAMP tiles trigger a balance evaluation.
# Failure → FELLED.

func check_hazard_trip(entity: HumanoidCore, tile_slot: CombatLaneSlot, is_charge: bool) -> bool:
	# Only MUD triggers slip checks (SWAMP would be added to TileBackground if needed)
	if tile_slot.background != CombatRules.TileBackground.MUD:
		return false
	
	var slip_base: float = 0.15 # 15% base slip chance on MUD
	if is_charge:
		slip_base = 0.30 # 30% — The Momentum Risk for CHARGE
	
	# Finesse helps keep your footing
	var finesse_bonus: float = float(entity.definition.finesse) * 0.02
	var final_slip_chance: float = max(0.05, slip_base - finesse_bonus)
	
	var roll: float = randf()
	
	if roll < final_slip_chance:
		print("[HAZARD] ", entity.name, " slips on the treacherous terrain!")
		return entity.try_fell()
	
	return false

# ---------------------------------------------------------
# DODGE HAZARD CHECK (The Hazard Clause)
# ---------------------------------------------------------
# Dodging inside MUD/SWAMP tiles forces a trip evaluation.

func check_dodge_hazard(entity: HumanoidCore, tile_slot: CombatLaneSlot) -> bool:
	if tile_slot.background != CombatRules.TileBackground.MUD:
		return false
	
	var trip_chance: float = 0.20 # 20% chance of tripping while dodging in mud
	var finesse_bonus: float = float(entity.definition.finesse) * 0.015
	var final_chance: float = max(0.05, trip_chance - finesse_bonus)
	
	if randf() < final_chance:
		print("[DODGE HAZARD] ", entity.name, " slipped while dodging in the mud!")
		return entity.try_fell()
	
	return false

# ---------------------------------------------------------
# BLOCK RESOLUTION
# ---------------------------------------------------------

func resolve_block(defender: HumanoidCore, attacker: HumanoidCore, weapon: ItemData) -> bool:
	if not defender.body.has_functional_arms():
		print("[BLOCK FAILED] ", defender.name, " cannot block — arms are shattered.")
		return false
	
	print("[BLOCK] ", defender.name, " raises a guard against the incoming strike!")
	
	# Damage type rules: blunt stance bleed-through (50% stance damage) vs. sharp mitigation (0 stance, 10% flesh)
	var final_stance: float = 0.0
	var final_flesh: float = 0.0
	
	if weapon:
		if weapon.damage_type == GameEnums.DamageType.BLUNT:
			final_stance = weapon.stance_damage * 0.5
			final_flesh = weapon.flesh_damage * 0.25
		elif weapon.damage_type == GameEnums.DamageType.SHARP:
			final_stance = 0.0
			final_flesh = weapon.flesh_damage * 0.10
		else:
			# Ballistic or other types
			final_stance = 0.0
			final_flesh = weapon.flesh_damage * 0.25
	else:
		# Unarmed block
		final_stance = 1.0
		final_flesh = 0.5
		
	# Apply reduced damage to the blocking arm
	var block_arm: GameEnums.LimbRegion = GameEnums.LimbRegion.LEFT_ARM
	if defender.body.limb_hp[GameEnums.LimbRegion.LEFT_ARM] <= 0:
		block_arm = GameEnums.LimbRegion.RIGHT_ARM
	
	if final_flesh > 0.0:
		defender.body.apply_targeted_hit(block_arm, final_flesh, 1.0)
		print("[BLOCK] ", defender.name, " absorbed the strike. Arm took ", final_flesh, " bleed-through damage.")
		
	if final_stance > 0.0:
		var resulting_state = defender.apply_stance_damage(final_stance)
		print("[BLOCK BLEED-THROUGH] Blunt impact rattled posture: -", final_stance, " stance → ", GameEnums.StanceState.keys()[resulting_state])
		
	return true

# ---------------------------------------------------------
# DODGE RESOLUTION
# ---------------------------------------------------------

func resolve_dodge(defender: HumanoidCore, attacker: HumanoidCore) -> bool:
	# The Cripple Clause
	if defender.body.limb_hp[GameEnums.LimbRegion.LEFT_LEG] <= 0 or defender.body.limb_hp[GameEnums.LimbRegion.RIGHT_LEG] <= 0:
		print("[DODGE FAILED] ", defender.name, " cannot dodge — legs are crippled.")
		return false
	
	# Finesse-based dodge roll
	var dodge_roll: float = randf() * float(defender.definition.finesse)
	
	# Derived dynamically from attacker's stats: finesse (ranged) or brawn (melee)
	# Check what weapon they are currently holding to define attack type
	var weapon: ItemData = attacker.inventory.get_active_weapon(false) # Assume ranged first
	if weapon == null: weapon = attacker.inventory.get_active_weapon(true) # Fallback to melee
	var is_ranged_attack: bool = weapon != null and weapon.is_ranged()
	var attacker_stat: float = float(attacker.definition.finesse) if is_ranged_attack else float(attacker.definition.brawn)
	var hit_roll: float = randf() * attacker_stat
	
	print("[DODGE] ", defender.name, " attempts to evade! Roll: ", dodge_roll, " vs ", hit_roll)
	
	if dodge_roll > hit_roll:
		# Check the Hazard Clause — dodging in mud might trip you
		var defender_idx = _find_entity_index(defender)
		if defender_idx >= 0:
			var tile = lane_manager.lane_slots[defender_idx]
			if check_dodge_hazard(defender, tile):
				print("[DODGE] Evaded the attack but tripped in the mud!")
				return true # Dodge succeeded but entity is now FELLED
		
		print("[DODGE SUCCESS] ", defender.name, " deftly sidesteps the attack!")
		return true
	
	print("[DODGE FAILED] ", defender.name, " couldn't clear the trajectory.")
	return false

# ---------------------------------------------------------
# TRAUMA ROUTER
# ---------------------------------------------------------

func _apply_ballistic_trauma(
	victim: HumanoidCore,
	weapon: ItemData,
	damage_multiplier: float = 1.0
) -> void:
	# Prototype: Randomize which limb gets hit. 
	# A real system would let the player spend extra AP to "Aim" for the head.
	var hit_location = [
		GameEnums.LimbRegion.UPPER_TORSO, GameEnums.LimbRegion.LOWER_TORSO, GameEnums.LimbRegion.LEFT_ARM, 
		GameEnums.LimbRegion.RIGHT_ARM, GameEnums.LimbRegion.LEFT_LEG, GameEnums.LimbRegion.RIGHT_LEG
	].pick_random()
	
	# Run the damage through the armor resolution pipeline
	_resolve_damage(victim, weapon, hit_location, damage_multiplier)

# ---------------------------------------------------------
# ARMOR RESOLUTION PIPELINE
# ---------------------------------------------------------

func _resolve_damage(
	victim: HumanoidCore,
	weapon: ItemData,
	hit_location: GameEnums.LimbRegion,
	damage_multiplier: float = 1.0
) -> void:
	var raw_flesh: float = weapon.flesh_damage * damage_multiplier
	var raw_stance: float = weapon.stance_damage
	var penetration: float = weapon.armor_penetration
	var damage_type: GameEnums.DamageType = weapon.damage_type
	
	if damage_type == GameEnums.DamageType.BALLISTIC:
		raw_stance = 0.0
	
	# 1. Get the victim's armor protection for this damage type
	var armor_value: float = victim.inventory.get_protection_for(damage_type)
	
	# 2. BULK provides bonus damage resistance (only positive BULK helps here)
	var bulk_bonus: float = max(0.0, victim.get_bulk_modifier()) * 0.5
	var total_defense: float = armor_value + bulk_bonus
	
	# 3. Penetration is authored on 0-12 and becomes a ratio only for this formula.
	var penetration_ratio := clampf(
		penetration / GameEnums.SCALE_MAX,
		0.0,
		1.0
	)
	var effective_defense: float = total_defense * (1.0 - penetration_ratio)
	
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

# ---------------------------------------------------------
# AMMO UTILITY
# ---------------------------------------------------------

func _inventory_has_item(entity: HumanoidCore, item_id: String) -> bool:
	if item_id.is_empty():
		return true
	for item in entity.inventory.backpack_array:
		if item.id == item_id:
			return true
	return false

## Consume one compatible loose round from the backpack.
func _consume_ammunition_from_backpack(
	entity: HumanoidCore,
	ammunition_id: String
) -> bool:
	var resolved_id := ammunition_id if not ammunition_id.is_empty() else "ammo_round"
	for item in entity.inventory.backpack_array:
		if item.id == resolved_id:
			entity.inventory.backpack_array.erase(item)
			entity.inventory._recalculate_bounds()
			return true
	return false

func _find_entity_index(entity: HumanoidCore) -> int:
	for i in range(lane_manager.lane_slots.size()):
		if lane_manager.lane_slots[i].occupants.has(entity):
			return i
	return -1
