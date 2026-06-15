extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var inventory := InventorySystem.new()
	root.add_child(inventory)
	await process_frame

	var water := load("res://ItemCore/Items/water_bottle.tres") as ItemData
	if inventory.base_max_capacity != 0 or inventory.current_max_capacity != 0:
		_fail("A naked inventory still has unexplained base capacity.")
		return
	if inventory.add_to_backpack(water):
		_fail("A naked character carried an item without worn storage.")
		return

	inventory.equip_item(
		load("res://ItemCore/Items/backpack_service_big.tres"),
		GameEnums.EquipmentSlot.BACKPACK
	)
	inventory.equip_item(
		load("res://ItemCore/Items/coat_leather.tres"),
		GameEnums.EquipmentSlot.OUTER_TORSO
	)
	inventory.equip_item(
		load("res://ItemCore/Items/webbing_service.tres"),
		GameEnums.EquipmentSlot.VEST
	)

	var rifle := load("res://ItemCore/Items/service_rifle.tres") as ItemData
	if inventory.add_to_backpack(rifle, GameEnums.EquipmentSlot.OUTER_TORSO):
		_fail("An average rifle fit inside a coat pocket.")
		return
	if not inventory.add_to_backpack(
		rifle,
		GameEnums.EquipmentSlot.BACKPACK
	):
		_fail("An average rifle did not fit inside the backpack.")
		return
	var stored_rifle: ItemData = inventory.backpack_array.back()
	var crowbar := load("res://ItemCore/Items/crowbar.tres") as ItemData
	if not inventory.add_to_backpack(
		crowbar,
		GameEnums.EquipmentSlot.BACKPACK
	):
		_fail("The offhand test weapon did not fit in the backpack.")
		return
	var runtime_crowbar: ItemData = inventory.backpack_array.back()
	if not inventory.equip_item(
		runtime_crowbar,
		GameEnums.EquipmentSlot.OFFHAND
	):
		_fail("A one-handed weapon could not equip in OFFHAND.")
		return
	if inventory.equip_item(
		stored_rifle,
		GameEnums.EquipmentSlot.HAND
	):
		_fail("A two-handed weapon equipped while OFFHAND was occupied.")
		return
	inventory.unequip_item(GameEnums.EquipmentSlot.OFFHAND)
	if stored_rifle == null or not inventory.equip_item(
		stored_rifle,
		GameEnums.EquipmentSlot.HAND
	):
		_fail("The two-handed rifle did not equip after OFFHAND was cleared.")
		return
	if inventory.can_equip_in_slot(
		stored_rifle,
		GameEnums.EquipmentSlot.SLING
	):
		_fail("A weapon still treated SLING as a ready-weapon slot.")
		return

	var rounds := load("res://ItemCore/Items/pistol_round.tres") as ItemData
	for _index in range(25):
		if not inventory.add_to_backpack(
			rounds,
			GameEnums.EquipmentSlot.VEST
		):
			_fail("The four-slot rig could not store two ammunition stacks.")
			return
	var round_stacks := inventory.get_container_items(
		GameEnums.EquipmentSlot.VEST
	)
	if (
		round_stacks.size() != 2
		or round_stacks[0].stack_count != 24
		or round_stacks[1].stack_count != 1
	):
		_fail("Pistol rounds did not stack at 24 per slot.")
		return

	var magazine := (
		load("res://ItemCore/Items/service_pistol_magazine.tres") as ItemData
	).create_runtime_instance()
	if not inventory.add_to_backpack(
		magazine,
		GameEnums.EquipmentSlot.VEST
	):
		_fail("The service magazine did not fit in the rig.")
		return
	if inventory.load_magazine(magazine) != 8 or magazine.loaded_rounds != 8:
		_fail("Fitting rounds did not load the service magazine.")
		return
	if inventory.consume_filled_magazine(magazine.id) != magazine:
		_fail("Reload consumption did not spend the fitted magazine.")
		return

	var backpack_water := water.create_runtime_instance()
	if not inventory.add_to_backpack(
		backpack_water,
		GameEnums.EquipmentSlot.BACKPACK
	):
		_fail("A small item did not fit in the backpack.")
		return
	if inventory.is_combat_accessible(backpack_water):
		_fail("A backpack item was exposed as combat-accessible.")
		return
	if not inventory.is_combat_accessible(round_stacks[0]):
		_fail("A rig item was not exposed as combat-accessible.")
		return

	var oversized := ItemData.new()
	oversized.id = "immovable_test_object"
	oversized.item_size = GameEnums.ItemSize.BIG
	if inventory.add_to_backpack(oversized):
		_fail("A BIG world object was picked up.")
		return

	print(
		"[TEST PASS] Worn containers, size gates, combat access, stacks, "
		+ "magazine fitting, and zero naked capacity obey the inventory rules."
	)
	quit(0)

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
