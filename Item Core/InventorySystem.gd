extends Node
class_name InventorySystem

# ---------------------------------------------------------
# SIGNALS: The only way this script talks to the outside world
# ---------------------------------------------------------
signal capacity_updated(current: int, maximum: int)
signal equipment_changed(slot: GameEnums.EquipmentSlot, item: ItemData)
signal items_spilled(spilled_items: Array[ItemData]) # The Safety Valve
signal inventory_error(message: String)

@export var base_max_capacity: int = 6

var current_max_capacity: int = 6
var current_size: int = 0

var backpack_array: Array[ItemData] = []
var paper_doll: Dictionary = {
	GameEnums.EquipmentSlot.INNER_TORSO: null,
	GameEnums.EquipmentSlot.OUTER_TORSO: null,
	GameEnums.EquipmentSlot.HANDS: null
}

func _ready() -> void:
	_recalculate_bounds()

# ---------------------------------------------------------
# CORE OPERATIONS
# ---------------------------------------------------------

func add_to_backpack(item: ItemData) -> bool:
	if current_size + item.size_cost <= current_max_capacity:
		backpack_array.append(item)
		_recalculate_bounds()
		return true
		
	inventory_error.emit("Capacity exceeded.")
	return false

func equip_item(item: ItemData, slot: GameEnums.EquipmentSlot) -> bool:
	if not paper_doll.has(slot):
		inventory_error.emit("You can't wear that there.")
		return false
		
	# Extract from backpack if it's currently in there
	if backpack_array.has(item):
		backpack_array.erase(item)
		
	# Swap logic: If wearing something, put it back in the bag (or drop it if it doesn't fit)
	var old_item: ItemData = paper_doll[slot]
	if old_item != null:
		if not add_to_backpack(old_item):
			# If the old coat doesn't fit in the bag, it falls to the mud
			items_spilled.emit([old_item])
			
	paper_doll[slot] = item
	equipment_changed.emit(slot, item)
	
	_recalculate_bounds()
	return true

func unequip_item(slot: GameEnums.EquipmentSlot) -> void:
	var item: ItemData = paper_doll[slot]
	if item == null: return
	
	paper_doll[slot] = null
	equipment_changed.emit(slot, null) # Null means empty slot
	
	if not add_to_backpack(item):
		items_spilled.emit([item])
		
	_recalculate_bounds()

# ---------------------------------------------------------
# THE PARADOX FIX (Spill Over Logic)
# ---------------------------------------------------------

func _recalculate_bounds() -> void:
	var bonus_capacity: int = 0
	var outer_layer: ItemData = paper_doll[GameEnums.EquipmentSlot.OUTER_TORSO]
	
	# Check coat bonuses
	if outer_layer != null:
		if outer_layer.id == "military_rucksack": bonus_capacity = 30
		elif outer_layer.id == "heavy_coat": bonus_capacity = 12
			
	current_max_capacity = base_max_capacity + bonus_capacity
	
	# Recalculate backpack weight
	current_size = 0
	for item in backpack_array:
		current_size += item.size_cost
		
	# THE FIX: If taking off a coat shrunk our capacity below our current mass
	if current_size > current_max_capacity:
		_execute_spill_over()
		
	capacity_updated.emit(current_size, current_max_capacity)

func _execute_spill_over() -> void:
	var dropped_items: Array[ItemData] = []
	
	# Eject items from the backpack until the math is legal again
	# We eject from the end of the array (most recently added items)
	while current_size > current_max_capacity and backpack_array.size() > 0:
		var ejected_item: ItemData = backpack_array.pop_back()
		current_size -= ejected_item.size_cost
		dropped_items.append(ejected_item)
		
	if dropped_items.size() > 0:
		items_spilled.emit(dropped_items)
		inventory_error.emit("Your bag overflowed. Items spilled to the ground.")
