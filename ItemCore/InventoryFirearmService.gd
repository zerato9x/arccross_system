extends RefCounted
class_name InventoryFirearmService

## Owns firearm-specific inventory mutations behind the InventorySystem facade.
## Storage ownership stays with the facade; signal and capacity policy arrive as
## callbacks so this service remains independent of scene/UI code.

var backpack_array: Array[ItemData]
var item_container_slots: Dictionary
var combat_accessibility_callback: Callable
var container_slot_callback: Callable
var add_to_backpack_callback: Callable
var recalculate_callback: Callable
var error_callback: Callable
var spilled_callback: Callable
var transfer_callback: Callable


func configure(
	backpack: Array[ItemData],
	container_slots: Dictionary,
	callbacks: Dictionary
) -> void:
	backpack_array = backpack
	item_container_slots = container_slots
	combat_accessibility_callback = _callback(callbacks, "combat_accessible")
	container_slot_callback = _callback(callbacks, "container_slot")
	add_to_backpack_callback = _callback(callbacks, "add_to_backpack")
	recalculate_callback = _callback(callbacks, "recalculate")
	error_callback = _callback(callbacks, "error")
	spilled_callback = _callback(callbacks, "spilled")
	transfer_callback = _callback(callbacks, "transfer")


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
		if combat_only and not _is_combat_accessible(item):
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
	_recalculate()
	return consumed


