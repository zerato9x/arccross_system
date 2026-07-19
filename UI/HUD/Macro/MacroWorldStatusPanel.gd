extends Control
class_name MacroWorldStatusPanel

signal settings_requested
signal node_map_requested

const MAX_LOG_LINES := 12
const PANEL_SIZE := Vector2(420.0, 316.0)
const COMPACT_SIZE := Vector2(420.0, 96.0)
const SCREEN_MARGIN := 14.0
const LOG_KIND_TOKENS := {
	"world": "WORLD",
	"travel": "ROUTE",
	"discovery": "FIND",
	"success": "CLEAR",
	"warning": "WARN",
	"danger": "DANGER",
	"anomaly": "ANOM",
	"system": "SYS",
}

var _snapshot: Dictionary = {}
var _log_entries: Array[Dictionary] = []
var _signal_tween: Tween
var _clock_tween: Tween
var _last_clock_text := ""
var _work_surface_active := false
var _layout_tween: Tween

@onready var _frame: PanelContainer = %Frame
@onready var _eyebrow_label: Label = %WorldLogEyebrow
@onready var _phase_label: Label = %PhaseLabel
@onready var _time_label: Label = %TimeLabel
@onready var _day_label: Label = %DayLabel
@onready var _calendar_label: Label = %CalendarLabel
@onready var _signal_pulse: ColorRect = %SignalPulse
@onready var _signal_label: Label = %SignalLabel
@onready var _log_title: Label = %LogTitle
@onready var _legend: Label = %Legend
@onready var _log_header: HBoxContainer = %LogHeader
@onready var _settings_button: Button = %SettingsButton
@onready var _node_map_button: Button = %NodeMapButton
@onready var _log_frame: PanelContainer = %LogFrame
@onready var _log_scroll: ScrollContainer = %LogScroll
@onready var _log_list: VBoxContainer = %LogList
@onready var _button_row: HBoxContainer = %ButtonRow


func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	pivot_offset = size
	HUDAssetLibrary.apply_panel(_frame, "neutral")
	HUDAssetLibrary.apply_panel(_log_frame, "neutral")
	HUDAssetLibrary.apply_label(_eyebrow_label, "info")
	HUDAssetLibrary.apply_label(_phase_label, "muted")
	HUDAssetLibrary.apply_label(_time_label, "title")
	HUDAssetLibrary.apply_label(_day_label, "body")
	HUDAssetLibrary.apply_label(_calendar_label, "muted")
	HUDAssetLibrary.apply_label(_signal_label, "info")
	HUDAssetLibrary.apply_label(_log_title, "info")
	HUDAssetLibrary.apply_label(_legend, "success")
	_time_label.add_theme_font_size_override("font_size", 24)
	_node_map_button.text = "NODE MAP"
	_settings_button.text = "SETTINGS"
	HUDAssetLibrary.apply_button(_settings_button, "settings")
	HUDAssetLibrary.apply_button(_node_map_button, "map")
	_settings_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size()
	_node_map_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size()
	_settings_button.pressed.connect(func(): settings_requested.emit())
	_node_map_button.pressed.connect(func(): node_map_requested.emit())
	_start_signal_pulse()
	if _log_entries.is_empty():
		append_log("World channel synchronized.", "system")


func set_hud_scale(value: float) -> void:
	pivot_offset = size
	scale = Vector2.ONE * value


func set_work_surface_active(active: bool) -> void:
	if _work_surface_active == active:
		return
	_work_surface_active = active
	_log_header.visible = not active
	_log_frame.visible = not active
	_button_row.visible = not active
	var target_size := COMPACT_SIZE if active else PANEL_SIZE
	custom_minimum_size = target_size
	offset_top = -SCREEN_MARGIN - target_size.y
	offset_bottom = -SCREEN_MARGIN
	offset_left = -SCREEN_MARGIN - target_size.x
	offset_right = -SCREEN_MARGIN
	size = target_size
	pivot_offset = size
	if _layout_tween:
		_layout_tween.kill()
	_frame.modulate.a = 0.58
	_layout_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_layout_tween.tween_property(_frame, "modulate:a", 1.0, 0.16)


func is_work_surface_compact() -> bool:
	return _work_surface_active


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var clock: Dictionary = snapshot.get("world_time", {})
	var calendar: Dictionary = snapshot.get("calendar", {})
	var hour := int(clock.get("hour", 0))
	var minute := int(clock.get("minute", 0))
	var clock_text := "%02d:%02d" % [hour, minute]
	if _time_label:
		_time_label.text = clock_text
		if not _last_clock_text.is_empty() and _last_clock_text != clock_text:
			_animate_clock_tick()
	_last_clock_text = clock_text
	var phase := _phase_for_hour(hour)
	var phase_color := _phase_color(phase)
	if _phase_label:
		_phase_label.text = "%s LIGHT // SECTOR LINK" % phase.to_upper()
		_phase_label.add_theme_color_override("font_color", phase_color)
	if _signal_pulse:
		_signal_pulse.color = phase_color
	if _day_label:
		_day_label.text = "DAY %03d" % int(calendar.get("day", clock.get("day", 1)))
	if _calendar_label:
		_calendar_label.text = "%s %04d" % [
			_month_name(int(calendar.get("month", 1))),
			int(calendar.get("year", 1)),
		]


