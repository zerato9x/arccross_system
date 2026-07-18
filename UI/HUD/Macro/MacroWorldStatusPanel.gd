extends Control
class_name MacroWorldStatusPanel

signal settings_requested
signal node_map_requested

const MAX_LOG_LINES := 8

var _snapshot: Dictionary = {}
var _log_lines: PackedStringArray = []

@onready var _frame: PanelContainer = %Frame
@onready var _clock: PocketClockDisplay = %PocketClock
@onready var _day_icon: TextureRect = %DayIcon
@onready var _day_label: Label = %DayLabel
@onready var _calendar_label: Label = %CalendarLabel
@onready var _settings_button: Button = %SettingsButton
@onready var _node_map_button: Button = %NodeMapButton
@onready var _log_scroll: ScrollContainer = %LogScroll
@onready var _log_list: VBoxContainer = %LogList


func _ready() -> void:
	custom_minimum_size = Vector2(300.0, 240.0)
	HUDAssetLibrary.apply_panel(_frame, "neutral")
	HUDAssetLibrary.apply_label(_day_label, "body")
	HUDAssetLibrary.apply_label(_calendar_label, "muted")
	HUDAssetLibrary.apply_button(_settings_button, "settings")
	HUDAssetLibrary.apply_button(_node_map_button, "map")
	_settings_button.text = "Settings"
	_node_map_button.text = "Node Map"
	_settings_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size()
	_node_map_button.custom_minimum_size = HUDAssetLibrary.macro_button_minimum_size()
	_settings_button.pressed.connect(func(): settings_requested.emit())
	_node_map_button.pressed.connect(func(): node_map_requested.emit())
	if _log_lines.is_empty():
		append_log("Systems online.")


func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var clock: Dictionary = snapshot.get("world_time", {})
	var calendar: Dictionary = snapshot.get("calendar", {})
	var hour := int(clock.get("hour", 0))
	var minute := int(clock.get("minute", 0))
	if _clock:
		_clock.visible = true
		_clock.set_time(hour, minute)
	var phase: String = RevampedHUDAtlas.time_of_day_phase(hour)
	if _day_icon:
		_day_icon.visible = true
		_day_icon.texture = RevampedHUDAtlas.time_of_day_icon(phase)
	if _day_label:
		_day_label.text = "DAY %03d" % int(calendar.get("day", clock.get("day", 1)))
	if _calendar_label:
		_calendar_label.text = "%s %04d" % [
			_month_name(int(calendar.get("month", 1))),
			int(calendar.get("year", 1)),
		]


func append_log(message: String) -> void:
	var line := message.strip_edges()
	if line.is_empty():
		return
	if not _log_lines.is_empty() and _log_lines[_log_lines.size() - 1] == line:
		return
	_log_lines.append(line)
	while _log_lines.size() > MAX_LOG_LINES:
		_log_lines.remove_at(0)
	_render_log()


func _render_log() -> void:
	if _log_list == null:
		return
	for child in _log_list.get_children():
		_log_list.remove_child(child)
		child.queue_free()
	for i in range(_log_lines.size()):
		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = _log_lines[i]
		var style := "muted" if i < _log_lines.size() - 1 else "body"
		HUDAssetLibrary.apply_label(label, style)
		_log_list.add_child(label)
	call_deferred("_scroll_log_to_end")


func _scroll_log_to_end() -> void:
	if _log_scroll == null:
		return
	_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


func _month_name(month: int) -> String:
	const NAMES := [
		"JAN", "FEB", "MAR", "APR", "MAY", "JUN",
		"JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
	]
	return NAMES[clampi(month - 1, 0, 11)]
