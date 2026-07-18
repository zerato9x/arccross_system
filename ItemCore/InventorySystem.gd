extends Node
class_name InventorySystem

signal capacity_updated(current: int, maximum: int)
signal equipment_changed(slot: GameEnums.EquipmentSlot, item: ItemData)
signal items_spilled(spilled_items: Array[ItemData])
signal inventory_error(message: String)

const STORAGE_SLOTS := [
	GameEnums.EquipmentSlot.VEST,
	GameEnums.EquipmentSlot.OUTER_TORSO,
	GameEnums.EquipmentSlot.LEGS,
	GameEnums.EquipmentSlot.BELT,
	GameEnums.EquipmentSlot.SLING,
	GameEnums.EquipmentSlot.BACKPACK,
]
const AVERAGE_ITEM_STORAGE := [
	GameEnums.EquipmentSlot.SLING,
	GameEnums.EquipmentSlot.BACKPACK,
]
const COMBAT_ACCESSIBLE_STORAGE := [
	GameEnums.EquipmentSlot.VEST,
]

@export var base_max_capacity: int = 0
var current_max_capacity: int = 0
var current_size: int = 0

## All stowed items remain in one authoritative collection for compatibility.
## item_container_slots records which worn storage item actually contains each one.
var backpack_array: Array[ItemData] = []
var item_container_slots: Dictionary = {}
var paper_doll: Dictionary = {}

## Optional owner-supplied policy. ItemCore does not import biological types.
var equipment_validator: Callable

func _ready() -> void:
	for slot in GameEnums.EquipmentSlot.values():
		if slot != GameEnums.EquipmentSlot.NONE:
			paper_doll[slot] = null
	base_max_capacity = 0
	_recalculate_bounds()

func add_to_backpack(
	item: ItemData,
	preferred_container: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE
) -> bool:
	var runtime_item := _ensure_runtime_item(item)
	if runtime_item.get_effective_item_size() == GameEnums.ItemSize.BIG:
		inventory_error.emit("That item is too large to carry.")
		return false
	if runtime_item.stack_count > runtime_item.get_stack_limit():
		inventory_error.emit("That stack exceeds its slot limit.")
		return false

	var merged_item := _find_stack_target(runtime_item, preferred_container)
	if merged_item != null:
		var available := (
			merged_item.get_stack_limit() - merged_item.stack_count
		)
		if available >= runtime_item.stack_count:
			merged_item.stack_count += runtime_item.stack_count
			_recalculate_bounds()
			return true

	var container_slot := _find_container_for_item(
		runtime_item,
		preferred_container
	)
	if container_slot == GameEnums.EquipmentSlot.NONE:
		inventory_error.emit(_fit_error(runtime_item, preferred_container))
		return false

	backpack_array.append(runtime_item)
	item_container_slots[runtime_item.instance_id] = container_slot
	_recalculate_bounds()
	return true

func move_to_container(
	item: ItemData,
	container_slot: GameEnums.EquipmentSlot
) -> bool:
	if not backpack_array.has(item):
		inventory_error.emit("Only stowed items can be moved between containers.")
		return false
	if not _container_accepts_item(container_slot, item, true):
		inventory_error.emit(_fit_error(item, container_slot))
		return false
	item_container_slots[item.instance_id] = container_slot
	_recalculate_bounds()
	return true

func equip_item(item: ItemData, slot: GameEnums.EquipmentSlot) -> bool:
	var runtime_item := _ensure_runtime_item(item)
	if not paper_doll.has(slot):
		inventory_error.emit("You can't wear that there.")
		return false
	if not can_equip_in_slot(runtime_item, slot):
		inventory_error.emit("That item does not belong in that equipment slot.")
		return false
	if equipment_validator.is_valid() and not equipment_validator.call(
		runtime_item,
		slot
	):
		inventory_error.emit("The owning system rejected this equipment change.")
		return false

	if runtime_item.item_type == GameEnums.ItemType.WEAPON:
		if not _validate_weapon_equip(runtime_item, slot):
			return false

	if backpack_array.has(runtime_item):
		backpack_array.erase(runtime_item)
		item_container_slots.erase(runtime_item.instance_id)

	var old_item: ItemData = paper_doll[slot]
	paper_doll[slot] = runtime_item
	equipment_changed.emit(slot, runtime_item)

	if old_item != null and not add_to_backpack(old_item):
		_emit_spilled_item(old_item)

	_recalculate_bounds()
	return true

