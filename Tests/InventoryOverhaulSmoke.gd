extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _verify_catalog():
		return
	if not await _verify_authored_inventory_scene():
		return
	if not await _verify_shared_combat_card():
		return
	print("[INVENTORY_OVERHAUL] PASS")
	quit(0)

func _verify_catalog() -> bool:
	var directory := DirAccess.open("res://ItemCore/Items")
	if directory == null:
		return _fail("Could not open item catalog.")
	var files: Array[String] = []
	for path in directory.get_files():
		if str(path).ends_with(".tres"):
			files.append(str(path))
	if files.size() < 168:
		return _fail("Expected at least 168 authored items, found %d." % files.size())
	var grades := {}
	for file_name in files:
		var item := load("res://ItemCore/Items/" + str(file_name)) as ItemData
		if item == null:
			return _fail("Could not load %s." % file_name)
		if item.lore_description.begins_with("Field catalog entry"):
			return _fail("Placeholder field note survived on %s." % item.id)
		grades[item.item_grade] = int(grades.get(item.item_grade, 0)) + 1
		if (
			item.item_grade == GameEnums.ItemGrade.UNIQUE
			and item.item_type in [GameEnums.ItemType.WEAPON, GameEnums.ItemType.ARMOR]
			and item.maintenance_constraint.is_empty()
		):
			return _fail("Unique item %s has no authored maintenance constraint." % item.id)
	if int(grades.get(GameEnums.ItemGrade.UNIQUE, 0)) <= 0:
		return _fail("Catalog contains no authored Unique sources.")
	if int(grades.get(GameEnums.ItemGrade.CARBON, 0)) <= 0:
		return _fail("Catalog contains no Carbon equipment.")
	return true

func _verify_authored_inventory_scene() -> bool:
	var scene := load("res://UI/Inventory/InventoryUI.tscn") as PackedScene
	var ui := scene.instantiate() as InventoryUI
	root.add_child(ui)
	await process_frame
	for unique_name in [
		"PaperDollPanel",
		"ItemsPanel",
		"InspectorPanel",
		"DynamicCapacityGrids",
		"GroundList",
		"ConditionBar",
		"RepairTray",
		"FilterRow",
		"ConfirmDialog",
	]:
		if ui.get_node_or_null("%%%s" % unique_name) == null:
			return _fail("Authored inventory scene is missing %s." % unique_name)
	var filter_row := ui.get_node("%FilterRow") as HFlowContainer
	if filter_row.get_child_count() != 7:
		return _fail("Inventory filter row does not expose all seven filters.")
	var equipment_region := ui.get_node("%EquipmentSlots") as Control
	var authored_slots: Array[Node] = equipment_region.find_children(
		"*", "InventorySlot", true, false
	)
	if authored_slots.size() != 15:
		return _fail(
			"Paper-doll stage must author all 15 equipment slots; found %d."
			% authored_slots.size()
		)
	var slot_ids := {}
	for slot_node: Node in authored_slots:
		var slot := slot_node as InventorySlot
		if slot_ids.has(int(slot.equipment_slot)):
			return _fail("Paper-doll stage repeats equipment slot %d." % slot.equipment_slot)
		slot_ids[int(slot.equipment_slot)] = true
		if slot.get_node_or_null("EquipmentStateOverlay/ConditionRail") == null:
			return _fail("Equipment slot %s has no condition rail." % slot.name)
		if slot.get_node_or_null("EquipmentStateOverlay/StateBadge") == null:
			return _fail("Equipment slot %s has no condition-state badge." % slot.name)
	if ui.get_node_or_null("%PaperDollSummary") == null:
		return _fail("Paper-doll stage has no occupancy/readiness summary.")
	ui.open_inventory({
		"coords": Vector2i.ZERO,
		"current_capacity": 0,
		"maximum_capacity": 0,
		"equipment": [],
		"containers": [],
		"backpack": [],
		"ground": [],
		"limbs": [],
		"loadout_stats": {},
	})
	await process_frame
	if not ui.visible or not (ui.get_node("%InspectorPanel") as Control).visible:
		return _fail("Fullscreen inventory did not retain its persistent inspector.")
	ui.queue_free()
	await process_frame
	return true

func _verify_shared_combat_card() -> bool:
	var card_scene := load("res://UI/Inventory/CombatItemCard.tscn") as PackedScene
	var card := card_scene.instantiate() as CombatItemCard
	root.add_child(card)
	await process_frame
	card.show_descriptor({
		"id": "test_firearm",
		"display_name": "Test Firearm",
		"item_grade": GameEnums.ItemGrade.SERVICE,
		"current_condition": 4.0,
		"condition_band": "Damaged",
		"fault_chance": 1.0 / 12.0,
		"current_magazine": 3,
		"max_magazine": 8,
		"optimal_range_cells": Vector2i(2, 4),
		"maximum_range_cells": 6,
		"readiness": {"ready": false, "reason": "jammed"},
	}, true)
	if card.state_label.text != "JAMMED" or card.grade_label.text != "SERVICE // DAMAGED":
		return _fail("Shared combat item card reinterpreted the descriptor.")
	card.queue_free()
	await process_frame
	return true

func _fail(message: String) -> bool:
	push_error("[INVENTORY_OVERHAUL] " + message)
	quit(1)
	return false
