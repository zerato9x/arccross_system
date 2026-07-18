extends PanelContainer
class_name RealtimeActorPanel

@export var side_label := "PLAYER"

@onready var title_label: Label = %TitleLabel
@onready var action_label: Label = %ActionLabel
@onready var blood_bar: ProgressBar = %BloodBar
@onready var blood_value: Label = %BloodValue
@onready var ap_bar: ProgressBar = %APBar
@onready var ap_value: Label = %APValue
@onready var stance_bar: ProgressBar = %StanceBar
@onready var stance_value: Label = %StanceValue
@onready var condition_label: Label = %ConditionLabel
@onready var wound_label: Label = %WoundLabel
@onready var paper_doll: PaperDollModel = %PaperDoll
@onready var limb_bars: Array[RealtimeLimbBar] = [
	%HeadLimb,
	%UpperTorsoLimb,
	%LowerTorsoLimb,
	%LeftArmLimb,
	%RightArmLimb,
	%LeftLegLimb,
	%RightLegLimb,
]

var _equipment_signature := ""
var _wound_signature := ""

func _ready() -> void:
	paper_doll.set_backdrop_visible(false)

func show_actor(data: Dictionary) -> void:
	if data.is_empty():
		visible = false
		return
	visible = true
	title_label.text = "%s // %s" % [
		side_label,
		str(data.get("display_name", data.get("archetype", data.get("name", "UNKNOWN")))).to_upper(),
	]
	blood_bar.max_value = float(data.get("blood_max", GameEnums.SCALE_MAX))
	blood_bar.value = float(data.get("blood", 0.0))
	blood_value.text = "BLOOD  %.1f / %.0f" % [blood_bar.value, blood_bar.max_value]
	ap_bar.max_value = float(data.get("ap_max", 12.0))
	ap_bar.value = float(data.get("ap", 0.0))
	ap_value.text = "AP  %.1f / %.0f    +%.1f/s" % [
		ap_bar.value,
		ap_bar.max_value,
		float(data.get("ap_regen", 0.0)),
	]
	stance_bar.max_value = GameEnums.SCALE_MAX
	stance_bar.value = float(data.get("stance", 0.0))
	stance_value.text = "STANCE  %.0f / %d" % [stance_bar.value, GameEnums.SCALE_MAX]
	condition_label.text = "%s  //  %s" % [
		str(data.get("stance_state", "STABLE")),
		str(data.get("kinetic_tier", "FLUID")),
	]
	action_label.text = _action_text(data)
	var limbs: Array = data.get("limbs", [])
	for index in range(limb_bars.size()):
		if index < limbs.size():
			limb_bars[index].show_limb(limbs[index])
	wound_label.text = _wound_summary(limbs)
	var equipment: Array = data.get("equipment", [])
	var equipment_signature := str(equipment)
	if equipment_signature != _equipment_signature:
		_equipment_signature = equipment_signature
		paper_doll.update_model(equipment)
	var wound_signature := str(limbs)
	if wound_signature != _wound_signature:
		_wound_signature = wound_signature
		paper_doll.update_wounds(limbs)

func _action_text(data: Dictionary) -> String:
	if bool(data.get("aiming", false)):
		return "AIMING  %d%%" % int(round(float(data.get("aim_progress", 0.0)) * 100.0))
	var action := int(data.get("action", GameEnums.DuelActionType.NONE))
	if action == GameEnums.DuelActionType.NONE:
		return "READY"
	var names := GameEnums.DuelActionType.keys()
	var label := str(names[action]) if action >= 0 and action < names.size() else "ACTION"
	var elapsed := float(data.get("action_elapsed", 0.0))
	var duration := maxf(0.01, float(data.get("action_duration", 0.0)))
	return "%s  %.1fs" % [label.replace("_", " "), maxf(0.0, duration - elapsed)]

func _wound_summary(limbs: Array) -> String:
	var damaged: Array[String] = []
	for raw_limb in limbs:
		var limb: Dictionary = raw_limb
		var maximum := maxf(1.0, float(limb.get("maximum", 1.0)))
		var current := clampf(float(limb.get("current", maximum)), 0.0, maximum)
		var trauma := str(limb.get("trauma", "NONE"))
		if current >= maximum * 0.95 and trauma == "NONE":
			continue
		var state := trauma if trauma != "NONE" else "%d%%" % int(round(current / maximum * 100.0))
		damaged.append("%s %s" % [str(limb.get("code", "??")), state])
	if damaged.is_empty():
		return "WOUNDS // NONE"
	return "WOUNDS // " + "   ".join(damaged)
