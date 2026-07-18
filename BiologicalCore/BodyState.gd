extends Resource
class_name BodyState

## Typed runtime state snapshot for HumanoidBody. Replaces the Dictionary
## previously returned by capture_runtime_state().

## Per-limb HP keyed by GameEnums.LimbRegion (as int).
var limb_hp: Dictionary = {}

## Per-limb trauma type keyed by GameEnums.LimbRegion (as int).
var limb_trauma: Dictionary = {}

## Last damaging vector keyed by GameEnums.LimbRegion (as int).
var limb_damage_types: Dictionary = {}

## Serialized Wound dictionaries keyed by GameEnums.LimbRegion (as int).
var wounds_by_limb: Dictionary = {}

var core_temperature: float = 37.0
var blood_level: float = GameEnums.SCALE_MAX
var hunger: float = GameEnums.SCALE_MAX
var thirst: float = GameEnums.SCALE_MAX
var fatigue: float = 0.0

func to_dict() -> Dictionary:
	var hp_state: Dictionary = {}
	var trauma_state: Dictionary = {}
	var damage_type_state: Dictionary = {}
	var wound_state: Dictionary = {}
	for limb in limb_hp.keys():
		hp_state[str(limb)] = limb_hp[limb]
		trauma_state[str(limb)] = limb_trauma.get(limb, GameEnums.TraumaType.NONE)
		if limb_damage_types.has(limb):
			damage_type_state[str(limb)] = limb_damage_types[limb]
		var serialized_wounds: Array = []
		for wound in wounds_by_limb.get(limb, []):
			serialized_wounds.append(wound.to_dict() if wound is Wound else wound)
		if not serialized_wounds.is_empty():
			wound_state[str(limb)] = serialized_wounds
	return {
		"limb_hp": hp_state,
		"limb_trauma": trauma_state,
		"limb_damage_types": damage_type_state,
		"wounds_by_limb": wound_state,
		"core_temperature": core_temperature,
		"blood_level": blood_level,
		"hunger": hunger,
		"thirst": thirst,
		"fatigue": fatigue,
	}

static func from_dict(data: Dictionary) -> BodyState:
	var state := BodyState.new()

	var hp_data: Dictionary = data.get("limb_hp", {})
	for limb_key in hp_data.keys():
		state.limb_hp[int(limb_key)] = hp_data[limb_key]

	var trauma_data: Dictionary = data.get("limb_trauma", {})
	for limb_key in trauma_data.keys():
		state.limb_trauma[int(limb_key)] = trauma_data[limb_key]

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

	state.core_temperature = data.get("core_temperature", 37.0)
	state.blood_level = clampf(
		float(data.get("blood_level", GameEnums.SCALE_MAX)),
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
	return state
