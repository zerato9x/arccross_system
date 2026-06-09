extends Node
class_name HumanoidBody

# ---------------------------------------------------------
# SIGNALS: The sounds of suffering
# ---------------------------------------------------------
signal limb_destroyed(limb: GameEnums.LimbRegion)
signal vital_failure(reason: String)
signal blood_level_changed(current_level: float)
signal metabolic_crisis(condition: GameEnums.MetabolicCondition, severity: float)

const BASE_LIMB_MAX = {
	GameEnums.LimbRegion.HEAD: 6.0,
	GameEnums.LimbRegion.UPPER_TORSO: 12.0,
	GameEnums.LimbRegion.LOWER_TORSO: 8.0,
	GameEnums.LimbRegion.LEFT_ARM: 8.0,
	GameEnums.LimbRegion.RIGHT_ARM: 8.0,
	GameEnums.LimbRegion.LEFT_LEG: 10.0,
	GameEnums.LimbRegion.RIGHT_LEG: 10.0
}

var limb_hp: Dictionary = {}
var limb_max: Dictionary = {}
var limb_trauma: Dictionary = {} # Tracks bleeding rates per limb

@export_group("Systemic Vitals")
var core_temperature: float = 37.0
var blood_level: float = GameEnums.SCALE_MAX # 12 = Full, 0 = Exsanguinated
var hunger: float = GameEnums.SCALE_MAX      # 12 = Fed, 0 = Starving
var thirst: float = GameEnums.SCALE_MAX      # 12 = Hydrated, 0 = Dehydrated
var fatigue: float = 0.0                     # 0 = Rested, 12 = Passing out
# The structural baseline. Everyone gets the same bones.

func _ready() -> void:
	for limb in BASE_LIMB_MAX.keys():
		limb_max[limb] = BASE_LIMB_MAX[limb]
		limb_hp[limb] = BASE_LIMB_MAX[limb]
		limb_trauma[limb] = GameEnums.TraumaType.NONE

func configure_structure(fortitude: int) -> void:
	var hp_multiplier := float(fortitude) / GameEnums.SCALE_MIDPOINT
	for limb in BASE_LIMB_MAX.keys():
		limb_max[limb] = BASE_LIMB_MAX[limb] * hp_multiplier
		limb_hp[limb] = limb_max[limb]

func get_limb_max(limb: GameEnums.LimbRegion) -> float:
	return float(limb_max.get(limb, BASE_LIMB_MAX.get(limb, 0.0)))

# ---------------------------------------------------------
# TRAUMA APPLICATION
# ---------------------------------------------------------

func apply_targeted_hit(limb: GameEnums.LimbRegion, raw_damage: float, penetration: float) -> void:
	# You can't kill a limb that's already gone
	if limb_hp[limb] <= 0:
		return 
		
	# High penetration causes bleeding trauma
	if (
		penetration > GameEnums.SCALE_MIDPOINT
		and limb_trauma[limb] != GameEnums.TraumaType.BLEEDING
	):
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
	process_elapsed_time(15, environmental_temp, insulation_rating, exertion_level)

func process_elapsed_time(
	elapsed_minutes: int,
	environmental_temp: float,
	insulation_rating: float,
	exertion_level: float = 1.0
) -> void:
	if elapsed_minutes <= 0:
		return
	var remaining_minutes := elapsed_minutes
	while remaining_minutes > 0:
		var interval_minutes := mini(15, remaining_minutes)
		_process_biological_interval(
			float(interval_minutes) / 15.0,
			environmental_temp,
			insulation_rating,
			exertion_level
		)
		if blood_level <= 0.0:
			return
		remaining_minutes -= interval_minutes

