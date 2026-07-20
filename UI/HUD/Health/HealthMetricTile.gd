extends PanelContainer
class_name HealthMetricTile

const ANIMATED_METER_SCENE := preload("res://UI/HUD/Widgets/AnimatedMeter.tscn")
const ANIMATED_ICON_SCENE := preload("res://UI/HUD/Widgets/AnimatedHudIcon.tscn")

var _definition: HealthMetricDefinition
var _meter: AnimatedMeter
var _animated_icon: AnimatedHudIcon
var _last_severity := ""

@onready var _icon: TextureRect = %MetricIcon
@onready var _name_label: Label = %MetricName
@onready var _value_label: Label = %MetricValue
@onready var _bar: ProgressBar = %MetricBar
@onready var _state_label: Label = %MetricState


func _ready() -> void:
	HUDAssetLibrary.apply_inset_panel(self)
	HUDAssetLibrary.apply_label(_name_label, "muted")
	HUDAssetLibrary.apply_label(_value_label)
	HUDAssetLibrary.apply_label(_state_label, "muted")
	_name_label.add_theme_font_size_override("font_size", 13)
	_value_label.add_theme_font_size_override("font_size", 15)
	_state_label.add_theme_font_size_override("font_size", 11)
	_install_animated_meter()
	_install_animated_icon()


func _install_animated_meter() -> void:
	if _bar == null or _meter != null:
		return
	var parent := _bar.get_parent()
	var index := _bar.get_index()
	_meter = ANIMATED_METER_SCENE.instantiate() as AnimatedMeter
	_meter.name = "MetricBar"
	_meter.unique_name_in_owner = true
	_meter.custom_minimum_size = _bar.custom_minimum_size
	_meter.size_flags_horizontal = _bar.size_flags_horizontal
	_meter.max_value = _bar.max_value
	_meter.value = _bar.value
	parent.add_child(_meter)
	parent.move_child(_meter, index)
	_bar.queue_free()
	_bar = _meter


func _install_animated_icon() -> void:
	if _icon == null or _animated_icon != null:
		return
	var parent := _icon.get_parent()
	var index := _icon.get_index()
	_animated_icon = ANIMATED_ICON_SCENE.instantiate() as AnimatedHudIcon
	_animated_icon.name = "MetricIcon"
	_animated_icon.unique_name_in_owner = true
	_animated_icon.custom_minimum_size = _icon.custom_minimum_size
	_animated_icon.autoplay = false
	parent.add_child(_animated_icon)
	parent.move_child(_animated_icon, index)
	_icon.queue_free()
	_icon = _animated_icon


func configure(definition: HealthMetricDefinition) -> void:
	_definition = definition
	if not is_node_ready():
		await ready
	_name_label.text = definition.display_name
	var icon_tex := HUDAssetLibrary.official_texture(definition.icon_path)
	if _animated_icon:
		var anim_name := _animation_for_metric(str(definition.snapshot_key))
		if anim_name.is_empty():
			_animated_icon.set_static_texture(icon_tex)
		else:
			_animated_icon.set_animation(anim_name)
			_animated_icon.play()
	elif _icon:
		_icon.texture = icon_tex
	if _meter:
		_meter.configure(str(definition.fill_kind))
	else:
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
	_value_label.text = value_text
	if _meter:
		_meter.min_value = 0.0
		_meter.max_value = 12.0
		_meter.set_meter_value(meter_value, true)
	else:
		_bar.min_value = 0.0
		_bar.max_value = 12.0
		_bar.value = meter_value
	_apply_state(_severity_for(raw))


func _animation_for_metric(key: String) -> String:
	match key.to_lower():
		"blood", "bleeding":
			return "bleeding"
		"fatigue", "pain":
			return "heartbeat"
		"anomaly":
			return "anomaly"
	return ""


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
	HUDAssetLibrary.apply_inset_panel(self, state if state != "stable" else "neutral")
	var value_role := state if state in ["critical", "warning"] else "body"
	HUDAssetLibrary.apply_label(
		_state_label,
		state if state in ["critical", "warning"] else "muted"
	)
	HUDAssetLibrary.apply_label(_value_label, value_role)
	_state_label.add_theme_font_size_override("font_size", 11)
	_value_label.add_theme_font_size_override("font_size", 15)
	if state != _last_severity and _last_severity != "" and state != "stable":
		HudMotion.severity_flash(self, self, state)
		if state == "critical":
			HudMotion.micro_shake(self, self, 2.0, 0.16)
	_last_severity = state
	if _animated_icon and state == "critical" and not _animated_icon.is_playing():
		_animated_icon.play()
