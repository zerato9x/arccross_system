extends Node
class_name HumanoidBody

# ---------------------------------------------------------
# SIGNALS: The sounds of suffering
# ---------------------------------------------------------
signal limb_destroyed(limb: GameEnums.LimbRegion)
signal vital_failure(reason: String)
signal blood_level_changed(current_level: float)
signal wounds_changed(limb: GameEnums.LimbRegion)
signal incapacitated(reason: String)
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

## Read-only compatibility projections for old debug/tests. They are rebuilt
## from wounds and are never serialized or used as biological authority.
var limb_hp: Dictionary = {}
var limb_max: Dictionary = {}
var limb_trauma: Dictionary = {} # Tracks bleeding rates per limb
var limb_damage_types: Dictionary = {}
var wounds_by_limb: Dictionary = {}

@export_group("Systemic Vitals")
var core_temperature: float = 37.0
var blood_level: float = GameEnums.SCALE_MAX # 12 = Full, 0 = Exsanguinated
var shock: float = 0.0
var consciousness: float = GameEnums.SCALE_MAX
var wet_exposure: float = 0.0
var hunger: float = GameEnums.SCALE_MAX      # 12 = Fed, 0 = Starving
var thirst: float = GameEnums.SCALE_MAX      # 12 = Hydrated, 0 = Dehydrated
var fatigue: float = 0.0                     # 0 = Rested, 12 = Passing out
var zero_hunger_minutes: int = 0
var zero_thirst_minutes: int = 0

@export var survival_balance: SurvivalBalance = preload(
	"res://BiologicalCore/survival_balance.tres"
)
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
	damage_type: int = -1,
	source_context: Dictionary = {}
) -> void:
	if damage_type >= 0:
		limb_damage_types[limb] = damage_type
	if raw_damage > 0.0:
		_add_wound(limb, raw_damage, penetration, damage_type, source_context)
	_rebuild_limb_projection(limb)
	shock = clampf(
		shock + raw_damage * 0.35 + get_total_bleeding_rate() * 0.2,
		0.0,
		GameEnums.SCALE_MAX
	)
	consciousness = clampf(
		GameEnums.SCALE_MAX - shock * 0.65 - get_total_pain() * 0.25,
		0.0,
		GameEnums.SCALE_MAX
	)
	var latest_wound: Wound = wounds_by_limb[limb].back()
	if (
		limb in [GameEnums.LimbRegion.HEAD, GameEnums.LimbRegion.UPPER_TORSO, GameEnums.LimbRegion.LOWER_TORSO]
		and latest_wound.severity >= GameEnums.SCALE_MAX
	):
		vital_failure.emit("Catastrophic vital injury")
	elif consciousness <= 0.0:
		incapacitated.emit("Loss of consciousness")
	
	var bus = get_node_or_null("/root/GameEventBus")
	if bus:
		var injury_context := latest_wound.damage_source.duplicate(true)
		injury_context["body_region"] = limb
		injury_context["wound_id"] = latest_wound.wound_id
		injury_context["wound_type"] = latest_wound.wound_type
		bus.emit_humanoid_injured(self, latest_wound.wound_type, injury_context)
	wounds_changed.emit(limb)


func _add_wound(limb: int, damage: float, penetration: float, damage_type: int, source_context: Dictionary = {}) -> void:
	var wound := Wound.new()
	wound.wound_id = "%d-%d-%d" % [limb, Time.get_ticks_msec(), randi()]
	wound.body_region = limb
	wound.severity = clampf(damage + penetration * 0.2, 0.25, GameEnums.SCALE_MAX)
	wound.depth = clampf(penetration, 0.0, GameEnums.SCALE_MAX)
	wound.damage_source = source_context.duplicate(true)
	wound.damage_source["damage_type"] = damage_type
	wound.damage_source["raw_damage"] = damage
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
			if wound.wound_type == GameEnums.WoundType.FRACTURE:
				wound.fracture_state = "unstable"
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


func _rebuild_limb_projection(limb: int) -> void:
	var function := get_limb_function(limb)
	limb_hp[limb] = get_limb_max(limb) * function / GameEnums.SCALE_MAX
	_refresh_legacy_trauma(limb)
	if function <= 0.0:
		limb_destroyed.emit(limb)

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
	shock = clampf(
		shock + blood_loss * 0.45,
		0.0,
		GameEnums.SCALE_MAX
	)
	consciousness = clampf(
		GameEnums.SCALE_MAX - shock * 0.65 - get_total_pain() * 0.25,
		0.0,
		GameEnums.SCALE_MAX
	)
	if consciousness <= 0.0 and blood_level > 0.0:
		incapacitated.emit("Shock-induced unconsciousness")
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
			interval_minutes,
			environmental_temp,
			insulation_rating,
			exertion_level
		)
		if blood_level <= 0.0:
			return
		remaining_minutes -= interval_minutes

