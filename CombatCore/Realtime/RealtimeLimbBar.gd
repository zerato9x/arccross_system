extends HBoxContainer
class_name RealtimeLimbBar

@export var limb_code := "HD"

@onready var code_label: Label = %CodeLabel
@onready var health_bar: ProgressBar = %HealthBar
@onready var state_label: Label = %StateLabel


func _ready() -> void:
	code_label.text = limb_code


func show_limb(data: Dictionary) -> void:
	var maximum := maxf(1.0, float(data.get("maximum", GameEnums.SCALE_MAX)))
	var current := clampf(float(data.get("current", maximum)), 0.0, maximum)
	var trauma := str(data.get("trauma", "NONE"))
	health_bar.max_value = maximum
	health_bar.value = current
	code_label.text = str(data.get("code", limb_code))
	state_label.text = (
		"%d/%d" % [roundi(current), roundi(maximum)]
		if trauma == "NONE"
		else trauma.replace("SHATTERED_LIMB", "SHATTERED")
	)
	var ratio := current / maximum
	health_bar.modulate = (
		Color(0.95, 0.28, 0.22)
		if ratio <= 0.25
		else Color(1.0, 0.65, 0.22)
		if ratio <= 0.55
		else Color(0.42, 0.82, 0.6)
	)
	state_label.modulate = Color(1.0, 0.42, 0.36) if trauma != "NONE" else Color(0.74, 0.82, 0.84)
