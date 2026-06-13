extends SceneTree

var inventory_ui: InventoryUI

var actions_recorded: Array = []

func _init() -> void:
	print("--- BEGINNING INVENTORY UI VERIFICATION ---")
	
	# Step 1: Setup
	inventory_ui = preload("res://UI/Inventory/InventoryUI.tscn").instantiate()
	root.add_child(inventory_ui)
	
	if not inventory_ui.is_node_ready():
		inventory_ui._ready()
		
	inventory_ui.inventory_action_requested.connect(_on_action_requested)
	
	print("[OK] Step 1: Added InventoryUI node to test scene.")
	
	# Step 2: Push Snapshot
	var mock_snapshot = {
		"current_capacity": 5,
		"maximum_capacity": 24,
		"equipment": [
			{
				"instance_id": "item_helm_01",
				"equipment_slot": GameEnums.EquipmentSlot.HEAD,
				"sprite_path": "res://Asset/UI/head.png",
				"paperdoll_texture_path": "res://Asset/Innawoods_Asset/Equipments/Head/boonie_equip.png",
				"name": "Test Helmet"
			}
		],
		"capacity_breakdown": [
			{ "name": "Backpack", "capacity": 12 },
			{ "name": "Pockets", "capacity": 4 }
		],
		"backpack": [
			{
				"instance_id": "item_medkit_01",
				"sprite_path": "res://Asset/UI/backpack.png",
				"name": "First Aid Kit"
			}
		],
		"ground": [
			{
				"instance_id": "item_junk_01",
				"name": "Rusty Can",
				"size_cost": 1
			}
		]
	}
	
	inventory_ui.open_inventory(mock_snapshot)
	
	if inventory_ui.equipment_slots_ui[GameEnums.EquipmentSlot.HEAD].item_descriptor.has("name"):
		print("[OK] Step 2: UI populated equipment from snapshot.")
	else:
		print("[FAIL] Step 2: UI failed to populate equipment.")
		
	if inventory_ui.paperdoll_model.layer_nodes[GameEnums.EquipmentSlot.HEAD].texture != null:
		print("[OK] Step 2b: PaperDollModel correctly loaded assigned texture path.")
	else:
		print("[FAIL] Step 2b: PaperDollModel failed to load texture.")
		
	# Step 3: Test Right-Click Unequip
	var head_slot = inventory_ui.equipment_slots_ui[GameEnums.EquipmentSlot.HEAD]
	var right_click_event = InputEventMouseButton.new()
	right_click_event.button_index = MOUSE_BUTTON_RIGHT
	right_click_event.pressed = true
	
	head_slot._on_gui_input(right_click_event)
	
	if actions_recorded.size() > 0 and actions_recorded.back()["action"] == "unequip":
		print("[OK] Step 3: Right-click emitted UNEQUIP action.")
	else:
		print("[FAIL] Step 3: Right-click failed to emit UNEQUIP action.")
		
	# Step 4: Test Take from Ground
	var ground_container = inventory_ui.ground_list
	if ground_container.get_child_count() > 0:
		var row = ground_container.get_child(0)
		var btn = null
		for child in row.get_children():
			if child is Button:
				btn = child
				break
		if btn:
			btn.pressed.emit()
			if actions_recorded.back()["action"] == "take":
				print("[OK] Step 4: Ground TAKE button emitted action.")
			else:
				print("[FAIL] Step 4: TAKE button failed.")
		else:
			print("[FAIL] Step 4: No TAKE button found.")
	else:
		print("[FAIL] Step 4: Ground list was empty.")
		
	print("--- VERIFICATION COMPLETE ---")
	quit()

func _on_action_requested(action_id: String, instance_id: String, equipment_slot: int) -> void:
	actions_recorded.append({
		"action": action_id,
		"instance": instance_id,
		"slot": equipment_slot
	})
