extends Node
class_name HumanoidCore

const MINDLESS_BASE_AP: int = 8

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
var has_stance_recovery_guard: bool = false

# Psychological & Metaphysical Status
var current_morale: float = 12.0
var is_fleeing: bool = false
var is_escaping: bool = false # Tracks the 1-turn delay for escaping
var current_arc_energy: float = 0.0
var red_mist_corruption: float = 0.0 # 0 = Pure, 12 = Feral Craven
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
	take_morale_damage(severity / GameEnums.SCALE_MIDPOINT)
	print(name, " is suffering from ", GameEnums.MetabolicCondition.keys()[condition], ". Morale dropping.")
func _initialize_metaphysics() -> void:
	current_arc_energy = definition.max_arc_energy
	
	if definition.faction == GameEnums.Faction.CRAVEN_HIVE or definition.agenda == GameEnums.Agenda.MINDLESS:
		is_mindless_hive_thrall = true
		red_mist_corruption = GameEnums.SCALE_MAX
		print("[Stats] ", name, " flagged MINDLESS HIVE THRALL (no flight response, ignores THREAT).")

func _derive_physical_reality() -> void:
	# 1. Fortitude dictates structural integrity (Base 12)
	body.configure_structure(definition.fortitude)
		
	# 2. Carrying space comes from worn containers, not unexplained anatomy.
	inventory.base_max_capacity = 0
	inventory._recalculate_bounds()
	
	# 3. Will establishes psychological baseline
	current_morale = float(definition.will)
	
	# 4. Mindless thralls are frantic but biologically ruined. They get a shorter
	# action budget instead of chaining a charge and several attacks every turn.
	base_ap = MINDLESS_BASE_AP if is_mindless_hive_thrall else 12
	current_max_ap = base_ap
	_calculate_kinetic_burden()

	print(
		"[Stats] ", name, " (", definition.archetype_name, ") derived -> ",
		"BRAWN ", definition.brawn, " FINESSE ", definition.finesse,
		" FORT ", definition.fortitude, " WILL ", definition.will,
		" | morale ", current_morale, " | tactic ",
		GameEnums.CombatTactic.keys()[definition.combat_tactic]
	)

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
	var max_torso = (
		body.get_limb_max(GameEnums.LimbRegion.UPPER_TORSO)
		+ body.get_limb_max(GameEnums.LimbRegion.LOWER_TORSO)
	)
	
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
# 1-6 = STUMBLING (normal turn, passive recovery, THREAT = 0)
# 0 = FELLED (must spend the next active turn getting up)

## Apply equilibrium loss from an impact. Ordinary impacts stop at 1 Stance;
## explicit takedown actions may pass can_fell=true to reduce a target to 0.
func apply_stance_damage(
	amount: float,
	can_fell: bool = false
) -> GameEnums.StanceState:
	if is_dead: return current_stance
	if current_stance == GameEnums.StanceState.FELLED:
		return current_stance
	
	var stance_floor := (
		0
		if can_fell and not has_stance_recovery_guard
		else 1
	)
	var previous_points := stance_points
	stance_points = max(
		stance_floor,
		stance_points - int(ceil(amount))
	)
	_evaluate_stance_state()
	if (
		has_stance_recovery_guard
		and previous_points > stance_floor
		and stance_points == stance_floor
	):
		print(
			"[RECOVERY GUARD] ",
			name,
			" cannot be FELLED again before their next active turn."
		)
	return current_stance

## Attempt to recover stance points. Capped at 12.
## Use force=true to rise from FELLED while resolving GET_UP.
func recover_stance(amount: int, force: bool = false) -> void:
	if is_dead: return
	if current_stance == GameEnums.StanceState.FELLED and not force: return
	
	stance_points = min(12, stance_points + amount)
	_evaluate_stance_state()

## Full stance reset for encounter setup and explicit restoration effects.
func reset_stance() -> void:
	stance_points = 12
	has_stance_recovery_guard = false
	_evaluate_stance_state()

## Resolve GET_UP by rising from FELLED into STUMBLING.
## The floor prevents an opponent from creating an indefinite knockdown loop.
func begin_felled_recovery(recovery_points: int) -> void:
	if is_dead or current_stance != GameEnums.StanceState.FELLED:
		return
	recover_stance(recovery_points, true)
	has_stance_recovery_guard = true
	print(
		"[RECOVERY GUARD] ",
		name,
		" is protected from another knockdown until their next active turn."
	)

