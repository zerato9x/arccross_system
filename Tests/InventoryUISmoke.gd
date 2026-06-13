extends SceneTree

var inventory_ui: InventoryUI

var actions_recorded: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- BEGINNING INVENTORY UI VERIFICATION ---")
	
	# Step 1: Setup
	inventory_ui = preload("res://UI/Inventory/InventoryUI.tscn").instantiate()
	root.add_child(inventory_ui)
	await process_frame
		
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

	if inventory_ui.backpack_slots_ui.size() == 24:
		print("[OK] Step 2c: Backpack rendered all capacity cells.")
	else:
		print("[FAIL] Step 2c: Backpack capacity cells were not rendered.")
		
	# Step 3: Test equipment-slot Unequip
	var head_slot = inventory_ui.equipment_slots_ui[GameEnums.EquipmentSlot.HEAD]
	inventory_ui._execute_primary(head_slot)
	
	if actions_recorded.size() > 0 and actions_recorded.back()["action"] == "unequip":
		print("[OK] Step 3: Right-click emitted UNEQUIP action.")
	else:
		print("[FAIL] Step 3: Right-click failed to emit UNEQUIP action.")
		
	# Step 4: Test Take from slot-based Ground
	if inventory_ui.ground_slots_ui.size() > 0:
		var ground_slot := inventory_ui.ground_slots_ui[0]
		inventory_ui._execute_primary(ground_slot)
		if actions_recorded.back()["action"] == "take":
			print("[OK] Step 4: Ground slot emitted TAKE action.")
		else:
			print("[FAIL] Step 4: Ground slot TAKE action failed.")
	else:
		print("[FAIL] Step 4: Ground slots were empty.")

	var detail_text := inventory_ui._format_item_stats(
		mock_snapshot["backpack"][0]
	)
	if detail_text.contains("Size"):
		print("[OK] Step 5: Hover HUD formatted item details.")
	else:
		print("[FAIL] Step 5: Hover HUD did not format item details.")
		
	print("--- VERIFICATION COMPLETE ---")
	await process_frame
	quit()

func _on_action_requested(action_id: String, instance_id: String, equipment_slot: int) -> void:
	actions_recorded.append({
		"action": action_id,
		"instance": instance_id,
		"slot": equipment_slot
	})
