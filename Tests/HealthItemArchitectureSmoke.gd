extends SceneTree

const PROFILE_PATH := "res://PresentationCore/health_hud_profile.tres"


func _init() -> void:
	var failures: Array[String] = []
	_check_new_hud_cutover(failures)
	_check_snapshot_only_presentation(failures)
	_check_profile(failures)
	_check_health_item_contracts(failures)
	if not failures.is_empty():
		for failure in failures:
			push_error(failure)
		quit(1)
		return
	print("[HEALTH_ITEM_ARCHITECTURE_SMOKE] PASS")
	quit(0)


func _check_new_hud_cutover(failures: Array[String]) -> void:
	var corner_scene := FileAccess.get_file_as_string(
		"res://UI/HUD/Macro/MacroHealthCornerPanel.tscn"
	)
	if corner_scene.count("FieldHealthHUD.tscn") != 1:
		failures.append("Macro health corner must source one reusable FieldHealthHUD scene.")
	if "MacroStatusPanel.tscn" in corner_scene or "MedicalMonitor.tscn" in corner_scene:
		failures.append("Macro health corner still references a legacy health widget.")
	var manager := FileAccess.get_file_as_string("res://WorldCore/MacroGameManager.gd")
	if "MedicalMonitor" in manager or "res://UI/HUD/Health" in manager:
		failures.append("WorldCore still knows a concrete health presentation type/path.")


func _check_snapshot_only_presentation(failures: Array[String]) -> void:
	for path in [
		"res://UI/HUD/Health/FieldHealthHUD.gd",
		"res://UI/HUD/Health/HealthMetricTile.gd",
		"res://UI/HUD/Health/WoundRegionCard.gd",
		"res://UI/HUD/Health/WoundRegionHotspot.gd",
	]:
		var source := FileAccess.get_file_as_string(path)
		for forbidden in [
			"HumanoidBody",
			"HumanoidCore",
			"InventorySystem",
			"BiologicalCore/",
			"ItemCore/",
			"WorldCore/",
			"SystemCore/",
		]:
			if forbidden in source:
				failures.append("%s reaches into domain state through %s." % [path, forbidden])


func _check_profile(failures: Array[String]) -> void:
	var profile := load(PROFILE_PATH) as HealthHUDProfile
	if profile == null:
		failures.append("Health HUD profile could not be loaded.")
		return
	if profile.metrics.size() != 7:
		failures.append("Health HUD profile must author seven systemic metrics.")
	if profile.regions.size() != 7:
		failures.append("Health HUD profile must author seven body regions.")
	for resource in profile.metrics + profile.regions:
		var icon_path := str(resource.get("icon_path"))
		if icon_path.is_empty() or not ResourceLoader.exists(icon_path):
			failures.append("Missing profile icon: " + icon_path)


func _check_health_item_contracts(failures: Array[String]) -> void:
	var snapshot_builder := FileAccess.get_file_as_string(
		"res://WorldCore/MacroSnapshotBuilder.gd"
	)
	for key in [
		'"blood"',
		'"pain"',
		'"bleeding_rate"',
		'"wound_count"',
		'"infection_risk"',
		'"limbs"',
		'"loadout_stats"',
		'"medical_items"',
		'"treatment"',
	]:
		if key not in snapshot_builder:
			failures.append("Neutral snapshot contract is missing " + key)
	var item_data := FileAccess.get_file_as_string("res://ItemCore/ItemData.gd")
	for field in ["threat", "bulk", "protection_blunt", "protection_sharp", "protection_ballistic"]:
		if ("var " + field) not in item_data:
			failures.append("ItemData is missing authored field: " + field)
	var treatment_profile := load(
		"res://BiologicalCore/default_wound_treatments.tres"
	) as WoundTreatmentProfile
	if treatment_profile == null or treatment_profile.definitions.size() != 6:
		failures.append("All six wound types require authored treatment definitions.")
