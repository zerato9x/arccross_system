extends Node
class_name InventorySystem

const _CapacityCalculator := preload("res://ItemCore/InventoryCapacityCalculator.gd")
const _Ledger := preload("res://ItemCore/InventoryLedger.gd")
const _EquipmentRules := preload("res://ItemCore/EquipmentRules.gd")
const _RuntimeCodec := preload("res://ItemCore/InventoryRuntimeCodec.gd")
const _FirearmService := preload("res://ItemCore/InventoryFirearmService.gd")

signal capacity_updated(current: int, maximum: int)
signal equipment_changed(slot: GameEnums.EquipmentSlot, item: ItemData)
signal items_spilled(spilled_items: Array[ItemData])
signal inventory_error(message: String)
signal transfer_committed(receipt: Dictionary)

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
	GameEnums.EquipmentSlot.BELT,
	GameEnums.EquipmentSlot.SLING,
]
const ACCESS_HANDS := "hands"
const ACCESS_QUICK := "quick"
const ACCESS_RUMMAGE := "rummage"
const ACCESS_ADJACENT := "adjacent"

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
var condition_service := InventoryConditionService.new()
var capacity_calculator := _CapacityCalculator.new()
var ledger := _Ledger.new()
var equipment_rules := _EquipmentRules.new()
var runtime_codec := _RuntimeCodec.new()
var firearm_service := _FirearmService.new()

func _ready() -> void:
	ensure_runtime_initialized()


func ensure_runtime_initialized() -> void:
	## EntityFactory may fabricate a parentless neutral projection for validation
	## or result application. Such nodes do not receive _ready(), so equipment
	## slots and firearm callbacks must be initialized explicitly and idempotently.
	for slot in GameEnums.EquipmentSlot.values():
		if slot != GameEnums.EquipmentSlot.NONE and not paper_doll.has(slot):
			paper_doll[slot] = null
	base_max_capacity = 0
	_recalculate_bounds()
	_configure_firearm_service()


func _configure_firearm_service() -> void:
	firearm_service.configure(
		backpack_array,
		item_container_slots,
		{
			"combat_accessible": Callable(self, "is_combat_accessible"),
			"container_slot": Callable(self, "get_item_container_slot"),
			"add_to_backpack": Callable(self, "add_to_backpack"),
			"recalculate": Callable(self, "_recalculate_bounds"),
			"error": Callable(self, "_emit_inventory_error"),
			"spilled": Callable(self, "_emit_spilled_item"),
			"transfer": Callable(self, "_emit_transfer_receipt"),
		}
	)


func _ensure_firearm_service() -> void:
	if firearm_service == null:
		firearm_service = _FirearmService.new()
	_configure_firearm_service()


func _emit_inventory_error(message: String) -> void:
	inventory_error.emit(message)


func _emit_transfer_receipt(receipt: Dictionary) -> void:
	transfer_committed.emit(receipt)


