extends SceneTree

const HUD_SCENE := preload("res://UI/HUD/Health/FieldHealthHUD.tscn")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var background := ColorRect.new()
	background.color = Color("#26291f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var compact := HUD_SCENE.instantiate() as FieldHealthHUD
	compact.display_mode = FieldHealthHUD.DisplayMode.COMPACT
	background.add_child(compact)
	compact.position = Vector2(10, 10)
	compact.size = Vector2(450, 322)

	var detailed := HUD_SCENE.instantiate() as FieldHealthHUD
	detailed.display_mode = FieldHealthHUD.DisplayMode.DETAILED
	background.add_child(detailed)
	detailed.position = Vector2(470, 10)
	detailed.size = Vector2(800, 700)

	var snapshot := _fixture_snapshot()
	compact.apply_snapshot(snapshot)
	detailed.apply_snapshot(snapshot)
	await process_frame
	await process_frame

	if compact.get_node("%CompactMetricGrid").get_child_count() != 6:
		_fail("Compact HUD must render six profile-defined metric tiles.")
		return
	if detailed.get_node("%DetailMetricList").get_child_count() != 7:
		_fail("Detailed HUD must render seven profile-defined metric tiles.")
		return
	var paper_doll_slots := [
		"HeadSlot",
		"UpperTorsoSlot",
		"LowerTorsoSlot",
		"LeftArmSlot",
		"RightArmSlot",
		"LeftLegSlot",
		"RightLegSlot",
	]
	for slot_name in paper_doll_slots:
		if detailed.get_node("%" + slot_name).get_child_count() != 1:
			_fail("Paper doll slot is missing its region hotspot: " + slot_name)
			return
	if not (detailed.get_node("%PaperDollSurface") as BoxContainer).vertical:
		_fail("Narrow detailed HUD must stack the paper doll and inspector.")
		return
	detailed.call("_show_region_details", "LEFT_ARM")
	if "LACERATION" not in (detailed.get_node("%InspectorWounds") as RichTextLabel).text:
		_fail("Hover inspector did not expose full wound details.")
		return
	var treatment_request := {"instance_id": "", "limb_region": -1}
	detailed.limb_treatment_requested.connect(
		func(instance_id: String, limb_region: int):
			treatment_request["instance_id"] = instance_id
			treatment_request["limb_region"] = limb_region
	)
	detailed.call("_open_treatment", "LEFT_ARM", GameEnums.LimbRegion.LEFT_ARM)
	if detailed.get_node("%PaperDollSurface").get_child(0) != detailed.get_node("%InspectorStack"):
		_fail("Narrow treatment tray must move above the paper doll when opened.")
		return
	var treatment_items := detailed.get_node("%TreatmentItems") as VBoxContainer
	if treatment_items.get_child_count() != 1:
		_fail("Right-click treatment tray did not list the compatible carried item.")
		return
	(treatment_items.get_child(0) as Button).pressed.emit()
	if treatment_request["instance_id"] != "fixture_bandage":
		_fail("Treatment button did not emit the selected medical item instance.")
		return
	if detailed.get_node("%PaperDollSurface").get_child(0) != detailed.get_node("%PaperDollStage"):
		_fail("Closing treatment must restore the paper doll above the inspector.")
		return
	detailed.size = Vector2(940, 700)
	await process_frame
	if (detailed.get_node("%PaperDollSurface") as BoxContainer).vertical:
		_fail("Wide detailed HUD must place the paper doll beside its inspector.")
		return
	if (compact.get_node("%ConditionIcon") as TextureRect).texture == null:
		_fail("Condition icon did not load.")
		return
	if not (compact.get_node("%ConditionLabel") as Label).text in ["WOUNDED", "CRITICAL"]:
		_fail("Wound snapshot did not drive the condition hierarchy.")
		return
	print("[FIELD_HEALTH_HUD_SMOKE] PASS")
	quit(0)


func _fixture_snapshot() -> Dictionary:
	var limbs: Array = []
	for region in [
		"HEAD",
		"UPPER_TORSO",
		"LOWER_TORSO",
		"LEFT_ARM",
		"RIGHT_ARM",
		"LEFT_LEG",
		"RIGHT_LEG",
	]:
		var wounds: Array = []
		var current := 12.0
		var bleeding := 0.0
		if region == "LEFT_ARM":
			current = 6.0
			bleeding = 0.65
			wounds.append({
				"id": "fixture_cut",
				"type": "LACERATION",
				"severity": 7.5,
				"bleeding_rate": bleeding,
				"pain": 5.0,
				"contamination": 4.0,
				"treated": false,
				"treatment": {
					"care_label": "CONTROL BLEEDING",
					"instructions": "Apply direct pressure and dress the wound.",
					"required_effect": GameEnums.ConsumableEffect.STOP_BLEEDING,
					"recommended_item_ids": ["bandage"],
					"currently_treatable": true,
				},
			})
		limbs.append({
			"region": region,
			"current": current,
			"maximum": 12.0,
			"bleeding_rate": bleeding,
			"wounds": wounds,
		})
	return {
		"blood": 7.25,
		"pain": 5.0,
		"bleeding_rate": 0.65,
		"wound_count": 1,
		"infection_risk": 4.0,
		"hunger": 8.0,
		"thirst": 6.5,
		"fatigue": 4.0,
		"core_temperature": 37.2,
		"emergencies": ["BLEEDING"],
		"medical_items": [{
			"instance_id": "fixture_bandage",
			"item_id": "bandage",
			"name": "Bandage",
			"sprite_path": "res://Asset/Innawoods_Asset/Items/Medicines/bandage.png",
			"effect": GameEnums.ConsumableEffect.STOP_BLEEDING,
			"potency": 3.0,
			"stack_count": 1,
		}],
		"limbs": limbs,
	}


func _fail(message: String) -> void:
	push_error("[FIELD_HEALTH_HUD_SMOKE] FAIL // " + message)
	quit(1)