func _process_biological_interval(
	tick_scale: float,
	interval_minutes: int,
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
	var balance := survival_balance
	if balance == null or not balance.validate():
		balance = load("res://BiologicalCore/survival_balance.tres") as SurvivalBalance
	hunger = max(0.0, hunger - (balance.hunger_drain * exertion_level * tick_scale))
	thirst = max(
		0.0,
		thirst - (balance.thirst_drain * exertion_level * tick_scale)
	)
	fatigue = min(
		GameEnums.SCALE_MAX,
		fatigue + (balance.fatigue_gain * exertion_level * tick_scale)
	)
	_process_zero_reserve_crises(interval_minutes, balance)
	if blood_level <= 0.0:
		return

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


func _process_zero_reserve_crises(
	interval_minutes: int,
	balance: SurvivalBalance
) -> void:
	zero_hunger_minutes = (
		zero_hunger_minutes + interval_minutes if hunger <= 0.0 else 0
	)
	zero_thirst_minutes = (
		zero_thirst_minutes + interval_minutes if thirst <= 0.0 else 0
	)

	var blood_loss := 0.0
	var fatigue_gain_from_crisis := 0.0
	if zero_hunger_minutes > balance.hunger_grace_minutes:
		blood_loss += balance.hunger_blood_loss_per_hour * float(interval_minutes) / 60.0
		fatigue_gain_from_crisis += (
			balance.hunger_fatigue_per_hour * float(interval_minutes) / 60.0
		)
	if zero_thirst_minutes > balance.thirst_grace_minutes:
		blood_loss += balance.thirst_blood_loss_per_hour * float(interval_minutes) / 60.0
		fatigue_gain_from_crisis += (
			balance.thirst_fatigue_per_hour * float(interval_minutes) / 60.0
		)
	if blood_loss > 0.0:
		blood_level = maxf(0.0, blood_level - blood_loss)
		blood_level_changed.emit(blood_level)
	if fatigue_gain_from_crisis > 0.0:
		fatigue = minf(GameEnums.SCALE_MAX, fatigue + fatigue_gain_from_crisis)

	if zero_thirst_minutes >= balance.thirst_fatal_minutes:
		vital_failure.emit("Terminal dehydration")
		return
	if zero_hunger_minutes >= balance.hunger_fatal_minutes:
		vital_failure.emit("Terminal starvation")
		return
	if blood_level <= 0.0:
		vital_failure.emit("Metabolic collapse")


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
		_rebuild_limb_projection(limb)

# ---------------------------------------------------------
# UTILITY MATH
# ---------------------------------------------------------

func get_motor_efficiency() -> float:
	# A combined metric of leg health and blood volume to calculate AP
	var leg_efficiency := (
		get_limb_function(GameEnums.LimbRegion.LEFT_LEG)
		+ get_limb_function(GameEnums.LimbRegion.RIGHT_LEG)
	) / (GameEnums.SCALE_MAX * 2.0)
	
	# Ratios are allowed as local calculation outputs; stored vitals stay on 0-12.
	var blood_ratio := blood_level / GameEnums.SCALE_MAX
	var pain_ratio := get_total_pain() / GameEnums.SCALE_MAX
	return clamp(leg_efficiency * blood_ratio * (1.0 - pain_ratio * 0.35), 0.1, 1.0)


func get_limb_function(limb: int) -> float:
	var impairment := 0.0
	for wound in get_wounds_for_limb(limb):
		if not wound is Wound:
			continue
		impairment += wound.severity * 0.72
		if wound.fracture_state != "none":
			impairment += 3.0 if not wound.stabilized else 1.5
		if wound.burn_state != "none":
			impairment += wound.severity * 0.2
	return clampf(GameEnums.SCALE_MAX - impairment, 0.0, GameEnums.SCALE_MAX)


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
	return get_limb_bleeding_rate(limb) > 0.0


func treat_worst_bleed(limb: int, potency: float) -> bool:
	var wounds: Array = wounds_by_limb.get(limb, [])
	var target: Wound = null
	for wound in wounds:
		if wound is Wound and wound.active_bleeding_rate() > 0.0:
			if target == null or wound.active_bleeding_rate() > target.active_bleeding_rate():
				target = wound
	if target == null:
		return false
	target.apply_treatment(potency)
	_refresh_legacy_trauma(limb)
	wounds_changed.emit(limb)
	return true


func treat_wound(wound_id: String, treatment: String, potency: float) -> bool:
	for limb in wounds_by_limb.keys():
		for wound in wounds_by_limb[limb]:
			if not wound is Wound or wound.wound_id != wound_id:
				continue
			match treatment:
				"bandage":
					wound.apply_treatment(potency)
				"splint":
					if wound.fracture_state == "none":
						return false
					wound.stabilized = true
					wound.treatment_state["splinted"] = true
				"clean":
					wound.contamination = maxf(0.0, wound.contamination - potency)
					wound.treatment_state["cleaned"] = true
				_:
					return false
			_rebuild_limb_projection(limb)
			wounds_changed.emit(limb)
			return true
	return false


func apply_environment_exposure(hazard: Dictionary) -> void:
	if bool(hazard.get("contaminates_wounds", false)):
		for limb in wounds_by_limb.keys():
			for wound in wounds_by_limb[limb]:
				if wound is Wound and not wound.stabilized:
					wound.contamination = clampf(
						wound.contamination + 0.5,
						0.0,
						GameEnums.SCALE_MAX
					)
					wounds_changed.emit(limb)
	if bool(hazard.get("wet_exposure", false)):
		wet_exposure = clampf(wet_exposure + 1.0, 0.0, GameEnums.SCALE_MAX)
	if float(hazard.get("cold_exposure", 0.0)) > 0.0:
		core_temperature = maxf(
			20.0,
			core_temperature
			- 0.1 * float(hazard.get("cold_exposure", 0.0))
		)

func has_functional_arms() -> bool:
	return get_limb_function(GameEnums.LimbRegion.LEFT_ARM) > 0.0 and get_limb_function(GameEnums.LimbRegion.RIGHT_ARM) > 0.0

func are_both_legs_disabled() -> bool:
	return (
		_is_limb_disabled(GameEnums.LimbRegion.LEFT_LEG)
		and _is_limb_disabled(GameEnums.LimbRegion.RIGHT_LEG)
	)

func _is_limb_disabled(limb: GameEnums.LimbRegion) -> bool:
	return get_limb_function(limb) <= 0.0

func capture_runtime_state() -> BodyState:
	var state := BodyState.new()
	state.limb_damage_types = limb_damage_types.duplicate()
	state.wounds_by_limb = wounds_by_limb.duplicate(true)
	state.core_temperature = core_temperature
	state.blood_level = blood_level
	state.shock = shock
	state.consciousness = consciousness
	state.wet_exposure = wet_exposure
	state.hunger = hunger
	state.thirst = thirst
	state.fatigue = fatigue
	state.zero_hunger_minutes = zero_hunger_minutes
	state.zero_thirst_minutes = zero_thirst_minutes
	return state

func restore_runtime_state(state) -> void:
	var body_state: BodyState
	if state is BodyState:
		body_state = state
	elif state is Dictionary:
		body_state = BodyState.from_dict(state)
	else:
		return

	limb_damage_types.clear()
	for limb in body_state.limb_damage_types.keys():
		limb_damage_types[limb] = body_state.limb_damage_types[limb]
	wounds_by_limb.clear()
	for limb in BASE_LIMB_MAX.keys():
		wounds_by_limb[limb] = body_state.wounds_by_limb.get(limb, []).duplicate(true)
		_rebuild_limb_projection(limb)

	core_temperature = body_state.core_temperature
	blood_level = clampf(body_state.blood_level, 0.0, GameEnums.SCALE_MAX)
	shock = clampf(body_state.shock, 0.0, GameEnums.SCALE_MAX)
	consciousness = clampf(body_state.consciousness, 0.0, GameEnums.SCALE_MAX)
	wet_exposure = clampf(body_state.wet_exposure, 0.0, GameEnums.SCALE_MAX)
	hunger = clampf(body_state.hunger, 0.0, GameEnums.SCALE_MAX)
	thirst = clampf(body_state.thirst, 0.0, GameEnums.SCALE_MAX)
	fatigue = clampf(body_state.fatigue, 0.0, GameEnums.SCALE_MAX)
	zero_hunger_minutes = maxi(0, body_state.zero_hunger_minutes)
	zero_thirst_minutes = maxi(0, body_state.zero_thirst_minutes)