## Called only when this entity receives a usable active turn.
func expire_stance_recovery_guard() -> void:
	if not has_stance_recovery_guard:
		return
	has_stance_recovery_guard = false
	print("[RECOVERY GUARD] ", name, " can be FELLED normally again.")

## Force a collapse while respecting temporary recovery protection.
func try_fell() -> bool:
	if is_dead:
		return false
	if has_stance_recovery_guard:
		stance_points = 1
		_evaluate_stance_state()
		print(
			"[RECOVERY GUARD] ",
			name,
			" resisted a forced knockdown."
		)
		return false
	stance_points = 0
	_evaluate_stance_state()
	return true

## Clear tactical state that has no meaning outside one combat encounter.
## Wounds, Blood, Morale, inventory, and survival state remain untouched.
func reset_combat_transients() -> void:
	stance_points = int(GameEnums.SCALE_MAX)
	has_stance_recovery_guard = false
	is_fleeing = false
	is_escaping = false
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
			print("[FELLED] ", name, " has collapsed and must use GET UP.")
			felled.emit()
			
		if current_stance == GameEnums.StanceState.STUMBLING:
			# Stumbling entities project zero THREAT
			print(
				"[STUMBLING] ",
				name,
				"'s THREAT drops to 0, but their active turn remains available."
			)

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
		
	var held_item: ItemData = inventory.paper_doll.get(GameEnums.EquipmentSlot.HAND, null)
	
	if held_item != null and held_item.requires_two_hands:
		print(name, " physically cannot hold [", held_item.display_name, "] with one arm!")
		inventory.unequip_item(GameEnums.EquipmentSlot.HAND)

func _can_equip_item(item: ItemData, _slot: GameEnums.EquipmentSlot) -> bool:
	if item.requires_two_hands and not body.has_functional_arms():
		return false
	return true

# ---------------------------------------------------------
# DYNAMIC ACTION POINT MATH
# ---------------------------------------------------------

func _on_inventory_weight_shifted(_current: int, _max: int) -> void:
	_calculate_kinetic_burden()

func _on_vitals_shifted(current_blood_level: float) -> void:
	_calculate_kinetic_burden()
	
	# If you are bleeding out, panic sets in
	if current_blood_level < GameEnums.SCALE_MIDPOINT:
		take_morale_damage(2.0)

func _calculate_kinetic_burden() -> void:
	if is_dead: return
	
	# 1. The Meat Penalty (Trauma)
	var motor_efficiency: float = body.get_motor_efficiency()
	var trauma_penalty: int = floor((1.0 - motor_efficiency) * 6.0)
	
	# 2. The Junk Penalty (Encumbrance)
	var encumbrance_ratio: float = float(inventory.current_size) / float(max(1, inventory.current_max_capacity))
	var weight_penalty: int = floor(encumbrance_ratio * 4.0)
	
	# 3. Equipped mass and bulk tax movement; neither stat is free armor.
	var gear_weight_penalty: int = floor(inventory.get_total_weight() * 0.25)
	var bulk_penalty: int = floor(inventory.get_total_bulk() * 0.25)
	
	# 4. The Survival Penalty (Hunger, Thirst, Fatigue)
	var survival_penalty: int = 0
	if body.hunger < GameEnums.SCALE_MAX * 0.2: survival_penalty += 1
	if body.thirst < GameEnums.SCALE_MAX * 0.2: survival_penalty += 2
	if body.fatigue > GameEnums.SCALE_MAX * 0.8:
		var fatigue_ratio := body.fatigue / GameEnums.SCALE_MAX
		survival_penalty += int(fatigue_ratio * 4.0)
	if body.core_temperature < 34.0: survival_penalty += 2 # Shivering ruins coordination
	
	total_burden = trauma_penalty + weight_penalty + gear_weight_penalty + bulk_penalty + survival_penalty
	
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
		if kinetic_tier == GameEnums.KineticTier.AGONIZING:
			var bus = get_node_or_null("/root/GameEventBus")
			if bus:
				bus.emit_humanoid_exhausted(self)
		
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
		
	# THE THREAT CHECK: survivalists compare the opponent's projected threat
	# against both their nerve and their own equipment. The old WILL-only check
	# made any scavenger facing the player's starting pistol flee immediately,
	# even when the scavenger was armed just as well.
	if definition.agenda == GameEnums.Agenda.SURVIVALIST and opponent_threat >= 0.0:
		var threat_tolerance := float(definition.will) + get_effective_threat()
		if opponent_threat > threat_tolerance:
			is_fleeing = true
			print(
				"\n[THREAT OVERRIDE] ",
				name,
				" sees THREAT(",
				opponent_threat,
				") > TOLERANCE(",
				threat_tolerance,
				"). Fleeing immediately!"
			)
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

