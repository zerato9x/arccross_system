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
