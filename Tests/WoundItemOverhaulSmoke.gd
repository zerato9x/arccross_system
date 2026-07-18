extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var body := HumanoidBody.new()
	root.add_child(body)
	await process_frame

	var arm := GameEnums.LimbRegion.LEFT_ARM
	body.apply_targeted_hit(arm, 4.0, 8.0, GameEnums.DamageType.SHARP)
	var arm_wounds := body.get_wounds_for_limb(arm)
	if arm_wounds.size() != 1 or (arm_wounds[0] as Wound).wound_type != GameEnums.WoundType.LACERATION:
		_fail("Sharp damage did not create a persistent laceration.")
		return
	var bleeding_before := body.get_total_bleeding_rate()
	if bleeding_before <= 0.0:
		_fail("Laceration did not produce a bleeding rate.")
		return
	var blood_before := body.blood_level
	var bleed_result := body.process_combat_bleeding_tick()
	if bleed_result.is_empty() or body.blood_level >= blood_before:
		_fail("Active wounds did not drive combat blood loss.")
		return
	if not body.treat_worst_bleed(arm, 3.0):
		_fail("Treatment could not target the worst limb bleed.")
		return
	if body.get_total_bleeding_rate() >= bleeding_before:
		_fail("Treatment potency did not reduce bleeding.")
		return

	var leg := GameEnums.LimbRegion.LEFT_LEG
	body.apply_targeted_hit(leg, 8.0, 0.0, GameEnums.DamageType.BLUNT)
	var leg_wounds := body.get_wounds_for_limb(leg)
	if leg_wounds.is_empty() or (leg_wounds[0] as Wound).wound_type != GameEnums.WoundType.FRACTURE:
		_fail("Severe blunt damage did not create a fracture.")
		return
	if (leg_wounds[0] as Wound).active_bleeding_rate() > 0.0:
		_fail("Closed blunt fracture incorrectly caused external bleeding.")
		return

	var restored := BodyState.from_dict(body.capture_runtime_state().to_dict())
	if restored.wounds_by_limb.get(arm, []).is_empty():
		_fail("Wounds were lost during body save/load serialization.")
		return

	var inventory := InventorySystem.new()
	root.add_child(inventory)
	await process_frame
	var coat := ItemData.new()
	coat.item_type = GameEnums.ItemType.ARMOR
	coat.protection_sharp = 4.0
	inventory.paper_doll[GameEnums.EquipmentSlot.OUTER_TORSO] = coat
	if inventory.get_protection_for(GameEnums.DamageType.SHARP, GameEnums.LimbRegion.UPPER_TORSO) != 4.0:
		_fail("Torso armor did not protect the torso.")
		return
	if inventory.get_protection_for(GameEnums.DamageType.SHARP, GameEnums.LimbRegion.HEAD) != 0.0:
		_fail("Torso armor still projected global protection onto the head.")
		return

	var card_scene := load("res://UI/Inventory/InventorySlotExamineCard.tscn") as PackedScene
	var card := card_scene.instantiate() as InventorySlotExamineCard
	root.add_child(card)
	await process_frame
	card.show_descriptor({
		"name": "Test Coat",
		"weight": 2.0,
		"bulk": 2.0,
		"threat": 1.0,
		"protection_blunt": 2.0,
		"protection_sharp": 4.0,
		"protection_ballistic": 1.0,
	})
	var stats := card.get_node("%StatsLabel") as Label
	if stats == null or "THREAT 1.0" not in stats.text or "SHARP 4.0" not in stats.text:
		_fail("Examine card still hid core item stats.")
		return

	print("[TEST PASS] Wound and item overhaul.")
	quit(0)


func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
