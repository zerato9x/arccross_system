extends ProgressBar
class_name AnimatedMeter

@export var fill_kind: String = "health"
@export var animate_duration: float = 0.28
@export var flash_on_threshold: bool = true

var _value_tween: Tween
var _last_severity := ""


func _ready() -> void:
	show_percentage = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	HUDAssetLibrary.apply_progress_bar(self, fill_kind)


func configure(kind: String) -> void:
	fill_kind = kind
	HUDAssetLibrary.apply_progress_bar(self, fill_kind)


func set_meter_value(target: float, animate: bool = true) -> void:
	var clamped := clampf(target, min_value, max_value)
	HudMotion.kill(_value_tween)
	if not animate or not is_inside_tree():
		value = clamped
		_update_severity()
		return
	_value_tween = HudMotion.lerp_progress(self, self, clamped, animate_duration)
	if _value_tween:
		_value_tween.finished.connect(_update_severity, CONNECT_ONE_SHOT)
	else:
		_update_severity()


func _update_severity() -> void:
	var ratio := 0.0
	if max_value > min_value:
		ratio = (value - min_value) / (max_value - min_value)
	var severity := "stable"
	if ratio <= 0.25:
		severity = "critical"
	elif ratio <= 0.5:
		severity = "warning"
	if severity == _last_severity:
		return
	var previous := _last_severity
	_last_severity = severity
	if flash_on_threshold and previous != "" and severity != "stable":
		HudMotion.severity_flash(self, self, severity)
