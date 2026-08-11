extends RefCounted
class_name InventoryConditionService

## ItemCore application adapter. Inventory and combat can share one condition
## contract without importing either scheduler into the rules kernel.

const _Rules := preload("res://ItemCore/ItemConditionRules.gd")


func resolve_use(
	item: ItemData,
	event_kind: String,
	roll_override: float = -1.0
) -> Dictionary:
	return _Rules.resolve_use(item, event_kind, roll_override)


func readiness_descriptor(item: ItemData) -> Dictionary:
	return _Rules.readiness_descriptor(item)


func clear_malfunction(item: ItemData) -> bool:
	return _Rules.clear_malfunction(item)


func repair_recipe(domain: int) -> Dictionary:
	return _Rules.repair_recipe(domain)


func universal_repair_recipe() -> Dictionary:
	return _Rules.universal_repair_recipe()


func repair_material_units() -> int:
	return _Rules.repair_material_units()


func repair_cap(context: String, universal: bool, unique_field_repair: bool) -> float:
	return _Rules.repair_cap(context, universal, unique_field_repair)


func repair_amount(context: String) -> float:
	return _Rules.repair_amount(context)


func repair_item(
	inventory: InventorySystem,
	target: ItemData,
	tool: ItemData,
	material: ItemData,
	context: String,
	roll_override: float = -1.0
) -> Dictionary:
	var result := {
		"success": false,
		"attempted": false,
		"message": "The repair could not be completed.",
		"condition_before": 0.0 if target == null else target.current_condition,
		"condition_after": 0.0 if target == null else target.current_condition,
		"tool_outcome": {},
	}
	if target == null or tool == null or material == null:
		result.message = "The target, tool, and material are all required."
		return result
	if (
		inventory == null
		or not inventory.get_all_items().has(target)
		or not inventory.get_all_items().has(tool)
		or not inventory.get_all_items().has(material)
	):
		result.message = "Every repair component must be in your inventory."
		return result
	if target == tool or target == material or tool == material:
		result.message = "A repair needs three distinct item instances."
		return result

	var universal_recipe := universal_repair_recipe()
	var universal := (
		tool.id == str(universal_recipe.get("tool_id", ""))
		and material.id == str(universal_recipe.get("material_id", ""))
	)
	var recipe := repair_recipe(int(target.repair_domain))
	var recipe_matches := (
		not recipe.is_empty()
		and tool.id == str(recipe.get("tool_id", ""))
		and material.id == str(recipe.get("material_id", ""))
	)
	if not recipe_matches and not universal:
		result.message = "Those components do not match this item's repair domain."
		return result

	var cap := repair_cap(
		context,
		universal,
		target.item_grade == GameEnums.ItemGrade.UNIQUE
	)
	var amount := repair_amount(context)
	if target.current_condition >= cap:
		result.message = "This repair cannot improve the item beyond its current condition."
		return result

	var tool_outcome := resolve_use(
		tool,
		ItemConditionRules.EVENT_TOOL,
		roll_override
	)
	result.attempted = true
	result.tool_outcome = tool_outcome
	# Materials and time are committed with the attempt, even when the worn tool
	# fails. Otherwise repairs become a free reroll machine wearing a trench coat.
	inventory.consume_item_units(material, repair_material_units())
	if bool(tool_outcome.faulted) or bool(tool_outcome.broke):
		result.message = "%s failed during the repair attempt." % tool.display_name
		return result
	target.current_condition = minf(cap, target.current_condition + amount)
	result.success = true
	result.condition_after = target.current_condition
	result.message = "Repaired %s to %.2f/12." % [target.display_name, target.current_condition]
	return result


func apply_tool_wear(
	inventory: InventorySystem,
	method_id: String,
	receipt_wear: float = 0.0
) -> void:
	if inventory == null or method_id.is_empty():
		return
	var wear := maxf(
		receipt_wear,
		_Rules.tool_wear_for_method(method_id)
	)
	if wear <= 0.0:
		return
	for item in inventory.get_all_items():
		if item == null:
			continue
		var matches_method := (
			(method_id == "crowbar" and item.id in ["crowbar", "bent_pry_bar"])
			or (method_id == "multitool" and item.id in ["multitool", "lockpick"])
		)
		if not matches_method:
			continue
		item.current_condition = maxf(0.0, item.current_condition - wear)
		inventory.equipment_changed.emit(GameEnums.EquipmentSlot.NONE, item)
		return
