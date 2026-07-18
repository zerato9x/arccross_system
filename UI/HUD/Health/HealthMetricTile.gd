extends PanelContainer
class_name HealthMetricTile

var _definition: HealthMetricDefinition

@onready var _icon: TextureRect = %MetricIcon
@onready var _name_label: Label = %MetricName
@onready var _value_label: Label = %MetricValue
@onready var _bar: ProgressBar = %MetricBar
@onready var _state_label: Label = %MetricState


func _ready() -> void:
	HUDAssetLibrary.apply_panel(self)
	HUDAssetLibrary.apply_label(_name_label, "muted")
	HUDAssetLibrary.apply_label(_value_label)
	HUDAssetLibrary.apply_label(_state_label, "muted")
	_name_label.add_theme_font_size_override("font_size", 13)
	_value_label.add_theme_font_size_override("font_size", 15)
	_state_label.add_theme_font_size_override("font_size", 11)
	HUDAssetLibrary.apply_progress_bar(_bar)


func configure(definition: HealthMetricDefinition) -> void:
	_definition = definition
	if not is_node_ready():
		await ready
	_name_label.text = definition.display_name
	_icon.texture = HUDAssetLibrary.official_texture(definition.icon_path)
	HUDAssetLibrary.apply_progress_bar(_bar, str(definition.fill_kind))


func apply_snapshot(snapshot: Dictionary) -> void:
	if _definition == null:
		return
	var raw := float(snapshot.get(str(_definition.snapshot_key), 0.0))
	var meter_value := raw
	var value_text := "%.1f / 12" % raw
	match _definition.value_transform:
		HealthMetricDefinition.ValueTransform.INVERTED_12:
			meter_value = 12.0 - raw
			value_text = "%.1f / 12" % meter_value
		HealthMetricDefinition.ValueTransform.TEMPERATURE:
			meter_value = clampf(raw - 30.0, 0.0, 12.0)
			value_text = "%.1f C" % raw
	_bar.min_value = 0.0
	_bar.max_value = 12.0
	_bar.value = meter_value
	_value_label.text = value_text
	_apply_state(_severity_for(raw))


func _severity_for(raw: float) -> String:
	if (
		(_definition.danger_below >= 0.0 and raw <= _definition.danger_below)
		or (_definition.danger_above >= 0.0 and raw >= _definition.danger_above)
	):
		return "critical"
	if (
		(_definition.caution_below >= 0.0 and raw <= _definition.caution_below)
		or (_definition.caution_above >= 0.0 and raw >= _definition.caution_above)
	):
		return "warning"
	return "stable"


func _apply_state(state: String) -> void:
	_state_label.text = state.to_upper()
	HUDAssetLibrary.apply_panel(self, state if state != "stable" else "neutral")
	HUDAssetLibrary.apply_label(
		_state_label,
		state if state in ["critical", "warning"] else "muted"
	)
	_state_label.add_theme_font_size_override("font_size", 11)
