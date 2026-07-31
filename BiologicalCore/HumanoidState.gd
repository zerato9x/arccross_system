extends Resource
class_name HumanoidState

## Typed runtime state snapshot for HumanoidCore. Replaces the Dictionary
## previously returned by capture_runtime_state().

var body: BodyState = null
var inventory: InventoryState = null

var base_ap: int = 12
var current_max_ap: int = 12
var is_dead: bool = false
var current_morale: float = 12.0
var is_fleeing: bool = false
var is_escaping: bool = false
var current_arc_energy: float = 0.0
var red_mist_corruption: float = 0.0
var is_mindless_hive_thrall: bool = false
var is_comatose: bool = false

func to_dict() -> Dictionary:
	return {
		"body": body.to_dict() if body else {},
		"inventory": inventory.to_dict() if inventory else {},
		"base_ap": base_ap,
		"current_max_ap": current_max_ap,
		"is_dead": is_dead,
		"current_morale": current_morale,
		"is_fleeing": is_fleeing,
		"is_escaping": is_escaping,
		"current_arc_energy": current_arc_energy,
		"red_mist_corruption": red_mist_corruption,
		"is_mindless_hive_thrall": is_mindless_hive_thrall,
		"is_comatose": is_comatose,
	}

static func from_dict(data: Dictionary) -> HumanoidState:
	var state := HumanoidState.new()
	var body_data: Dictionary = data.get("body", {})
	if not body_data.is_empty():
		state.body = BodyState.from_dict(body_data)
	var inventory_data: Dictionary = data.get("inventory", {})
	if not inventory_data.is_empty():
		state.inventory = InventoryState.from_dict(inventory_data)
	state.base_ap = data.get("base_ap", 12)
	state.current_max_ap = data.get("current_max_ap", 12)
	state.is_dead = data.get("is_dead", false)
	state.current_morale = clampf(
		float(data.get("current_morale", 12.0)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.is_fleeing = data.get("is_fleeing", false)
	state.is_escaping = data.get("is_escaping", false)
	state.current_arc_energy = clampf(
		float(data.get("current_arc_energy", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.red_mist_corruption = clampf(
		float(data.get("red_mist_corruption", 0.0)),
		0.0,
		GameEnums.SCALE_MAX
	)
	state.is_mindless_hive_thrall = data.get("is_mindless_hive_thrall", false)
	state.is_comatose = data.get("is_comatose", false)
	return state