func process_survival_time(
	elapsed_minutes: int,
	environmental_temp: float,
	exertion_level: float = 1.0,
	insulation_bonus: float = 0.0
) -> void:
	if is_dead or elapsed_minutes <= 0:
		return
	body.process_elapsed_time(
		elapsed_minutes,
		environmental_temp,
		get_insulation_rating() + insulation_bonus,
		exertion_level
	)
	_calculate_kinetic_burden()

# ---------------------------------------------------------
# ARC & RED MIST (The World Hooks)
# ---------------------------------------------------------

func process_environmental_tick(in_red_mist_zone: bool, mist_intensity: float) -> void:
	if is_mindless_hive_thrall: return
		
	if in_red_mist_zone:
		var intensity := clampf(mist_intensity, 0.0, GameEnums.SCALE_MAX)
		var resistance_ratio := clampf(
			definition.red_mist_resistance / GameEnums.SCALE_MAX,
			0.0,
			1.0
		)
		var net_exposure = intensity * (1.0 - resistance_ratio)
		red_mist_corruption = clamp(
			red_mist_corruption + (net_exposure * 0.01),
			0.0,
			GameEnums.SCALE_MAX
		)
		
		if red_mist_corruption >= GameEnums.SCALE_MAX:
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
	inventory.unequip_item(GameEnums.EquipmentSlot.HAND)
	inventory.unequip_item(GameEnums.EquipmentSlot.BACKPACK)
	print(name, " succumbed to the Red Mist. Structural autonomy and tools lost.")

# ---------------------------------------------------------
# CONSUMABLE USE
# ---------------------------------------------------------

func apply_consumable_to_limb(
	item: ItemData,
	region: int,
	combat_only: bool = false
) -> bool:
	if item == null:
		return false
	match item.consumable_effect:
		GameEnums.ConsumableEffect.STOP_BLEEDING:
			if not body.can_treat_bleeding(region):
				return false
			if not inventory.use_consumable(item, combat_only):
				return false
			body.treat_worst_bleed(region, item.consumable_potency)
			print(name, " treated the worst bleed on ", GameEnums.LimbRegion.keys()[region], " with [", item.display_name, "].")
		GameEnums.ConsumableEffect.RESTORE_BLOOD:
			if not inventory.use_consumable(item, combat_only):
				return false
			body.blood_level = clamp(
				body.blood_level + item.consumable_potency,
				0.0,
				GameEnums.SCALE_MAX
			)
			body.blood_level_changed.emit(body.blood_level)
		GameEnums.ConsumableEffect.RESTORE_HUNGER:
			if not inventory.use_consumable(item, combat_only):
				return false
			body.hunger = clamp(
				body.hunger + item.consumable_potency,
				0.0,
				GameEnums.SCALE_MAX
			)
		GameEnums.ConsumableEffect.RESTORE_THIRST:
			if not inventory.use_consumable(item, combat_only):
				return false
			body.thirst = clamp(
				body.thirst + item.consumable_potency,
				0.0,
				GameEnums.SCALE_MAX
			)
		GameEnums.ConsumableEffect.RESTORE_FATIGUE:
			if not inventory.use_consumable(item, combat_only):
				return false
			body.fatigue = clamp(
				body.fatigue - item.consumable_potency,
				0.0,
				GameEnums.SCALE_MAX
			)
		_:
			return false
	_calculate_kinetic_burden()
	return true