func can_equip_in_slot(item: ItemData, slot: GameEnums.EquipmentSlot) -> bool:
	if item.item_type == GameEnums.ItemType.WEAPON:
		if item.requires_two_hands:
			return slot == GameEnums.EquipmentSlot.HAND
		return slot in [
			GameEnums.EquipmentSlot.HAND,
			GameEnums.EquipmentSlot.OFFHAND,
		]
	if (
		item.item_type == GameEnums.ItemType.ARMOR
		and item.target_slot == GameEnums.EquipmentSlot.HAND
	):
		return slot == GameEnums.EquipmentSlot.OFFHAND
	return item.target_slot == slot

func get_preferred_equipment_slot(item: ItemData) -> GameEnums.EquipmentSlot:
	if item.item_type == GameEnums.ItemType.WEAPON:
		if paper_doll.get(GameEnums.EquipmentSlot.HAND) == null:
			return GameEnums.EquipmentSlot.HAND
		if not item.requires_two_hands:
			return GameEnums.EquipmentSlot.OFFHAND
		return GameEnums.EquipmentSlot.HAND
	if (
		item.item_type == GameEnums.ItemType.ARMOR
		and item.target_slot == GameEnums.EquipmentSlot.HAND
	):
		return GameEnums.EquipmentSlot.OFFHAND
	return item.target_slot

func unequip_item(slot: GameEnums.EquipmentSlot) -> void:
	if not paper_doll.has(slot):
		return
	var item: ItemData = paper_doll[slot]
	if item == null:
		return

	var displaced_contents := get_container_items(slot)
	paper_doll[slot] = null
	equipment_changed.emit(slot, null)

	for contained_item in displaced_contents:
		item_container_slots.erase(contained_item.instance_id)

	var item_container := _find_container_for_item(item)
	if item_container == GameEnums.EquipmentSlot.NONE:
		_emit_spilled_item(item)
	else:
		backpack_array.append(item)
		item_container_slots[item.instance_id] = item_container

	var spilled: Array[ItemData] = []
	for contained_item in displaced_contents:
		var replacement := _find_container_for_item(contained_item)
		if replacement == GameEnums.EquipmentSlot.NONE:
			backpack_array.erase(contained_item)
			spilled.append(contained_item)
		else:
			item_container_slots[contained_item.instance_id] = replacement
	if not spilled.is_empty():
		_emit_spilled_items(spilled)

	_recalculate_bounds()

func _validate_weapon_equip(
	item: ItemData,
	slot: GameEnums.EquipmentSlot
) -> bool:
	if item.requires_two_hands:
		var offhand: ItemData = paper_doll.get(GameEnums.EquipmentSlot.OFFHAND)
		if offhand != null and offhand != item:
			inventory_error.emit("The offhand must be empty for a two-handed weapon.")
			return false
	elif slot == GameEnums.EquipmentSlot.OFFHAND:
		var main_hand: ItemData = paper_doll.get(GameEnums.EquipmentSlot.HAND)
		if main_hand != null and main_hand.requires_two_hands:
			inventory_error.emit("The main-hand weapon already requires both hands.")
			return false

	var is_equipping_melee := item.is_melee()
	for existing_slot in [
		GameEnums.EquipmentSlot.HAND,
		GameEnums.EquipmentSlot.OFFHAND,
	]:
		if existing_slot == slot:
			continue
		var existing: ItemData = paper_doll.get(existing_slot)
		if existing == null or existing.item_type != GameEnums.ItemType.WEAPON:
			continue
		if is_equipping_melee and existing.is_melee():
			inventory_error.emit("You can only ready one melee weapon.")
			return false
		if not is_equipping_melee and existing.is_ranged():
			inventory_error.emit("You can only ready one firearm.")
			return false
	return true

