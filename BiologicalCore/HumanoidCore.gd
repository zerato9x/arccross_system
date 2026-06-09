extends Node
class_name HumanoidCore

# ---------------------------------------------------------
# SIGNALS: The Nervous System Broadcasting
# ---------------------------------------------------------
signal kinetic_burden_calculated(tier: GameEnums.KineticTier, burden: int)
signal died(cause: String)
signal arc_energy_depleted()
signal red_mist_corruption_maxed()
signal morale_broken()
signal stance_changed(new_state: GameEnums.StanceState, points: int)
signal felled()

@export_group("Core Identity")
@export var definition: EntityDefinition

# The Sub-Systems
@onready var body: HumanoidBody = $HumanoidBody
@onready var inventory: InventorySystem = $InventorySystem

# Dynamic Vitals
var base_ap: int = 12
var current_max_ap: int = 12 # Locked at 12 for the Base-12 system
var is_dead: bool = false
var kinetic_tier: GameEnums.KineticTier = GameEnums.KineticTier.FLUID
var total_burden: int = 0

# The 12-Point Stance Equilibrium Scale
var stance_points: int = 12 # 12 = rock solid, 0 = face in the mud
var current_stance: GameEnums.StanceState = GameEnums.StanceState.PLANTED

# Psychological & Metaphysical Status
var current_morale: float = 12.0
var is_fleeing: bool = false
var is_escaping: bool = false # Tracks the 1-turn delay for escaping
var current_arc_energy: float = 0.0
var red_mist_corruption: float = 0.0 # 0.0 = Pure, 1.0 = Feral Craven
var is_mindless_hive_thrall: bool = false
var is_comatose: bool = false # Physically paralyzed/comatose

# ---------------------------------------------------------
# INITIALIZATION & GENETICS
# ---------------------------------------------------------

func _ready() -> void:
	if not body or not inventory:
		push_error(name + " is missing its meat or pockets! Add HumanoidBody and InventorySystem.")
		return
		
	if definition: definition = definition.duplicate()
	if definition:
		_initialize_metaphysics()
		_derive_physical_reality()
	else:
		push_error(name + " has no EntityDefinition. It is a soul without a blueprint.")
		
	# Wire up the biological trauma sensors
	body.limb_destroyed.connect(_on_limb_destroyed)
	body.vital_failure.connect(_on_vital_failure)
	body.blood_level_changed.connect(_on_vitals_shifted)
	body.metabolic_crisis.connect(_on_metabolic_crisis)
	
	# Wire up the Vault feedback loop
	inventory.capacity_updated.connect(_on_inventory_weight_shifted)
	inventory.set_equipment_validator(_can_equip_item)
func _on_metabolic_crisis(condition: GameEnums.MetabolicCondition, severity: float) -> void:
	_calculate_kinetic_burden()
	
	# Being starving, freezing, or exhausted crushes the will to fight
	take_morale_damage(severity * 2.0)
	print(name, " is suffering from ", GameEnums.MetabolicCondition.keys()[condition], ". Morale dropping.")
func _initialize_metaphysics() -> void:
	current_arc_energy = definition.max_arc_energy
	
	if definition.faction == GameEnums.Faction.CRAVEN_HIVE or definition.agenda == GameEnums.Agenda.MINDLESS:
		is_mindless_hive_thrall = true
		red_mist_corruption = 1.0

func _derive_physical_reality() -> void:
	# 1. Fortitude dictates structural integrity (Base 12)
	var hp_multiplier: float = definition.fortitude / 6.0 # 6 is baseline average
	for limb in body.limb_hp.keys():
		body.limb_hp[limb] = body.BASE_LIMB_MAX[limb] * hp_multiplier
		
	# 2. Brawn strictly equals base pocket space
	inventory.base_max_capacity = definition.brawn
	inventory._recalculate_bounds()
	
	# 3. Will establishes psychological baseline
	current_morale = float(definition.will)
	
	# 4. Time is a constant. AP is heavily punished later by condition.
	base_ap = 12 
	_calculate_kinetic_burden()

# ---------------------------------------------------------
# THE HIDDEN COMBAT MECHANICS (Base-12 Getters)
# ---------------------------------------------------------

func get_initiative_roll() -> float:
	var reaction_speed: float = float(definition.finesse)
	
	# Encumbrance penalty (Maxes at a -6 to the roll if 100% full)
	var encumbrance_ratio: float = float(inventory.current_size) / float(max(1, inventory.current_max_capacity))
	var encumbrance_penalty: float = encumbrance_ratio * 6.0 
	
	return (randf() * 12.0) + reaction_speed - encumbrance_penalty

