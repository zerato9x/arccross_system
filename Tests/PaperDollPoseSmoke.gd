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

	doll.update_wounds([{
		"region": GameEnums.LimbRegion.HEAD,
		"current": 1.0,
		"maximum": 6.0,
		"trauma": "BLEEDING",
		"damage_type": "BLUNT",
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
	if head_wound.z_index <= doll._head_layer.z_index:
		_fail("The paperdoll head wound rendered underneath the head.")
		return
	if head_wound.z_index >= doll.layer_nodes[GameEnums.EquipmentSlot.HEAD].z_index:
		_fail("The paperdoll head wound rendered above head equipment.")
		return

	doll.update_wounds([
		{
			"region": GameEnums.LimbRegion.LEFT_ARM,
			"current": 4.0,
			"maximum": 8.0,
			"trauma": "BLEEDING",
			"damage_type": "SHARP",
		},
		{
			"region": GameEnums.LimbRegion.RIGHT_LEG,
			"current": 7.0,
			"maximum": 10.0,
			"trauma": "NONE",
			"damage_type": "BALLISTIC",
		},
	])
	await process_frame
	var arm_decal := doll._decal_wound_nodes["LEFT_ARM"] as TextureRect
	var leg_decal := doll._decal_wound_nodes["RIGHT_LEG"] as TextureRect
	if (
		arm_decal == null
		or not arm_decal.visible
		or arm_decal.texture == null
		or not arm_decal.texture.resource_path.ends_with("wound_laceration.png")
	):
		_fail("A sharp arm wound did not render the laceration decal.")
		return
	if (
		leg_decal == null
		or not leg_decal.visible
		or leg_decal.texture == null
		or not leg_decal.texture.resource_path.ends_with("wound_bullet.png")
	):
		_fail("A ballistic leg wound did not render the bullet decal.")
		return
	var content_rect := doll._model_content_rect()
	if (
		not content_rect.has_point(arm_decal.position + arm_decal.size * 0.5)
		or not content_rect.has_point(leg_decal.position + leg_decal.size * 0.5)
	):
		_fail("Paperdoll wound decals were placed outside the fitted model art.")
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