func _process_biological_interval(
	tick_scale: float,
	environmental_temp: float,
	insulation_rating: float,
	exertion_level: float
) -> void:
	# 1. Process Blood Loss (Your original code)
	var active_bleeds: int = 0
	for limb in limb_trauma.keys():
		if limb_trauma[limb] == GameEnums.TraumaType.BLEEDING:
			active_bleeds += 1
			
	if active_bleeds > 0:
		blood_level = max(
			0.0,
			blood_level - (active_bleeds * 0.6 * tick_scale)
		)
		blood_level_changed.emit(blood_level)
		if blood_level <= 0.0:
			vital_failure.emit("Exsanguination")
			return
			
	# 2. Process Core Temperature
	var thermal_differential = environmental_temp - core_temperature
	if thermal_differential < 0:
		var insulation_ratio := clampf(
			insulation_rating / GameEnums.SCALE_MAX,
			0.0,
			1.0
		)
		core_temperature += (
			thermal_differential
			* (1.0 - insulation_ratio)
			* 0.05
			* tick_scale
		)
		
	# 3. Process Calories, Hydration, and Sleep
	# Exertion level (e.g., walking through Swamp vs Plains) accelerates the drain
	hunger = max(0.0, hunger - (0.12 * exertion_level * tick_scale))
	thirst = max(
		0.0,
		thirst - (0.36 * exertion_level * tick_scale)
	)
	fatigue = min(
		GameEnums.SCALE_MAX,
		fatigue + (0.24 * exertion_level * tick_scale)
	)

	# 4. Trigger Crisis Alarms
	var crisis_threshold := GameEnums.SCALE_MAX * 0.2
	var exhaustion_threshold := GameEnums.SCALE_MAX * 0.8
	if hunger < crisis_threshold:
		metabolic_crisis.emit(
			GameEnums.MetabolicCondition.STARVING,
			((crisis_threshold - hunger) / crisis_threshold) * GameEnums.SCALE_MAX
		)
	if thirst < crisis_threshold:
		metabolic_crisis.emit(
			GameEnums.MetabolicCondition.DEHYDRATED,
			((crisis_threshold - thirst) / crisis_threshold) * GameEnums.SCALE_MAX
		)
	if fatigue > exhaustion_threshold:
		metabolic_crisis.emit(
			GameEnums.MetabolicCondition.EXHAUSTED,
			((fatigue - exhaustion_threshold) / crisis_threshold)
			* GameEnums.SCALE_MAX
		)
	if core_temperature < 32.0:
		metabolic_crisis.emit(
			GameEnums.MetabolicCondition.HYPOTHERMIA,
			clampf(
				((32.0 - core_temperature) / 10.0) * GameEnums.SCALE_MAX,
				0.0,
				GameEnums.SCALE_MAX
			)
		)

# ---------------------------------------------------------
# UTILITY MATH
# ---------------------------------------------------------

func get_motor_efficiency() -> float:
	# A combined metric of leg health and blood volume to calculate AP
	var leg_current: float = limb_hp[GameEnums.LimbRegion.LEFT_LEG] + limb_hp[GameEnums.LimbRegion.RIGHT_LEG]
	var leg_max: float = (
		get_limb_max(GameEnums.LimbRegion.LEFT_LEG)
		+ get_limb_max(GameEnums.LimbRegion.RIGHT_LEG)
	)
	
	var leg_efficiency: float = leg_current / leg_max
	
	# Ratios are allowed as local calculation outputs; stored vitals stay on 0-12.
	var blood_ratio := blood_level / GameEnums.SCALE_MAX
	return clamp(leg_efficiency * blood_ratio, 0.1, 1.0)

func has_functional_arms() -> bool:
	return limb_hp[GameEnums.LimbRegion.LEFT_ARM] > 0 and limb_hp[GameEnums.LimbRegion.RIGHT_ARM] > 0

func capture_runtime_state() -> Dictionary:
	var hp_state: Dictionary = {}
	var trauma_state: Dictionary = {}
	for limb in limb_hp.keys():
		hp_state[str(limb)] = limb_hp[limb]
		trauma_state[str(limb)] = limb_trauma[limb]

	return {
		"limb_hp": hp_state,
		"limb_trauma": trauma_state,
		"core_temperature": core_temperature,
		"blood_level": blood_level,
		"hunger": hunger,
		"thirst": thirst,
		"fatigue": fatigue,
	}

func restore_runtime_state(state: Dictionary) -> void:
	var hp_state: Dictionary = state.get("limb_hp", {})
	for limb_key in hp_state.keys():
		limb_hp[int(limb_key)] = hp_state[limb_key]

	var trauma_state: Dictionary = state.get("limb_trauma", {})
	for limb_key in trauma_state.keys():
		limb_trauma[int(limb_key)] = trauma_state[limb_key]

	core_temperature = state.get("core_temperature", core_temperature)
	blood_level = clampf(
		float(state.get("blood_level", blood_level)),
		0.0,
		GameEnums.SCALE_MAX
	)
	hunger = clampf(
		float(state.get("hunger", hunger)),
		0.0,
		GameEnums.SCALE_MAX
	)
	thirst = clampf(
		float(state.get("thirst", thirst)),
		0.0,
		GameEnums.SCALE_MAX
	)
	fatigue = clampf(
		float(state.get("fatigue", fatigue)),
		0.0,
		GameEnums.SCALE_MAX
	)