func get_grapple_strength() -> float:
	var muscle: float = float(definition.brawn)
	
	# Combine both torso regions for structural integrity
	var current_torso = body.limb_hp[GameEnums.LimbRegion.UPPER_TORSO] + body.limb_hp[GameEnums.LimbRegion.LOWER_TORSO]
	var max_torso = (body.BASE_LIMB_MAX[GameEnums.LimbRegion.UPPER_TORSO] + body.BASE_LIMB_MAX[GameEnums.LimbRegion.LOWER_TORSO]) * (definition.fortitude / 6.0)
	
	var structural_health: float = current_torso / max_torso
	
	return muscle * structural_health

func get_combat_accuracy(is_ranged: bool) -> float:
	if is_ranged:
		return definition.finesse / 12.0 
	else:
		return definition.brawn / 12.0

# ---------------------------------------------------------
# THE 12-POINT STANCE SCALE
# ---------------------------------------------------------
# 12 = PLANTED (stable, full action set)
# 7-11 = PLANTED (stable)
# 1-6 = STUMBLING (restricted actions, THREAT = 0, cannot flee)
# 0 = FELLED (stunned for one round, open to EXECUTE)

## Apply stance damage from a combat impact. Returns the new stance state.
func apply_stance_damage(amount: float) -> GameEnums.StanceState:
	if is_dead: return current_stance
	
	stance_points = max(0, stance_points - int(ceil(amount)))
	_evaluate_stance_state()
	return current_stance

## Attempt to recover stance points. Capped at 12.
## Use force=true to bypass the FELLED guard (e.g., mandatory turn-skip recovery).
func recover_stance(amount: int, force: bool = false) -> void:
	if is_dead: return
	if current_stance == GameEnums.StanceState.FELLED and not force: return
	
	stance_points = min(12, stance_points + amount)
	_evaluate_stance_state()

## Full stance reset (e.g., after successfully using GET_UP action).
func reset_stance() -> void:
	stance_points = 12
	_evaluate_stance_state()

func _evaluate_stance_state() -> void:
	var previous_state: GameEnums.StanceState = current_stance
	
	if stance_points >= 7:
		current_stance = GameEnums.StanceState.PLANTED
	elif stance_points >= 1:
		current_stance = GameEnums.StanceState.STUMBLING
	else:
		current_stance = GameEnums.StanceState.FELLED
	
	if current_stance != previous_state:
		stance_changed.emit(current_stance, stance_points)
		print(name, " stance shifted to ", GameEnums.StanceState.keys()[current_stance], " (", stance_points, "/12)")
		
		if current_stance == GameEnums.StanceState.FELLED:
			print("[FELLED] ", name, " has collapsed! Open to EXECUTE.")
			felled.emit()
			
		if current_stance == GameEnums.StanceState.STUMBLING:
			# Stumbling entities project zero THREAT
			print("[STUMBLING] ", name, "'s THREAT drops to 0. Actions restricted.")

## Override: THREAT is 0 when stumbling or felled.
func get_effective_threat() -> float:
	if current_stance != GameEnums.StanceState.PLANTED:
		return 0.0
	return get_threat_level()

# ---------------------------------------------------------
# THE "BLACK KNIGHT" FIX (Limb vs. Inventory Validation)
# ---------------------------------------------------------

func _on_limb_destroyed(limb: GameEnums.LimbRegion) -> void:
	if limb == GameEnums.LimbRegion.LEFT_ARM or limb == GameEnums.LimbRegion.RIGHT_ARM:
		_validate_equipment_requirements()
		
	# Massive psychological shock from losing a limb
	take_morale_damage(5.0) 
	_calculate_kinetic_burden()
		
	
func _validate_equipment_requirements() -> void:
	if body.has_functional_arms(): return
		
	var held_item: ItemData = inventory.paper_doll[GameEnums.EquipmentSlot.HANDS]
	
	if held_item != null and held_item.requires_two_hands:
		print(name, " physically cannot hold [", held_item.display_name, "] with one arm!")
		inventory.unequip_item(GameEnums.EquipmentSlot.HANDS) # Vault handles spill-over automatically

func _can_equip_item(item: ItemData, _slot: GameEnums.EquipmentSlot) -> bool:
	if item.requires_two_hands and not body.has_functional_arms():
		return false
	return true

# ---------------------------------------------------------
# DYNAMIC ACTION POINT MATH
# ---------------------------------------------------------

func _on_inventory_weight_shifted(_current: int, _max: int) -> void:
	_calculate_kinetic_burden()

func _on_vitals_shifted(blood_level: float) -> void:
	_calculate_kinetic_burden()
	
	# If you are bleeding out, panic sets in
	if blood_level < 0.5:
		take_morale_damage(2.0)

