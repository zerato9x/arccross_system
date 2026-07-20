extends SceneTree

## Headless check for inventory character strip + inspector hover restore.

const SNAPSHOT_BUILDER := preload("res://WorldCore/MacroSnapshotBuilder.gd")

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var player_definition := load("res://BiologicalCore/player_def.tres") as EntityDefinition
	if player_definition == null:
		_fail("player_def.tres missing.")
		return
	if player_definition.occupation_id != "scavenger":
		_fail("player_def occupation seed missing.")
		return

	var core := EntityFactory.record_to_humanoid_core(
		{
			"entity_id": "inventory_hud_probe",
			"definition": player_definition.to_state(),
			"runtime": {},
		},
		root,
		"InventoryHudProbe"
	)
	await process_frame

	var character: Dictionary = SNAPSHOT_BUILDER.build_character_snapshot(core)
	if str(character.get("archetype_name", "")) != player_definition.archetype_name:
		_fail("Character snapshot missing archetype.")
		return
	if int(character.get("brawn", 0)) != player_definition.brawn:
		_fail("Character snapshot missing pillars.")
		return
	var occupation: Dictionary = character.get("occupation", {})
	if str(occupation.get("id", "")) != "scavenger":
		_fail("Character snapshot missing occupation.")
		return
	var traits: Array = character.get("traits", [])
	if traits.is_empty() or str(traits[0].get("id", "")) != "field_sense":
		_fail("Character snapshot missing trait.")
		return

	var ui_scene := load("res://UI/Inventory/InventoryUI.tscn") as PackedScene
	if ui_scene == null:
		_fail("InventoryUI scene missing.")
		return
	var ui := ui_scene.instantiate() as InventoryUI
	root.add_child(ui)
	await process_frame

	if ui.get_node_or_null("%CharacterStrip") == null:
		_fail("CharacterStrip missing from InventoryUI.")
		return
	if ui.get_node_or_null("%StatGaugeList") == null:
		_fail("StatGaugeList missing from InventoryUI.")
		return
	if ui.get_node_or_null("%EffectChipRow") == null:
		_fail("EffectChipRow missing from InventoryUI.")
		return

	var descriptor := {
		"name": "Test Revolver",
		"description": "Probe weapon.",
		"item_grade": GameEnums.ItemGrade.CIVILIAN,
		"catalog_category": GameEnums.ItemCategory.FIREARM,
		"preferred_equipment_slot": GameEnums.EquipmentSlot.OFFHAND,
		"condition_enabled": true,
		"current_condition": 12.0,
		"condition_band": "Fine",
		"weight": 1.2,
		"bulk": 0.7,
		"threat": 6.0,
		"item_type": GameEnums.ItemType.WEAPON,
		"flesh_damage": 7.0,
		"stance_damage": 0.0,
		"armor_penetration": 6.0,
		"accuracy_rating": 6.0,
		"optimal_range": 4,
		"effective_range": 6,
		"max_magazine": 6,
		"current_magazine": 6,
		"search_loot_bonus": 1.0,
	}
	ui.show_item_details(descriptor)
	await process_frame
	var gauges := ui.get_node("%StatGaugeList") as VBoxContainer
	if gauges == null or gauges.get_child_count() < 5:
		_fail("Inspector did not populate stat gauges.")
		return
	var chips := ui.get_node("%EffectChipRow") as HFlowContainer
	if chips == null or chips.get_child_count() < 1:
		_fail("Inspector did not populate effect chips.")
		return

	ui.hide_item_details()
	await process_frame
	if gauges.get_child_count() != 0:
		_fail("Inspector did not clear gauges on hide with no selection.")
		return

	print("[TEST PASS] Inventory character and visual inspector.")
	quit(0)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
