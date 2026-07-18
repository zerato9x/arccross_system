extends Node
class_name HumanoidBody

# ---------------------------------------------------------
# SIGNALS: The sounds of suffering
# ---------------------------------------------------------
signal limb_destroyed(limb: GameEnums.LimbRegion)
signal vital_failure(reason: String)
signal blood_level_changed(current_level: float)
signal wounds_changed(limb: GameEnums.LimbRegion)
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
var limb_damage_types: Dictionary = {}
var wounds_by_limb: Dictionary = {}

@export_group("Systemic Vitals")
var core_temperature: float = 37.0
var blood_level: float = GameEnums.SCALE_MAX # 12 = Full, 0 = Exsanguinated
var hunger: float = GameEnums.SCALE_MAX      # 12 = Fed, 0 = Starving
var thirst: float = GameEnums.SCALE_MAX      # 12 = Hydrated, 0 = Dehydrated
var fatigue: float = 0.0                     # 0 = Rested, 12 = Passing out
# The structural baseline. Everyone gets the same bones.

const MAX_WOUNDS_PER_LIMB: int = 4

func _ready() -> void:
	for limb in BASE_LIMB_MAX.keys():
		limb_max[limb] = BASE_LIMB_MAX[limb]
		limb_hp[limb] = BASE_LIMB_MAX[limb]
		limb_trauma[limb] = GameEnums.TraumaType.NONE
		limb_damage_types.erase(limb)
		wounds_by_limb[limb] = []

func configure_structure(fortitude: int) -> void:
	var hp_multiplier := float(fortitude) / GameEnums.SCALE_MIDPOINT
	for limb in BASE_LIMB_MAX.keys():
		limb_max[limb] = BASE_LIMB_MAX[limb] * hp_multiplier
		limb_hp[limb] = limb_max[limb]
		limb_damage_types.erase(limb)
		wounds_by_limb[limb] = []

func get_limb_max(limb: GameEnums.LimbRegion) -> float:
	return float(limb_max.get(limb, BASE_LIMB_MAX.get(limb, 0.0)))

# ---------------------------------------------------------
# TRAUMA APPLICATION
# ---------------------------------------------------------

func apply_targeted_hit(
	limb: GameEnums.LimbRegion,
	raw_damage: float,
	penetration: float,
	damage_type: int = -1
) -> void:
	# You can't kill a limb that's already gone
	if limb_hp[limb] <= 0:
		return 

	if damage_type >= 0:
		limb_damage_types[limb] = damage_type
		
	limb_hp[limb] = max(0.0, limb_hp[limb] - raw_damage)
	if raw_damage > 0.0:
		_add_wound(limb, raw_damage, penetration, damage_type)
	
	if limb_hp[limb] == 0:
		_handle_destroyed_limb(limb)
	else:
		_refresh_legacy_trauma(limb)
	
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		bus.emit_humanoid_injured(self, limb_trauma[limb])
	wounds_changed.emit(limb)


func _add_wound(limb: int, damage: float, penetration: float, damage_type: int) -> void:
	var wound := Wound.new()
	wound.wound_id = "%d-%d-%d" % [limb, Time.get_ticks_msec(), randi()]
	wound.severity = clampf(damage + penetration * 0.2, 0.25, GameEnums.SCALE_MAX)
	match damage_type:
		GameEnums.DamageType.SHARP:
			wound.wound_type = GameEnums.WoundType.LACERATION
			wound.bleeding_rate = clampf(wound.severity * 0.09, 0.1, 1.1)
			wound.pain = clampf(wound.severity * 0.7, 0.0, GameEnums.SCALE_MAX)
			wound.contamination = 2.0
		GameEnums.DamageType.BALLISTIC:
			wound.wound_type = (
				GameEnums.WoundType.GUNSHOT
				if penetration >= GameEnums.SCALE_MIDPOINT
				else GameEnums.WoundType.PUNCTURE
			)
			wound.bleeding_rate = clampf(wound.severity * 0.11, 0.15, 1.4)
			wound.pain = clampf(wound.severity * 0.85, 0.0, GameEnums.SCALE_MAX)
			wound.contamination = 1.0
		_:
			wound.wound_type = (
				GameEnums.WoundType.FRACTURE
				if wound.severity >= 7.0
				else GameEnums.WoundType.BRUISE
			)
			wound.bleeding_rate = 0.0
			wound.pain = clampf(wound.severity * 0.65, 0.0, GameEnums.SCALE_MAX)
	var wounds: Array = wounds_by_limb.get(limb, [])
	if wounds.size() >= MAX_WOUNDS_PER_LIMB:
		var least_severe_index := 0
		for index in range(1, wounds.size()):
			if (wounds[index] as Wound).severity < (wounds[least_severe_index] as Wound).severity:
				least_severe_index = index
		wounds.remove_at(least_severe_index)
	wounds.append(wound)
	wounds_by_limb[limb] = wounds


