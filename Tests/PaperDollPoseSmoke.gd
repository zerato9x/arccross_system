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

	var coat_layer: TextureRect = doll.layer_nodes[
		GameEnums.EquipmentSlot.OUTER_TORSO
	]

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
	if head_wound.modulate.a < 0.6:
		_fail("The paperdoll wound overlay rendered too transparently.")
		return
	if head_wound.z_index >= coat_layer.z_index:
		_fail("The paperdoll wound overlay renders above equipped gear.")
		return

	print(
		"[TEST PASS] Rest paperdoll layers "
		+ "keep weapons disabled, with visible opaque wounds."
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
