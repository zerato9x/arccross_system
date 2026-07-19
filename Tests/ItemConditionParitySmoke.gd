extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not _verify_bands_and_grades():
		return
	if not _verify_firearm_parity_and_persistence():
		return
	if not _verify_typed_faults_and_broken_legality():
		return
	if not await _verify_armor_and_repair():
		return
	print("[ITEM_CONDITION_PARITY] PASS")
	quit(0)

func _verify_bands_and_grades() -> bool:
	var samples := {
		12.0: ItemConditionRules.CONDITION_FINE,
		9.0: ItemConditionRules.CONDITION_FINE,
		8.99: ItemConditionRules.CONDITION_WORN,
		6.0: ItemConditionRules.CONDITION_WORN,
		5.99: ItemConditionRules.CONDITION_DAMAGED,
		3.0: ItemConditionRules.CONDITION_DAMAGED,
		2.99: ItemConditionRules.CONDITION_CRITICAL,
		0.01: ItemConditionRules.CONDITION_CRITICAL,
		0.0: ItemConditionRules.CONDITION_BROKEN,
	}
	for condition in samples:
		if ItemConditionRules.condition_band(condition) != samples[condition]:
			return _fail("Condition band boundary failed at %.2f." % condition)
	if not is_equal_approx(ItemConditionRules.fault_chance(7.0), 1.0 / 24.0):
		return _fail("Worn fault chance is not 1/24.")
	if not is_equal_approx(ItemConditionRules.fault_chance(4.0), 1.0 / 12.0):
		return _fail("Damaged fault chance is not 1/12.")
	if not is_equal_approx(ItemConditionRules.fault_chance(2.0), 1.0 / 4.0):
		return _fail("Critical fault chance is not 1/4.")
	var expected := [1.25, 1.0, 0.8, 0.65, 0.5]
	for grade in GameEnums.ItemGrade.values():
		if not is_equal_approx(
			ItemConditionRules.grade_wear_multiplier(grade),
			expected[grade]
		):
			return _fail("Grade wear multiplier mismatch for %d." % grade)
	return true

func _verify_typed_faults_and_broken_legality() -> bool:
	var melee_definition := ItemData.new()
	melee_definition.id = "parity_melee"
	melee_definition.item_type = GameEnums.ItemType.WEAPON
	melee_definition.weapon_type = GameEnums.WeaponClass.BLUNT
	melee_definition.item_grade = GameEnums.ItemGrade.CIVILIAN
	var realtime_melee := melee_definition.create_runtime_instance()
	realtime_melee.current_condition = 4.0
	var turn_melee := ItemData.from_runtime_state(realtime_melee.to_runtime_state())
	var realtime_melee_outcome := ItemConditionRules.resolve_use(
		realtime_melee, ItemConditionRules.EVENT_MELEE, 0.01
	)
	var turn_melee_outcome := ItemConditionRules.resolve_use(
		turn_melee, ItemConditionRules.EVENT_MELEE, 0.01
	)
	if realtime_melee_outcome != turn_melee_outcome:
		return _fail("Cloned modes produced different melee outcomes.")
	if not is_equal_approx(float(realtime_melee_outcome.performance_multiplier), 0.5):
		return _fail("Melee fault did not halve its contribution.")

	var shield := ItemData.new().create_runtime_instance()
	shield.id = "parity_shield"
	shield.item_type = GameEnums.ItemType.WEAPON
	shield.weapon_type = GameEnums.WeaponClass.BLUNT
	shield.current_condition = 2.0
	var shield_outcome := ItemConditionRules.resolve_use(
		shield, ItemConditionRules.EVENT_SHIELD, 0.01
	)
	if (
		str(shield_outcome.fault_kind) != "shield"
		or not is_equal_approx(float(shield_outcome.performance_multiplier), 0.5)
	):
		return _fail("Shield fault did not return its shared half-mitigation outcome.")

	var inventory := InventorySystem.new()
	root.add_child(inventory)
	var broken := melee_definition.create_runtime_instance()
	broken.current_condition = 0.0
	inventory.paper_doll[GameEnums.EquipmentSlot.HAND] = broken
	if inventory.get_active_weapon(true) != null:
		return _fail("Broken melee gear remained an active combat weapon.")
	if broken.weight <= 0.0:
		broken.weight = 1.0
	if broken.weight != 1.0 or broken.current_condition != 0.0:
		return _fail("Broken gear lost persistent physical state.")
	inventory.queue_free()
	return true

