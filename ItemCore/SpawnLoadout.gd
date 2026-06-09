extends Resource
class_name SpawnLoadout

## Defines the starting equipment and backpack contents for an entity at spawn time.
## Drag ItemData .tres files into these slots in the Inspector.

@export_group("Paper Doll (Equipped)")
@export var weapon: ItemData         ## HANDS slot
@export var inner_torso: ItemData    ## INNER_TORSO slot
@export var outer_torso: ItemData    ## OUTER_TORSO slot
@export var legs: ItemData           ## LEGS slot
@export var feet: ItemData           ## FEET slot
@export var backpack_gear: ItemData  ## BACKPACK slot (the bag itself, not contents)

@export_group("Backpack Contents (Loose Items)")
@export var starting_items: Array[ItemData] = []

## Equips all items from this loadout onto the given inventory system.
## Call this AFTER the InventorySystem has initialized its paper_doll.
func apply_to(inventory: InventorySystem) -> void:
	# 1. Equip paper doll slots (order matters: backpack first for capacity)
	if backpack_gear:
		inventory.equip_item(backpack_gear, GameEnums.EquipmentSlot.BACKPACK)
	if inner_torso:
		inventory.equip_item(inner_torso, GameEnums.EquipmentSlot.INNER_TORSO)
	if outer_torso:
		inventory.equip_item(outer_torso, GameEnums.EquipmentSlot.OUTER_TORSO)
	if legs:
		inventory.equip_item(legs, GameEnums.EquipmentSlot.LEGS)
	if feet:
		inventory.equip_item(feet, GameEnums.EquipmentSlot.FEET)
	if weapon:
		inventory.equip_item(weapon, GameEnums.EquipmentSlot.HANDS)
	
	# 2. Stuff loose items into the backpack
	for item in starting_items:
		if not inventory.add_to_backpack(item):
			print("[LOADOUT] WARNING: Backpack full. Could not fit: ", item.display_name)

func to_state() -> Dictionary:
	return {
		"weapon": _item_definition_path(weapon),
		"inner_torso": _item_definition_path(inner_torso),
		"outer_torso": _item_definition_path(outer_torso),
		"legs": _item_definition_path(legs),
		"feet": _item_definition_path(feet),
		"backpack_gear": _item_definition_path(backpack_gear),
		"starting_items": starting_items.map(
			func(item: ItemData) -> String: return _item_definition_path(item)
		),
	}

static func from_state(state: Dictionary) -> SpawnLoadout:
	var loadout := SpawnLoadout.new()
	loadout.weapon = _load_item_definition(state.get("weapon", ""))
	loadout.inner_torso = _load_item_definition(state.get("inner_torso", ""))
	loadout.outer_torso = _load_item_definition(state.get("outer_torso", ""))
	loadout.legs = _load_item_definition(state.get("legs", ""))
	loadout.feet = _load_item_definition(state.get("feet", ""))
	loadout.backpack_gear = _load_item_definition(state.get("backpack_gear", ""))

	for item_path in state.get("starting_items", []):
		var item := _load_item_definition(item_path)
		if item:
			loadout.starting_items.append(item)

	return loadout

func _item_definition_path(item: ItemData) -> String:
	return item.resource_path if item else ""

static func _load_item_definition(path: String) -> ItemData:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as ItemData