func can_add_to_backpack(
	item: ItemData,
	preferred_container: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE
) -> bool:
	"""Return whether add_to_backpack can accept the item without mutating state.

	This is intentionally a pure capacity/compatibility preflight. Callers that
	need to move an item between inventories must use it before removing the
	item from its source, because removal can have equipment-container side
	effects such as content redistribution and spills.
	"""
	if item == null:
		return false
	var runtime_item := _ensure_runtime_item(item)
	if runtime_item.get_effective_item_size() == GameEnums.ItemSize.BIG:
		return false
	if runtime_item.stack_count > runtime_item.get_stack_limit():
		return false

	var stack_target := _find_stack_target(runtime_item, preferred_container)
	if (
		stack_target != null
		and stack_target.stack_count + runtime_item.stack_count
		<= stack_target.get_stack_limit()
	):
		return backpack_array.find(stack_target) >= 0

	return _find_container_for_item(runtime_item, preferred_container) != GameEnums.EquipmentSlot.NONE


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

	var stack_target := _find_stack_target(
		runtime_item,
		preferred_container
	)
	if (
		stack_target != null
		and stack_target.stack_count + runtime_item.stack_count
		<= stack_target.get_stack_limit()
	):
		var target_slot := get_item_container_slot(stack_target)
		var target_index := backpack_array.find(stack_target)
		if target_index < 0:
			return false
		runtime_item.stack_count += stack_target.stack_count
		# The incoming runtime instance is the ownership-transfer subject. Keep
		# its stable ID when merging so ground pickup, save records, and UI intent
		# acknowledgements continue to refer to the same item instance.
		backpack_array[target_index] = runtime_item
		item_container_slots.erase(stack_target.instance_id)
		item_container_slots[runtime_item.instance_id] = target_slot
		_set_stowed_location(runtime_item, target_slot)
		_recalculate_bounds()
		transfer_committed.emit({
			"type": "pickup",
			"stacked": true,
			"source_instance_id": runtime_item.instance_id,
			"instance_id": runtime_item.instance_id,
			"container_instance_id": runtime_item.container_instance_id,
			"retired_instance_id": stack_target.instance_id,
			"quantity": runtime_item.stack_count,
		})
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
	_set_stowed_location(runtime_item, container_slot)
	_recalculate_bounds()
	transfer_committed.emit({
		"type": "pickup",
		"instance_id": runtime_item.instance_id,
		"container_instance_id": runtime_item.container_instance_id,
	})
	return true


func consolidate_instances(survivor: ItemData, retired: ItemData) -> Dictionary:
	if (
		survivor == null
		or retired == null
		or survivor == retired
		or not backpack_array.has(survivor)
		or not backpack_array.has(retired)
		or not survivor.can_stack_with(retired)
		or survivor.stack_count + retired.stack_count > survivor.get_stack_limit()
	):
		return {}
	survivor.stack_count += retired.stack_count
	backpack_array.erase(retired)
	item_container_slots.erase(retired.instance_id)
	var receipt := {
		"type": "consolidate",
		"surviving_instance_id": survivor.instance_id,
		"retired_instance_ids": [retired.instance_id],
		"quantity": survivor.stack_count,
	}
	_recalculate_bounds()
	transfer_committed.emit(receipt)
	return receipt


func get_access_tier(item: ItemData) -> String:
	if item == null:
		return "invalid"
	if item.physical_location == "equipped" and item.equipped_slot in [
		GameEnums.EquipmentSlot.HAND,
		GameEnums.EquipmentSlot.OFFHAND,
	]:
		return ACCESS_HANDS
	var container_slot := int(item_container_slots.get(
		item.instance_id,
		GameEnums.EquipmentSlot.NONE
	))
	if container_slot in COMBAT_ACCESSIBLE_STORAGE:
		return ACCESS_QUICK
	if container_slot in STORAGE_SLOTS:
		return ACCESS_RUMMAGE
	if item.physical_location in ["ground", "body"]:
		return ACCESS_ADJACENT
	return "unavailable"

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
	_set_stowed_location(item, container_slot)
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
		var weapon_error := equipment_rules.weapon_equip_error(
			runtime_item,
			slot,
			paper_doll
		)
		if not weapon_error.is_empty():
			inventory_error.emit(weapon_error)
			return false

	if backpack_array.has(runtime_item):
		backpack_array.erase(runtime_item)
		item_container_slots.erase(runtime_item.instance_id)
	runtime_item.physical_location = "equipped"
	runtime_item.equipped_slot = slot
	runtime_item.container_instance_id = ""

	var old_item: ItemData = paper_doll[slot]
	paper_doll[slot] = runtime_item
	equipment_changed.emit(slot, runtime_item)

	if old_item != null and not add_to_backpack(old_item):
		_emit_spilled_item(old_item)

	_recalculate_bounds()
	return true

func can_equip_in_slot(item: ItemData, slot: GameEnums.EquipmentSlot) -> bool:
	return equipment_rules.can_equip_in_slot(item, slot)

func get_preferred_equipment_slot(item: ItemData) -> GameEnums.EquipmentSlot:
	return equipment_rules.preferred_equipment_slot(item, paper_doll)

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
		_set_stowed_location(item, item_container)

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

