extends Resource
class_name InventoryState

## Typed runtime state snapshot for InventorySystem. Replaces the Dictionary
## previously returned by capture_runtime_state().

## Always 0 — capacity comes from worn containers.
var base_max_capacity: int = 0

## Equipment in each slot, keyed by slot index as String.
## Values are ItemData runtime state Dictionaries.
var equipment: Dictionary = {}

## Stowed items. Each entry is an ItemData runtime state Dictionary
## with an additional "container_slot" key.
var backpack: Array = []

func to_dict() -> Dictionary:
	return {
		"base_max_capacity": base_max_capacity,
		"equipment": equipment.duplicate(true),
		"backpack": backpack.duplicate(true),
	}

static func from_dict(data: Dictionary) -> InventoryState:
	var state := InventoryState.new()
	state.base_max_capacity = int(data.get("base_max_capacity", 0))
	state.equipment = data.get("equipment", {}).duplicate(true)
	state.backpack = data.get("backpack", []).duplicate(true)
	return state
