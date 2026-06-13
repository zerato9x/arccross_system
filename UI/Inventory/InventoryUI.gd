extends Control
class_name InventoryUI

signal inventory_action_requested(
	action_id: String,
	instance_id: String,
	equipment_slot: int
)
signal inventory_closed

const ACTION_TAKE := "take"
const ACTION_DROP := "drop"
const ACTION_EQUIP := "equip"
const ACTION_UNEQUIP := "unequip"
const ACTION_CONSUME := "consume"

var InventorySlotClass = preload("res://UI/Inventory/InventorySlot.tscn")

# UI Components from Scene
@onready var equipment_container = %EquipmentSlots
@onready var dynamic_capacity_grids = %DynamicCapacityGrids
@onready var stats_label = %StatsLabel
@onready var spill_warning = %SpillWarningLabel
@onready var ground_list = %GroundList
@onready var close_button = %CloseButton
@onready var paperdoll_model = %PaperDollModel

var equipment_slots_ui: Dictionary = {}
var _snapshot: Dictionary = {}
var _feedback: String = ""

func _ready() -> void:
	# Register Equipment Slots natively constructed in Editor
	for child in equipment_container.get_children():
		if child is InventorySlot:
			equipment_slots_ui[child.equipment_slot] = child
			child.item_dropped.connect(_on_item_dropped)
			child.slot_clicked.connect(_on_slot_clicked)

	if close_button:
		close_button.pressed.connect(func(): close_panel())
	
	close_panel(false)

func open_inventory(snapshot: Dictionary, feedback: String = "") -> void:
	_snapshot = snapshot.duplicate(true)
	_feedback = feedback
	visible = true
	_render()

func close_panel(notify: bool = true) -> void:
	visible = false
	_snapshot.clear()
	_feedback = ""
	if notify:
		inventory_closed.emit()

func is_open() -> bool:
	return visible

func _render() -> void:
	# Update Capacity & Weight
	var current = _snapshot.get("current_capacity", 0)
	var maximum = _snapshot.get("maximum_capacity", 0)
	stats_label.text = "Capacity: %d / %d" % [current, maximum]
	
	spill_warning.visible = (current > maximum)
	if not _feedback.is_empty():
		stats_label.text += " | " + _feedback

	# Update Paperdoll Visuals
	if paperdoll_model:
		paperdoll_model.update_model(_snapshot.get("equipment", []))

	# Update Equipment Slots
	var equipment_data: Array = _snapshot.get("equipment", [])
	for slot_ui in equipment_slots_ui.values():
		slot_ui.set_item({}) # clear first

	for descriptor in equipment_data:
		var slot_id = descriptor.get("equipment_slot", GameEnums.EquipmentSlot.NONE)
		if equipment_slots_ui.has(slot_id):
			equipment_slots_ui[slot_id].set_item(descriptor)

	# Build Dynamic Capacity Grids
	for child in dynamic_capacity_grids.get_children():
		child.queue_free()

	var all_dynamic_slots: Array = []
	var breakdown: Array = _snapshot.get("capacity_breakdown", [])
	var bp_tex = load("res://Asset/UI/backpack_item_slot.png")
	
	for section in breakdown:
		var section_name = section.get("name", "Unknown")
		var section_cap = section.get("capacity", 0)
		
		var header = Label.new()
		header.text = section_name.to_upper()
		header.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		header.add_theme_font_size_override("font_size", 18)
		dynamic_capacity_grids.add_child(header)
		
		var grid = GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		dynamic_capacity_grids.add_child(grid)
		
		# Add a separator below the grid for visual spacing
		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		dynamic_capacity_grids.add_child(spacer)
		
		for i in range(section_cap):
			var slot_ui = InventorySlotClass.instantiate()
			slot_ui.equipment_slot = GameEnums.EquipmentSlot.NONE
			slot_ui.empty_texture = bp_tex
			slot_ui.item_dropped.connect(_on_item_dropped)
			slot_ui.slot_clicked.connect(_on_slot_clicked)
			grid.add_child(slot_ui)
			all_dynamic_slots.append(slot_ui)

	# Distribute Backpack Data
	var backpack_data: Array = _snapshot.get("backpack", [])
	for i in range(all_dynamic_slots.size()):
		if i < backpack_data.size():
			all_dynamic_slots[i].set_item(backpack_data[i])
		else:
			all_dynamic_slots[i].set_item({})

	# Update Ground List
	_populate_list(ground_list, _snapshot.get("ground", []), "ground")

func _populate_list(container: Control, items: Array, source: String) -> void:
	for child in container.get_children():
		child.queue_free()
		
	for descriptor in items:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		container.add_child(row)
		
		var label = Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = descriptor.get("name", "Unknown Item") + " [Size " + str(descriptor.get("size_cost", 0)) + "]"
		label.tooltip_text = _get_item_stats_string(descriptor)
		row.add_child(label)
		
		var instance_id: String = descriptor.get("instance_id", "")
		var slot: int = descriptor.get("equipment_slot", GameEnums.EquipmentSlot.NONE)
		
		match source:
			"ground":
				_add_action_button(row, "TAKE", ACTION_TAKE, instance_id, slot)

func _add_action_button(parent: Control, text: String, action_id: String, instance_id: String, equipment_slot: int) -> void:
	var button = Button.new()
	button.text = text
	button.pressed.connect(func(): inventory_action_requested.emit(action_id, instance_id, equipment_slot))
	parent.add_child(button)

func show_item_details(descriptor: Dictionary) -> void:
	pass

func _get_item_stats_string(descriptor: Dictionary) -> String:
	return descriptor.get("description", "") + "\n\n"

# --- Interactions from Paper Doll ---
func _on_slot_clicked(slot_node, event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_LEFT:
		var desc = slot_node.item_descriptor
		if desc.is_empty(): return
			
		var instance_id = desc.get("instance_id", "")
		if slot_node.equipment_slot != GameEnums.EquipmentSlot.NONE:
			inventory_action_requested.emit(ACTION_UNEQUIP, instance_id, slot_node.equipment_slot)

func _on_item_dropped(from_slot, to_slot) -> void:
	var desc = from_slot.item_descriptor
	if desc.is_empty(): return
	if from_slot == to_slot: return
	
	var instance_id = desc.get("instance_id", "")
	
	if from_slot.equipment_slot != GameEnums.EquipmentSlot.NONE and to_slot.equipment_slot == GameEnums.EquipmentSlot.NONE:
		inventory_action_requested.emit(ACTION_UNEQUIP, instance_id, from_slot.equipment_slot)
	elif from_slot.equipment_slot == GameEnums.EquipmentSlot.NONE and to_slot.equipment_slot != GameEnums.EquipmentSlot.NONE:
		inventory_action_requested.emit(ACTION_EQUIP, instance_id, to_slot.equipment_slot)
	elif from_slot.equipment_slot != GameEnums.EquipmentSlot.NONE and to_slot.equipment_slot != GameEnums.EquipmentSlot.NONE:
		inventory_action_requested.emit(ACTION_UNEQUIP, instance_id, from_slot.equipment_slot)
		inventory_action_requested.emit(ACTION_EQUIP, instance_id, to_slot.equipment_slot)