func _recalculate_bounds() -> void:
	base_max_capacity = 0
	current_max_capacity = capacity_calculator.total_capacity(
		paper_doll,
		STORAGE_SLOTS
	)

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

	current_size = capacity_calculator.total_item_cost(backpack_array)

	if not spilled.is_empty():
		_emit_spilled_items(spilled)
	capacity_updated.emit(current_size, current_max_capacity)

func get_container_capacity(slot: GameEnums.EquipmentSlot) -> int:
	return capacity_calculator.container_capacity(paper_doll, slot)

func get_container_used_capacity(slot: GameEnums.EquipmentSlot) -> int:
	return capacity_calculator.container_used_capacity(
		backpack_array,
		item_container_slots,
		slot
	)

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
	_ensure_firearm_service()
	return firearm_service.consume_ammunition(ammunition_id, amount, combat_only)

func load_magazine(magazine: ItemData) -> int:
	_ensure_firearm_service()
	return firearm_service.load_magazine(magazine)

func consume_filled_magazine(magazine_id: String) -> ItemData:
	_ensure_firearm_service()
	return firearm_service.consume_filled_magazine(magazine_id)


func swap_fitted_magazine(weapon: ItemData, incoming: ItemData) -> Dictionary:
	_ensure_firearm_service()
	return firearm_service.swap_fitted_magazine(weapon, incoming)


func use_reload_aid(weapon: ItemData, aid: ItemData) -> Dictionary:
	_ensure_firearm_service()
	return firearm_service.use_reload_aid(weapon, aid)


func fit_attachment(weapon: ItemData, attachment: ItemData) -> Dictionary:
	_ensure_firearm_service()
	return firearm_service.fit_attachment(weapon, attachment)


func detach_attachment(weapon: ItemData, attachment_instance_id: String) -> Dictionary:
	_ensure_firearm_service()
	return firearm_service.detach_attachment(weapon, attachment_instance_id)

func find_filled_magazine(magazine_id: String) -> ItemData:
	_ensure_firearm_service()
	return firearm_service.find_filled_magazine(magazine_id)

func _find_stack_target(
	item: ItemData,
	preferred_container: GameEnums.EquipmentSlot
) -> ItemData:
	for existing in backpack_array:
		if existing == item:
			continue
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


func _set_stowed_location(
	item: ItemData,
	container_slot: GameEnums.EquipmentSlot
) -> void:
	item.physical_location = "container"
	item.equipped_slot = GameEnums.EquipmentSlot.NONE
	var container: ItemData = paper_doll.get(container_slot)
	item.container_instance_id = container.instance_id if container != null else ""

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
	for item in spilled:
		item.physical_location = "ground"
		item.equipped_slot = GameEnums.EquipmentSlot.NONE
		item.container_instance_id = ""
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
		if (
			item != null
			and item.has_active_function()
			and (limb_region < 0 or _item_covers_limb(item, limb_region))
		):
			total += float(item.get(stat_name))
	return total

## Mutating combat query. Equipment is always evaluated in stable numeric slot
## order so identical rolls yield identical records in either combat scheduler.
func resolve_protection_event(
	damage_type: GameEnums.DamageType,
	limb_region: int = -1,
	rolls: Array[float] = []
) -> Dictionary:
	var stat_name := ""
	match damage_type:
		GameEnums.DamageType.BLUNT:
			stat_name = "protection_blunt"
		GameEnums.DamageType.SHARP:
			stat_name = "protection_sharp"
		GameEnums.DamageType.BALLISTIC:
			stat_name = "protection_ballistic"
	var result := {"total_protection": 0.0, "item_outcomes": []}
	if stat_name.is_empty():
		return result

	var slots: Array = paper_doll.keys()
	slots.sort()
	var roll_index := 0
	for slot_value in slots:
		var slot := int(slot_value)
		var item: ItemData = paper_doll.get(slot)
		if item == null or (limb_region >= 0 and not _item_covers_limb(item, limb_region)):
			continue
		var authored := float(item.get(stat_name))
		if authored <= 0.0:
			continue
		var roll := -1.0
		if roll_index < rolls.size():
			roll = rolls[roll_index]
		roll_index += 1
		var outcome := condition_service.resolve_use(
			item,
			ItemConditionRules.EVENT_ARMOR,
			roll
		)
		var contribution := authored * float(outcome.performance_multiplier)
		outcome["equipment_slot"] = slot
		outcome["authored_protection"] = authored
		outcome["protection_contribution"] = contribution
		result.item_outcomes.append(outcome)
		result.total_protection += contribution
	return result


