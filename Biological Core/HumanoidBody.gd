extends Node
class_name HumanoidBody

# ---------------------------------------------------------
# SIGNALS: The sounds of suffering
# ---------------------------------------------------------
signal limb_destroyed(limb: GameEnums.Limb)
signal vital_failure(reason: String)
signal blood_level_changed(current_level: float)

# The structural baseline. Everyone gets the same bones.
const BASE_LIMB_MAX = {
	GameEnums.Limb.HEAD: 30.0,
	GameEnums.Limb.TORSO: 100.0,
	GameEnums.Limb.LEFT_ARM: 40.0,
	GameEnums.Limb.RIGHT_ARM: 40.0,
	GameEnums.Limb.LEFT_LEG: 50.0,
	GameEnums.Limb.RIGHT_LEG: 50.0
}

var limb_hp: Dictionary = {}
var limb_trauma: Dictionary = {} # Tracks bleeding rates per limb

@export_group("Systemic Vitals")
var core_temperature: float = 37.0
var blood_level: float = 1.0 # 1.0 = Full, 0.0 = You are a puddle
var hunger: float = 1.0 
var thrist: float = 1.0

func _ready() -> void:
	for limb in BASE_LIMB_MAX.keys():
		limb_hp[limb] = BASE_LIMB_MAX[limb]
		limb_trauma[limb] = GameEnums.TraumaType.NONE

# ---------------------------------------------------------
# TRAUMA APPLICATION
# ---------------------------------------------------------

func apply_targeted_hit(limb: GameEnums.Limb, raw_damage: float, penetration: float) -> void:
	# You can't kill a limb that's already gone
	if limb_hp[limb] <= 0:
		return 
		
	# High penetration causes bleeding trauma
	if penetration > 0.5 and limb_trauma[limb] != GameEnums.TraumaType.BLEEDING:
		limb_trauma[limb] = GameEnums.TraumaType.BLEEDING
		
	limb_hp[limb] = max(0.0, limb_hp[limb] - raw_damage)
	
	if limb_hp[limb] == 0:
		_handle_destroyed_limb(limb)

func _handle_destroyed_limb(limb: GameEnums.Limb) -> void:
	limb_trauma[limb] = GameEnums.TraumaType.SHATTERED
	limb_destroyed.emit(limb)
	
	# The lethal checks
	if limb == GameEnums.Limb.HEAD:
		vital_failure.emit("Cranial destruction")
	elif limb == GameEnums.Limb.TORSO:
		vital_failure.emit("Circulatory collapse")

# ---------------------------------------------------------
# BIOLOGICAL TICK (Called on the Macro Hex-Map Loop)
# ---------------------------------------------------------

func process_biological_tick(environmental_temp: float, insulation_rating: float) -> void:
	# 1. Process Blood Loss
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
			
	# 2. Process Core Temperature (Hypothermia)
	var thermal_differential = environmental_temp - core_temperature
	if thermal_differential < 0:
		# The better your coat (insulation_rating), the slower you freeze
		core_temperature += (thermal_differential * (1.0 - clamp(insulation_rating, 0.0, 1.0))) * 0.05

# ---------------------------------------------------------
# UTILITY MATH
# ---------------------------------------------------------

func get_motor_efficiency() -> float:
	# A combined metric of leg health and blood volume to calculate AP
	var leg_current: float = limb_hp[GameEnums.Limb.LEFT_LEG] + limb_hp[GameEnums.Limb.RIGHT_LEG]
	var leg_max: float = BASE_LIMB_MAX[GameEnums.Limb.LEFT_LEG] + BASE_LIMB_MAX[GameEnums.Limb.RIGHT_LEG]
	
	var leg_efficiency: float = leg_current / leg_max
	
	# If you have no blood, you can't run, even with perfect legs
	return clamp(leg_efficiency * blood_level, 0.1, 1.0)

func has_functional_arms() -> bool:
	return limb_hp[GameEnums.Limb.LEFT_ARM] > 0 and limb_hp[GameEnums.Limb.RIGHT_ARM] > 0
