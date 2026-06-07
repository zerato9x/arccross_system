extends Node
class_name HumanoidCore

# ---------------------------------------------------------
# SIGNALS: The Nervous System Broadcasting
# ---------------------------------------------------------
signal ap_calculated(max_ap: int)
signal died(cause: String)
signal arc_energy_depleted()
signal red_mist_corruption_maxed()
signal morale_broken()

@export_group("Core Identity")
@export var definition: EntityDefinition

# The Sub-Systems
@onready var body: HumanoidBody = $HumanoidBody
@onready var inventory: InventorySystem = $InventorySystem

# Dynamic Vitals
var base_ap: int = 12
var current_max_ap: int = 12
var is_dead: bool = false

# Psychological & Metaphysical Status
var current_morale: float = 12.0
var is_fleeing: bool = false
var current_arc_energy: float = 0.0
var red_mist_corruption: float = 0.0 # 0.0 = Pure, 1.0 = Feral Craven
var is_mindless_hive_thrall: bool = false

# ---------------------------------------------------------
# INITIALIZATION & GENETICS
# ---------------------------------------------------------

func _ready() -> void:
	if not body or not inventory:
		push_error(name + " is missing its meat or pockets! Add HumanoidBody and InventorySystem.")
		return
		
	if definition:
		_initialize_metaphysics()
		_derive_physical_reality()
	else:
		push_error(name + " has no EntityDefinition. It is a soul without a blueprint.")
		
	# Wire up the biological trauma sensors
	body.limb_destroyed.connect(_on_limb_destroyed)
	body.vital_failure.connect(_on_vital_failure)
	body.blood_level_changed.connect(_on_vitals_shifted)
	
	# Wire up the Vault feedback loop
	inventory.capacity_updated.connect(_on_inventory_weight_shifted)

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
	_calculate_action_points()

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
	var structural_health: float = body.limb_hp[GameEnums.Limb.TORSO] / (100.0 * (definition.fortitude / 6.0))
	
	return muscle * structural_health

func get_combat_accuracy(is_ranged: bool) -> float:
	if is_ranged:
		return definition.finesse / 12.0 
	else:
		return definition.brawn / 12.0

# ---------------------------------------------------------
# THE "BLACK KNIGHT" FIX (Limb vs. Inventory Validation)
# ---------------------------------------------------------

func _on_limb_destroyed(limb: GameEnums.Limb) -> void:
	if limb == GameEnums.Limb.LEFT_ARM or limb == GameEnums.Limb.RIGHT_ARM:
		_validate_equipment_requirements()
		
	# Massive psychological shock from losing a limb
	take_morale_damage(5.0) 
	_calculate_action_points()

func _validate_equipment_requirements() -> void:
	if body.has_functional_arms(): return
		
	var held_item: ItemData = inventory.paper_doll[GameEnums.EquipmentSlot.HANDS]
	
	if held_item != null and held_item.requires_two_hands:
		print(name, " physically cannot hold [", held_item.display_name, "] with one arm!")
		inventory.unequip_item(GameEnums.EquipmentSlot.HANDS) # Vault handles spill-over automatically

# ---------------------------------------------------------
# DYNAMIC ACTION POINT MATH
# ---------------------------------------------------------

func _on_inventory_weight_shifted(_current: int, _max: int) -> void:
	_calculate_action_points()

func _on_vitals_shifted(blood_level: float) -> void:
	_calculate_action_points()
	
	# If you are bleeding out, panic sets in
	if blood_level < 0.5:
		take_morale_damage(2.0)

func _calculate_action_points() -> void:
	if is_dead: return
	
	# Start with the perfect 12
	var ap: float = float(base_ap)
	
	# The Meat Penalty: Leg trauma and blood loss crush mobility
	ap *= body.get_motor_efficiency()
	
	# The Junk Penalty: Encumbrance drains AP (up to half your pool if fully loaded)
	var encumbrance_ratio: float = float(inventory.current_size) / float(max(1, inventory.current_max_capacity))
	var weight_penalty: int = floor(encumbrance_ratio * 6.0)
	
	current_max_ap = max(2, int(ap) - weight_penalty) # Hard floor of 2 AP
	ap_calculated.emit(current_max_ap)

# ---------------------------------------------------------
# PSYCHOLOGICAL TRAUMA LOGIC
# ---------------------------------------------------------

func take_morale_damage(amount: float) -> void:
	if is_mindless_hive_thrall or is_fleeing: return
		
	current_morale = max(0.0, current_morale - amount)
	_evaluate_flight_response()

func _evaluate_flight_response() -> void:
	var breakpoint_ratio: float = 0.0
	
	match definition.agenda:
		GameEnums.Agenda.SURVIVALIST: breakpoint_ratio = 0.6 # Runs at 60% morale
		GameEnums.Agenda.BELLIGERENT: breakpoint_ratio = 0.2 # Runs at 20% morale
		GameEnums.Agenda.ZEALOT, GameEnums.Agenda.MINDLESS: return # Never runs
		
	var breaking_point = float(definition.will) * breakpoint_ratio
	
	if current_morale <= breaking_point:
		is_fleeing = true
		print("\n[MORALE SHATTERED] ", name, " has broken! Self-preservation override engaged!")
		morale_broken.emit()

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
# DEATH PROTOCOL
# ---------------------------------------------------------

func _on_vital_failure(reason: String) -> void:
	if is_dead: return
	
	is_dead = true
	current_max_ap = 0
	print(name, " has flatlined. Cause: ", reason)
	died.emit(reason)
