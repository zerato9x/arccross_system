extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load(
		"res://UI/Inventory/PaperDollModel.tscn"
	) as PackedScene
	var doll := scene.instantiate() as PaperDollModel
	root.add_child(doll)
	await process_frame

	var coat := load("res://ItemCore/Items/coat_leather.tres") as ItemData
	var pistol := load("res://ItemCore/Items/service_pistol.tres") as ItemData
	var rifle := load("res://ItemCore/Items/service_rifle.tres") as ItemData
	var coat_descriptor := _descriptor(
		coat,
		GameEnums.EquipmentSlot.OUTER_TORSO
	)

	doll.update_model([coat_descriptor])
	if doll._base_main_arm_under.texture == null:
		_fail("The relaxed main arm was not rendered.")
		return
	if doll._base_main_arm_over.texture != null:
		_fail("The weapon grip arm rendered while no weapon was equipped.")
		return
	if doll.find_child("Layer_Arm_Offhand", true, false) != null:
		_fail("The obsolete resting offhand layer still exists.")
		return

	doll.update_model([
		coat_descriptor,
		_descriptor(pistol, GameEnums.EquipmentSlot.HAND),
	])
	var pistol_layer: TextureRect = doll.layer_nodes[
		GameEnums.EquipmentSlot.HAND
	]
	var coat_grip: TextureRect = doll.secondary_layer_nodes[
		GameEnums.EquipmentSlot.OUTER_TORSO
	]
	if pistol_layer.texture == null or coat_grip.texture == null:
		_fail("The one-handed weapon or authored coat grip was not rendered.")
		return
	if pistol_layer.z_index >= coat_grip.z_index:
		_fail("The weapon still renders above the gripping hand.")
		return

	doll.update_model([
		coat_descriptor,
		_descriptor(rifle, GameEnums.EquipmentSlot.HAND),
	])
	if (
		doll._two_handed_grip.texture == null
		or doll._two_handed_grip.texture.resource_path
			!= PaperDollModel.ARM_OFFHAND_2H_PATH
	):
		_fail("The two-handed weapon did not render its offhand grip.")
		return

	doll.update_wounds([{
		"region": GameEnums.LimbRegion.HEAD,
		"current": 1.0,
		"maximum": 6.0,
		"trauma": "BLEEDING",
	}])
	await process_frame
	var head_wound := doll._full_wound_nodes[
		"res://Asset/Innawoods_Asset/Humanoid/Wounds/head_disfigured.png"
	] as TextureRect
	if head_wound == null or not head_wound.visible:
		_fail("The paperdoll did not render an active head wound overlay.")
		return
	if head_wound.modulate.a >= 0.85:
		_fail("The paperdoll wound overlay rendered at full-force opacity.")
		return
	if head_wound.z_index >= pistol_layer.z_index:
		_fail("The paperdoll wound overlay renders above equipped gear.")
		return

	print(
		"[TEST PASS] Rest, one-handed, and two-handed paperdoll layers "
		+ "keep weapons below their authored gripping hands, with wounds."
	)
	quit(0)

func _descriptor(item: ItemData, slot: int) -> Dictionary:
	return {
		"item_type": item.item_type,
		"weapon_type": item.weapon_type,
		"equipment_slot": slot,
		"requires_two_hands": item.requires_two_hands,
		"equipped_sprite_paths": item.get_equipped_sprite_paths(),
	}

func _fail(message: String) -> void:
	push_error("[TEST FAIL] " + message)
	quit(1)
