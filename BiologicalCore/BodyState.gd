extends Resource
class_name BodyState

## Typed runtime state snapshot for HumanoidBody. Replaces the Dictionary
## previously returned by capture_runtime_state().

## Last damaging vector keyed by GameEnums.LimbRegion (as int).
var limb_damage_types: Dictionary = {}

## Serialized Wound dictionaries keyed by GameEnums.LimbRegion (as int).
var wounds_by_limb: Dictionary = {}

## Limb regions that reached zero structural function. Wounds can recover, but
## ordinary recovery cannot remove this terminal local state.
var destroyed_limbs: Array[int] = []

var core_temperature: float = 37.0
var blood_level: float = GameEnums.SCALE_MAX
var shock: float = 0.0
var consciousness: float = GameEnums.SCALE_MAX
var wet_exposure: float = 0.0
var hunger: float = GameEnums.SCALE_MAX
var thirst: float = GameEnums.SCALE_MAX
var fatigue: float = 0.0
var zero_hunger_minutes: int = 0
var zero_thirst_minutes: int = 0

func to_dict() -> Dictionary:
	var damage_type_state: Dictionary = {}
	var wound_state: Dictionary = {}
	for limb in wounds_by_limb.keys():
		if limb_damage_types.has(limb):
			damage_type_state[str(limb)] = limb_damage_types[limb]
		var serialized_wounds: Array = []
		for wound in wounds_by_limb.get(limb, []):
			serialized_wounds.append(wound.to_dict() if wound is Wound else wound)
		if not serialized_wounds.is_empty():
			wound_state[str(limb)] = serialized_wounds
	return {
		"limb_damage_types": damage_type_state,
		"wounds_by_limb": wound_state,
		"destroyed_limbs": destroyed_limbs.duplicate(),
		"core_temperature": core_temperature,
		"blood_level": blood_level,
		"shock": shock,
		"consciousness": consciousness,
		"wet_exposure": wet_exposure,
		"hunger": hunger,
		"thirst": thirst,
		"fatigue": fatigue,
		"zero_hunger_minutes": zero_hunger_minutes,
		"zero_thirst_minutes": zero_thirst_minutes,
	}

static func from_dict(data: Dictionary) -> BodyState:
	var state := BodyState.new()

	var damage_type_data: Dictionary = data.get("limb_damage_types", {})
	for limb_key in damage_type_data.keys():
		state.limb_damage_types[int(limb_key)] = damage_type_data[limb_key]

	var wound_data: Dictionary = data.get("wounds_by_limb", {})
	for limb_key in wound_data.keys():
		var restored_wounds: Array[Wound] = []
		for raw_wound in wound_data[limb_key]:
			if raw_wound is Dictionary:
				restored_wounds.append(Wound.from_dict(raw_wound))
		state.wounds_by_limb[int(limb_key)] = restored_wounds
	for limb_value in data.get("destroyed_limbs", []):
		var limb := int(limb_value)
		if limb in GameEnums.LimbRegion.values() and not state.destroyed_limbs.has(limb):
			state.destroyed_limbs.append(limb)

	state.core_temperature = data.get("core_temperature", 37.0)
	state.blood_level = clampf(
		float(data.get("blood_level", GameEnums.SCALE_MAX)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.shock = clampf(float(data.get("shock", 0.0)), 0.0, GameEnums.SCALE_MAX)
	state.consciousness = clampf(
		float(data.get("consciousness", GameEnums.SCALE_MAX)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.wet_exposure = clampf(
		float(data.get("wet_exposure", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.hunger = clampf(
		float(data.get("hunger", GameEnums.SCALE_MAX)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.thirst = clampf(
		float(data.get("thirst", GameEnums.SCALE_MAX)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.fatigue = clampf(
		float(data.get("fatigue", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.zero_hunger_minutes = maxi(0, int(data.get("zero_hunger_minutes", 0)))
	state.zero_thirst_minutes = maxi(0, int(data.get("zero_thirst_minutes", 0)))
	return state