func preview_protection(damage_type: GameEnums.DamageType, limb_region: int = -1) -> float:
	## Read-only armor forecast. This never rolls faults or applies wear.
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
	for slot_value in paper_doll:
		var item: ItemData = paper_doll.get(slot_value)
		if item == null or (limb_region >= 0 and not _item_covers_limb(item, limb_region)):
			continue
		if item.condition_enabled and item.current_condition <= 0.0:
			continue
		total += float(item.get(stat_name))
	return total

## Shared repair transaction. WorldCore owns combat gating and time passage;
## ItemCore owns recipes, material consumption, tool wear, and condition caps.
func repair_item(
	target: ItemData,
	tool: ItemData,
	material: ItemData,
	context: String,
	roll_override: float = -1.0
) -> Dictionary:
	return condition_service.repair_item(
		self,
		target,
		tool,
		material,
		context,
		roll_override
	)


func _item_covers_limb(item: ItemData, limb: int) -> bool:
	if item == null:
		return false
	if not item.armor_coverage.is_empty():
		return item.armor_coverage.has(limb)
	# Legacy/custom armor definitions often author only their equipment slot.
	# Resolve that neutral slot into the broad body region without making the
	# combat scheduler know about inventory authoring details.
	match item.target_slot:
		GameEnums.EquipmentSlot.HEAD:
			return limb == GameEnums.LimbRegion.HEAD
		GameEnums.EquipmentSlot.INNER_TORSO, GameEnums.EquipmentSlot.OUTER_TORSO:
			return limb in [
				GameEnums.LimbRegion.UPPER_TORSO,
				GameEnums.LimbRegion.LOWER_TORSO,
			]
		GameEnums.EquipmentSlot.ARMS:
			return limb in [
				GameEnums.LimbRegion.LEFT_ARM,
				GameEnums.LimbRegion.RIGHT_ARM,
			]
		GameEnums.EquipmentSlot.LEGS:
			return limb in [
				GameEnums.LimbRegion.LEFT_LEG,
				GameEnums.LimbRegion.RIGHT_LEG,
			]
	return false

func get_active_weapon(requires_melee: bool) -> ItemData:
	for slot in [
		GameEnums.EquipmentSlot.HAND,
		GameEnums.EquipmentSlot.OFFHAND,
	]:
		var item: ItemData = paper_doll.get(slot)
		if item == null or item.item_type != GameEnums.ItemType.WEAPON:
			continue
		if not item.has_active_function():
			continue
		if requires_melee and item.is_melee():
			return item
		if not requires_melee and item.is_ranged():
			return item
	return null

func get_all_items() -> Array[ItemData]:
	return ledger.all_items(backpack_array, paper_doll)

func find_item_by_instance_id(instance_id: String) -> ItemData:
	return ledger.find_item_by_instance_id(
		backpack_array,
		paper_doll,
		instance_id
	)

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
			equipped.equipped_slot = GameEnums.EquipmentSlot.NONE
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
		equipped.equipped_slot = GameEnums.EquipmentSlot.NONE
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
	return runtime_codec.capture(
		paper_doll,
		backpack_array,
		item_container_slots
	)

func restore_runtime_state(state) -> void:
	if not runtime_codec.restore(
		state,
		paper_doll,
		backpack_array,
		item_container_slots
	):
		return
	base_max_capacity = 0
	_recalculate_bounds()

func _ensure_runtime_item(item: ItemData) -> ItemData:
	if item.is_runtime_instance():
		return item
	return item.create_runtime_instance()

func set_equipment_validator(validator: Callable) -> void:
	equipment_validator = validator
