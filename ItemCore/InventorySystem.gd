extends Node
class_name InventorySystem

# ---------------------------------------------------------
# SIGNALS: The only way this script talks to the outside world
# ---------------------------------------------------------
signal capacity_updated(current: int, maximum: int)
signal equipment_changed(slot: GameEnums.EquipmentSlot, item: ItemData)
signal items_spilled(spilled_items: Array[ItemData])
signal inventory_error(message: String)

@export var base_max_capacity: int = 12 # Base-12.
var current_max_capacity: int = 12
var current_size: int = 0

var backpack_array: Array[ItemData] = []
var paper_doll: Dictionary = {}

## Optional owner-supplied policy. ItemCore does not import biological types.
var equipment_validator: Callable

func _ready() -> void:
	# Dynamically build the paper doll so you aren't walking around pantsless
	for slot in GameEnums.EquipmentSlot.values():
		if slot != GameEnums.EquipmentSlot.NONE:
			paper_doll[slot] = null
			
	_recalculate_bounds()

# ---------------------------------------------------------
# CORE OPERATIONS
# ---------------------------------------------------------
func add_to_backpack(item: ItemData) -> bool:
	var runtime_item := _ensure_runtime_item(item)
	if current_size + runtime_item.size_cost <= current_max_capacity:
		backpack_array.append(runtime_item)
		_recalculate_bounds()
		return true
		
	inventory_error.emit("Capacity exceeded.")
	return false

func equip_item(item: ItemData, slot: GameEnums.EquipmentSlot) -> bool:
	var runtime_item := _ensure_runtime_item(item)
	if not paper_doll.has(slot):
		inventory_error.emit("You can't wear that there.")
		return false
		
	if equipment_validator.is_valid():
		if not equipment_validator.call(runtime_item, slot):
			inventory_error.emit("The owning system rejected this equipment change.")
			return false
		
	# THE 2-WEAPON RULE: Only 1 Melee and 1 Ranged allowed.
	if runtime_item.item_type == GameEnums.ItemType.WEAPON:
		var is_equipping_melee = runtime_item.is_melee()
		for existing_slot in paper_doll.keys():
			if existing_slot == slot: continue
			var existing = paper_doll[existing_slot]
			if existing != null and existing.item_type == GameEnums.ItemType.WEAPON:
				if is_equipping_melee and existing.is_melee():
					inventory_error.emit("You can only carry one melee weapon. Unequip the other first.")
					return false
				elif not is_equipping_melee and existing.is_ranged():
					inventory_error.emit("You can only carry one firearm. Unequip the other first.")
					return false

	if backpack_array.has(runtime_item):
		backpack_array.erase(runtime_item)

	var old_item: ItemData = paper_doll[slot]
	if old_item != null:
		if not add_to_backpack(old_item):
			_emit_spilled_item(old_item)
			
	paper_doll[slot] = runtime_item
	equipment_changed.emit(slot, runtime_item)
	_recalculate_bounds()
	return true

func unequip_item(slot: GameEnums.EquipmentSlot) -> void:
	var item: ItemData = paper_doll[slot]
	if item == null:
		return
		
	paper_doll[slot] = null
	equipment_changed.emit(slot, null)
	
	if not add_to_backpack(item):
		_emit_spilled_item(item)
		
	_recalculate_bounds()

# ---------------------------------------------------------
# THE PARADOX FIX (Spill Over Logic)
# ---------------------------------------------------------
func _recalculate_bounds() -> void:
	var bonus_capacity: int = 0
	
	# THE FIX: Data-driven loop. No hardcoded string IDs.
	for slot in paper_doll.keys():
		var equipped_item: ItemData = paper_doll[slot]
		if equipped_item != null:
			bonus_capacity += equipped_item.capacity_bonus
			
	current_max_capacity = base_max_capacity + bonus_capacity

	current_size = 0
	for item in backpack_array:
		current_size += item.size_cost

	if current_size > current_max_capacity:
		_execute_spill_over()
		
	capacity_updated.emit(current_size, current_max_capacity)

func _execute_spill_over() -> void:
	var dropped_items: Array[ItemData] = []
	
	while current_size > current_max_capacity and backpack_array.size() > 0:
		var ejected_item: ItemData = backpack_array.pop_back()
		current_size -= ejected_item.size_cost
		dropped_items.append(ejected_item)
		
	if dropped_items.size() > 0:
		items_spilled.emit(dropped_items)
		inventory_error.emit("Your bag overflowed. Items spilled into the dirt.")

func _emit_spilled_item(item: ItemData) -> void:
	var spilled: Array[ItemData] = [item]
	items_spilled.emit(spilled)

# ---------------------------------------------------------
# GEAR STAT AGGREGATION (The Paper Doll Math)
# ---------------------------------------------------------

## Sum a specific float field across all equipped items on the paper doll.
func _sum_equipped_stat(stat_name: String) -> float:
	var total: float = 0.0
	for slot in paper_doll.keys():
		var item: ItemData = paper_doll[slot]
		if item != null and item.get(stat_name) != null:
			total += item.get(stat_name)
	return total

## Total WEIGHT tax from all equipped gear. Penalizes AP on every action.
func get_total_weight() -> float:
	return _sum_equipped_stat("weight")