func _recalculate_bounds() -> void:
	base_max_capacity = 0
	current_max_capacity = 0
	for slot in STORAGE_SLOTS:
		current_max_capacity += get_container_capacity(slot)

	var displaced: Array[ItemData] = []
	for item in backpack_array:
		var assigned_slot := get_item_container_slot(item)
		if not _container_accepts_item(assigned_slot, item, false):
			displaced.append(item)

	for item in displaced:
		item_container_slots.erase(item.instance_id)
		var replacement := _find_container_for_item(item)
		if replacement != GameEnums.EquipmentSlot.NONE:
			item_container_slots[item.instance_id] = replacement

	var spilled: Array[ItemData] = []
	for item in displaced:
		if not item_container_slots.has(item.instance_id):
			backpack_array.erase(item)
			spilled.append(item)

	for slot in STORAGE_SLOTS:
		while get_container_used_capacity(slot) > get_container_capacity(slot):
			var contents := get_container_items(slot)
			if contents.is_empty():
				break
			var ejected: ItemData = contents.back()
			item_container_slots.erase(ejected.instance_id)
			var replacement := _find_container_for_item(
				ejected,
				GameEnums.EquipmentSlot.NONE,
				[slot]
			)
			if replacement == GameEnums.EquipmentSlot.NONE:
				backpack_array.erase(ejected)
				spilled.append(ejected)
			else:
				item_container_slots[ejected.instance_id] = replacement

	current_size = 0
	for item in backpack_array:
		current_size += item.get_inventory_cost()

	if not spilled.is_empty():
		_emit_spilled_items(spilled)
	capacity_updated.emit(current_size, current_max_capacity)

func get_container_capacity(slot: GameEnums.EquipmentSlot) -> int:
	var storage_item: ItemData = paper_doll.get(slot)
	return storage_item.capacity_bonus if storage_item != null else 0

func get_container_used_capacity(slot: GameEnums.EquipmentSlot) -> int:
	var used := 0
	for item in backpack_array:
		if get_item_container_slot(item) == slot:
			used += item.get_inventory_cost()
	return used

func get_container_items(slot: GameEnums.EquipmentSlot) -> Array[ItemData]:
	var items: Array[ItemData] = []
	for item in backpack_array:
		if get_item_container_slot(item) == slot:
			items.append(item)
	return items

func get_item_container_slot(item: ItemData) -> GameEnums.EquipmentSlot:
	return int(item_container_slots.get(
		item.instance_id,
		GameEnums.EquipmentSlot.NONE
	)) as GameEnums.EquipmentSlot

func get_storage_slots() -> Array[int]:
	var slots: Array[int] = []
	for slot in STORAGE_SLOTS:
		if get_container_capacity(slot) > 0:
			slots.append(slot)
	return slots

func is_combat_accessible(item: ItemData) -> bool:
	if item == null:
		return false
	if not backpack_array.has(item):
		return true
	return get_item_container_slot(item) in COMBAT_ACCESSIBLE_STORAGE

func has_combat_item(item_id: String) -> bool:
	return find_combat_item(item_id) != null

func find_combat_item(item_id: String) -> ItemData:
	for item in backpack_array:
		if (
			item.id == item_id
			and is_combat_accessible(item)
			and item.stack_count > 0
		):
			return item
	return null

func consume_item_units(item: ItemData, amount: int = 1) -> bool:
	if item == null or not backpack_array.has(item) or amount <= 0:
		return false
	if item.stack_count > amount:
		item.stack_count -= amount
	else:
		backpack_array.erase(item)
		item_container_slots.erase(item.instance_id)
	_recalculate_bounds()
	return true