func _refresh_legacy_trauma(limb: int) -> void:
	if float(limb_hp.get(limb, 0.0)) <= 0.0:
		limb_trauma[limb] = GameEnums.TraumaType.SHATTERED_LIMB
		return
	limb_trauma[limb] = (
		GameEnums.TraumaType.BLEEDING
		if get_limb_bleeding_rate(limb) > 0.0
		else GameEnums.TraumaType.NONE
	)

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

func process_combat_bleeding_tick() -> Dictionary:
	var active_bleeds := get_active_bleeding_wound_count()
	var total_bleeding := get_total_bleeding_rate()
	if total_bleeding <= 0.0:
		return {}
	var previous_blood := blood_level
	var blood_loss := minf(previous_blood, total_bleeding)
	blood_level = max(0.0, blood_level - blood_loss)
	blood_level_changed.emit(blood_level)
	if blood_level <= 0.0:
		vital_failure.emit("Exsanguination")
	return {
		"active_bleeds": active_bleeds,
		"blood_loss": blood_loss,
		"blood_level": blood_level,
	}

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
	# 1. Wounds drive blood loss; Blood is a systemic reserve, not a random timer.
	var bleeding_rate := get_total_bleeding_rate()
	if bleeding_rate > 0.0:
		blood_level = max(
			0.0,
			blood_level - (bleeding_rate * 0.75 * tick_scale)
		)
		blood_level_changed.emit(blood_level)
		if blood_level <= 0.0:
			vital_failure.emit("Exsanguination")
			return

	_process_wound_recovery(tick_scale)
			
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


func _process_wound_recovery(tick_scale: float) -> void:
	var recovery_quality := minf(
		blood_level / GameEnums.SCALE_MAX,
		minf(hunger / GameEnums.SCALE_MAX, thirst / GameEnums.SCALE_MAX)
	)
	for limb in wounds_by_limb.keys():
		var wounds: Array = wounds_by_limb[limb]
		for wound in wounds.duplicate():
			if not wound is Wound:
				continue
			wound.process_recovery(tick_scale, recovery_quality)
			if wound.severity <= 0.05 and wound.active_bleeding_rate() <= 0.0:
				wounds.erase(wound)
		wounds_by_limb[limb] = wounds
		_refresh_legacy_trauma(limb)

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
	var pain_ratio := get_total_pain() / GameEnums.SCALE_MAX
	return clamp(leg_efficiency * blood_ratio * (1.0 - pain_ratio * 0.35), 0.1, 1.0)


func get_wounds_for_limb(limb: int) -> Array:
	return wounds_by_limb.get(limb, [])


func get_limb_bleeding_rate(limb: int) -> float:
	var total := 0.0
	for wound in get_wounds_for_limb(limb):
		if wound is Wound:
			total += wound.active_bleeding_rate()
	return total


func get_total_bleeding_rate() -> float:
	var total := 0.0
	for limb in wounds_by_limb.keys():
		total += get_limb_bleeding_rate(limb)
	return total


func get_active_bleeding_wound_count() -> int:
	var count := 0
	for wounds in wounds_by_limb.values():
		for wound in wounds:
			if wound is Wound and wound.active_bleeding_rate() > 0.0:
				count += 1
	return count


func get_total_wound_count() -> int:
	var count := 0
	for wounds in wounds_by_limb.values():
		count += wounds.size()
	return count


func get_total_pain() -> float:
	var pain_total := 0.0
	for wounds in wounds_by_limb.values():
		for wound in wounds:
			if wound is Wound:
				pain_total += wound.pain * (0.75 if wound.treated else 1.0)
	return clampf(pain_total, 0.0, GameEnums.SCALE_MAX)