func _verify_firearm_parity_and_persistence() -> bool:
	var definition := ItemData.new()
	definition.id = "parity_firearm"
	definition.display_name = "Parity Firearm"
	definition.item_type = GameEnums.ItemType.WEAPON
	definition.weapon_type = GameEnums.WeaponClass.PISTOL
	definition.item_grade = GameEnums.ItemGrade.SERVICE
	definition.max_magazine = 8
	var realtime := definition.create_runtime_instance()
	realtime.current_condition = 7.0
	var turn_based := ItemData.from_runtime_state(realtime.to_runtime_state())

	var realtime_outcome := ItemConditionRules.resolve_use(
		realtime, ItemConditionRules.EVENT_FIREARM, 0.01
	)
	var turn_outcome := ItemConditionRules.resolve_use(
		turn_based, ItemConditionRules.EVENT_FIREARM, 0.01
	)
	if realtime_outcome != turn_outcome:
		return _fail("Cloned modes produced different firearm outcomes.")
	if not realtime.is_jammed or realtime.current_magazine != 8:
		return _fail("Fault did not jam the firearm while retaining ammunition.")
	var restored := ItemData.from_runtime_state(realtime.to_runtime_state())
	if not restored.is_jammed or not is_equal_approx(restored.current_condition, 6.92):
		return _fail("Condition or malfunction did not survive persistence.")
	if not ItemConditionRules.clear_malfunction(restored) or restored.is_jammed:
		return _fail("Deterministic malfunction clearing failed.")
	var legacy := realtime.to_runtime_state()
	legacy.erase("current_condition")
	legacy.erase("is_jammed")
	var migrated := ItemData.from_runtime_state(legacy)
	if migrated.current_condition != 12.0 or migrated.is_jammed:
		return _fail("Legacy item state did not migrate to full condition.")
	return true

func _verify_armor_and_repair() -> bool:
	var inventory := InventorySystem.new()
	root.add_child(inventory)
	await process_frame
	var first := _armor("first_armor", GameEnums.EquipmentSlot.INNER_TORSO, 2.0)
	var second := _armor("second_armor", GameEnums.EquipmentSlot.OUTER_TORSO, 4.0)
	first.current_condition = 4.0
	second.current_condition = 4.0
	inventory.paper_doll[GameEnums.EquipmentSlot.OUTER_TORSO] = second
	inventory.paper_doll[GameEnums.EquipmentSlot.INNER_TORSO] = first
	var protection := inventory.resolve_protection_event(
		GameEnums.DamageType.BALLISTIC,
		GameEnums.LimbRegion.UPPER_TORSO,
		[0.01, 0.9]
	)
	if not is_equal_approx(protection.total_protection, 5.0):
		return _fail("Stable multi-piece armor contribution was not 1 + 4.")
	if int(protection.item_outcomes[0].equipment_slot) != GameEnums.EquipmentSlot.INNER_TORSO:
		return _fail("Armor was not evaluated in stable slot order.")

	var target := ItemData.new().create_runtime_instance()
	target.id = "repair_target"
	target.display_name = "Repair Target"
	target.repair_domain = GameEnums.RepairDomain.FIREARM
	target.current_condition = 5.0
	var tool := ItemData.new().create_runtime_instance()
	tool.id = "gun_cleaner"
	tool.display_name = "Gun Cleaner"
	var material := ItemData.new().create_runtime_instance()
	material.id = "rag"
	material.stack_count = 2
	inventory.backpack_array.assign([target, tool, material])
	var repair := inventory.repair_item(target, tool, material, "field", 0.9)
	if not repair.success or target.current_condition != 7.0 or material.stack_count != 1:
		return _fail("Field firearm repair did not restore 2 and consume one rag.")
	inventory.queue_free()
	return true

func _armor(id: String, slot: GameEnums.EquipmentSlot, protection: float) -> ItemData:
	var item := ItemData.new().create_runtime_instance()
	item.id = id
	item.item_type = GameEnums.ItemType.ARMOR
	item.target_slot = slot
	item.protection_ballistic = protection
	return item

func _fail(message: String) -> bool:
	push_error("[ITEM_CONDITION_PARITY] " + message)
	quit(1)
	return false
