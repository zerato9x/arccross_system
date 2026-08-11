extends SceneTree


func _init() -> void:
	var profile := load("res://ItemCore/default_item_condition_profile.tres") as ItemConditionProfile
	print("[CONDITION_PROFILE] thresholds=%s faults=%s grades=%s wear=%s" % [
		str(profile.condition_thresholds),
		str(profile.fault_chances),
		str(profile.grade_multipliers),
		str(profile.wear_rates),
	])
	var item := ItemData.new().create_runtime_instance()
	item.current_condition = 4.0
	var outcome := ItemConditionRules.resolve_use(item, ItemConditionRules.EVENT_ARMOR, 0.01)
	print("[CONDITION_PROFILE] outcome=%s" % str(outcome))
	if not is_equal_approx(float(outcome.get("performance_multiplier", 0.0)), 0.5):
		push_error("Condition profile did not preserve the authored damaged armor fault.")
		quit(1)
		return
	var firearm_recipe := profile.repair_recipe(GameEnums.RepairDomain.FIREARM)
	if firearm_recipe.get("tool_id", "") != "gun_cleaner" or profile.repair_amount("field") != 2.0:
		push_error("Repair recipes and restoration amounts are not authored by the condition profile.")
		quit(1)
		return
	print("[CONDITION_PROFILE] PASS")
	quit()