func use_consumable_item(item: ItemData, combat_only: bool = false) -> bool:
	if item == null:
		return false
	if item.consumable_effect == GameEnums.ConsumableEffect.STOP_BLEEDING:
		var has_treatable_bleed := false
		for limb in body.limb_trauma.keys():
			if body.can_treat_bleeding(limb):
				has_treatable_bleed = true
				break
		if not has_treatable_bleed:
			return false
	if not inventory.use_consumable(item, combat_only):
		return false
	
	# Route the effect to the appropriate biological system
	match item.consumable_effect:
		GameEnums.ConsumableEffect.RESTORE_HUNGER:
			body.hunger = clamp(
				body.hunger + item.consumable_potency,
				0.0,
				GameEnums.SCALE_MAX
			)
			print(name, " consumed [", item.display_name, "]. Hunger restored.")
		GameEnums.ConsumableEffect.RESTORE_THIRST:
			body.thirst = clamp(
				body.thirst + item.consumable_potency,
				0.0,
				GameEnums.SCALE_MAX
			)
			print(name, " consumed [", item.display_name, "]. Thirst quenched.")
		GameEnums.ConsumableEffect.RESTORE_FATIGUE:
			body.fatigue = clamp(
				body.fatigue - item.consumable_potency,
				0.0,
				GameEnums.SCALE_MAX
			)
			print(name, " consumed [", item.display_name, "]. Fatigue reduced.")
		GameEnums.ConsumableEffect.STOP_BLEEDING:
			var target_limb := -1
			var worst_rate := 0.0
			for limb in body.limb_trauma.keys():
				var rate := body.get_limb_bleeding_rate(limb)
				if body.can_treat_bleeding(limb) and (target_limb < 0 or rate > worst_rate):
					target_limb = limb
					worst_rate = rate
			if target_limb < 0:
				return false
			body.treat_worst_bleed(target_limb, item.consumable_potency)
			print(name, " treated the worst active bleed on ", GameEnums.LimbRegion.keys()[target_limb], ".")
		GameEnums.ConsumableEffect.RESTORE_BLOOD:
			body.blood_level = clamp(
				body.blood_level + item.consumable_potency,
				0.0,
				GameEnums.SCALE_MAX
			)
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

func capture_runtime_state() -> HumanoidState:
	var state := HumanoidState.new()
	state.body = body.capture_runtime_state()
	state.inventory = inventory.capture_runtime_state()
	state.base_ap = base_ap
	state.current_max_ap = current_max_ap
	state.is_dead = is_dead
	state.stance_points = stance_points
	state.current_morale = current_morale
	state.is_fleeing = is_fleeing
	state.is_escaping = is_escaping
	state.current_arc_energy = current_arc_energy
	state.red_mist_corruption = red_mist_corruption
	state.is_mindless_hive_thrall = is_mindless_hive_thrall
	state.is_comatose = is_comatose
	return state

func restore_runtime_state(state) -> void:
	var humanoid_state: HumanoidState
	if state is HumanoidState:
		humanoid_state = state
	elif state is Dictionary:
		if state.is_empty():
			return
		humanoid_state = HumanoidState.from_dict(state)
	else:
		return

	if humanoid_state.body:
		body.restore_runtime_state(humanoid_state.body)
	if humanoid_state.inventory:
		inventory.restore_runtime_state(humanoid_state.inventory)
	base_ap = humanoid_state.base_ap
	current_max_ap = humanoid_state.current_max_ap
	is_dead = humanoid_state.is_dead
	stance_points = clampi(humanoid_state.stance_points, 0, int(GameEnums.SCALE_MAX))
	current_morale = clampf(humanoid_state.current_morale, 0.0, GameEnums.SCALE_MAX)
	is_fleeing = humanoid_state.is_fleeing
	is_escaping = humanoid_state.is_escaping
	current_arc_energy = clampf(
		humanoid_state.current_arc_energy,
		0.0,
		definition.max_arc_energy if definition else GameEnums.SCALE_MAX
	)
	red_mist_corruption = clampf(
		humanoid_state.red_mist_corruption,
		0.0,
		GameEnums.SCALE_MAX
	)
	is_mindless_hive_thrall = humanoid_state.is_mindless_hive_thrall
	is_comatose = humanoid_state.is_comatose
	has_stance_recovery_guard = false
	_evaluate_stance_state()
	_calculate_kinetic_burden()