func _calculate_kinetic_burden() -> void:
	if is_dead: return
	
	# 1. The Meat Penalty (Trauma)
	var motor_efficiency: float = body.get_motor_efficiency()
	var trauma_penalty: int = floor((1.0 - motor_efficiency) * 6.0)
	
	# 2. The Junk Penalty (Encumbrance)
	var encumbrance_ratio: float = float(inventory.current_size) / float(max(1, inventory.current_max_capacity))
	var weight_penalty: int = floor(encumbrance_ratio * 6.0)
	
	# 3. The Iron Tax (Gear WEIGHT across all equipped items)
	var gear_weight_penalty: int = floor(inventory.get_total_weight())
	
	# 4. The Survival Penalty (Hunger, Thirst, Fatigue)
	var survival_penalty: int = 0
	if body.hunger < 0.2: survival_penalty += 1
	if body.thirst < 0.2: survival_penalty += 2 # Dehydration heavily limits muscle function
	if body.fatigue > 0.8: survival_penalty += int(body.fatigue * 4.0) # Up to -4 AP from sheer exhaustion
	if body.core_temperature < 34.0: survival_penalty += 2 # Shivering ruins coordination
	
	total_burden = trauma_penalty + weight_penalty + gear_weight_penalty + survival_penalty
	
	var old_tier = kinetic_tier
	if total_burden >= 9:
		kinetic_tier = GameEnums.KineticTier.AGONIZING
	elif total_burden >= 4:
		kinetic_tier = GameEnums.KineticTier.LABORED
	else:
		kinetic_tier = GameEnums.KineticTier.FLUID
		
	is_comatose = (total_burden >= 18)
	if is_comatose:
		print(name, " has entered a comatose/paralyzed state due to extreme physiological exhaustion!")
	elif kinetic_tier != old_tier:
		print(name, " Kinetic Tier shifted to ", GameEnums.KineticTier.keys()[kinetic_tier], " (Burden: ", total_burden, ")")
		
	kinetic_burden_calculated.emit(kinetic_tier, total_burden)
# ---------------------------------------------------------
# PSYCHOLOGICAL TRAUMA LOGIC
# ---------------------------------------------------------

func take_morale_damage(amount: float) -> void:
	if is_mindless_hive_thrall or is_fleeing: return
		
	current_morale = max(0.0, current_morale - amount)
	_evaluate_flight_response()

func _evaluate_flight_response(opponent_threat: float = -1.0) -> void:
	var breakpoint_ratio: float = 0.0
	
	match definition.agenda:
		GameEnums.Agenda.SURVIVALIST: breakpoint_ratio = 0.6 # Runs at 60% morale
		GameEnums.Agenda.BELLIGERENT: breakpoint_ratio = 0.2 # Runs at 20% morale
		GameEnums.Agenda.ZEALOT, GameEnums.Agenda.MINDLESS: return # Never runs
		
	# THE THREAT CHECK: SURVIVALIST enemies flee immediately if out-Threatened
	if definition.agenda == GameEnums.Agenda.SURVIVALIST and opponent_threat >= 0.0:
		if opponent_threat > float(definition.will):
			is_fleeing = true
			print("\n[THREAT OVERRIDE] ", name, " sees THREAT(", opponent_threat, ") > WILL(", definition.will, "). Fleeing immediately!")
			morale_broken.emit()
			return
	
	var breaking_point = float(definition.will) * breakpoint_ratio
	
	if current_morale <= breaking_point:
		is_fleeing = true
		print("\n[MORALE SHATTERED] ", name, " has broken! Self-preservation override engaged!")
		morale_broken.emit()

## Get total THREAT projected by this entity's equipped gear.
func get_threat_level() -> float:
	return inventory.get_total_threat()

## Get total BULK modifier from equipped gear. Negative = agile, Positive = tanky.
func get_bulk_modifier() -> float:
	return inventory.get_total_bulk()

## Get insulation rating from equipped torso layers for hypothermia calculations.
func get_insulation_rating() -> float:
	return inventory.get_total_insulation()

# ---------------------------------------------------------
# ARC & RED MIST (The World Hooks)
# ---------------------------------------------------------

func process_environmental_tick(in_red_mist_zone: bool, mist_intensity: float) -> void:
	if is_mindless_hive_thrall: return
		
	if in_red_mist_zone:
		var net_exposure = mist_intensity * (1.0 - definition.red_mist_resistance)
		red_mist_corruption = clamp(red_mist_corruption + (net_exposure * 0.01), 0.0, 1.0)
		
		if red_mist_corruption >= 1.0:
			_mutate_into_craven()

