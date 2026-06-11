extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not await _verify_body_scale():
		return
	if not _verify_item_scale():
		return
	if not _verify_macro_interaction_scale():
		return

	print(
		"[TEST PASS] Biological meters, item modifiers, and macro interaction "
		+ "metrics use the shared 0-12 scale."
	)
	quit(0)

func _verify_body_scale() -> bool:
	var body := HumanoidBody.new()
	root.add_child(body)
	await process_frame
	body.configure_structure(8)

	if (
		not is_equal_approx(body.blood_level, GameEnums.SCALE_MAX)
		or not is_equal_approx(body.hunger, GameEnums.SCALE_MAX)
		or not is_equal_approx(body.thirst, GameEnums.SCALE_MAX)
		or not is_zero_approx(body.fatigue)
	):
		return _fail("A fresh body did not initialize on the 0-12 scale.")

	var expected_arm_max := (
		body.BASE_LIMB_MAX[GameEnums.LimbRegion.LEFT_ARM]
		* (8.0 / GameEnums.SCALE_MIDPOINT)
	)
	if not is_equal_approx(
		body.get_limb_max(GameEnums.LimbRegion.LEFT_ARM),
		expected_arm_max
	):
		return _fail("Fortitude did not derive the authoritative limb maximum.")

	body.process_biological_tick(15.0, 0.0, 1.0)
	if (
		body.hunger >= GameEnums.SCALE_MAX
		or body.thirst >= GameEnums.SCALE_MAX
		or body.fatigue <= 0.0
	):
		return _fail("Biological ticking did not move twelve-point vitals.")

	var snapshot := body.capture_runtime_state()
	var restored := HumanoidBody.new()
	root.add_child(restored)
	await process_frame
	restored.configure_structure(8)
	restored.restore_runtime_state(snapshot)
	if (
		not is_equal_approx(restored.hunger, body.hunger)
		or not is_equal_approx(restored.thirst, body.thirst)
		or not is_equal_approx(restored.fatigue, body.fatigue)
	):
		return _fail("Twelve-point vitals failed their snapshot round trip.")

	body.queue_free()
	restored.queue_free()
	return true

func _verify_item_scale() -> bool:
	var pistol := load("res://ItemCore/Items/makeshift_sidearm.tres") as ItemData
	var water := load("res://ItemCore/Items/clean_water.tres") as ItemData
	var coat := load("res://ItemCore/Items/scavenger_coat.tres") as ItemData
	if not pistol or not water or not coat:
		return _fail("Base-12 item fixtures could not be loaded.")

	if not is_equal_approx(pistol.armor_penetration, GameEnums.SCALE_MIDPOINT):
		return _fail("Weapon penetration was not migrated to the 0-12 scale.")
	if water.consumable_potency <= 1.0 or water.consumable_potency > 12.0:
		return _fail("Consumable potency still resembles a normalized value.")
	if coat.insulation <= 1.0 or coat.insulation > 12.0:
		return _fail("Insulation still resembles a normalized value.")
	return true

func _verify_macro_interaction_scale() -> bool:
	var profile := MacroInteractionResolver.build_poi_profile(
		"BASE_12_SMOKE",
		Vector2i(3, -2),
		GameEnums.GridBiome.FOREST,
		"test_poi"
	)
	if (
		not _metrics_use_base_twelve(profile.get("search", {}))
		or not _metrics_use_base_twelve(profile.get("camp", {}))
	):
		return _fail("Generated POI metrics escaped the 0-12 scale.")

	var crowbar := load("res://ItemCore/Items/crowbar.tres") as ItemData
	var sleeping_bag := load("res://ItemCore/Items/sleeping_bag.tres") as ItemData
	var search_metrics := MacroInteractionResolver.calculate_search_metrics(
		profile["search"],
		[crowbar.create_runtime_instance().to_interaction_descriptor()],
		1
	)
	var camp_metrics := MacroInteractionResolver.calculate_camp_metrics(
		profile["camp"],
		[sleeping_bag.create_runtime_instance().to_interaction_descriptor()]
	)
	if (
		not _metrics_use_base_twelve(search_metrics)
		or not _metrics_use_base_twelve(camp_metrics)
	):
		return _fail("Interaction equipment produced metrics outside 0-12.")

	var camp_result := MacroInteractionResolver.resolve_camp(
		"BASE_12_SMOKE",
		Vector2i(3, -2),
		0,
		camp_metrics
	)
	var fatigue_recovery := float(camp_result.get("fatigue_recovery", -1.0))
	if fatigue_recovery < 0.0 or fatigue_recovery > GameEnums.SCALE_MAX:
		return _fail("Camp recovery did not return twelve-point fatigue.")
	return true

func _metrics_use_base_twelve(metrics: Dictionary) -> bool:
	for key in metrics.keys():
		var value := float(metrics[key])
		if value < 0.0 or value > GameEnums.SCALE_MAX:
			return false
	return true

func _fail(message: String) -> bool:
	push_error("[TEST FAIL] " + message)
	quit(1)
	return false