func append_log(message: String, kind: String = "") -> void:
	var line := message.strip_edges()
	if line.is_empty():
		return
	var resolved_kind := kind.to_lower().strip_edges()
	if resolved_kind.is_empty():
		resolved_kind = _classify_log(line)
	if not LOG_KIND_TOKENS.has(resolved_kind):
		resolved_kind = "world"
	if not _log_entries.is_empty():
		var previous: Dictionary = _log_entries[_log_entries.size() - 1]
		if str(previous.get("message", "")) == line:
			return
	_log_entries.append({
		"message": line,
		"kind": resolved_kind,
		"stamp": _current_stamp(),
	})
	while _log_entries.size() > MAX_LOG_LINES:
		_log_entries.remove_at(0)
	_render_log()


func get_log_entry_count() -> int:
	return _log_entries.size()


func get_latest_log_kind() -> String:
	if _log_entries.is_empty():
		return ""
	return str(_log_entries[_log_entries.size() - 1].get("kind", ""))


func _render_log() -> void:
	if _log_list == null:
		return
	for child in _log_list.get_children():
		_log_list.remove_child(child)
		child.queue_free()
	for i in range(_log_entries.size()):
		var entry: Dictionary = _log_entries[i]
		var latest := i == _log_entries.size() - 1
		var kind := str(entry.get("kind", "world"))
		var row := PanelContainer.new()
		row.custom_minimum_size = Vector2(0.0, 28.0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_meta("log_kind", kind)
		row.add_theme_stylebox_override("panel", HUDAssetLibrary.log_row_style(kind, latest))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		row.add_child(line)
		var marker := ColorRect.new()
		marker.custom_minimum_size = Vector2(3.0, 0.0)
		marker.color = HUDAssetLibrary.semantic_color(kind)
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(marker)
		var meta := Label.new()
		meta.custom_minimum_size = Vector2(70.0, 0.0)
		meta.text = "%s %s" % [
			str(entry.get("stamp", "--:--")),
			str(LOG_KIND_TOKENS.get(kind, "WORLD")),
		]
		HUDAssetLibrary.apply_label(meta, kind)
		line.add_child(meta)
		var body := Label.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.text = str(entry.get("message", ""))
		HUDAssetLibrary.apply_label(body, "body" if latest else "muted")
		line.add_child(body)
		_log_list.add_child(row)
		if latest:
			row.modulate.a = 0.0
			var tween := row.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(row, "modulate:a", 1.0, 0.18)
	call_deferred("_scroll_log_to_end")


func _scroll_log_to_end() -> void:
	if _log_scroll == null:
		return
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _start_signal_pulse() -> void:
	if _signal_pulse == null:
		return
	if _signal_tween:
		_signal_tween.kill()
	_signal_tween = create_tween().set_loops()
	_signal_tween.tween_property(_signal_pulse, "modulate:a", 0.35, 0.9)
	_signal_tween.tween_property(_signal_pulse, "modulate:a", 1.0, 0.9)


func _animate_clock_tick() -> void:
	if _time_label == null:
		return
	if _clock_tween:
		_clock_tween.kill()
	_time_label.modulate = HUDAssetLibrary.COLOR_INFO.lightened(0.28)
	_clock_tween = create_tween()
	_clock_tween.tween_property(_time_label, "modulate", Color.WHITE, 0.22)


func _current_stamp() -> String:
	var clock: Dictionary = _snapshot.get("world_time", {})
	if clock.is_empty():
		return "--:--"
	return "%02d:%02d" % [
		int(clock.get("hour", 0)),
		int(clock.get("minute", 0)),
	]


func _classify_log(message: String) -> String:
	var lower := message.to_lower()
	if _contains_any(lower, ["anomaly", "red mist", "distortion", "impossible"]):
		return "anomaly"
	if _contains_any(lower, ["ambush", "hostile", "attack", "bleed", "critical", "killed"]):
		return "danger"
	if _contains_any(lower, ["warning", "storm", "hazard", "risk", "low "]):
		return "warning"
	if _contains_any(lower, ["discovered", "found", "landmark", "cache", "signal located"]):
		return "discovery"
	if _contains_any(lower, ["arrived", "entered", "travel", "route", "crossed", "departed"]):
		return "travel"
	if _contains_any(lower, ["success", "secured", "recovered", "completed", "safe"]):
		return "success"
	if _contains_any(lower, ["system", "online", "saved", "loaded", "synchronized"]):
		return "system"
	return "world"


func _contains_any(text: String, needles: Array[String]) -> bool:
	for needle in needles:
		if text.contains(needle):
			return true
	return false


func _phase_for_hour(hour: int) -> String:
	if hour < 5:
		return "night"
	if hour < 7:
		return "dawn"
	if hour < 11:
		return "morning"
	if hour < 14:
		return "midday"
	if hour < 17:
		return "afternoon"
	if hour < 20:
		return "dusk"
	return "night"


func _phase_color(phase: String) -> Color:
	match phase:
		"dawn", "dusk":
			return HUDAssetLibrary.COLOR_CAUTION
		"night":
			return HUDAssetLibrary.COLOR_TRAVEL
	return HUDAssetLibrary.COLOR_INFO


func _month_name(month: int) -> String:
	const NAMES := [
		"JAN", "FEB", "MAR", "APR", "MAY", "JUN",
		"JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
	]
	return NAMES[clampi(month - 1, 0, 11)]
