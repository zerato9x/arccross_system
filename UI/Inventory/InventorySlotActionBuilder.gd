extends RefCounted
class_name InventorySlotActionBuilder

const KIND_INVENTORY := "inventory"
const KIND_EXAMINE := "examine"
const KIND_EXPLORATION_ASSIGN := "exploration_assign"
const KIND_EXPLORATION_CLEAR := "exploration_clear"

const SLOT_SHORT_LABELS := {
	GameEnums.EquipmentSlot.INNER_TORSO: "INNER",
	GameEnums.EquipmentSlot.OUTER_TORSO: "ARMOR",
	GameEnums.EquipmentSlot.HAND: "HAND",
	GameEnums.EquipmentSlot.LEGS: "LEGS",
	GameEnums.EquipmentSlot.FEET: "FEET",
	GameEnums.EquipmentSlot.BACKPACK: "PACK",
	GameEnums.EquipmentSlot.SLING: "SLING",
	GameEnums.EquipmentSlot.BELT: "BELT",
	GameEnums.EquipmentSlot.VEST: "RIG",
	GameEnums.EquipmentSlot.HEAD: "HEAD",
	GameEnums.EquipmentSlot.EYES: "EYES",
	GameEnums.EquipmentSlot.FACE: "FACE",
	GameEnums.EquipmentSlot.NECK: "NECK",
	GameEnums.EquipmentSlot.ARMS: "ARMS",
	GameEnums.EquipmentSlot.OFFHAND: "OFFHAND",
}


static func build_for_inventory_slot(slot: InventorySlot) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if slot == null or not slot.has_item():
		return actions

	var descriptor: Dictionary = slot.item_descriptor
	actions.append(_examine_entry())

	match slot.source_kind:
		InventorySlot.SOURCE_EQUIPMENT:
			actions.append(_inventory_entry(
				GameEnums.MACRO_INV_UNEQUIP,
				"Unequip",
				slot.equipment_slot
			))
			actions.append(_inventory_entry(
				GameEnums.MACRO_INV_DROP,
				"Drop to Ground"
			))
		InventorySlot.SOURCE_GROUND:
			if descriptor.get("can_pick_up", true):
				actions.append(_inventory_entry(
					GameEnums.MACRO_INV_TAKE,
					"Take"
				))
			else:
				actions.append(_inventory_entry(
					GameEnums.MACRO_INV_INTERACT,
					"Interact"
				))
		InventorySlot.SOURCE_BACKPACK:
			_append_backpack_actions(actions, descriptor, slot.container_slot)
	return actions


static func build_for_exploration_gear(
	slot: InventorySlot,
	drop_targets: Array
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if slot == null or not slot.has_item():
		return actions

	var descriptor: Dictionary = slot.item_descriptor
	actions.append(_examine_entry())

	var assign_actions: Array[Dictionary] = []
	for drop in drop_targets:
		if not drop is InteractionDropTarget:
			continue
		var target: InteractionDropTarget = drop
		if not target.accepts_descriptor(descriptor):
			continue
		var occupied := not target.get_assigned_instance().is_empty()
		var same_item := (
			occupied
			and target.get_assigned_instance() == str(descriptor.get("instance_id", ""))
		)
		if same_item:
			continue
		assign_actions.append({
			"kind": KIND_EXPLORATION_ASSIGN,
			"label": (
				"Replace %s" % target.get_slot_label().to_upper()
				if occupied
				else "Assign to %s" % target.get_slot_label().to_upper()
			),
			"enabled": true,
			"target_id": target.target_id,
			"drop_target": target,
		})

	if assign_actions.is_empty():
		assign_actions.append({
			"kind": KIND_EXPLORATION_ASSIGN,
			"label": "Assign to Slot",
			"enabled": false,
			"target_id": "",
		})
	actions.append_array(assign_actions)
	return actions


static func build_for_exploration_ground(slot: InventorySlot) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if slot == null or not slot.has_item():
		return actions

	var descriptor: Dictionary = slot.item_descriptor
	actions.append(_examine_entry())
	if descriptor.get("can_pick_up", true):
		actions.append(_inventory_entry(GameEnums.MACRO_INV_TAKE, "Take"))
	else:
		actions.append(_inventory_entry(GameEnums.MACRO_INV_INTERACT, "Interact"))
	return actions


static func build_for_drop_target(drop: InteractionDropTarget) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if drop == null or drop.get_assigned_instance().is_empty():
		return actions

	actions.append({
		"kind": KIND_EXAMINE,
		"label": "Inspect Assignment",
		"enabled": true,
	})
	actions.append({
		"kind": KIND_EXPLORATION_CLEAR,
		"label": "Remove from Slot",
		"enabled": true,
		"target_id": drop.target_id,
		"drop_target": drop,
	})
	return actions


static func menu_header_for_slot(slot: InventorySlot) -> String:
	if slot == null or not slot.has_item():
		return ""
	return str(slot.item_descriptor.get("name", "Item")).to_upper()


static func menu_header_for_drop_target(drop: InteractionDropTarget) -> String:
	if drop == null:
		return ""
	if drop.get_assigned_instance().is_empty():
		return drop.target_id.to_upper()
	return str(drop.get_assignment_payload().get("name", drop.target_id)).to_upper()


static func _append_backpack_actions(
	actions: Array[Dictionary],
	descriptor: Dictionary,
	container_slot: int
) -> void:
	if descriptor.get("can_inspect_knowledge", false):
		actions.append(_inventory_entry(
			GameEnums.MACRO_INV_INSPECT,
			"Decode Evidence",
			container_slot
		))
	if descriptor.get("can_load_magazine", false):
		actions.append(_inventory_entry(
			GameEnums.MACRO_INV_LOAD_MAGAZINE,
			"Load Rounds",
			container_slot
		))
	if descriptor.get("can_equip", false):
		var allowed_slots: Array = descriptor.get("allowed_equipment_slots", [])
		if allowed_slots.is_empty():
			actions.append(_inventory_entry(
				GameEnums.MACRO_INV_EQUIP,
				"Equip",
				int(descriptor.get(
					"preferred_equipment_slot",
					GameEnums.EquipmentSlot.NONE
				))
			))
		else:
			for slot_enum in allowed_slots:
				var label := "Equip to %s" % _slot_short_label(int(slot_enum))
				actions.append(_inventory_entry(
					GameEnums.MACRO_INV_EQUIP,
					label,
					int(slot_enum)
				))
	if descriptor.get("can_consume", false):
		actions.append(_inventory_entry(
			GameEnums.MACRO_INV_CONSUME,
			"Use"
		))
	actions.append(_inventory_entry(
		GameEnums.MACRO_INV_DROP,
		"Drop to Ground"
	))


static func _inventory_entry(
	action_id: String,
	label: String,
	equipment_slot: int = GameEnums.EquipmentSlot.NONE
) -> Dictionary:
	return {
		"kind": KIND_INVENTORY,
		"action_id": action_id,
		"label": label,
		"equipment_slot": equipment_slot,
		"enabled": true,
	}


static func _examine_entry() -> Dictionary:
	return {
		"kind": KIND_EXAMINE,
		"label": "Examine",
		"enabled": true,
	}


static func _slot_short_label(slot: int) -> String:
	if SLOT_SHORT_LABELS.has(slot):
		return SLOT_SHORT_LABELS[slot]
	for key in GameEnums.EquipmentSlot:
		if int(GameEnums.EquipmentSlot[key]) == slot:
			return str(key).replace("_", " ")
	return "SLOT"
