extends RefCounted
class_name InventorySnapshotPresenter

## Read-only inventory presentation math. This presenter consumes dictionaries
## and never reaches into InventorySystem or HumanoidCore instances.

func comparison_text(
	snapshot: Dictionary,
	descriptor: Dictionary
) -> String:
	var equipped: Dictionary = {}
	var preferred := int(descriptor.get(
		"preferred_equipment_slot",
		GameEnums.EquipmentSlot.NONE
	))
	for candidate_value in snapshot.get("equipment", []):
		if not candidate_value is Dictionary:
			continue
		var candidate: Dictionary = candidate_value
		if int(candidate.get(
			"equipment_slot",
			GameEnums.EquipmentSlot.NONE
		)) == preferred:
			equipped = candidate
			break
	if equipped.is_empty() or equipped.get("instance_id", "") == descriptor.get("instance_id", ""):
		return "COMPARISON: no different equipped item in the relevant slot"
	return "VS %s  |  Flesh %+.1f  Impact %+.1f  Pen %+.1f  Prot %+.1f  Weight %+.1f  Bulk %+.1f" % [
		str(equipped.get("name", "EQUIPPED")).to_upper(),
		float(descriptor.get("flesh_damage", 0.0)) - float(equipped.get("flesh_damage", 0.0)),
		float(descriptor.get("balance_impact", 0.0)) - float(equipped.get("balance_impact", 0.0)),
		float(descriptor.get("armor_penetration", 0.0)) - float(equipped.get("armor_penetration", 0.0)),
		total_protection(descriptor) - total_protection(equipped),
		float(descriptor.get("weight", 0.0)) - float(equipped.get("weight", 0.0)),
		float(descriptor.get("bulk", 0.0)) - float(equipped.get("bulk", 0.0)),
	]


func total_protection(descriptor: Dictionary) -> float:
	return (
		float(descriptor.get("protection_blunt", 0.0))
		+ float(descriptor.get("protection_sharp", 0.0))
		+ float(descriptor.get("protection_ballistic", 0.0))
	)


func matches_filter(filter_id: String, descriptor: Dictionary) -> bool:
	if filter_id == "all":
		return true
	var item_type := int(descriptor.get("item_type", GameEnums.ItemType.JUNK))
	var category := int(descriptor.get("catalog_category", GameEnums.ItemCategory.MISC))
	match filter_id:
		"weapons":
			return item_type == GameEnums.ItemType.WEAPON
		"armor":
			return item_type == GameEnums.ItemType.ARMOR
		"aid":
			return category == GameEnums.ItemCategory.MEDICINE
		"tools":
			return item_type == GameEnums.ItemType.TOOL
		"ammunition":
			return item_type == GameEnums.ItemType.AMMUNITION
		"materials_misc":
			return item_type in [
				GameEnums.ItemType.MATERIAL,
				GameEnums.ItemType.JUNK,
				GameEnums.ItemType.ATTACHMENT,
			]
	return true