func get_infection_risk() -> float:
	var risk := 0.0
	for wounds in wounds_by_limb.values():
		for wound in wounds:
			if wound is Wound:
				risk = maxf(risk, wound.contamination)
	return clampf(risk, 0.0, GameEnums.SCALE_MAX)


func can_treat_bleeding(limb: int) -> bool:
	return get_limb_bleeding_rate(limb) > 0.0 or limb_trauma.get(limb) == GameEnums.TraumaType.BLEEDING


func treat_worst_bleed(limb: int, potency: float) -> bool:
	var wounds: Array = wounds_by_limb.get(limb, [])
	var target: Wound = null
	for wound in wounds:
		if wound is Wound and wound.active_bleeding_rate() > 0.0:
			if target == null or wound.active_bleeding_rate() > target.active_bleeding_rate():
				target = wound
	if target == null and limb_trauma.get(limb) == GameEnums.TraumaType.BLEEDING:
		# Migration seam for old saves and debug tools that only set TraumaType.
		_add_wound(limb, maxf(1.0, potency * 0.5), GameEnums.SCALE_MIDPOINT, GameEnums.DamageType.SHARP)
		return treat_worst_bleed(limb, potency)
	if target == null:
		return false
	target.apply_treatment(potency)
	_refresh_legacy_trauma(limb)
	wounds_changed.emit(limb)
	return true

func has_functional_arms() -> bool:
	return limb_hp[GameEnums.LimbRegion.LEFT_ARM] > 0 and limb_hp[GameEnums.LimbRegion.RIGHT_ARM] > 0

func are_both_legs_disabled() -> bool:
	return (
		_is_limb_disabled(GameEnums.LimbRegion.LEFT_LEG)
		and _is_limb_disabled(GameEnums.LimbRegion.RIGHT_LEG)
	)

func _is_limb_disabled(limb: GameEnums.LimbRegion) -> bool:
	return (
		float(limb_hp.get(limb, 0.0)) <= 0.0
		or int(limb_trauma.get(
			limb,
			GameEnums.TraumaType.NONE
		)) == GameEnums.TraumaType.SHATTERED_LIMB
	)

func capture_runtime_state() -> BodyState:
	var state := BodyState.new()
	state.limb_hp = limb_hp.duplicate()
	state.limb_trauma = limb_trauma.duplicate()
	state.limb_damage_types = limb_damage_types.duplicate()
	state.wounds_by_limb = wounds_by_limb.duplicate(true)
	state.core_temperature = core_temperature
	state.blood_level = blood_level
	state.hunger = hunger
	state.thirst = thirst
	state.fatigue = fatigue
	return state

func restore_runtime_state(state) -> void:
	var body_state: BodyState
	if state is BodyState:
		body_state = state
	elif state is Dictionary:
		body_state = BodyState.from_dict(state)
	else:
		return

	for limb in body_state.limb_hp.keys():
		limb_hp[limb] = body_state.limb_hp[limb]
	for limb in body_state.limb_trauma.keys():
		limb_trauma[limb] = body_state.limb_trauma[limb]
	limb_damage_types.clear()
	for limb in body_state.limb_damage_types.keys():
		limb_damage_types[limb] = body_state.limb_damage_types[limb]
	wounds_by_limb.clear()
	for limb in BASE_LIMB_MAX.keys():
		wounds_by_limb[limb] = body_state.wounds_by_limb.get(limb, []).duplicate(true)
		if wounds_by_limb[limb].is_empty() and body_state.limb_trauma.get(limb) == GameEnums.TraumaType.BLEEDING:
			_add_wound(limb, 3.0, GameEnums.SCALE_MIDPOINT, GameEnums.DamageType.SHARP)
		_refresh_legacy_trauma(limb)

	core_temperature = body_state.core_temperature
	blood_level = clampf(body_state.blood_level, 0.0, GameEnums.SCALE_MAX)
	hunger = clampf(body_state.hunger, 0.0, GameEnums.SCALE_MAX)
	thirst = clampf(body_state.thirst, 0.0, GameEnums.SCALE_MAX)
	fatigue = clampf(body_state.fatigue, 0.0, GameEnums.SCALE_MAX)
