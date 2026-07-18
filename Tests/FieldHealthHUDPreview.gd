extends Control


func _ready() -> void:
	var snapshot := _fixture_snapshot()
	%CompactHUD.apply_snapshot(snapshot)
	%DetailedHUD.apply_snapshot(snapshot)


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
					"recommended_item_ids": ["bandage", "dressingpack", "medkit", "tourniquet"],
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
