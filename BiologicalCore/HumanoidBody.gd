extends Node
class_name HumanoidBody

# ---------------------------------------------------------
# SIGNALS: The sounds of suffering
# ---------------------------------------------------------
signal limb_destroyed(limb: GameEnums.LimbRegion)
signal vital_failure(reason: String)
signal blood_level_changed(current_level: float)
signal metabolic_crisis(condition: String, severity: float)

const BASE_LIMB_MAX = {
	GameEnums.LimbRegion.HEAD: 30.0,
	GameEnums.LimbRegion.UPPER_TORSO: 60.0,
	GameEnums.LimbRegion.LOWER_TORSO: 40.0,
	GameEnums.LimbRegion.LEFT_ARM: 40.0,
	GameEnums.LimbRegion.RIGHT_ARM: 40.0,
	GameEnums.LimbRegion.LEFT_LEG: 50.0,
	GameEnums.LimbRegion.RIGHT_LEG: 50.0
}

var limb_hp: Dictionary = {}
var limb_trauma: Dictionary = {} # Tracks bleeding rates per limb

@export_group("Systemic Vitals")
var core_temperature: float = 37.0
var blood_level: float = 1.0 # 1.0 = Full, 0.0 = Puddle
var hunger: float = 1.0      # 1.0 = Full, 0.0 = Starving
var thirst: float = 1.0      # 1.0 = Hydrated, 0.0 = Dehydrated
var fatigue: float = 0.0     # 0.0 = Rested, 1.0 = Passing out
# The structural baseline. Everyone gets the same bones.

func _ready() -> void:
	for limb in BASE_LIMB_MAX.keys():
		limb_hp[limb] = BASE_LIMB_MAX[limb]
		limb_trauma[limb] = GameEnums.TraumaType.NONE

# ---------------------------------------------------------
# TRAUMA APPLICATION
# ---------------------------------------------------------

func apply_targeted_hit(limb: GameEnums.LimbRegion, raw_damage: float, penetration: float) -> void:
	# You can't kill a limb that's already gone
	if limb_hp[limb] <= 0:
		return 
		
	# High penetration causes bleeding trauma
	if penetration > 0.5 and limb_trauma[limb] != GameEnums.TraumaType.BLEEDING:
		limb_trauma[limb] = GameEnums.TraumaType.BLEEDING
		
	limb_hp[limb] = max(0.0, limb_hp[limb] - raw_damage)
	
	if limb_hp[limb] == 0:
		_handle_destroyed_limb(limb)

func _handle_destroyed_limb(limb: GameEnums.LimbRegion) -> void:
	limb_trauma[limb] = GameEnums.TraumaType.SHATTERED_LIMB
	limb_destroyed.emit(limb)
	
	# The lethal checks
	if limb == GameEnums.LimbRegion.HEAD:
		vital_failure.emit("Cranial destruction")
	elif limb == GameEnums.LimbRegion.UPPER_TORSO:
		vital_failure.emit("Circulatory collapse")
	elif limb == GameEnums.LimbRegion.LOWER_TORSO:
		vital_failure.emit("Organ failure")

# ---------------------------------------------------------
# BIOLOGICAL TICK (Called on the Macro Hex-Map Loop)
# ---------------------------------------------------------

func process_biological_tick(environmental_temp: float, insulation_rating: float, exertion_level: float = 1.0) -> void:
	# 1. Process Blood Loss (Your original code)
	var active_bleeds: int = 0
	for limb in limb_trauma.keys():
		if limb_trauma[limb] == GameEnums.TraumaType.BLEEDING:
			active_bleeds += 1
			
	if active_bleeds > 0:
		blood_level = max(0.0, blood_level - (active_bleeds * 0.05))
		blood_level_changed.emit(blood_level)
		if blood_level <= 0.0:
			vital_failure.emit("Exsanguination")
			return
			
	# 2. Process Core Temperature
	var thermal_differential = environmental_temp - core_temperature
	if thermal_differential < 0:
		core_temperature += (thermal_differential * (1.0 - clamp(insulation_rating, 0.0, 1.0))) * 0.05
		
	# 3. Process Calories, Hydration, and Sleep
	# Exertion level (e.g., walking through Swamp vs Plains) accelerates the drain
	hunger = max(0.0, hunger - (0.01 * exertion_level))
	thirst = max(0.0, thirst - (0.03 * exertion_level)) # Thirst kills faster than hunger
	fatigue = min(1.0, fatigue + (0.02 * exertion_level))

	# 4. Trigger Crisis Alarms
	if hunger < 0.2: metabolic_crisis.emit("STARVING", 1.0 - (hunger / 0.2))
	if thirst < 0.2: metabolic_crisis.emit("DEHYDRATED", 1.0 - (thirst / 0.2))
	if fatigue > 0.8: metabolic_crisis.emit("EXHAUSTED", (fatigue - 0.8) / 0.2)
	if core_temperature < 32.0: metabolic_crisis.emit("HYPOTHERMIA", (32.0 - core_temperature) / 10.0)

# ---------------------------------------------------------
# UTILITY MATH
# ---------------------------------------------------------

func get_motor_efficiency() -> float:
	# A combined metric of leg health and blood volume to calculate AP
	var leg_current: float = limb_hp[GameEnums.LimbRegion.LEFT_LEG] + limb_hp[GameEnums.LimbRegion.RIGHT_LEG]
	var leg_max: float = BASE_LIMB_MAX[GameEnums.LimbRegion.LEFT_LEG] + BASE_LIMB_MAX[GameEnums.LimbRegion.RIGHT_LEG]
	
	var leg_efficiency: float = leg_current / leg_max
	
	# If you have no blood, you can't run, even with perfect legs
	return clamp(leg_efficiency * blood_level, 0.1, 1.0)

func has_functional_arms() -> bool:
	return limb_hp[GameEnums.LimbRegion.LEFT_ARM] > 0 and limb_hp[GameEnums.LimbRegion.RIGHT_ARM] > 0