## Total BULK across equipped gear. Negative = dodge bonus, Positive = resistance bonus.
func get_total_bulk() -> float:
	return _sum_equipped_stat("bulk")

## Total THREAT projection from equipped gear. Drives AI fight-or-flight decisions.
func get_total_threat() -> float:
	return _sum_equipped_stat("threat")

## Total thermal insulation from equipped torso layers.
func get_total_insulation() -> float:
	return _sum_equipped_stat("insulation")

## Get armor protection value for a specific damage type from all equipped gear.
func get_protection_for(damage_type: GameEnums.DamageType) -> float:
	match damage_type:
		GameEnums.DamageType.BLUNT:
			return _sum_equipped_stat("protection_blunt")
		GameEnums.DamageType.SHARP:
			return _sum_equipped_stat("protection_sharp")
		GameEnums.DamageType.BALLISTIC:
			return _sum_equipped_stat("protection_ballistic")
	return 0.0

# ---------------------------------------------------------
# CONTEXTUAL WEAPON FETCHING (The 2-Weapon System)
# ---------------------------------------------------------

## Fetches the correct weapon for the given context (Melee vs Ranged).
## Due to the 2-weapon rule, this simply returns the only valid weapon equipped.
func get_active_weapon(requires_melee: bool) -> ItemData:
	var search_slots = [GameEnums.EquipmentSlot.HANDS, GameEnums.EquipmentSlot.SLING, GameEnums.EquipmentSlot.BELT]
	for slot in search_slots:
		if paper_doll.has(slot):
			var item: ItemData = paper_doll[slot]
			if item != null and item.item_type == GameEnums.ItemType.WEAPON:
				if requires_melee and item.is_melee():
					return item
				elif not requires_melee and item.is_ranged():
					return item
	return null

func get_all_items() -> Array[ItemData]:
	var items: Array[ItemData] = []
	items.append_array(backpack_array)
	for item in paper_doll.values():
		if item != null:
			items.append(item)
	return items

func find_item_by_instance_id(instance_id: String) -> ItemData:
	for item in get_all_items():
		if item.instance_id == instance_id:
			return item
	return null

func remove_item_by_instance_id(instance_id: String) -> ItemData:
	for item in backpack_array:
		if item.instance_id == instance_id:
			backpack_array.erase(item)
			_recalculate_bounds()
			return item

	for slot in paper_doll.keys():
		var equipped: ItemData = paper_doll[slot]
		if equipped != null and equipped.instance_id == instance_id:
			paper_doll[slot] = null
			equipment_changed.emit(slot, null)
			_recalculate_bounds()
			return equipped
	return null

## Removes and returns every carried and equipped runtime item.
## Used by outcome owners when an entity's inventory becomes world loot.
func drain_all_items() -> Array[ItemData]:
	var drained: Array[ItemData] = []
	drained.append_array(backpack_array)
	backpack_array.clear()

	for slot in paper_doll.keys():
		var equipped: ItemData = paper_doll[slot]
		if equipped == null:
			continue
		drained.append(equipped)
		paper_doll[slot] = null
		equipment_changed.emit(slot, null)

	_recalculate_bounds()
	return drained

# ---------------------------------------------------------
# CONSUMABLE USAGE
# ---------------------------------------------------------

## Use a consumable item from the backpack. Returns true if successfully consumed.
func use_consumable(item: ItemData) -> bool:
	if item.item_type != GameEnums.ItemType.CONSUMABLE:
		inventory_error.emit("That's not something you can eat or drink.")
		return false
	
	if not backpack_array.has(item):
		inventory_error.emit("Item not found in backpack.")
		return false
	
	# Remove the item before applying the effect (it's consumed)
	backpack_array.erase(item)
	_recalculate_bounds()
	
	# The owning system applies the domain-specific effect after this returns.
	return true

# ---------------------------------------------------------
# RUNTIME STATE CONTRACT
# ---------------------------------------------------------

func capture_runtime_state() -> Dictionary:
	var equipment_state: Dictionary = {}
	for slot in paper_doll.keys():
		var item: ItemData = paper_doll[slot]
		if item != null:
			equipment_state[str(slot)] = item.to_runtime_state()

	var backpack_state: Array = []
	for item in backpack_array:
		backpack_state.append(item.to_runtime_state())

	return {
		"base_max_capacity": base_max_capacity,
		"equipment": equipment_state,
		"backpack": backpack_state,
	}

func restore_runtime_state(state: Dictionary) -> void:
	base_max_capacity = state.get("base_max_capacity", base_max_capacity)
	backpack_array.clear()

	for slot in paper_doll.keys():
		paper_doll[slot] = null

	var equipment_state: Dictionary = state.get("equipment", {})
	for slot_key in equipment_state.keys():
		var slot := int(slot_key)
		if paper_doll.has(slot):
			paper_doll[slot] = ItemData.from_runtime_state(equipment_state[slot_key])

	for item_state in state.get("backpack", []):
		backpack_array.append(ItemData.from_runtime_state(item_state))

	_recalculate_bounds()

func _ensure_runtime_item(item: ItemData) -> ItemData:
	if item.is_runtime_instance():
		return item
	return item.create_runtime_instance()

func set_equipment_validator(validator: Callable) -> void:
	equipment_validator = validator