func consume_ammunition(
	ammunition_id: String,
	amount: int = 1,
	combat_only: bool = true
) -> int:
	var remaining := amount
	var consumed := 0
	for item in backpack_array.duplicate():
		if item.id != ammunition_id:
			continue
		if combat_only and not is_combat_accessible(item):
			continue
		var taken := mini(remaining, item.stack_count)
		item.stack_count -= taken
		remaining -= taken
		consumed += taken
		if item.stack_count <= 0:
			backpack_array.erase(item)
			item_container_slots.erase(item.instance_id)
		if remaining <= 0:
			break
	_recalculate_bounds()
	return consumed

func load_magazine(magazine: ItemData) -> int:
	if magazine == null or not backpack_array.has(magazine):
		inventory_error.emit("The magazine must be in carried storage.")
		return 0
	if not magazine.is_magazine():
		inventory_error.emit("That item cannot be fitted with rounds.")
		return 0
	var needed := magazine.magazine_capacity - magazine.loaded_rounds
	if needed <= 0:
		inventory_error.emit("That magazine is already full.")
		return 0
	var loaded := consume_ammunition(
		magazine.accepted_ammunition_id,
		needed,
		false
	)
	magazine.loaded_rounds += loaded
	if loaded == 0:
		inventory_error.emit(
			"No compatible %s rounds are available."
			% magazine.accepted_ammunition_id
		)
	return loaded

func consume_filled_magazine(magazine_id: String) -> ItemData:
	var magazine := find_filled_magazine(magazine_id)
	if magazine == null:
		return null
	backpack_array.erase(magazine)
	item_container_slots.erase(magazine.instance_id)
	_recalculate_bounds()
	return magazine

func find_filled_magazine(magazine_id: String) -> ItemData:
	for item in backpack_array:
		if (
			item.id == magazine_id
			and item.is_magazine()
			and item.loaded_rounds > 0
			and is_combat_accessible(item)
		):
			return item
	return null

func _find_stack_target(
	item: ItemData,
	preferred_container: GameEnums.EquipmentSlot
) -> ItemData:
	for existing in backpack_array:
		if not existing.can_stack_with(item):
			continue
		if existing.stack_count >= existing.get_stack_limit():
			continue
		if (
			preferred_container != GameEnums.EquipmentSlot.NONE
			and get_item_container_slot(existing) != preferred_container
		):
			continue
		return existing
	return null

func _find_container_for_item(
	item: ItemData,
	preferred_container: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE,
	excluded_slots: Array = []
) -> GameEnums.EquipmentSlot:
	if (
		preferred_container != GameEnums.EquipmentSlot.NONE
		and preferred_container not in excluded_slots
		and _container_accepts_item(preferred_container, item, true)
	):
		return preferred_container
	if preferred_container != GameEnums.EquipmentSlot.NONE:
		return GameEnums.EquipmentSlot.NONE

	for slot in _storage_priority_for(item):
		if slot in excluded_slots:
			continue
		if _container_accepts_item(slot, item, true):
			return slot
	return GameEnums.EquipmentSlot.NONE

func _storage_priority_for(item: ItemData) -> Array:
	if item.item_type == GameEnums.ItemType.AMMUNITION:
		return [
			GameEnums.EquipmentSlot.VEST,
			GameEnums.EquipmentSlot.BACKPACK,
			GameEnums.EquipmentSlot.OUTER_TORSO,
			GameEnums.EquipmentSlot.LEGS,
			GameEnums.EquipmentSlot.BELT,
			GameEnums.EquipmentSlot.SLING,
		]
	return [
		GameEnums.EquipmentSlot.BACKPACK,
		GameEnums.EquipmentSlot.OUTER_TORSO,
		GameEnums.EquipmentSlot.LEGS,
		GameEnums.EquipmentSlot.VEST,
		GameEnums.EquipmentSlot.BELT,
		GameEnums.EquipmentSlot.SLING,
	]