func load_magazine(magazine: ItemData) -> int:
	if magazine == null or not backpack_array.has(magazine):
		_error("The magazine must be in carried storage.")
		return 0
	if not magazine.is_magazine():
		_error("That item cannot be fitted with rounds.")
		return 0
	var needed := magazine.magazine_capacity - magazine.loaded_rounds
	if needed <= 0:
		_error("That magazine is already full.")
		return 0
	var loaded := consume_ammunition(
		magazine.accepted_ammunition_id,
		needed,
		false
	)
	magazine.loaded_rounds += loaded
	if loaded == 0:
		_error(
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
	_recalculate()
	return magazine


func swap_fitted_magazine(weapon: ItemData, incoming: ItemData) -> Dictionary:
	if (
		weapon == null
		or incoming == null
		or not backpack_array.has(incoming)
		or incoming.id != weapon.magazine_id
		or not incoming.is_magazine()
		or incoming.loaded_rounds <= 0
	):
		return {}
	var source_slot := _container_slot(incoming)
	var ejected: ItemData = null
	if not weapon.fitted_magazine_state.is_empty():
		ejected = ItemData.from_runtime_state(weapon.fitted_magazine_state)
	elif weapon.current_magazine > 0:
		# Legacy-authored starting weapons acquire a stable magazine identity at
		# the first physical swap, using the incoming magazine definition.
		ejected = incoming.duplicate(true) as ItemData
		ejected.instance_id = "item_" + str(ResourceUID.create_id())
		ejected.loaded_rounds = weapon.current_magazine
		ejected.current_magazine = 0
	backpack_array.erase(incoming)
	item_container_slots.erase(incoming.instance_id)
	incoming.physical_location = "fitted_magazine"
	incoming.container_instance_id = weapon.instance_id
	weapon.fitted_magazine_instance_id = incoming.instance_id
	weapon.fitted_magazine_state = incoming.to_runtime_state()
	weapon.current_magazine = mini(weapon.max_magazine, incoming.loaded_rounds)
	var ejected_location := "none"
	if ejected != null:
		if _add_to_backpack(ejected, source_slot):
			ejected_location = "container"
		else:
			ejected.physical_location = "ground"
			ejected.container_instance_id = ""
			_emit_spilled(ejected)
			ejected_location = "ground"
	var receipt := {
		"type": "reload",
		"weapon_instance_id": weapon.instance_id,
		"inserted_instance_id": incoming.instance_id,
		"ejected_instance_id": ejected.instance_id if ejected != null else "",
		"ejected_location": ejected_location,
	}
	_recalculate()
	_emit_transfer(receipt)
	return receipt


func use_reload_aid(weapon: ItemData, aid: ItemData) -> Dictionary:
	if (
		weapon == null
		or aid == null
		or not backpack_array.has(aid)
		or aid.id != weapon.reload_aid_id
		or not aid.is_magazine()
		or aid.loaded_rounds <= 0
		or not _is_combat_accessible(aid)
	):
		return {}
	var rounds_needed := maxi(0, weapon.max_magazine - weapon.current_magazine)
	if rounds_needed <= 0:
		return {}
	var transferred := mini(rounds_needed, aid.loaded_rounds)
	weapon.current_magazine += transferred
	aid.loaded_rounds -= transferred
	var receipt := {
		"type": "reload_aid",
		"weapon_instance_id": weapon.instance_id,
		"aid_instance_id": aid.instance_id,
		"rounds_transferred": transferred,
		"rounds_remaining": aid.loaded_rounds,
	}
	_emit_transfer(receipt)
	return receipt


func fit_attachment(weapon: ItemData, attachment: ItemData) -> Dictionary:
	if (
		weapon == null
		or attachment == null
		or not backpack_array.has(attachment)
		or attachment.item_type != GameEnums.ItemType.ATTACHMENT
		or (
			not attachment.compatible_weapon_ids.is_empty()
			and weapon.id not in attachment.compatible_weapon_ids
		)
	):
		return {}
	backpack_array.erase(attachment)
	item_container_slots.erase(attachment.instance_id)
	attachment.physical_location = "fitted_attachment"
	attachment.container_instance_id = weapon.instance_id
	weapon.fitted_attachment_instance_ids.append(attachment.instance_id)
	weapon.fitted_attachment_states.append(attachment.to_runtime_state())
	var receipt := {
		"type": "fit_attachment",
		"weapon_instance_id": weapon.instance_id,
		"attachment_instance_id": attachment.instance_id,
	}
	_recalculate()
	_emit_transfer(receipt)
	return receipt


func detach_attachment(weapon: ItemData, attachment_instance_id: String) -> Dictionary:
	if weapon == null or attachment_instance_id not in weapon.fitted_attachment_instance_ids:
		return {}
	var attachment: ItemData = null
	for state in weapon.fitted_attachment_states.duplicate(true):
		if str(state.get("instance_id", "")) == attachment_instance_id:
			attachment = ItemData.from_runtime_state(state)
			weapon.fitted_attachment_states.erase(state)
			break
	if attachment == null or not _add_to_backpack(attachment):
		return {}
	weapon.fitted_attachment_instance_ids.erase(attachment_instance_id)
	var receipt := {
		"type": "detach_attachment",
		"weapon_instance_id": weapon.instance_id,
		"attachment_instance_id": attachment_instance_id,
	}
	_emit_transfer(receipt)
	return receipt


func find_filled_magazine(magazine_id: String) -> ItemData:
	for item in backpack_array:
		if (
			item.id == magazine_id
			and item.is_magazine()
			and item.loaded_rounds > 0
			and _is_combat_accessible(item)
		):
			return item
	return null


func _is_combat_accessible(item: ItemData) -> bool:
	if not combat_accessibility_callback.is_valid():
		return false
	return bool(combat_accessibility_callback.call(item))


func _container_slot(item: ItemData) -> GameEnums.EquipmentSlot:
	if not container_slot_callback.is_valid():
		return GameEnums.EquipmentSlot.NONE
	return int(container_slot_callback.call(item))


func _add_to_backpack(
	item: ItemData,
	preferred_container: GameEnums.EquipmentSlot = GameEnums.EquipmentSlot.NONE
) -> bool:
	if not add_to_backpack_callback.is_valid():
		return false
	return bool(add_to_backpack_callback.call(item, preferred_container))


func _recalculate() -> void:
	if recalculate_callback.is_valid():
		recalculate_callback.call()


func _error(message: String) -> void:
	if error_callback.is_valid():
		error_callback.call(message)


func _emit_spilled(item: ItemData) -> void:
	if spilled_callback.is_valid():
		spilled_callback.call(item)


func _emit_transfer(receipt: Dictionary) -> void:
	if transfer_callback.is_valid():
		transfer_callback.call(receipt)


func _callback(callbacks: Dictionary, key: String) -> Callable:
	var value: Variant = callbacks.get(key, Callable())
	if value is Callable:
		return value
	return Callable()
