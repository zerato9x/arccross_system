extends PanelContainer
class_name WoundRegionCard

signal item_dropped(instance_id: String, limb_region: int)

const STATE_STABLE := "res://Asset/UI/HUD/medical/state_stable_32.png"
const STATE_DAMAGED := "res://Asset/UI/HUD/medical/state_damaged_32.png"
const STATE_CRITICAL := "res://Asset/UI/HUD/medical/state_critical_32.png"
const TRAUMA_BLEEDING := "res://Asset/UI/HUD/medical/trauma_bleeding_32.png"
const TRAUMA_FRACTURE := "res://Asset/UI/HUD/medical/trauma_fracture_32.png"
const TRAUMA_BURN := "res://Asset/UI/HUD/medical/trauma_burn_32.png"

var _definition: HealthRegionDefinition

@onready var _limb_icon: TextureRect = %LimbIcon
@onready var _state_icon: TextureRect = %StateIcon
@onready var _trauma_icon: TextureRect = %TraumaIcon
@onready var _region_label: Label = %RegionLabel
@onready var _integrity_label: Label = %IntegrityLabel
@onready var _integrity_bar: ProgressBar = %IntegrityBar
@onready var _wound_label: Label = %WoundLabel
@onready var _treatment_label: Label = %TreatmentLabel
@onready var _drop_target: LimbDropTarget = %DropTarget


func _ready() -> void:
	HUDAssetLibrary.apply_panel(self)
	HUDAssetLibrary.apply_label(_region_label)
	HUDAssetLibrary.apply_label(_integrity_label, "muted")
	HUDAssetLibrary.apply_label(_wound_label, "muted")
	HUDAssetLibrary.apply_label(_treatment_label, "muted")
	_region_label.add_theme_font_size_override("font_size", 14)
	_integrity_label.add_theme_font_size_override("font_size", 11)
	_wound_label.add_theme_font_size_override("font_size", 12)
	_treatment_label.add_theme_font_size_override("font_size", 11)
	HUDAssetLibrary.apply_progress_bar(_integrity_bar)
	_drop_target.item_dropped.connect(item_dropped.emit)


func configure(definition: HealthRegionDefinition) -> void:
	_definition = definition
	if not is_node_ready():
		await ready
	_region_label.text = definition.display_name
	_limb_icon.texture = HUDAssetLibrary.official_texture(definition.icon_path)
	_drop_target.configure(int(definition.limb_region))


func apply_limb_snapshot(limb: Dictionary) -> void:
	if _definition == null:
		return
	var current := float(limb.get("current", 0.0))
	var maximum := maxf(1.0, float(limb.get("maximum", 12.0)))
	var ratio := clampf(current / maximum, 0.0, 1.0)
	var wounds: Array = limb.get("wounds", [])
	var bleeding := float(limb.get("bleeding_rate", 0.0))
	_integrity_bar.max_value = maximum
	_integrity_bar.value = current
	_integrity_label.text = "%.0f%% INTEGRITY" % (ratio * 100.0)
	_update_wound_readout(wounds, bleeding)
	_update_state(ratio, wounds)


func _update_wound_readout(wounds: Array, bleeding: float) -> void:
	if wounds.is_empty():
		_wound_label.text = "NO ACTIVE WOUND"
		_treatment_label.text = "NO TREATMENT NEEDED"
		_trauma_icon.visible = false
		return
	var worst: Dictionary = wounds[0]
	for candidate in wounds:
		if float(candidate.get("severity", 0.0)) > float(worst.get("severity", 0.0)):
			worst = candidate
	var wound_type := str(worst.get("type", "WOUND"))
	_wound_label.text = "%d WOUND%s // %s %.1f" % [
		wounds.size(),
		"" if wounds.size() == 1 else "S",
		wound_type,
		float(worst.get("severity", 0.0)),
	]
	var all_treated := true
	for wound in wounds:
		if not bool(wound.get("treated", false)):
			all_treated = false
			break
	_treatment_label.text = (
		"DRESSED // BLEED %.2f" % bleeding
		if all_treated
		else "UNTREATED // DROP MEDICAL ITEM"
	)
	_trauma_icon.visible = true
	_trauma_icon.texture = HUDAssetLibrary.official_texture(_trauma_icon_for(wound_type))
	HUDAssetLibrary.apply_label(_treatment_label, "warning" if not all_treated else "muted")
	_treatment_label.add_theme_font_size_override("font_size", 11)


func _update_state(ratio: float, wounds: Array) -> void:
	var state_path := STATE_STABLE
	var panel_kind := "neutral"
	if ratio <= 0.25:
		state_path = STATE_CRITICAL
		panel_kind = "critical"
	elif ratio < 0.75 or not wounds.is_empty():
		state_path = STATE_DAMAGED
		panel_kind = "warning"
	_state_icon.texture = HUDAssetLibrary.official_texture(state_path)
	HUDAssetLibrary.apply_panel(self, panel_kind)


func _trauma_icon_for(wound_type: String) -> String:
	if wound_type.contains("BURN"):
		return TRAUMA_BURN
	if wound_type.contains("FRACTURE") or wound_type.contains("CRUSH"):
		return TRAUMA_FRACTURE
	return TRAUMA_BLEEDING
