extends RefCounted
class_name InventorySlotRenderer

const SLOT_SCENE := preload("res://UI/Inventory/InventorySlot.tscn")


func create(
	parent: Control,
	source_kind: String,
	index: int,
	label: String,
	container_slot: GameEnums.EquipmentSlot,
	text_only: bool,
	bind_slot: Callable
) -> InventorySlot:
	var slot := SLOT_SCENE.instantiate() as InventorySlot
	parent.add_child(slot)
	slot.configure(source_kind, index, label, null, container_slot)
	slot.set_text_only_mode(text_only)
	if bind_slot.is_valid():
		bind_slot.call(slot)
	return slot