func _container_accepts_item(
	slot: GameEnums.EquipmentSlot,
	item: ItemData,
	require_free_space: bool
) -> bool:
	if slot == GameEnums.EquipmentSlot.NONE:
		return false
	var capacity := get_container_capacity(slot)
	if capacity <= 0:
		return false
	var item_size := item.get_effective_item_size()
	if item_size == GameEnums.ItemSize.BIG:
		return false
	if (
		item_size == GameEnums.ItemSize.AVERAGE
		and slot not in AVERAGE_ITEM_STORAGE
	):
		return false
	if require_free_space:
		return (
			get_container_used_capacity(slot) + item.get_inventory_cost()
			<= capacity
		)
	return true

func _fit_error(
	item: ItemData,
	preferred_container: GameEnums.EquipmentSlot
) -> String:
	if item.get_effective_item_size() == GameEnums.ItemSize.BIG:
		return "That item is too large to pick up."
	if preferred_container != GameEnums.EquipmentSlot.NONE:
		return "That item does not fit in the selected container."
	return "No worn container has enough compatible space."

func _emit_spilled_item(item: ItemData) -> void:
	_emit_spilled_items([item])

func _emit_spilled_items(spilled: Array[ItemData]) -> void:
	if spilled.is_empty():
		return
	items_spilled.emit(spilled)
	inventory_error.emit("Storage changed. Items spilled onto the ground.")

func _sum_equipped_stat(stat_name: String) -> float:
	var total := 0.0
	for item in paper_doll.values():
		if item != null and item.get(stat_name) != null:
			total += float(item.get(stat_name))
	return total

func get_total_weight() -> float:
	return _sum_equipped_stat("weight")

func get_total_bulk() -> float:
	return _sum_equipped_stat("bulk")

func get_total_threat() -> float:
	return _sum_equipped_stat("threat")

func get_total_insulation() -> float:
	return _sum_equipped_stat("insulation")

func get_protection_for(damage_type: GameEnums.DamageType, limb_region: int = -1) -> float:
	var stat_name := ""
	match damage_type:
		GameEnums.DamageType.BLUNT:
			stat_name = "protection_blunt"
		GameEnums.DamageType.SHARP:
			stat_name = "protection_sharp"
		GameEnums.DamageType.BALLISTIC:
			stat_name = "protection_ballistic"
	if stat_name.is_empty():
		return 0.0
	var total := 0.0
	for slot in paper_doll.keys():
		var item: ItemData = paper_doll.get(slot)
		if item != null and (limb_region < 0 or _slot_covers_limb(int(slot), limb_region)):
			total += float(item.get(stat_name))
	return total


func _slot_covers_limb(slot: int, limb: int) -> bool:
	match slot:
		GameEnums.EquipmentSlot.HEAD, GameEnums.EquipmentSlot.EYES, GameEnums.EquipmentSlot.FACE:
			return limb == GameEnums.LimbRegion.HEAD
		GameEnums.EquipmentSlot.NECK:
			return limb in [GameEnums.LimbRegion.HEAD, GameEnums.LimbRegion.UPPER_TORSO]
		GameEnums.EquipmentSlot.INNER_TORSO, GameEnums.EquipmentSlot.OUTER_TORSO, GameEnums.EquipmentSlot.VEST:
			return limb in [GameEnums.LimbRegion.UPPER_TORSO, GameEnums.LimbRegion.LOWER_TORSO]
		GameEnums.EquipmentSlot.ARMS:
			return limb in [GameEnums.LimbRegion.LEFT_ARM, GameEnums.LimbRegion.RIGHT_ARM]
		GameEnums.EquipmentSlot.LEGS:
			return limb in [GameEnums.LimbRegion.LOWER_TORSO, GameEnums.LimbRegion.LEFT_LEG, GameEnums.LimbRegion.RIGHT_LEG]
		GameEnums.EquipmentSlot.FEET:
			return limb in [GameEnums.LimbRegion.LEFT_LEG, GameEnums.LimbRegion.RIGHT_LEG]
	return false

func get_active_weapon(requires_melee: bool) -> ItemData:
	for slot in [
		GameEnums.EquipmentSlot.HAND,
		GameEnums.EquipmentSlot.OFFHAND,
	]:
		var item: ItemData = paper_doll.get(slot)
		if item == null or item.item_type != GameEnums.ItemType.WEAPON:
			continue
		if requires_melee and item.is_melee():
			return item
		if not requires_melee and item.is_ranged():
			return item
	return null