func spend_arc_force(amount: float) -> bool:
	if definition.arc_tier == GameEnums.ArcbornTier.NONE: return false
		
	if current_arc_energy >= amount:
		current_arc_energy -= amount
		return true
		
	arc_energy_depleted.emit()
	return false

func _mutate_into_craven() -> void:
	is_mindless_hive_thrall = true
	definition.agenda = GameEnums.Agenda.MINDLESS
	current_arc_energy = 0.0
	red_mist_corruption_maxed.emit()
	
	# Strip complex items to prevent tactical zombies
	inventory.unequip_item(GameEnums.EquipmentSlot.HANDS)
	inventory.unequip_item(GameEnums.EquipmentSlot.BACKPACK)
	print(name, " succumbed to the Red Mist. Structural autonomy and tools lost.")

# ---------------------------------------------------------
# CONSUMABLE USE
# ---------------------------------------------------------

func use_consumable_item(item: ItemData) -> bool:
	if not inventory.use_consumable(item):
		return false
	
	# Route the effect to the appropriate biological system
	match item.consumable_effect:
		GameEnums.ConsumableEffect.RESTORE_HUNGER:
			body.hunger = clamp(body.hunger + item.consumable_potency, 0.0, 1.0)
			print(name, " consumed [", item.display_name, "]. Hunger restored.")
		GameEnums.ConsumableEffect.RESTORE_THIRST:
			body.thirst = clamp(body.thirst + item.consumable_potency, 0.0, 1.0)
			print(name, " consumed [", item.display_name, "]. Thirst quenched.")
		GameEnums.ConsumableEffect.RESTORE_FATIGUE:
			body.fatigue = clamp(body.fatigue - item.consumable_potency, 0.0, 1.0)
			print(name, " consumed [", item.display_name, "]. Fatigue reduced.")
		GameEnums.ConsumableEffect.STOP_BLEEDING:
			# Patch the worst bleed first
			for limb in body.limb_trauma.keys():
				if body.limb_trauma[limb] == GameEnums.TraumaType.BLEEDING:
					body.limb_trauma[limb] = GameEnums.TraumaType.NONE
					print(name, " applied [", item.display_name, "] to stop bleeding on ", GameEnums.LimbRegion.keys()[limb], ".")
					break
		GameEnums.ConsumableEffect.RESTORE_BLOOD:
			body.blood_level = clamp(body.blood_level + item.consumable_potency, 0.0, 1.0)
			body.blood_level_changed.emit(body.blood_level)
			print(name, " consumed [", item.display_name, "]. Blood volume stabilized.")
	
	_calculate_kinetic_burden()
	return true

# ---------------------------------------------------------
# DEATH PROTOCOL
# ---------------------------------------------------------

func _on_vital_failure(reason: String) -> void:
	if is_dead: return
	
	is_dead = true
	current_max_ap = 0
	print(name, " has flatlined. Cause: ", reason)
	died.emit(reason)

# ---------------------------------------------------------
# RUNTIME STATE CONTRACT
# ---------------------------------------------------------

func capture_runtime_state() -> Dictionary:
	return {
		"body": body.capture_runtime_state(),
		"inventory": inventory.capture_runtime_state(),
		"base_ap": base_ap,
		"current_max_ap": current_max_ap,
		"is_dead": is_dead,
		"stance_points": stance_points,
		"current_morale": current_morale,
		"is_fleeing": is_fleeing,
		"is_escaping": is_escaping,
		"current_arc_energy": current_arc_energy,
		"red_mist_corruption": red_mist_corruption,
		"is_mindless_hive_thrall": is_mindless_hive_thrall,
		"is_comatose": is_comatose,
	}

func restore_runtime_state(state: Dictionary) -> void:
	if state.is_empty():
		return

	body.restore_runtime_state(state.get("body", {}))
	inventory.restore_runtime_state(state.get("inventory", {}))
	base_ap = state.get("base_ap", base_ap)
	current_max_ap = state.get("current_max_ap", current_max_ap)
	is_dead = state.get("is_dead", is_dead)
	stance_points = state.get("stance_points", stance_points)
	current_morale = state.get("current_morale", current_morale)
	is_fleeing = state.get("is_fleeing", false)
	is_escaping = state.get("is_escaping", false)
	current_arc_energy = state.get("current_arc_energy", current_arc_energy)
	red_mist_corruption = state.get("red_mist_corruption", red_mist_corruption)
	is_mindless_hive_thrall = state.get(
		"is_mindless_hive_thrall",
		is_mindless_hive_thrall
	)
	is_comatose = state.get("is_comatose", is_comatose)
	_evaluate_stance_state()
	_calculate_kinetic_burden()
