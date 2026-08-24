extends RefCounted
class_name MacroMedicalResolver

static func validate_apply_to_limb(
	player_core: HumanoidCore,
	instance_id: String,
	limb_region: int
) -> Dictionary:
	var result := {"valid": false, "message": ""}
	if player_core == null:
		result["message"] = "No patient signal."
		return result
	if player_core.body == null or player_core.inventory == null:
		result["message"] = "Patient medical state is unavailable."
		return result
	var item := player_core.inventory.find_item_by_instance_id(instance_id)
	if item == null:
		result["message"] = "Item not found."
		return result
	if item.item_type != GameEnums.ItemType.CONSUMABLE:
		result["message"] = "Item is not consumable."
		return result
	if not _is_supported_medical_effect(item.consumable_effect):
		result["message"] = "Item has no supported medical effect."
		return result
	if not _can_apply_to_limb(item, player_core.body, limb_region):
		result["message"] = "Cannot apply item to that limb."
		return result
	result["valid"] = true
	result["message"] = "Treatment ready."
	return result


static func _is_supported_medical_effect(effect: int) -> bool:
	return effect in [
		GameEnums.ConsumableEffect.STOP_BLEEDING,
		GameEnums.ConsumableEffect.RESTORE_BLOOD,
		GameEnums.ConsumableEffect.RESTORE_HUNGER,
		GameEnums.ConsumableEffect.RESTORE_THIRST,
		GameEnums.ConsumableEffect.RESTORE_FATIGUE,
	]


static func _can_apply_to_limb(
	item: ItemData,
	body: HumanoidBody,
	limb_region: int
) -> bool:
	if body == null:
		return false
	match item.consumable_effect:
		GameEnums.ConsumableEffect.STOP_BLEEDING:
			return body.can_treat_bleeding(limb_region)
		GameEnums.ConsumableEffect.RESTORE_BLOOD:
			return body.blood_level < GameEnums.SCALE_MAX
		GameEnums.ConsumableEffect.RESTORE_HUNGER:
			return body.hunger < GameEnums.SCALE_MAX
		GameEnums.ConsumableEffect.RESTORE_THIRST:
			return body.thirst < GameEnums.SCALE_MAX
		GameEnums.ConsumableEffect.RESTORE_FATIGUE:
			return body.fatigue > 0.0
	return false


static func valid_limb_targets(
	item: ItemData,
	body: HumanoidBody
) -> Array[int]:
	var targets: Array[int] = []
	if item == null or body == null:
		return targets
	for region in GameEnums.LimbRegion.values():
		if _can_apply_to_limb(item, body, region):
			targets.append(region)
	return targets