func get_all_items() -> Array[ItemData]:
	var items: Array[ItemData] = []
	items.append_array(backpack_array)
	for item in paper_doll.values():
		if item != null and item not in items:
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
			item_container_slots.erase(instance_id)
			_recalculate_bounds()
			return item

	for slot in paper_doll.keys():
		var equipped: ItemData = paper_doll[slot]
		if equipped != null and equipped.instance_id == instance_id:
			var displaced_contents := get_container_items(slot)
			paper_doll[slot] = null
			equipment_changed.emit(slot, null)
			for contained_item in displaced_contents:
				item_container_slots.erase(contained_item.instance_id)
			var spilled: Array[ItemData] = []
			for contained_item in displaced_contents:
				var replacement := _find_container_for_item(contained_item)
				if replacement == GameEnums.EquipmentSlot.NONE:
					backpack_array.erase(contained_item)
					spilled.append(contained_item)
				else:
					item_container_slots[contained_item.instance_id] = replacement
			if not spilled.is_empty():
				_emit_spilled_items(spilled)
			_recalculate_bounds()
			return equipped
	return null

func drain_all_items() -> Array[ItemData]:
	var drained: Array[ItemData] = []
	drained.append_array(backpack_array)
	backpack_array.clear()
	item_container_slots.clear()

	for slot in paper_doll.keys():
		var equipped: ItemData = paper_doll[slot]
		if equipped == null:
			continue
		drained.append(equipped)
		paper_doll[slot] = null
		equipment_changed.emit(slot, null)

	_recalculate_bounds()
	return drained

func use_consumable(item: ItemData, combat_only: bool = false) -> bool:
	if item.item_type != GameEnums.ItemType.CONSUMABLE:
		inventory_error.emit("That's not something you can eat or drink.")
		return false
	if not backpack_array.has(item):
		inventory_error.emit("Item not found in carried storage.")
		return false
	if combat_only and not is_combat_accessible(item):
		inventory_error.emit("Only items in the rig can be used during combat.")
		return false
	return consume_item_units(item)

func capture_runtime_state() -> InventoryState:
	var state := InventoryState.new()
	state.base_max_capacity = 0

	var equipment_state: Dictionary = {}
	for slot in paper_doll.keys():
		var item: ItemData = paper_doll[slot]
		if item != null:
			equipment_state[str(slot)] = item.to_runtime_state()
	state.equipment = equipment_state

	var backpack_state: Array = []
	for item in backpack_array:
		var item_state := item.to_runtime_state()
		item_state["container_slot"] = get_item_container_slot(item)
		backpack_state.append(item_state)
	state.backpack = backpack_state

	return state

func restore_runtime_state(state) -> void:
	var inv_state: InventoryState
	if state is InventoryState:
		inv_state = state
	elif state is Dictionary:
		inv_state = InventoryState.from_dict(state)
	else:
		return

	base_max_capacity = 0
	backpack_array.clear()
	item_container_slots.clear()

	for slot in paper_doll.keys():
		paper_doll[slot] = null

	for slot_key in inv_state.equipment.keys():
		var slot := int(slot_key)
		if paper_doll.has(slot):
			paper_doll[slot] = ItemData.from_runtime_state(
				inv_state.equipment[slot_key]
			)

	for item_state in inv_state.backpack:
		var item := ItemData.from_runtime_state(item_state)
		backpack_array.append(item)
		var container_slot := int(item_state.get(
			"container_slot",
			GameEnums.EquipmentSlot.NONE
		))
		if container_slot != GameEnums.EquipmentSlot.NONE:
			item_container_slots[item.instance_id] = container_slot

	_recalculate_bounds()

func _ensure_runtime_item(item: ItemData) -> ItemData:
	if item.is_runtime_instance():
		return item
	return item.create_runtime_instance()

func set_equipment_validator(validator: Callable) -> void:
	equipment_validator = validator
