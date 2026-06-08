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

# We need to know about the meat to enforce the Black Knight rule
var _body_ref: HumanoidBody

func _ready() -> void:
	# Dynamically build the paper doll so you aren't walking around pantsless
	for slot in GameEnums.EquipmentSlot.values():
		if slot != GameEnums.EquipmentSlot.NONE:
			paper_doll[slot] = null
			
	_body_ref = get_parent().get_node_or_null("HumanoidBody")
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
		
	# THE BLACK KNIGHT PRE-CHECK
	if item.requires_two_hands and _body_ref and not _body_ref.has_functional_arms():
		inventory_error.emit("You lack the necessary biological hardware to hold this.")
		return false
		
	# THE 2-WEAPON RULE: Only 1 Melee and 1 Ranged allowed.
	if item.item_type == GameEnums.ItemType.WEAPON:
		var is_equipping_melee = item.is_melee()
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

	if backpack_array.has(item):
		backpack_array.erase(item)

	var old_item: ItemData = paper_doll[slot]
	if old_item != null:
		if not add_to_backpack(old_item):
			items_spilled.emit([old_item])
			
	paper_doll[slot] = item
	equipment_changed.emit(slot, item)
	_recalculate_bounds()
	return true

func unequip_item(slot: GameEnums.EquipmentSlot) -> void:
	var item: ItemData = paper_doll[slot]
	if item == null:
		return
		
	paper_doll[slot] = null
	equipment_changed.emit(slot, null)
	
	if not add_to_backpack(item):
		items_spilled.emit([item])
		
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
	
	# The actual metabolic effect is applied by HumanoidCore after this returns
	return true
